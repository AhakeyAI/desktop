//! AhaKey USB HID 设备直接连接 (Windows 专用)
//!
//! 当 AhaKey 通过 USB-C 连接到电脑时,它会以 HID 设备身份出现:
//!   - VID 0x1EA7 (AhaKey),PID 0x0064 (键盘 + 配置复合设备)
//!
//! 这是 Java 版本 (ahakeyconfig-win-java) 的 UsbHidTransport 在 Rust 端的等价实现。
//! 通过 WinRT Windows.Devices.HumanInterfaceDevice API 打开 HID 设备,直接读写 Input/Output
//! Reports。
//!
//! 优势: WinRT HID API 比 BLE 简单 — 不需要广播,不需要配对,不需要 30 秒等待。
//! 只要 USB-C 插着,打开就能用。

#![cfg(windows)]

use tracing::{error, info, warn};

const AHAKEY_VID: u32 = 0x1EA7;
const AHAKEY_PID: u32 = 0x0064;

/// AhaKey USB HID 设备信息
#[derive(Clone, Debug)]
pub struct UsbHidInfo {
    pub device_id: String,
}

/// 列出所有 AhaKey USB HID 设备。
///
/// 用 DeviceInformation::FindAllAsyncAqsFilter 配合 AQS 过滤器找 VID_1EA7&PID_0064。
pub async fn list_ahakey_usb_devices() -> Vec<UsbHidInfo> {
    use windows::Devices::Enumeration::DeviceInformation;

    let aqs = format!(
        "System.Devices.InterfaceClassGuid:=\"{}\" \
         AND System.Devices.InterfaceEnabled:=System.StructuredQueryType.Boolean#True \
         AND System.DeviceInterface.Hid.VendorId:={} \
         AND System.DeviceInterface.Hid.ProductId:={}",
        "{4D1E55B2-F16F-11CF-88CB-001111000030}", // HIDClass
        AHAKEY_VID,
        AHAKEY_PID
    );

    info!("[USB-HID] listing AhaKey USB devices via AQS...");
    info!("[USB-HID] AQS filter: {}", aqs);

    let result = tauri::async_runtime::spawn_blocking(move || -> Result<Vec<UsbHidInfo>, String> {
        unsafe {
            let aqs_h = windows::core::HSTRING::from(&aqs);
            let collection = DeviceInformation::FindAllAsyncAqsFilter(&aqs_h)
                .map_err(|e| format!("FindAllAsyncAqsFilter: {e}"))?
                .GetResults()
                .map_err(|e| format!("GetResults: {e}"))?;

            let count = collection.Size().unwrap_or(0);
            info!("[USB-HID] FindAllAsync returned {count} devices");

            let mut out = Vec::new();
            for i in 0..count {
                let dev_info = collection.GetAt(i).map_err(|e| format!("GetAt({i}): {e}"))?;
                let id = dev_info
                    .Id()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_default();
                info!("[USB-HID]   + device_id={}", id);
                out.push(UsbHidInfo { device_id: id });
            }
            Ok(out)
        }
    });

    match result.await {
        Ok(Ok(devices)) => devices,
        Ok(Err(e)) => {
            warn!("[USB-HID] listing failed: {e}");
            Vec::new()
        }
        Err(e) => {
            warn!("[USB-HID] join failed: {e}");
            Vec::new()
        }
    }
}

/// 测试 AhaKey USB 是否在线。
///
/// 返回 true 表示找到了至少一个 AhaKey VID/PID 的 HID 设备。
pub async fn probe_ahakey_usb() -> bool {
    !list_ahakey_usb_devices().await.is_empty()
}

/// 同步版本(用于 spawn_blocking 上下文)
pub fn probe_sync() -> bool {
    use windows::Devices::Enumeration::DeviceInformation;

    let aqs = format!(
        "System.Devices.InterfaceClassGuid:=\"{}\" \
         AND System.DeviceInterface.Hid.VendorId:={} \
         AND System.DeviceInterface.Hid.ProductId:={}",
        "{4D1E55B2-F16F-11CF-88CB-001111000030}",
        AHAKEY_VID,
        AHAKEY_PID
    );

    unsafe {
        let aqs_h = windows::core::HSTRING::from(&aqs);
        match DeviceInformation::FindAllAsyncAqsFilter(&aqs_h) {
            Ok(op) => match op.GetResults() {
                Ok(list) => {
                    let count = list.Size().unwrap_or(0);
                    info!("[USB-HID] sync probe: found {count} AhaKey HID device(s)");
                    count > 0
                }
                Err(e) => {
                    warn!("[USB-HID] sync probe GetResults: {e}");
                    false
                }
            },
            Err(e) => {
                warn!("[USB-HID] sync probe FindAllAsync: {e}");
                false
            }
        }
    }
}