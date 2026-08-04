// 设备信息 / 版本信息
use crate::error::AppResult;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct DeviceDetailInfo {
    pub device_name: String,
    pub firmware_version: String,
    pub hardware_revision: String,
    pub serial_number: String,
    pub battery_level: u8,
    pub charging: bool,
    pub signal_strength: i8,
    pub latency_ms: u32,
    pub transport: String,
    pub mac_address: String,
    pub pnp_id: String,
    pub manufacturer: String,
}

#[derive(Debug, Serialize)]
pub struct AppVersionInfo {
    pub app_version: String,
    pub core_version: String,
    pub platform: String,
    pub architecture: String,
    pub os_version: String,
    pub ui_framework: String,
    pub ble_backend: String,
    pub hook_backend: String,
    pub build_profile: String,
    pub build_timestamp: String,
}

pub fn get_device_info(connected: bool, name: &str, battery: u8, signal: i8) -> AppResult<DeviceDetailInfo> {
    Ok(DeviceDetailInfo {
        device_name: if connected { name.to_string() } else { "—".to_string() },
        firmware_version: "1.2.3".to_string(),
        hardware_revision: "AhaKey Pro v2".to_string(),
        serial_number: if connected { "AKP-2025-01823".to_string() } else { "—".to_string() },
        battery_level: if connected { battery } else { 0 },
        charging: false,
        signal_strength: if connected { signal } else { 0 },
        latency_ms: 18,
        transport: "BLE 5.0".to_string(),
        mac_address: if connected { "AA:BB:CC:DD:EE:FF".to_string() } else { "—".to_string() },
        pnp_id: "HID\\VID_1234&PID_5678".to_string(),
        manufacturer: "AhaKey Studio".to_string(),
    })
}

pub fn get_version_info() -> AppResult<AppVersionInfo> {
    Ok(AppVersionInfo {
        app_version: "1.0.0".to_string(),
        core_version: env!("CARGO_PKG_VERSION").to_string(),
        platform: "Windows".to_string(),
        architecture: std::env::consts::ARCH.to_string(),
        os_version: "Windows 11".to_string(),
        ui_framework: "Tauri 2.x + Svelte 4".to_string(),
        ble_backend: "btleplug (WinRT BLE)".to_string(),
        hook_backend: "windows-rs (WH_KEYBOARD_LL)".to_string(),
        build_profile: if cfg!(debug_assertions) { "debug".to_string() } else { "release".to_string() },
        build_timestamp: "2025-01-15".to_string(),
    })
}

