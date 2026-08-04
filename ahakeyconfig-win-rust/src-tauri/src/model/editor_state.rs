//! 编辑态 / 预览态 — 前后端共享

use serde::{Deserialize, Serialize};
use crate::model::KeyConfig;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct IDEState {
    pub selected_mode: u8,
    pub selected_key_id: u8,
    pub dirty: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LightBarPreviewState {
    pub enabled: bool,
    pub style: String,
    pub color: String,
    pub brightness: u8,
    pub segments: Vec<u8>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct OledModeDraft {
    pub mode: u8,
    pub image_path: Option<String>,
    pub gif_path: Option<String>,
    pub text: String,
}

