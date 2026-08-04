//! 语音路由服务 — 简化版,只保留核心钩子逻辑
//!
//! 替代原 `WindowsVoiceRelayService.java`:
//! - 监听低级别键盘钩子
//! - 匹配当前 Mode × Key 的路由
//! - 触发 Win+H(系统语音输入)或自定义 HID 键码

use std::sync::Arc;

use parking_lot::Mutex;
use tracing::{debug, info, warn};

use crate::error::AppResult;
use crate::hook::hook::{KeyEvent, KeyboardHook};
use crate::hook::injector::KeyboardInjector;
use crate::model::hid_usage::{HID_F17, HID_F18};
use crate::model::key_config::KeyConfig;
use crate::model::voice_preset::VoicePreset;

pub struct VoiceRelay {
    hook: Option<KeyboardHook>,
    enabled: Arc<Mutex<bool>>,
}

impl VoiceRelay {
    pub fn new() -> Self {
        Self {
            hook: None,
            enabled: Arc::new(Mutex::new(true)),
        }
    }

    pub fn install(&mut self) -> AppResult<()> {
        let mut hook = KeyboardHook::new();
        let en = self.enabled.clone();
        hook.on_event(move |ev: KeyEvent| -> bool {
            if !*en.lock() {
                return false;
            }
            let matches = ev.vk_code == HID_F17 as u16 || ev.vk_code == HID_F18 as u16;
            if !matches {
                return false;
            }
            if !ev.pressed {
                return true; // 释放也吞,避免穿透
            }
            debug!("voice key pressed: vk=0x{:04X}", ev.vk_code);
            let injector = KeyboardInjector::new();
            if let Err(e) = injector.trigger_win_h() {
                warn!("Win+H trigger failed: {e}");
            }
            true
        });
        hook.install()?;
        self.hook = Some(hook);
        Ok(())
    }

    pub fn uninstall(&mut self) -> AppResult<()> {
        if let Some(mut h) = self.hook.take() {
            h.uninstall()?;
        }
        Ok(())
    }

    pub fn set_enabled(&self, enabled: bool) {
        *self.enabled.lock() = enabled;
    }

    pub fn is_enabled(&self) -> bool {
        *self.enabled.lock()
    }
}

impl Default for VoiceRelay {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for VoiceRelay {
    fn drop(&mut self) {
        if let Err(e) = self.uninstall() {
            tracing::error!("relay uninstall failed on drop: {e}");
        }
    }
}
