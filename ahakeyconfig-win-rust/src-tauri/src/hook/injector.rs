//! 键盘事件注入器
//!
//! 通过 `SendInput` 模拟按键,用于触发 Win+H 系统语音输入。

use crate::error::{AppError, AppResult};

/// 键盘注入器
pub struct KeyboardInjector;

impl KeyboardInjector {
    pub fn new() -> Self {
        Self
    }

    /// 触发 Win+H(系统语音输入)
    pub fn trigger_win_h(&self) -> AppResult<()> {
        #[cfg(windows)]
        {
            windows_impl::send_win_h()
        }
        #[cfg(not(windows))]
        {
            Err(AppError::Hook("Win+H trigger only supported on Windows".into()))
        }
    }

    /// 通用 SendInput
    pub fn send_key(&self, vk_code: u16, pressed: bool) -> AppResult<()> {
        #[cfg(windows)]
        {
            windows_impl::send_key(vk_code, pressed)
        }
        #[cfg(not(windows))]
        {
            Err(AppError::Hook("SendInput only supported on Windows".into()))
        }
    }
}

impl Default for KeyboardInjector {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(windows)]
mod windows_impl {
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        SendInput, INPUT, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, VIRTUAL_KEY, VK_H,
        VK_LWIN,
    };

    use crate::error::AppResult;

    pub fn send_win_h() -> AppResult<()> {
        let mut inputs = [INPUT::default(); 4];

        // Win down
        inputs[0].r#type = INPUT_KEYBOARD;
        inputs[0].Anonymous.ki = KEYBDINPUT {
            wVk: VIRTUAL_KEY(VK_LWIN.0),
            wScan: 0,
            dwFlags: Default::default(),
            time: 0,
            dwExtraInfo: 0,
        };

        // H down
        inputs[1].r#type = INPUT_KEYBOARD;
        inputs[1].Anonymous.ki = KEYBDINPUT {
            wVk: VIRTUAL_KEY(VK_H.0),
            wScan: 0,
            dwFlags: Default::default(),
            time: 0,
            dwExtraInfo: 0,
        };

        // H up
        inputs[2].r#type = INPUT_KEYBOARD;
        inputs[2].Anonymous.ki = KEYBDINPUT {
            wVk: VIRTUAL_KEY(VK_H.0),
            wScan: 0,
            dwFlags: KEYEVENTF_KEYUP,
            time: 0,
            dwExtraInfo: 0,
        };

        // Win up
        inputs[3].r#type = INPUT_KEYBOARD;
        inputs[3].Anonymous.ki = KEYBDINPUT {
            wVk: VIRTUAL_KEY(VK_LWIN.0),
            wScan: 0,
            dwFlags: KEYEVENTF_KEYUP,
            time: 0,
            dwExtraInfo: 0,
        };

        unsafe {
            SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
        }
        Ok(())
    }

    pub fn send_key(vk_code: u16, pressed: bool) -> AppResult<()> {
        let mut input = INPUT::default();
        input.r#type = INPUT_KEYBOARD;
        input.Anonymous.ki = KEYBDINPUT {
            wVk: VIRTUAL_KEY(vk_code),
            wScan: 0,
            dwFlags: if !pressed { KEYEVENTF_KEYUP } else { Default::default() },
            time: 0,
            dwExtraInfo: 0,
        };
        unsafe {
            SendInput(&[input], std::mem::size_of::<INPUT>() as i32);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new() {
        let _ = KeyboardInjector::new();
    }
}

