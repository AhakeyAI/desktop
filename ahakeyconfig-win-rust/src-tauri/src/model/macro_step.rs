//! 宏步骤模型

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MacroStep {
    pub action: MacroAction,
    pub delay_ms: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum MacroAction {
    /// 按下 HID 键
    KeyDown { hid_code: u16 },
    /// 释放 HID 键
    KeyUp { hid_code: u16 },
    /// 文本输入
    Type { text: String },
    /// 系统命令
    Command { name: String },
    /// 等待
    Wait { ms: u32 },
}

