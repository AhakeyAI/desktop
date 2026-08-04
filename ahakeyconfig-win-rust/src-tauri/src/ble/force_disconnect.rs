//! 强制断开 AhaKey 当前的 Bluetooth Classic/HID 连接,让它进入广播状态。
//!
//! ## 为什么需要这个
//!
//! AhaKey 5A93 当前以 **HID over GATT** 方式连接到 Windows(蓝牙键盘通道),
//! 这是它跟 Windows 蓝牙子系统建立的 GATT 主连接。在这个状态下:
//!
//! - AhaKey 停止广播(GAP Peripheral 协议,连接后不广播)
//! - Windows 不允许第二个 GATT 客户端枚举 services
//! - btleplug 的 GetGattServicesAsync 返回 0 service 或失败
//!
//! 只有断开当前连接,让 AhaKey 进入 GAPROLE_WAITING → 重新广播,
//! 我们的应用才能作为第二个客户端连上。

#![cfg(windows)]

use tracing::{info, warn};
use windows::Devices::Enumeration::DeviceInformation;

/// 用 HID device id 强制关闭 BLE 设备,触发断开事件。
///
/// HID device id 格式:
///   \\?\HID#{00001812-...}_Dev_VID&0107d7_PID&0000_REV&0110_dc045a93df2c\KBD
///
/// 我们需要把它转成 BLE device id:
///   BluetoothLE#BluetoothLEb0:3c:dc:ad:75:fe-bc:04:5a:93:df:2c
///
/// 这个 BLE device id 可以从 PowerShell Get-PnpDevice 的 InstanceId 提取:
///   BTHLE\DEV_<MAC>\...
///
/// 但更可靠的: 用 `DeviceInformation::CreateFromIdAsync` with BluetoothLE device kind。
pub async fn force_disconnect_ahakey(hid_device_id: &str) -> Result<(), String> {
    use windows::Devices::Bluetooth::BluetoothLEDevice;
    use windows::Devices::Enumeration::DeviceInformation;

    info!("[BLE/ForceDisconnect] closing BLE device for hid_id={}", hid_device_id);

    // HID device id 里包含 MAC: _dc045a93df2c
    let mac = extract_mac_from_hid_path(hid_device_id)
        .ok_or_else(|| format!("cannot extract MAC from hid_id: {hid_device_id}"))?;

    // 格式化为小写无冒号,用于构建 BLE device id
    let mac_compact = mac.replace(':', "").to_lowercase();
    info!("[BLE/ForceDisconnect] mac={mac} compact={mac_compact}");

    // BluetoothLE device id 格式(根据 Windows 蓝牙栈):
    //   BluetoothLE#BluetoothLE{PC_MAC}-{DEV_MAC}
    //
    // 我们用 FromBluetoothAddressAsync 拿到 device 后,Close() 触发断开
    use windows::Devices::Bluetooth::BluetoothLEDevice as BDev;

    // 把 MAC "DC:04:5A:93:DF:2C" 转成整数(little-endian)
    let parts: Vec<&str> = mac.split(':').collect();
    if parts.len() != 6 {
        return Err(format!("invalid MAC format: {mac}"));
    }
    let mut bytes = [0u8; 6];
    for (i, p) in parts.iter().enumerate() {
        bytes[i] = u8::from_str_radix(p, 16)
            .map_err(|e| format!("invalid MAC hex: {e}"))?;
    }
    let mac_int = u64::from_le_bytes(bytes);

    info!("[BLE/ForceDisconnect] calling FromBluetoothAddressAsync({:#x})", mac_int);

    let device_op = unsafe { BDev::FromBluetoothAddressAsync(mac_int) }
        .map_err(|e| format!("FromBluetoothAddressAsync start failed: {e}"))?;

    let device = device_op
        .GetResults()
        .map_err(|e| format!("FromBluetoothAddressAsync.GetResults failed: {e}"))?;

    let name = device.Name().map(|s| s.to_string()).unwrap_or_default();
    let status = device.ConnectionStatus().ok();
    info!(
        "[BLE/ForceDisconnect] device: name='{name}' status={:?}",
        status
    );

    // 强制关闭 - 这一步会触发 Windows 蓝牙栈断开当前 GATT 主连接
    // AhaKey 收到 GAP_LINK_TERMINATED_EVENT → 进入 GAPROLE_WAITING → 自动广播
    info!("[BLE/ForceDisconnect] calling device.Close()...");
    unsafe {
        device.Close()
            .map_err(|e| format!("device.Close failed: {e}"))?;
    }

    info!("[BLE/ForceDisconnect] ✓ device closed — AhaKey should now be in GAPROLE_WAITING");
    Ok(())
}

/// 从 HID device id 提取 6 字节 MAC,转成 DC:04:5A:93:DF:2C 格式。
fn extract_mac_from_hid_path(path: &str) -> Option<String> {
    let chars: Vec<char> = path.chars().collect();
    let mut start: Option<usize> = None;
    let mut i = 0;
    while i + 12 <= chars.len() {
        if chars[i..i + 12].iter().all(|c| c.is_ascii_hexdigit()) {
            start = Some(i);
            break;
        }
        i += 1;
    }
    let s = start?;
    let hex: String = chars[s..s + 12].iter().collect();
    let bytes: Vec<u8> = (0..12)
        .step_by(2)
        .map(|j| u8::from_str_radix(&hex[j..j + 2], 16).ok())
        .collect::<Option<Vec<_>>>()?;
    if bytes.len() != 6 {
        return None;
    }
    Some(format!(
        "{:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}",
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]
    ))
}