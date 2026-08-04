// 配置文件持久化 — 写到 ~/.ahakey/keys.json
use crate::error::AppResult;
use crate::model::{KeyCodeBinding, KeyConfig, LightBarPreviewState, OledModeDraft, VoicePreset};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

fn ahakey_dir() -> PathBuf {
    let home = std::env::var("USERPROFILE").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".ahakey")
}

fn keys_path() -> PathBuf {
    ahakey_dir().join("keys.json")
}

fn oled_path() -> PathBuf {
    ahakey_dir().join("oled_draft.json")
}

fn light_path() -> PathBuf {
    ahakey_dir().join("light_preview.json")
}

pub fn load_keys() -> AppResult<HashMap<u8, Vec<KeyConfig>>> {
    let path = keys_path();
    if !path.exists() {
        return Ok(default_keys());
    }
    let s = fs::read_to_string(&path)?;
    Ok(serde_json::from_str(&s).unwrap_or_else(|_| default_keys()))
}

pub fn save_keys(keys: &HashMap<u8, Vec<KeyConfig>>) -> AppResult<()> {
    fs::create_dir_all(ahakey_dir())?;
    let s = serde_json::to_string_pretty(keys)?;
    fs::write(keys_path(), s)?;
    Ok(())
}

pub fn load_oled_draft() -> AppResult<OledModeDraft> {
    let path = oled_path();
    if !path.exists() {
        return Ok(OledModeDraft::default());
    }
    let s = fs::read_to_string(&path)?;
    Ok(serde_json::from_str(&s).unwrap_or_default())
}

pub fn save_oled_draft(d: &OledModeDraft) -> AppResult<()> {
    fs::create_dir_all(ahakey_dir())?;
    let s = serde_json::to_string_pretty(d)?;
    fs::write(oled_path(), s)?;
    Ok(())
}

pub fn load_light_preview() -> AppResult<LightBarPreviewState> {
    let path = light_path();
    if !path.exists() {
        return Ok(LightBarPreviewState::default());
    }
    let s = fs::read_to_string(&path)?;
    Ok(serde_json::from_str(&s).unwrap_or_default())
}

pub fn save_light_preview(p: &LightBarPreviewState) -> AppResult<()> {
    fs::create_dir_all(ahakey_dir())?;
    let s = serde_json::to_string_pretty(p)?;
    fs::write(light_path(), s)?;
    Ok(())
}

// ====================== 最近连接设备 ======================
// 持久化最近一次成功连接的设备 MAC(优先于扫描结果,解决隐私设备扫不到的问题)

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct LastDevice {
    pub address: String,
    pub name: String,
}

fn last_device_path() -> PathBuf {
    ahakey_dir().join("last_device.json")
}

pub fn load_last_device() -> Option<LastDevice> {
    let path = last_device_path();
    if !path.exists() {
        return None;
    }
    let s = fs::read_to_string(&path).ok()?;
    serde_json::from_str(&s).ok()
}

pub fn save_last_device(d: &LastDevice) -> AppResult<()> {
    fs::create_dir_all(ahakey_dir())?;
    let s = serde_json::to_string_pretty(d)?;
    fs::write(last_device_path(), s)?;
    Ok(())
}

fn default_keys() -> HashMap<u8, Vec<KeyConfig>> {
    let mut m = HashMap::new();
    m.insert(0, vec![
        KeyConfig { id: 1, label: "K1".into(), name: "Record".into(), bindings: vec![KeyCodeBinding { key: "Left Ctrl".into(), code: "0xE0".into() }], voice_preset: VoicePreset::WindowsNative },
        KeyConfig { id: 2, label: "K2".into(), name: "Yes".into(), bindings: vec![KeyCodeBinding { key: "Enter".into(), code: "0x28".into() }], voice_preset: VoicePreset::WindowsNative },
        KeyConfig { id: 3, label: "K3".into(), name: "No".into(), bindings: vec![KeyCodeBinding { key: "Escape".into(), code: "0x29".into() }], voice_preset: VoicePreset::WindowsNative },
        KeyConfig { id: 4, label: "K4".into(), name: "Backspace".into(), bindings: vec![KeyCodeBinding { key: "Backspace".into(), code: "0x2A".into() }], voice_preset: VoicePreset::WindowsNative },
    ]);
    m.insert(1, vec![
        KeyConfig { id: 1, label: "K1".into(), name: "Build".into(), bindings: vec![KeyCodeBinding { key: "Ctrl+B".into(), code: "0xE0+0x05".into() }], voice_preset: VoicePreset::WindowsNative },
        KeyConfig { id: 2, label: "K2".into(), name: "Run".into(), bindings: vec![KeyCodeBinding { key: "Ctrl+R".into(), code: "0xE0+0x0F".into() }], voice_preset: VoicePreset::WindowsNative },
        KeyConfig { id: 3, label: "K3".into(), name: "Debug".into(), bindings: vec![KeyCodeBinding { key: "F5".into(), code: "0x3E".into() }], voice_preset: VoicePreset::WindowsNative },
        KeyConfig { id: 4, label: "K4".into(), name: "Stop".into(), bindings: vec![KeyCodeBinding { key: "Shift+F5".into(), code: "0xE1+0x3E".into() }], voice_preset: VoicePreset::WindowsNative },
    ]);
    m.insert(2, vec![
        KeyConfig { id: 1, label: "K1".into(), name: "Compose".into(), bindings: vec![KeyCodeBinding { key: "Ctrl+I".into(), code: "0xE0+0x0C".into() }], voice_preset: VoicePreset::WindowsNative },
        KeyConfig { id: 2, label: "K2".into(), name: "Test".into(), bindings: vec![KeyCodeBinding { key: "Ctrl+T".into(), code: "0xE0+0x17".into() }], voice_preset: VoicePreset::WindowsNative },
        KeyConfig { id: 3, label: "K3".into(), name: "Lint".into(), bindings: vec![KeyCodeBinding { key: "Ctrl+L".into(), code: "0xE0+0x0F".into() }], voice_preset: VoicePreset::WindowsNative },
        KeyConfig { id: 4, label: "K4".into(), name: "Format".into(), bindings: vec![KeyCodeBinding { key: "Shift+Alt+F".into(), code: "0xE2+0x09".into() }], voice_preset: VoicePreset::WindowsNative },
    ]);
    m.insert(3, vec![
        KeyConfig { id: 1, label: "K1".into(), name: "Custom1".into(), bindings: vec![KeyCodeBinding { key: "F13".into(), code: "0x68".into() }], voice_preset: VoicePreset::Custom },
        KeyConfig { id: 2, label: "K2".into(), name: "Custom2".into(), bindings: vec![KeyCodeBinding { key: "F14".into(), code: "0x69".into() }], voice_preset: VoicePreset::Custom },
        KeyConfig { id: 3, label: "K3".into(), name: "Custom3".into(), bindings: vec![KeyCodeBinding { key: "F15".into(), code: "0x6A".into() }], voice_preset: VoicePreset::Custom },
        KeyConfig { id: 4, label: "K4".into(), name: "Custom4".into(), bindings: vec![KeyCodeBinding { key: "F16".into(), code: "0x6B".into() }], voice_preset: VoicePreset::Custom },
    ]);
    m
}
