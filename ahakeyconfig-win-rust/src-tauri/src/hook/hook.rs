//! 低级别键盘钩子 (WH_KEYBOARD_LL)
//!
//! 用 `windows-rs` 直接调 `SetWindowsHookExW`,无需 JNA 边界。

use std::sync::Arc;

use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use tracing::{debug, error, info};

use crate::error::{AppError, AppResult};

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct KeyEvent {
    pub vk_code: u16,
    pub scan_code: u16,
    pub flags: u32,
    pub pressed: bool,
}

/// 键盘钩子包装
pub struct KeyboardHook {
    installed: Arc<Mutex<bool>>,
    callback: Arc<Mutex<Option<Box<dyn Fn(KeyEvent) -> bool + Send + Sync>>>>,
}

impl KeyboardHook {
    pub fn new() -> Self {
        Self {
            installed: Arc::new(Mutex::new(false)),
            callback: Arc::new(Mutex::new(None)),
        }
    }

    pub fn on_event<F>(&mut self, cb: F)
    where
        F: Fn(KeyEvent) -> bool + Send + Sync + 'static,
    {
        *self.callback.lock() = Some(Box::new(cb));
    }

    /// 安装钩子
    pub fn install(&mut self) -> AppResult<()> {
        if *self.installed.lock() {
            return Ok(());
        }
        info!("installing low-level keyboard hook");
        #[cfg(windows)]
        {
            let cb = self.callback.clone();
            windows::hook_impl::install_hook(cb)?;
        }
        #[cfg(not(windows))]
        {
            debug!("non-Windows platform: hook not installed");
        }
        *self.installed.lock() = true;
        Ok(())
    }

    /// 卸载钩子
    pub fn uninstall(&mut self) -> AppResult<()> {
        if !*self.installed.lock() {
            return Ok(());
        }
        info!("uninstalling keyboard hook");
        #[cfg(windows)]
        {
            windows::hook_impl::uninstall_hook()?;
        }
        *self.installed.lock() = false;
        Ok(())
    }

    pub fn is_installed(&self) -> bool {
        *self.installed.lock()
    }
}

impl Default for KeyboardHook {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for KeyboardHook {
    fn drop(&mut self) {
        if let Err(e) = self.uninstall() {
            error!("failed to uninstall hook on drop: {e}");
        }
    }
}

#[cfg(windows)]
mod windows {
    pub mod hook_impl {
        use std::sync::Arc;

        use parking_lot::Mutex;
        use windows::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
        use windows::Win32::UI::WindowsAndMessaging::{
            CallNextHookEx, SetWindowsHookExW, UnhookWindowsHookEx, HHOOK, KBDLLHOOKSTRUCT,
            WH_KEYBOARD_LL, WM_KEYDOWN, WM_SYSKEYDOWN,
        };

        use crate::error::{AppError, AppResult};
        use crate::hook::hook::KeyEvent;

        type HookCallback = Arc<Mutex<Option<Box<dyn Fn(KeyEvent) -> bool + Send + Sync>>>>;

        static mut HOOK_HANDLE: isize = 0;
        static mut CALLBACK: Option<HookCallback> = None;

        pub fn install_hook(cb: HookCallback) -> AppResult<()> {
            unsafe {
                CALLBACK = Some(cb);
                let h = SetWindowsHookExW(WH_KEYBOARD_LL, Some(hook_proc), None, 0);
                match h {
                    Ok(hhook) => {
                        HOOK_HANDLE = hhook.0 as isize;
                        Ok(())
                    }
                    Err(_) => Err(AppError::Hook("SetWindowsHookExW failed".into())),
                }
            }
        }

        pub fn uninstall_hook() -> AppResult<()> {
            unsafe {
                if HOOK_HANDLE != 0 {
                    let h = HHOOK(HOOK_HANDLE as *mut std::ffi::c_void);
                    let ok = UnhookWindowsHookEx(h);
                    if ok.is_err() {
                        return Err(AppError::Hook("UnhookWindowsHookEx failed".into()));
                    }
                    HOOK_HANDLE = 0;
                }
                CALLBACK = None;
            }
            Ok(())
        }

        unsafe extern "system" fn hook_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
            if code == 0 {
                let kb = &*(lparam.0 as *const KBDLLHOOKSTRUCT);
                let msg = wparam.0 as u32;
                let pressed = matches!(msg, WM_KEYDOWN | WM_SYSKEYDOWN);
                let event = KeyEvent {
                    vk_code: kb.vkCode as u16,
                    scan_code: kb.scanCode as u16,
                    flags: kb.flags.0,
                    pressed,
                };
                if let Some(cb) = CALLBACK.as_ref() {
                    if let Some(f) = cb.lock().as_ref() {
                        let swallow = f(event);
                        if swallow {
                            return LRESULT(1);
                        }
                    }
                }
            }
            CallNextHookEx(None, code, wparam, lparam)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new() {
        let h = KeyboardHook::new();
        assert!(!h.is_installed());
    }
}

