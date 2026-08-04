// 全局应用状态管理
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::RwLock;
use std::sync::atomic::{AtomicBool, Ordering};

use tauri::AppHandle;
use tokio::sync::Mutex;

use crate::ble::BleManager;
use crate::error::AppResult;
use crate::model::{
    ConnectionInfo, DeviceStatus, IDEState, KeyConfig, LightBarPreviewState, OledModeDraft,
    StudioState,
};
use crate::service::config_store;

pub struct AppState {
    pub state: RwLock<StudioState>,
    pub keys: RwLock<HashMap<u8, Vec<KeyConfig>>>, // mode -> keys
    pub oled_draft: RwLock<OledModeDraft>,
    pub ide_state: RwLock<IDEState>,
    pub light_preview: RwLock<LightBarPreviewState>,
    pub hook_running: AtomicBool,
    pub ble_lock: Mutex<()>,
    /// BLE 管理器(btleplug 进程内直连)— 由 commands.rs 调用 connect/disconnect
    pub ble: Arc<BleManager>,
}

impl AppState {
    pub fn new(app: AppHandle) -> AppResult<Self> {
        let keys = config_store::load_keys().unwrap_or_default();
        let oled = config_store::load_oled_draft().unwrap_or_default();
        let light = config_store::load_light_preview().unwrap_or_default();

        let state = StudioState {
            connection: ConnectionInfo {
                connected: false,
                transport: "BLE".to_string(),
                device_address: String::new(),
                latency_ms: 0,
            },
            device: DeviceStatus {
                connected: false,
                device_name: String::new(),
                firmware_version: "1.2.3".to_string(),
                battery_level: 0,
                mode: 0,
                charging: false,
                signal_strength: 0,
            },
            active_mode: 0,
            active_route: "Windows Native (Win+H)".to_string(),
            parts: vec![
                crate::model::StudioPart { name: "F17".to_string(), enabled: true, role: "voice".to_string() },
                crate::model::StudioPart { name: "F18".to_string(), enabled: true, role: "voice".to_string() },
                crate::model::StudioPart { name: "Knob".to_string(), enabled: true, role: "volume".to_string() },
            ],
            aha_type_enabled: false,
            aha_type_status: "未启用".to_string(),
            language: "zh-CN".to_string(),
            switch_title: "手动批准".to_string(),
        };

        Ok(Self {
            state: RwLock::new(state),
            keys: RwLock::new(keys),
            oled_draft: RwLock::new(oled),
            ide_state: RwLock::new(IDEState::default()),
            light_preview: RwLock::new(light),
            hook_running: AtomicBool::new(false),
            ble_lock: Mutex::new(()),
            ble: Arc::new(BleManager::new(app)),
        })
    }

    pub fn is_hook_running(&self) -> bool {
        self.hook_running.load(Ordering::SeqCst)
    }

    pub fn set_hook_running(&self, on: bool) {
        self.hook_running.store(on, Ordering::SeqCst);
    }

    pub fn get_studio_state(&self) -> StudioState {
        self.state.read().unwrap().clone()
    }

    pub fn set_active_mode(&self, mode: u8) -> AppResult<()> {
        let mut s = self.state.write().unwrap();
        s.active_mode = mode.min(3);
        s.device.mode = s.active_mode;
        Ok(())
    }

    pub fn get_keys_for_mode(&self, mode: u8) -> Vec<KeyConfig> {
        let keys = self.keys.read().unwrap();
        keys.get(&mode).cloned().unwrap_or_default()
    }

    pub fn set_keys_for_mode(&self, mode: u8, keys: Vec<KeyConfig>) -> AppResult<()> {
        let mut all = self.keys.write().unwrap();
        all.insert(mode, keys);
        Ok(())
    }

    pub fn get_oled_draft(&self) -> OledModeDraft {
        self.oled_draft.read().unwrap().clone()
    }

    pub fn set_oled_draft(&self, draft: OledModeDraft) -> AppResult<()> {
        *self.oled_draft.write().unwrap() = draft;
        Ok(())
    }

    pub fn get_light_preview(&self) -> LightBarPreviewState {
        self.light_preview.read().unwrap().clone()
    }

    pub fn set_light_preview(&self, p: LightBarPreviewState) -> AppResult<()> {
        *self.light_preview.write().unwrap() = p;
        Ok(())
    }

    pub fn get_ide_state(&self) -> IDEState {
        self.ide_state.read().unwrap().clone()
    }

    pub fn set_ide_state(&self, s: IDEState) -> AppResult<()> {
        *self.ide_state.write().unwrap() = s;
        Ok(())
    }

    pub fn set_connected(&self, addr: String, name: String) {
        let mut s = self.state.write().unwrap();
        s.connection.connected = true;
        s.connection.device_address = addr;
        s.device.connected = true;
        s.device.device_name = name;
        s.device.battery_level = 87;
        s.device.signal_strength = -42;
    }

    pub fn set_disconnected(&self) {
        let mut s = self.state.write().unwrap();
        s.connection.connected = false;
        s.connection.device_address.clear();
        s.device.connected = false;
        s.device.battery_level = 0;
        s.device.signal_strength = 0;
    }

    /// 处理 BLE 通知帧 (来自 btleplug 直连的 notify 特征)
    /// data 是完整的 AhaKey 协议帧:
    ///   [0xAA][0xBB][cmd][battery][signal][fw_main][fw_sub][work_mode][light_mode][switch_state][light_brightness]...[0xCC][0xDD]
    /// 与 Java 端 AhaKeyProtocol.parseDeviceStatus 保持一致
    pub fn on_ble_notify(&self, data: &[u8]) {
        // 帧头帧尾校验
        if data.len() < 4
            || data[0] != 0xAA
            || data[1] != 0xBB
            || data[data.len() - 2] != 0xCC
            || data[data.len() - 1] != 0xDD
        {
            return;
        }
        // 忽略 6 字节的 CMD_UPDATE_STATE(0x90) 响应帧
        // 这些帧里的状态值是命令执行结果,不是真实拨杆位置
        if data.len() == 6 && data[2] == 0x90 {
            return;
        }
        // 只处理完整的状态查询响应(>=12 字节, cmd == 0x00)
        if data.len() < 12 || data[2] != 0x00 {
            return;
        }
        let base = 3; // payload 起始位置
        let battery = data[base];
        let mode = data[base + 4];
        let switch_state = data[base + 6];

        let mut s = self.state.write().unwrap();
        s.device.battery_level = battery.min(100);
        s.device.mode = mode.min(3);
        s.active_mode = mode.min(3);
        // 与 Java DeviceStatus.getSwitchTitle 一致:仅 0=自动批准,其余均为手动批准
        let title = match switch_state {
            0 => "自动批准",
            _ => "手动批准",
        };
        s.switch_title = title.to_string();
    }
}




