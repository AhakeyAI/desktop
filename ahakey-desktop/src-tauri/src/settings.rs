use serde::{Deserialize, Serialize};
use std::{fs, path::Path};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "kebab-case")]
pub enum Provider {
    Local,
    Doubao,
    #[default]
    Wechat,
    WindowsNative,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "kebab-case")]
pub enum TriggerMode {
    #[default]
    Hold,
    Toggle,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub accept: String,
    pub reject: String,
    #[serde(default)]
    pub keys: Vec<crate::keys::Binding>,
    #[serde(default = "default_lights")]
    pub light_effects: [u8; 9],
}
pub fn default_lights() -> [u8; 9] {
    [11, 5, 1, 1, 1, 6, 6, 7, 0]
}

pub fn default_profiles() -> Vec<Profile> {
    [
        ("claude-code", "Claude Code", "Y"),
        ("claude-desktop", "Claude Desktop", "Enter"),
        ("codex-cli", "Codex CLI", "Y"),
        ("chatgpt-app", "ChatGPT App", "Enter"),
    ]
    .into_iter()
    .map(|(id, name, accept)| Profile {
        id: id.into(),
        name: name.into(),
        accept: accept.into(),
        reject: if accept == "Y" { "N" } else { "Escape" }.into(),
        keys: vec![],
        light_effects: default_lights(),
    })
    .collect()
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Settings {
    pub schema_version: u32,
    pub provider: Provider,
    pub trigger_mode: TriggerMode,
    pub active_profile: String,
    pub captions_enabled: bool,
    pub caption_bottom_offset: u32,
    pub profiles: Vec<Profile>,
    #[serde(default)]
    pub microphone: Option<String>,
    #[serde(default)]
    pub saved_device: Option<String>,
    #[serde(default)]
    pub cloud_app_id: String,
    #[serde(default = "default_resource")]
    pub cloud_resource_id: String,
    #[serde(default = "yes")]
    pub auto_insert: bool,
    #[serde(default = "yes")]
    pub minimize_to_tray: bool,
    #[serde(default = "brightness")]
    pub light_brightness: u8,
    #[serde(default = "yes")]
    pub voice_keys_enabled: bool,
}

fn yes() -> bool {
    true
}
fn brightness() -> u8 {
    35
}
fn default_resource() -> String {
    "volc.bigasr.sauc.duration".into()
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            schema_version: 1,
            provider: if cfg!(windows) {
                Provider::Wechat
            } else {
                Provider::Local
            },
            trigger_mode: TriggerMode::Hold,
            active_profile: "codex-cli".into(),
            captions_enabled: true,
            caption_bottom_offset: 20,
            profiles: default_profiles(),
            microphone: None,
            saved_device: None,
            cloud_app_id: String::new(),
            cloud_resource_id: default_resource(),
            auto_insert: true,
            minimize_to_tray: true,
            light_brightness: 35,
            voice_keys_enabled: true,
        }
    }
}

