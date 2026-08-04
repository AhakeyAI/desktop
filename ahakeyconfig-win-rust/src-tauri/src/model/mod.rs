//! 数据模型层
//!
//! 对应原 Java 项目的 `model/` 目录,所有结构都 `Serialize + Deserialize`,
//! 既能在 Rust 内部使用,也能直接 walk 到 Tauri 前端。

pub mod device_status;
pub mod key_config;
pub mod scan_result;
pub mod studio_state;
pub mod macro_step;
pub mod oled_frame;
pub mod voice_preset;
pub mod hid_usage;
pub mod editor_state;

pub use device_status::DeviceStatus;
pub use key_config::{KeyConfig, KeyCodeBinding, KeyId, ModeSlot};
pub use scan_result::ScanResult;
pub use studio_state::{StudioState, StudioPart, ConnectionInfo};
pub use macro_step::{MacroStep, MacroAction};
pub use oled_frame::{OledFrame, OledFrameEncoder};
pub use voice_preset::VoicePreset;
pub use hid_usage::*;
pub use editor_state::{IDEState, LightBarPreviewState, OledModeDraft};

