//! 语音预设

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VoicePreset {
    /// Windows 原生语音输入(Win+H)
    WindowsNative,
    /// 自定义 HID 键码
    Custom,
}

impl Default for VoicePreset {
    fn default() -> Self {
        Self::WindowsNative
    }
}

