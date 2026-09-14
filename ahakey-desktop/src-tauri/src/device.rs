//! Connection-independent, read-only device information.
#[cfg(windows)]
use crate::state::Runtime;
use ahakey_ble::{BleSnapshot, ConnectionPhase, DeviceStatus};
use serde::Serialize;
#[cfg(windows)]
use tauri::Manager;

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct UsbSnapshot {
    pub supported: bool,
    pub present: Option<bool>,
    pub status: Option<DeviceStatus>,
    pub error: Option<String>,
}
impl Default for UsbSnapshot {
    fn default() -> Self {
        Self {
            supported: cfg!(windows),
            present: None,
            status: None,
            error: None,
        }
    }
}
impl UsbSnapshot {
    #[cfg(any(windows, test))]
    fn from_poll(present: Option<bool>, result: Result<Option<DeviceStatus>, String>) -> Self {
        match result {
            Ok(status) => Self {
                present,
                status,
                ..Self::default()
            },
            Err(error) => Self {
                present,
                error: Some(error),
                ..Self::default()
            },
        }
    }
}
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceView {
    pub transport: Option<&'static str>,
    pub name: Option<String>,
    pub status: Option<DeviceStatus>,
}
impl DeviceView {
    pub fn from_transports(usb: &UsbSnapshot, ble: Option<&BleSnapshot>) -> Self {
        if let Some(status) = &usb.status {
            return Self {
                transport: Some("usb"),
                name: Some("AhaKey · USB".into()),
                status: Some(status.clone()),
            };
        }
        if let Some(ble) = ble.filter(|b| b.phase == ConnectionPhase::Ready) {
            if let Some(status) = &ble.status {
                return Self {
                    transport: Some("ble"),
                    name: ble.device.as_ref().map(|d| d.name.clone()),
                    status: Some(status.clone()),
                };
            }
        }
        Self {
            transport: None,
            name: None,
            status: None,
        }
    }
}
#[cfg(windows)]
async fn poll_usb() -> UsbSnapshot {
    // One bounded deadline, but retain interface presence if only the read fails.
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(4);
    let opened =
        tokio::time::timeout_at(deadline, ahakey_ble::usb_routing::UsbRouting::try_open()).await;
    let mut port = match opened {
        Ok(Ok(Some(port))) => port,
        Ok(Ok(None)) => return UsbSnapshot::from_poll(Some(false), Ok(None)),
        Ok(Err(error)) => return UsbSnapshot::from_poll(None, Err(error)),
        Err(_) => return UsbSnapshot::from_poll(None, Err("USB 接口检测超时".into())),
    };
    let result = tokio::time::timeout_at(deadline, port.device_status())
        .await
        .map_err(|_| "USB 已识别，但设备状态读取超时；按键输入与状态通信是独立通道".to_owned())
        .and_then(|result| result.map(Some));
    UsbSnapshot::from_poll(Some(true), result)
}
pub fn start(app: &tauri::AppHandle) {
    #[cfg(windows)]
    {
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            let mut timer = tokio::time::interval(std::time::Duration::from_secs(2));
            timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
            loop {
                timer.tick().await;
                let state = app.state::<Runtime>();
                if state.closing.load(std::sync::atomic::Ordering::SeqCst) {
                    break;
                }
                // Explicit settings commands take priority; do not interleave
                // monitor reads with an A3 transaction on the same endpoint.
                let Ok(gate) = state.usb_gate.try_lock() else {
                    continue;
                };
                let next = poll_usb().await;
                drop(gate);
                let changed = {
                    let mut current = state.usb.lock().unwrap();
                    let changed = *current != next;
                    *current = next;
                    changed
                };
                if changed {
                    crate::backend::pulse(&app);
                }
            }
        });
    }
    #[cfg(not(windows))]
    let _ = app;
}
#[cfg(test)]
mod tests {
    use super::*;
    fn info(battery: u8) -> DeviceStatus {
        DeviceStatus {
            battery_level: battery,
            signal: 50,
            firmware_main: 1,
            firmware_sub: 0,
            work_mode: 3,
            light_mode: 5,
            switch_state: 1,
            light_brightness: 35,
        }
    }
    fn ble(phase: ConnectionPhase) -> BleSnapshot {
        BleSnapshot {
            generation: 1,
            phase,
            device: None,
            status: Some(info(42)),
            error: None,
        }
    }
    #[test]
    fn usb_works_without_ble_and_never_uses_ble_fields() {
        let usb = UsbSnapshot::from_poll(Some(true), Ok(Some(info(76))));
        let view = DeviceView::from_transports(&usb, Some(&ble(ConnectionPhase::Error)));
        assert_eq!(view.transport, Some("usb"));
        assert_eq!(view.status.unwrap().battery_level, 76);
        assert_eq!(
            DeviceView::from_transports(&usb, Some(&ble(ConnectionPhase::Ready))).transport,
            Some("usb")
        );
    }
    #[test]
    fn usb_removal_falls_back_only_to_a_ready_ble_snapshot() {
        let usb = UsbSnapshot::from_poll(Some(false), Ok(None));
        assert_eq!(usb.present, Some(false));
        assert_eq!(
            DeviceView::from_transports(&usb, Some(&ble(ConnectionPhase::Ready))).transport,
            Some("ble")
        );
        assert!(
            DeviceView::from_transports(&usb, Some(&ble(ConnectionPhase::Error)))
                .status
                .is_none()
        );
        assert!(DeviceView::from_transports(&usb, None).status.is_none());
    }
    #[test]
    fn failed_usb_poll_clears_old_status() {
        let failed = UsbSnapshot::from_poll(Some(true), Err("read failed".into()));
        assert_eq!(failed.present, Some(true));
        assert!(failed.status.is_none());
        assert!(failed.error.is_some());
        assert!(DeviceView::from_transports(&failed, None).status.is_none());
        let unknown = UsbSnapshot::from_poll(None, Err("open failed".into()));
        assert_eq!(unknown.present, None);
        assert!(DeviceView::from_transports(&unknown, None).status.is_none());
    }
}
