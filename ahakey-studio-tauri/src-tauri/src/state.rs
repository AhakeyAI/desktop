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
#[derive(Clone, Debug)]
pub struct TransferTask {
    pub id: u64,
    pub cancel: ahakey_speech::CancellationToken,
    pub kind: ahakey_speech::ModelKind,
    pub is_auto: bool,
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
    /// Application identity (tauri `config().identifier`); scopes the native
    /// credential namespace so preview and release never share tokens.
    pub identifier: String,
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
    pub transfer_generation: AtomicU64,
    pub transfer: Mutex<Option<TransferTask>>,
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
        identifier: String,
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
            identifier,
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
            transfer_generation: AtomicU64::new(0),
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
    pub fn model_dir_for(&self, kind: ahakey_speech::ModelKind) -> std::path::PathBuf {
        let standard = self.data_dir.join("models").join(kind.id());
        if kind == ahakey_speech::ModelKind::SenseVoice {
            let standard_store = ahakey_speech::ModelStore::new(standard.clone(), kind);
            if standard_store.is_installed() {
                return standard;
            }
            let legacy = self.data_dir.join("models/sensevoice-int8-2024-07-17");
            let legacy_store = ahakey_speech::ModelStore::new(legacy.clone(), kind);
            if legacy_store.is_installed() {
                return legacy;
            }
        }
        standard
    }
    pub fn model_store(&self) -> ahakey_speech::ModelStore {
        let kind = self.settings.lock().unwrap().local_model_kind();
        self.model_store_for(kind)
    }
    pub fn model_store_for(&self, kind: ahakey_speech::ModelKind) -> ahakey_speech::ModelStore {
        ahakey_speech::ModelStore::new(self.model_dir_for(kind), kind)
    }
    pub fn credentials(&self) -> ahakey_cloud::CredentialStore {
        ahakey_cloud::CredentialStore::new(self.data_dir.join("credentials"), &self.identifier)
    }
    pub fn next_transfer_id(&self) -> u64 {
        self.transfer_generation
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed)
            + 1
    }
    pub fn update_transfer_progress(&self, id: u64, fraction: f64) -> bool {
        let active = self.transfer.lock().unwrap();
        if active.as_ref().map(|t| t.id) != Some(id) {
            return false;
        }
        let mut p = self.download.lock().unwrap();
        let changed = (p.progress - fraction).abs() >= 0.01 || fraction >= 1.0;
        p.progress = fraction;
        changed
    }
    pub fn finish_transfer(&self, id: u64, message: String) -> bool {
        let mut active = self.transfer.lock().unwrap();
        if active.as_ref().map(|t| t.id) != Some(id) {
            return false;
        }
        *active = None;
        let mut p = self.download.lock().unwrap();
        p.busy = false;
        p.message = message;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ahakey_speech::{ModelKind, MODEL_BYTES, TOKENS_BYTES};
    use std::fs::{self, File};

    fn make_test_runtime(data_dir: std::path::PathBuf) -> Runtime {
        Runtime::new(
            Settings::default(),
            data_dir.join("settings.json"),
            None,
            data_dir,
            "ai.ahakey.test".into(),
        )
    }

    fn write_dummy_sensevoice(dir: &std::path::Path) {
        fs::create_dir_all(dir).unwrap();
        let f1 = File::create(dir.join("model.int8.onnx")).unwrap();
        f1.set_len(MODEL_BYTES).unwrap();
        let f2 = File::create(dir.join("tokens.txt")).unwrap();
        f2.set_len(TOKENS_BYTES).unwrap();
    }

    #[test]
    fn model_dir_for_prefers_standard_when_installed() {
        let temp = tempfile::tempdir().unwrap();
        let runtime = make_test_runtime(temp.path().to_path_buf());
        let standard = temp.path().join("models/sensevoice-2024-07-17");
        let legacy = temp.path().join("models/sensevoice-int8-2024-07-17");
        write_dummy_sensevoice(&standard);
        write_dummy_sensevoice(&legacy);

        assert_eq!(runtime.model_dir_for(ModelKind::SenseVoice), standard);
    }

    #[test]
    fn model_dir_for_falls_back_to_legacy_when_only_legacy_is_installed() {
        let temp = tempfile::tempdir().unwrap();
        let runtime = make_test_runtime(temp.path().to_path_buf());
        let standard = temp.path().join("models/sensevoice-2024-07-17");
        let legacy = temp.path().join("models/sensevoice-int8-2024-07-17");
        fs::create_dir_all(&standard).unwrap();
        write_dummy_sensevoice(&legacy);

        assert_eq!(runtime.model_dir_for(ModelKind::SenseVoice), legacy);
    }

    #[test]
    fn model_dir_for_defaults_to_standard_when_neither_is_installed() {
        let temp = tempfile::tempdir().unwrap();
        let runtime = make_test_runtime(temp.path().to_path_buf());
        let standard = temp.path().join("models/sensevoice-2024-07-17");

        assert_eq!(runtime.model_dir_for(ModelKind::SenseVoice), standard);
    }

    #[test]
    fn stale_transfer_completion_does_not_overwrite_replacement_transfer() {
        let temp = tempfile::tempdir().unwrap();
        let runtime = make_test_runtime(temp.path().to_path_buf());

        let cancel_a = ahakey_speech::CancellationToken::new();
        let id_a = runtime.next_transfer_id();
        *runtime.transfer.lock().unwrap() = Some(TransferTask {
            id: id_a,
            cancel: cancel_a.clone(),
            kind: ModelKind::SenseVoice,
            is_auto: true,
        });
        *runtime.download.lock().unwrap() = DownloadStatus {
            busy: true,
            progress: 0.25,
            message: "正在后台自动下载 SenseVoice Small INT8 模型…".into(),
        };

        // Cancel A and immediately install replacement transfer B
        cancel_a.cancel();
        let cancel_b = ahakey_speech::CancellationToken::new();
        let id_b = runtime.next_transfer_id();
        *runtime.transfer.lock().unwrap() = Some(TransferTask {
            id: id_b,
            cancel: cancel_b,
            kind: ModelKind::Whisper(ahakey_speech::WhisperSize::Base),
            is_auto: false,
        });
        *runtime.download.lock().unwrap() = DownloadStatus {
            busy: true,
            progress: 0.0,
            message: "正在准备 Whisper Base 模型…".into(),
        };

        // Stale progress and completion from A must be ignored
        assert!(!runtime.update_transfer_progress(id_a, 0.9));
        assert!(!runtime.finish_transfer(id_a, "模型自动下载已取消".into()));
        assert_eq!(
            runtime.transfer.lock().unwrap().as_ref().map(|t| t.id),
            Some(id_b),
            "Replacement transfer B must remain tracked after cancelled transfer A exits"
        );
        {
            let status = runtime.download.lock().unwrap();
            assert!(
                status.busy,
                "Download status must remain busy for active transfer B"
            );
            assert_eq!(status.progress, 0.0);
            assert_eq!(status.message, "正在准备 Whisper Base 模型…");
        }

        // Active transfer B updates and completes normally
        assert!(runtime.update_transfer_progress(id_b, 0.5));
        assert!(runtime.finish_transfer(id_b, "Whisper Base 模型已校验，可开始识别".into()));
        assert!(runtime.transfer.lock().unwrap().is_none());
        assert!(!runtime.download.lock().unwrap().busy);
    }
}
