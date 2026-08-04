//! Studio 全局状态

use serde::{Deserialize, Serialize};

use crate::model::device_status::DeviceStatus;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionInfo {
    pub connected: bool,
    pub transport: String,
    pub device_address: String,
    pub latency_ms: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StudioPart {
    pub name: String,
    pub enabled: bool,
    pub role: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StudioState {
    pub connection: ConnectionInfo,
    pub device: DeviceStatus,
    pub active_mode: u8,
    pub active_route: String,
    pub parts: Vec<StudioPart>,
    pub aha_type_enabled: bool,
    pub aha_type_status: String,
    pub language: String,
    /// 摇杆/开关档位: "手动批准" / "自动批准" / "静音"
    pub switch_title: String,
}

impl Default for StudioState {
    fn default() -> Self {
        Self {
            connection: ConnectionInfo {
                connected: false,
                transport: "BLE".into(),
                device_address: String::new(),
                latency_ms: 0,
            },
            device: DeviceStatus::default(),
            active_mode: 0,
            active_route: "Windows Native (Win+H)".into(),
            parts: vec![
                StudioPart {
                    name: "Device".into(),
                    enabled: true,
                    role: "primary".into(),
                },
                StudioPart {
                    name: "Hook".into(),
                    enabled: true,
                    role: "capture".into(),
                },
                StudioPart {
                    name: "Voice".into(),
                    enabled: true,
                    role: "route".into(),
                },
            ],
            aha_type_enabled: false,
            aha_type_status: "disabled".into(),
            language: "zh-CN".into(),
            switch_title: "手动批准".into(),
        }
    }
}

