//! 设备状态模型

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceStatus {
    pub connected: bool,
    pub device_name: String,
    pub firmware_version: String,
    pub battery_level: u8,
    pub mode: u8,
    pub charging: bool,
    pub signal_strength: i8,
}

impl Default for DeviceStatus {
    fn default() -> Self {
        Self {
            connected: false,
            device_name: String::new(),
            firmware_version: String::new(),
            battery_level: 0,
            mode: 0,
            charging: false,
            signal_strength: -100,
        }
    }
}