impl Settings {
    pub fn start_voice_keys(&self, settings_error: bool) -> bool {
        self.voice_keys_enabled && !settings_error
    }
    /// Apply only fields the caller edited. A stale open settings window must
    /// not undo a tray selection on an unrelated field.
    pub fn merge_changes(desired: &Self, base: &Self, current: &Self) -> Result<Self, String> {
        let desired = serde_json::to_value(desired).map_err(|e| e.to_string())?;
        let base = serde_json::to_value(base).map_err(|e| e.to_string())?;
        let mut merged = serde_json::to_value(current).map_err(|e| e.to_string())?;
        for (key, value) in desired.as_object().ok_or("无效设置")? {
            if base.get(key) != Some(value) {
                merged[key] = value.clone();
            }
        }
        serde_json::from_value(merged).map_err(|e| e.to_string())
    }
    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != 1 {
            return Err("配置版本不兼容，原文件已保留".into());
        }
        if !(8..=160).contains(&self.caption_bottom_offset) {
            return Err("字幕底部间距必须为 8–160".into());
        }
        let expected = default_profiles();
        if !(1..=100).contains(&self.light_brightness)
            || self.cloud_app_id.len() > 128
            || self.cloud_app_id.chars().any(|c| c.is_control())
            || self.saved_device.as_ref().is_some_and(|s| s.len() > 4096)
            || self.microphone.as_ref().is_some_and(|s| s.len() > 1024)
        {
            return Err("设备或语音设置无效".into());
        }
        if ![
            "volc.bigasr.sauc.duration",
            "volc.bigasr.sauc.concurrent",
            "volc.seedasr.sauc.duration",
            "volc.seedasr.sauc.concurrent",
        ]
        .contains(&self.cloud_resource_id.as_str())
        {
            return Err("不支持的豆包语音资源".into());
        }
        if self.profiles.len() != expected.len() {
            return Err("需要四个应用配置".into());
        }
        for (profile, default) in self.profiles.iter().zip(&expected) {
            if !profile.keys.is_empty() && profile.keys.len() != 4 {
                return Err("每个模式需要四个按键定义".into());
            }
            if profile
                .keys
                .iter()
                .filter(|k| k.action == crate::keys::Action::Voice)
                .count()
                > 1
            {
                return Err("每个模式最多设置一个语音键".into());
            }
            for (index, key) in profile.keys.iter().enumerate() {
                key.hid(0)
                    .map_err(|e| format!("{} · 按键 {}：{e}", profile.name, index + 1))?;
            }
            if profile.light_effects.iter().any(|&v| v > 16) {
                return Err("不支持的灯效".into());
            }
            if profile.id != default.id || profile.name != default.name {
                return Err("应用配置标识不兼容".into());
            }
            for key in [&profile.accept, &profile.reject] {
                if !["Enter", "Escape", "Y", "N", "Tab", "Space"].contains(&key.as_str()) {
                    return Err("不支持的快捷键".into());
                }
            }
        }
        if !expected.iter().any(|p| p.id == self.active_profile) {
            return Err("应用配置不存在".into());
        }
        Ok(())
    }
}

pub fn load(path: &Path) -> Result<Settings, String> {
    if !path.exists() {
        return Ok(Settings::default());
    }
    let data = fs::read(path).map_err(|_| "无法读取设置文件，原文件已保留")?;
    let settings: Settings =
        serde_json::from_slice(&data).map_err(|_| "设置文件格式不正确，原文件已保留")?;
    settings.validate()?;
    Ok(settings)
}

/// One-time settings import for the production identity. Never edits previews
/// or copies credentials/model files; an existing production config always wins.
pub fn load_for_launch(path: &Path) -> Result<Settings, String> {
    if path.exists() {
        return load(path);
    }
    let Some(directory) = path.parent() else {
        return load(path);
    };
    if directory.file_name().and_then(|s| s.to_str()) != Some("ai.ahakey.studio") {
        return load(path);
    }
    let Some(parent) = directory.parent() else {
        return load(path);
    };
    for namespace in [
        "ai.ahakey.studio.app006.routing.preview",
        "ai.ahakey.studio.preview",
    ] {
        let candidate = parent.join(namespace).join("settings.json");
        if candidate.exists() {
            let settings = load(&candidate)?;
            save(path, &settings)?;
            return Ok(settings);
        }
    }
    load(path)
}

