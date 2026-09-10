use crate::{caption::Caption, settings::Settings, voice::Active};
use ahakey_ble::{BleClient, BleSnapshot, DeviceInfo};
use serde::Serialize;
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicU64},
        Arc, Mutex,
    },
};
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpeechStatus {
    pub phase: String,
    pub message: String,
    pub recording: bool,
}
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadStatus {
    pub busy: bool,
    pub progress: f64,
    pub message: String,
}
pub type KeyAction = (u64, u64, bool, Option<usize>);
#[derive(Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyObservation {
    pub events: u64,
    pub key: String,
    pub pressed: bool,
}
pub struct Runtime {
    pub settings: Mutex<Settings>,
    pub settings_gate: tokio::sync::Mutex<()>,
    pub settings_notice: Mutex<String>,
    pub settings_change_id: Mutex<Option<String>>,
    pub tray_controls: Mutex<Option<crate::tray::Controls>>,
    pub foreground_hook: AtomicU64,
    pub settings_path: PathBuf,
    pub settings_error: Option<String>,
    pub data_dir: PathBuf,
    pub caption: Mutex<Caption>,
    pub caption_target: Mutex<Option<usize>>,
    pub caption_placement: Mutex<Option<crate::caption::Placement>>,
    pub key_enabled: AtomicBool,
    #[cfg(windows)]
    pub windows_voice_hook: Mutex<Option<crate::windows_voice_keys::VoiceKeyHook>>,
    pub key_observation: Mutex<KeyObservation>,
    pub key_write_notice: Mutex<String>,
    pub key_write_busy: AtomicBool,
    pub keys_down: Mutex<std::collections::HashSet<u32>>,
    pub key_state: Mutex<crate::input::KeyTest>,
    pub generation: AtomicU64,
    pub recording: AtomicBool,
    pub key_epoch: AtomicU64,
    pub key_sequence: AtomicU64,
    pub key_actions: Mutex<Option<tokio::sync::mpsc::Sender<KeyAction>>>,
    pub voice: Mutex<Option<Active>>,
    pub voice_gate: tokio::sync::Mutex<()>,
    pub speech: Mutex<SpeechStatus>,
    pub ble: tokio::sync::Mutex<Option<Arc<BleClient>>>,
    pub ble_initialization: tokio::sync::Mutex<()>,
    pub ble_connection_gate: tokio::sync::Mutex<()>,
    pub ble_recovery: Mutex<crate::recovery::Recovery>,
    pub devices: Mutex<Vec<DeviceInfo>>,
    pub ble_error: Mutex<Option<String>>,
    pub usb: Mutex<crate::device::UsbSnapshot>,
    pub usb_gate: tokio::sync::Mutex<()>,
    pub transfer: Mutex<Option<ahakey_speech::CancellationToken>>,
    pub download: Mutex<DownloadStatus>,
    pub hook: Mutex<Option<crate::hooks::HookServer>>,
    pub closing: AtomicBool,
    pub tray: AtomicBool,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub version: String,
    pub platform: String,
    pub settings: Settings,
    pub settings_path: String,
    pub settings_error: Option<String>,
    pub foreground_caption_supported: bool,
    pub settings_notice: String,
    pub settings_change_id: Option<String>,
    pub speech_engine_ready: bool,
    pub model_installed: bool,
    pub model_directory: String,
    pub native_key_test_supported: bool,
    pub native_key_test_enabled: bool,
    pub key_observation: KeyObservation,
    pub key_write_notice: String,
    pub ble_ready: bool,
    pub device: crate::device::DeviceView,
    pub usb: crate::device::UsbSnapshot,
    pub ble: Option<BleSnapshot>,
    pub ble_error: Option<String>,
    pub ble_recovery: crate::recovery::Status,
    pub devices: Vec<DeviceInfo>,
    pub caption: Caption,
    pub speech: SpeechStatus,
    pub download: DownloadStatus,
    pub cloud_configured: bool,
    pub hook_port: Option<u16>,
    pub hook_last_event: Option<String>,
    pub auto_insert_supported: bool,
}
impl Runtime {
    pub fn new(
        settings: Settings,
        path: PathBuf,
        error: Option<String>,
        data_dir: PathBuf,
    ) -> Self {
        let recovery = crate::recovery::Recovery::new(settings.saved_device.clone());
        Self {
            settings: Mutex::new(settings),
            settings_gate: tokio::sync::Mutex::new(()),
            settings_notice: Mutex::new(String::new()),
            settings_change_id: Mutex::new(None),
            tray_controls: Mutex::new(None),
            foreground_hook: AtomicU64::new(0),
            settings_path: path,
            settings_error: error,
            data_dir,
            caption: Mutex::new(Caption::idle()),
            caption_target: Mutex::new(None),
            caption_placement: Mutex::new(None),
            key_enabled: AtomicBool::new(false),
            #[cfg(windows)]
            windows_voice_hook: Mutex::new(None),
            key_observation: Mutex::new(KeyObservation::default()),
            key_write_busy: AtomicBool::new(false),
            key_write_notice: Mutex::new("本次运行尚未写入四键；本机保存不等于键盘已更新".into()),
            keys_down: Mutex::new(Default::default()),
            key_state: Mutex::new(Default::default()),
            generation: AtomicU64::new(0),
            recording: AtomicBool::new(false),
            voice: Mutex::new(None),
            voice_gate: tokio::sync::Mutex::new(()),
            key_epoch: AtomicU64::new(0),
            key_sequence: AtomicU64::new(0),
            key_actions: Mutex::new(None),
            speech: Mutex::new(SpeechStatus {
                phase: "idle".into(),
                message: "按需启用识别；没有自动录音".into(),
                recording: false,
            }),
            ble: tokio::sync::Mutex::new(None),
            ble_initialization: tokio::sync::Mutex::new(()),
            ble_connection_gate: tokio::sync::Mutex::new(()),
            ble_recovery: Mutex::new(recovery),
            devices: Mutex::new(vec![]),
            ble_error: Mutex::new(None),
            usb: Mutex::new(crate::device::UsbSnapshot::default()),
            usb_gate: tokio::sync::Mutex::new(()),
            transfer: Mutex::new(None),
            download: Mutex::new(DownloadStatus {
                busy: false,
                progress: 0.0,
                message: String::new(),
            }),
            hook: Mutex::new(None),
            closing: AtomicBool::new(false),
            tray: AtomicBool::new(false),
        }
    }
    pub fn model_store(&self) -> ahakey_speech::ModelStore {
        ahakey_speech::ModelStore::new(self.data_dir.join("models/sensevoice-int8-2024-07-17"))
    }
    pub fn credentials(&self) -> ahakey_cloud::CredentialStore {
        ahakey_cloud::CredentialStore::new(self.data_dir.join("credentials"))
    }
}
