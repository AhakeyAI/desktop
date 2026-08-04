// 语音路由引擎 — 选 Win+H / F17 / F18 / 自定义
use crate::model::VoicePreset;
use serde::Serialize;

#[derive(Debug, Serialize, Clone)]
pub struct VoiceRouteSummary {
    pub mode: u8,
    pub preset: VoicePreset,
    pub active_hid: String,
    pub description: String,
}

pub fn route_for_mode(mode: u8, preset: &VoicePreset) -> VoiceRouteSummary {
    let (hid, desc) = match preset {
        VoicePreset::WindowsNative => {
            let hid = match mode {
                0 => "F18",
                1 => "F17",
                _ => "F18",
            };
            (hid.to_string(), "Windows Native (Win+H)".to_string())
        }
        VoicePreset::Custom => {
            (format!("Custom-{}", mode), "用户自定义".to_string())
        }
    };
    VoiceRouteSummary {
        mode,
        preset: preset.clone(),
        active_hid: hid,
        description: desc,
    }
}

pub fn all_routes_for_modes(preset: &VoicePreset) -> Vec<VoiceRouteSummary> {
    (0..4).map(|m| route_for_mode(m, preset)).collect()
}