pub fn save(path: &Path, settings: &Settings) -> Result<(), String> {
    settings.validate()?;
    // Refuse to silently replace an incompatible/corrupt file from another version.
    load(path)?;
    // Keep the pre-editor configuration so an older client can be restored
    // without discarding user choices if its strict schema rejects new fields.
    if let Ok(previous) = fs::read(path) {
        if serde_json::from_slice::<serde_json::Value>(&previous)
            .ok()
            .is_some_and(|v| v.get("voiceKeysEnabled").is_none())
        {
            use std::io::Write;
            let backup = path.with_extension("before-four-keys.json");
            match fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(backup)
            {
                Ok(mut file) => {
                    file.write_all(&previous)
                        .and_then(|_| file.sync_all())
                        .map_err(|_| "旧设置备份失败，未覆盖配置")?;
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
                Err(_) => return Err("无法备份旧设置，未覆盖配置".into()),
            }
        }
    }
    let parent = path.parent().ok_or("无效的设置目录")?;
    fs::create_dir_all(parent).map_err(|_| "无法创建设置目录")?;
    let temporary = path.with_extension("json.pending");
    let bytes = serde_json::to_vec_pretty(settings).map_err(|_| "无法编码设置")?;
    {
        use std::io::Write;
        let mut file = fs::File::create(&temporary).map_err(|_| "无法写入临时设置")?;
        file.write_all(&bytes)
            .and_then(|_| file.sync_all())
            .map_err(|_| "保存设置失败")?;
    }
    // Windows MoveFileEx atomically replaces the destination on the same volume.
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        use windows_sys::Win32::Storage::FileSystem::{
            MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
        };
        let src: Vec<u16> = temporary.as_os_str().encode_wide().chain(Some(0)).collect();
        let dst: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
        if unsafe {
            MoveFileExW(
                src.as_ptr(),
                dst.as_ptr(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        } == 0
        {
            return Err("无法完成设置保存，原设置已保留".into());
        }
    }
    #[cfg(not(windows))]
    fs::rename(&temporary, path).map_err(|_| "无法完成设置保存")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn production_import_preserves_preview_and_explicit_choices() {
        let temp = tempfile::tempdir().unwrap();
        let preview = temp
            .path()
            .join("ai.ahakey.studio.app006.routing.preview/settings.json");
        let production = temp.path().join("ai.ahakey.studio/settings.json");
        let mut expected = Settings {
            voice_keys_enabled: false,
            active_profile: "chatgpt-app".into(),
            ..Settings::default()
        };
        save(&preview, &expected).unwrap();
        let before = fs::read(&preview).unwrap();
        assert_eq!(load_for_launch(&production).unwrap(), expected);
        assert_eq!(fs::read(&preview).unwrap(), before);
        expected.voice_keys_enabled = true;
        save(&production, &expected).unwrap();
        assert_eq!(load_for_launch(&production).unwrap(), expected);
    }
    #[test]
    fn voice_keys_default_on_but_explicit_off_and_bad_settings_stay_off() {
        let defaults = Settings::default();
        assert!(defaults.voice_keys_enabled);
        assert!(defaults.start_voice_keys(false));
        assert!(!defaults.start_voice_keys(true));
        let mut old = serde_json::to_value(&defaults).unwrap();
        old.as_object_mut().unwrap().remove("voiceKeysEnabled");
        assert!(
            serde_json::from_value::<Settings>(old.clone())
                .unwrap()
                .voice_keys_enabled
        );
        old["voiceKeysEnabled"] = false.into();
        assert!(!serde_json::from_value::<Settings>(old)
            .unwrap()
            .start_voice_keys(false));
    }
    #[test]
    fn stale_ui_save_only_applies_edited_fields() {
        let base = Settings::default();
        let mut desired = base.clone();
        desired.caption_bottom_offset = 44;
        let current = Settings {
            provider: Provider::Doubao,
            active_profile: "chatgpt-app".into(),
            ..base.clone()
        };
        let merged = Settings::merge_changes(&desired, &base, &current).unwrap();
        assert_eq!(merged.provider, Provider::Doubao);
        assert_eq!(merged.active_profile, "chatgpt-app");
        assert_eq!(merged.caption_bottom_offset, 44);
    }
    #[test]
    fn four_keys_and_explicit_listener_choice_round_trip() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("settings.json");
        let mut settings = Settings {
            voice_keys_enabled: true,
            ..Settings::default()
        };
        settings.profiles[3].keys = crate::keys::defaults("Enter", "Escape");
        settings.profiles[3].keys[3].shortcut = "Ctrl+Shift+V".into();
        save(&path, &settings).unwrap();
        assert_eq!(load(&path).unwrap(), settings);
        settings.profiles[3].keys[1].action = crate::keys::Action::Voice;
        assert!(settings.validate().is_err());
    }
    #[test]
    fn first_editor_save_backs_up_old_settings_without_resetting_custom_keys() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("settings.json");
        let mut old = serde_json::to_value(Settings::default()).unwrap();
        old.as_object_mut().unwrap().remove("voiceKeysEnabled");
        old["profiles"][3]["accept"] = "Tab".into();
        for profile in old["profiles"].as_array_mut().unwrap() {
            profile.as_object_mut().unwrap().remove("keys");
        }
        let bytes = serde_json::to_vec(&old).unwrap();
        fs::write(&path, &bytes).unwrap();
        let settings = load(&path).unwrap();
        save(&path, &settings).unwrap();
        assert_eq!(
            fs::read(path.with_extension("before-four-keys.json")).unwrap(),
            bytes
        );
        assert_eq!(load(&path).unwrap().profiles[3].accept, "Tab");
    }
    #[test]
    fn migrates_preview_settings_without_losing_profiles() {
        let mut old = serde_json::to_value(Settings::default()).unwrap();
        for key in [
            "microphone",
            "savedDevice",
            "cloudAppId",
            "cloudResourceId",
            "autoInsert",
            "minimizeToTray",
            "lightBrightness",
        ] {
            old.as_object_mut().unwrap().remove(key);
        }
        for profile in old["profiles"].as_array_mut().unwrap() {
            profile.as_object_mut().unwrap().remove("lightEffects");
        }
        let loaded: Settings = serde_json::from_value(old).unwrap();
        loaded.validate().unwrap();
        assert_eq!(loaded, Settings::default());
    }
    #[test]
    fn refuses_invalid_light_mapping_and_plaintext_secrets() {
        let mut settings = Settings::default();
        settings.profiles[0].light_effects[1] = 17;
        assert!(settings.validate().is_err());
        let mut value = serde_json::to_value(Settings::default()).unwrap();
        value["token"] = "must-not-be-persisted".into();
        assert!(serde_json::from_value::<Settings>(value).is_err());
    }
    #[test]
    fn profiles_use_stable_ids_and_desktop_enter() {
        let settings = Settings::default();
        settings.validate().unwrap();
        assert_eq!(settings.profiles[3].id, "chatgpt-app");
        assert_eq!(settings.profiles[3].accept, "Enter");
        assert_eq!(settings.profiles[2].accept, "Y");
    }
    #[test]
    fn save_reload_preserves_choice_and_replaces_existing_file() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("settings.json");
        let mut settings = load(&path).unwrap();
        save(&path, &settings).unwrap();
        settings.provider = Provider::Doubao;
        settings.active_profile = "chatgpt-app".into();
        settings.profiles[3].accept = "Tab".into();
        save(&path, &settings).unwrap();
        assert_eq!(load(&path).unwrap(), settings);
    }
    #[test]
    fn refuse_corrupt_and_future_schema_without_overwrite() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("settings.json");
        fs::write(&path, b"incomplete").unwrap();
        assert!(save(&path, &Settings::default()).is_err());
        assert_eq!(fs::read(&path).unwrap(), b"incomplete");
        let future = Settings {
            schema_version: 2,
            ..Settings::default()
        };
        assert!(future.validate().is_err());
    }
    #[test]
    fn reject_out_of_bounds_overlay_and_arbitrary_key_sequences() {
        let mut settings = Settings {
            caption_bottom_offset: 0,
            ..Settings::default()
        };
        assert!(settings.validate().is_err());
        settings.caption_bottom_offset = 20;
        settings.profiles[0].accept = "arbitrary shell command".into();
        assert!(settings.validate().is_err());
    }
}
