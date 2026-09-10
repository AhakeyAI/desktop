//! Explicit vendor-interface control, independent of BLE pairing and input selection.
//! Never opens the keyboard interface or sends keyboard input reports.
use crate::{
    protocol::{self, DeviceStatus},
    routing::{self, Config, Status},
};
use std::{future::IntoFuture, time::Duration};
use tokio::{sync::mpsc, time::timeout};
use windows::{
    core::Ref,
    Devices::{
        Enumeration::DeviceInformation,
        HumanInterfaceDevice::{HidDevice, HidInputReportReceivedEventArgs},
    },
    Foundation::TypedEventHandler,
    Storage::{
        FileAccessMode,
        Streams::{DataReader, DataWriter},
    },
};
type Result<T> = std::result::Result<T, String>;
fn native<T>(result: windows::core::Result<T>) -> Result<T> {
    result.map_err(|e| e.to_string())
}
pub struct UsbRouting {
    device: HidDevice,
    token: Option<i64>,
    input: mpsc::Receiver<Vec<u8>>,
}
impl Drop for UsbRouting {
    fn drop(&mut self) {
        if let Some(token) = self.token {
            let _ = self.device.RemoveInputReportReceived(token);
        }
        let _ = self.device.Close();
    }
}
fn output_packet(frame: &[u8]) -> Result<[u8; 65]> {
    if frame.len() > 62 {
        return Err("USB command exceeds vendor report capacity".into());
    }
    let mut packet = [0; 65];
    packet[1] = 0xa1;
    packet[2] = frame.len() as u8;
    packet[3..3 + frame.len()].copy_from_slice(frame);
    Ok(packet)
}
fn input_frame(packet: &[u8]) -> Option<&[u8]> {
    // Windows HID prefixes a zero Report ID; no fallback to an arbitrary interface.
    if packet.len() != 65 || packet[0] != 0 || packet[1..3] != [0xaa, 0xbb] {
        return None;
    }
    let length = match packet[3] {
        0 => 13,
        0xa2 => 15,
        0xa3 => 17,
        _ => return None,
    };
    Some(&packet[1..1 + length])
}
impl UsbRouting {
    pub async fn open() -> Result<Self> {
        Self::try_open()
            .await?
            .ok_or_else(|| "未检测到 AhaKey USB 配置接口，请检查数据线".into())
    }
    pub async fn try_open() -> Result<Option<Self>> {
        let selector = native(HidDevice::GetDeviceSelectorVidPid(
            0xff00, 1, 0x413c, 0x2107,
        ))?;
        let found = native(
            native(DeviceInformation::FindAllAsyncAqsFilter(&selector))?
                .into_future()
                .await,
        )?;
        match native(found.Size())? {
            0 => return Ok(None),
            1 => {}
            _ => return Err("检测到多个 AhaKey USB 配置接口，请只连接一块键盘".into()),
        }
        let info = native(found.GetAt(0))?;
        let id = native(info.Id())?;
        let device = native(
            native(HidDevice::FromIdAsync(&id, FileAccessMode::ReadWrite))?
                .into_future()
                .await,
        )?;
        let (sender, input) = mpsc::channel(16);
        let mut port = Self {
            device,
            token: None,
            input,
        };
        if native(port.device.VendorId())? != 0x413c || native(port.device.ProductId())? != 0x2107 {
            return Err("USB device identity mismatch".into());
        }
        let token = native(port.device.InputReportReceived(&TypedEventHandler::new(
            move |_: Ref<HidDevice>, args: Ref<HidInputReportReceivedEventArgs>| {
                let report = args.ok()?.Report()?;
                let buffer = report.Data()?;
                if buffer.Length()? != 65 {
                    return Ok(());
                }
                let reader = DataReader::FromBuffer(&buffer)?;
                let mut bytes = vec![0; 65];
                reader.ReadBytes(&mut bytes)?;
                let _ = sender.try_send(bytes);
                Ok(())
            },
        )))?;
        port.token = Some(token);
        Ok(Some(port))
    }
    async fn exchange(
        &mut self,
        frame: &[u8],
        request: Option<u16>,
        config: Option<&Config>,
    ) -> Result<Status> {
        let bytes = self
            .roundtrip(frame, |bytes| {
                routing::parse(bytes).is_some_and(|r| r.request == request)
            })
            .await?;
        routing::confirmed(
            routing::parse(&bytes).ok_or("Invalid routing response")?,
            request,
            config,
        )
        .map_err(|e| e.to_string())
    }
    async fn roundtrip(&mut self, frame: &[u8], accept: impl Fn(&[u8]) -> bool) -> Result<Vec<u8>> {
        while self.input.try_recv().is_ok() {}
        let report = native(self.device.CreateOutputReport())?;
        if native(report.Id())? != 0 || native(native(report.Data())?.Length())? != 65 {
            return Err("Unexpected vendor output report layout".into());
        }
        let packet = output_packet(frame)?;
        let writer = native(DataWriter::new())?;
        native(writer.WriteBytes(&packet))?;
        native(report.SetData(&native(writer.DetachBuffer())?))?;
        let sent = native(
            native(self.device.SendOutputReportAsync(&report))?
                .into_future()
                .await,
        )?;
        if sent != 65 {
            return Err(format!("Short USB command write: {sent}/65"));
        }
        timeout(Duration::from_secs(4), async {
            while let Some(packet) = self.input.recv().await {
                if let Some(frame) = input_frame(&packet) {
                    if accept(frame) {
                        return Ok(frame.to_vec());
                    }
                }
            }
            Err("USB input stream ended".into())
        })
        .await
        .map_err(|_| "USB 设备回读超时；未确认操作结果".to_owned())?
    }
    /// The same read-only status payload used by BLE: no pairing or Flash write.
    pub async fn device_status(&mut self) -> Result<DeviceStatus> {
        let bytes = self
            .roundtrip(&protocol::QUERY_STATUS, |b| {
                protocol::parse_status(b).is_some()
            })
            .await?;
        protocol::parse_status(&bytes).ok_or_else(|| "无效 USB 设备状态".into())
    }
    pub async fn read(&mut self) -> Result<Status> {
        self.exchange(&routing::QUERY, None, None).await
    }
    pub async fn apply(&mut self, config: &Config) -> Result<Status> {
        use std::sync::atomic::{AtomicU16, Ordering};
        static NEXT: AtomicU16 = AtomicU16::new(1);
        config.validate().map_err(|e| e.to_string())?;
        self.read().await?; // Capability gate, on this same open USB device.
        let request = NEXT.fetch_add(1, Ordering::Relaxed) & 0x3fff;
        let frame = config.frame(request).map_err(|e| e.to_string())?;
        self.exchange(&frame, Some(request), Some(config)).await
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn decodes_device_telemetry_without_accepting_routing_as_telemetry() {
        let mut packet = [0; 65];
        packet[1..14].copy_from_slice(&[0xaa, 0xbb, 0, 76, 50, 1, 0, 3, 5, 1, 35, 0xcc, 0xdd]);
        let status = protocol::parse_status(input_frame(&packet).unwrap()).unwrap();
        assert_eq!(status.battery_level, 76);
        assert_eq!(status.work_mode, 3);
        assert_eq!(status.light_brightness, 35);
        packet[13] = 0;
        assert!(protocol::parse_status(input_frame(&packet).unwrap()).is_none());
    }
    #[test]
    fn uses_vendor_command_report_not_keyboard_report() {
        let p = output_packet(&routing::QUERY).unwrap();
        assert_eq!(&p[..8], &[0, 0xa1, 5, 0xaa, 0xbb, 0xa2, 0xcc, 0xdd]);
        assert!(output_packet(&[0; 63]).is_err());
        let mut input = [0; 65];
        input[1..16].copy_from_slice(&[0xaa, 0xbb, 0xa2, 0, 1, 1, 0, 1, 0, 4, 4, 0, 0, 0xcc, 0xdd]);
        assert!(routing::parse(input_frame(&input).unwrap()).is_some());
        input[0] = 1;
        assert!(input_frame(&input).is_none());
        assert!(input_frame(&[0; 8]).is_none());
    }
}
