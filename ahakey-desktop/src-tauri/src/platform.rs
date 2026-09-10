#[cfg(windows)]
static LAST_EXTERNAL_WINDOW: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);
#[cfg(windows)]
fn external_window(hwnd: windows_sys::Win32::Foundation::HWND) -> Option<usize> {
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        GetClassNameW, GetWindowThreadProcessId, IsWindow,
    };
    unsafe {
        if hwnd.is_null() || IsWindow(hwnd) == 0 {
            return None;
        }
        let mut pid = 0;
        GetWindowThreadProcessId(hwnd, &mut pid);
        if pid == 0 || pid == std::process::id() {
            return None;
        }
        let mut class = [0u16; 80];
        let len = GetClassNameW(hwnd, class.as_mut_ptr(), class.len() as i32);
        let class = String::from_utf16_lossy(&class[..len.max(0) as usize]);
        if matches!(
            class.as_str(),
            "Shell_TrayWnd" | "Shell_SecondaryTrayWnd" | "Progman" | "WorkerW" | "#32768"
        ) {
            None
        } else {
            Some(hwnd as usize)
        }
    }
}
pub fn foreground() -> Option<usize> {
    #[cfg(windows)]
    unsafe {
        external_window(windows_sys::Win32::UI::WindowsAndMessaging::GetForegroundWindow())
    }
    #[cfg(not(windows))]
    {
        None
    }
}
pub fn last_external_window() -> Option<usize> {
    #[cfg(windows)]
    {
        foreground().or_else(|| {
            external_window(LAST_EXTERNAL_WINDOW.load(std::sync::atomic::Ordering::Relaxed) as _)
        })
    }
    #[cfg(not(windows))]
    {
        None
    }
}
pub fn watch_foreground() -> usize {
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::UI::{Accessibility::*, WindowsAndMessaging::*};
        unsafe extern "system" fn changed(
            _: HWINEVENTHOOK,
            _: u32,
            hwnd: windows_sys::Win32::Foundation::HWND,
            _: i32,
            _: i32,
            _: u32,
            _: u32,
        ) {
            if let Some(window) = external_window(hwnd) {
                LAST_EXTERNAL_WINDOW.store(window, std::sync::atomic::Ordering::Relaxed);
            }
        }
        if let Some(window) = foreground() {
            LAST_EXTERNAL_WINDOW.store(window, std::sync::atomic::Ordering::Relaxed);
        }
        // Metadata only: keep the last external HWND, never titles or contents.
        SetWinEventHook(
            EVENT_SYSTEM_FOREGROUND,
            EVENT_SYSTEM_FOREGROUND,
            std::ptr::null_mut(),
            Some(changed),
            0,
            0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS,
        ) as usize
    }
    #[cfg(not(windows))]
    {
        0
    }
}
pub fn stop_foreground_watch(hook: usize) {
    #[cfg(windows)]
    if hook != 0 {
        unsafe {
            windows_sys::Win32::UI::Accessibility::UnhookWinEvent(hook as _);
        }
    }
    #[cfg(not(windows))]
    let _ = hook;
}
#[cfg(windows)]
fn other_legacy_launcher(name: &str, pid: u32, current_pid: u32) -> bool {
    pid != current_pid && name.eq_ignore_ascii_case("AhaKeyStudio.exe")
}
pub fn java_running() -> bool {
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::{
            Foundation::{CloseHandle, INVALID_HANDLE_VALUE},
            System::Diagnostics::ToolHelp::*,
        };
        let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snapshot == INVALID_HANDLE_VALUE {
            return false;
        }
        let mut item: PROCESSENTRY32W = std::mem::zeroed();
        item.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
        let mut found = false;
        let mut more = Process32FirstW(snapshot, &mut item);
        while more != 0 {
            let end = item
                .szExeFile
                .iter()
                .position(|&c| c == 0)
                .unwrap_or(item.szExeFile.len());
            if other_legacy_launcher(
                &String::from_utf16_lossy(&item.szExeFile[..end]),
                item.th32ProcessID,
                std::process::id(),
            ) {
                found = true;
                break;
            }
            more = Process32NextW(snapshot, &mut item);
        }
        CloseHandle(snapshot);
        found
    }
    #[cfg(not(windows))]
    {
        false
    }
}
pub fn process_alive(pid: u32) -> bool {
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::{Foundation::CloseHandle, System::Threading::*};
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if h.is_null() {
            return false;
        }
        let mut code = 0;
        let ok = GetExitCodeProcess(h, &mut code) != 0 && code == 259;
        CloseHandle(h);
        ok
    }
    #[cfg(unix)]
    {
        pid > 0
            && pid <= i32::MAX as u32
            && (unsafe { libc::kill(pid as i32, 0) } == 0
                || std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM))
    }
    #[cfg(not(any(windows, unix)))]
    {
        pid == std::process::id()
    }
}
#[cfg(windows)]
fn key(vk: u16, scan: u16, flags: u32) -> windows_sys::Win32::UI::Input::KeyboardAndMouse::INPUT {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: vk,
                wScan: scan,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: 0,
            },
        },
    }
}
pub fn insert(target: Option<usize>, text: &str) -> Result<(), String> {
    let target = target.ok_or("已识别；界面录音仅预览，请使用复制或在目标输入框按硬件键")?;
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::UI::{Input::KeyboardAndMouse::*, WindowsAndMessaging::*};
        if GetForegroundWindow() as usize != target || IsWindow(target as _) == 0 {
            return Err("目标焦点已变化，文字保留在预览中，未自动输入".into());
        }
        for vk in [0x10, 0x11, 0x12, 0x5b, 0x5c] {
            if GetAsyncKeyState(vk) < 0 {
                return Err("修饰键仍按住，文字保留在预览中".into());
            }
        }
        let events: Vec<_> = text
            .encode_utf16()
            .filter(|&u| u >= 32 || u == 10 || u == 13 || u == 9)
            .flat_map(|u| {
                [
                    key(0, u, KEYEVENTF_UNICODE),
                    key(0, u, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP),
                ]
            })
            .collect();
        if events.is_empty() {
            return Ok(());
        }
        if SendInput(
            events.len() as u32,
            events.as_ptr(),
            std::mem::size_of::<INPUT>() as i32,
        ) != events.len() as u32
        {
            return Err("系统拒绝输入；请检查目标窗口权限，文字仍在预览中".into());
        }
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = (target, text);
        Err("此平台请从预览复制文字；原生输入适配待验证".into())
    }
}
#[cfg(windows)]
fn external_events(wechat: bool) -> Vec<windows_sys::Win32::UI::Input::KeyboardAndMouse::INPUT> {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::KEYEVENTF_KEYUP;
    // Match Java simulateKeyByHid(0x0B00), including generic VKs and order.
    let keys: &[u16] = if wechat {
        &[0x10, 0x11, 0x5b]
    } else {
        &[0x5b, 0x48]
    };
    keys.iter()
        .map(|&v| key(v, 0, 0))
        .chain(keys.iter().rev().map(|&v| key(v, 0, KEYEVENTF_KEYUP)))
        .collect()
}
pub fn external_toggle(wechat: bool) -> Result<(), String> {
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
        let events = external_events(wechat);
        if SendInput(
            events.len() as u32,
            events.as_ptr(),
            std::mem::size_of::<INPUT>() as i32,
        ) != events.len() as u32
        {
            return Err("系统拒绝语音快捷键".into());
        }
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = wechat;
        Err("微信和 Win+H 快捷键仅在 Windows 提供".into())
    }
}

#[cfg(all(test, windows))]
mod shortcut_tests {
    #[test]
    fn renamed_rust_launcher_does_not_block_its_own_voice_keys() {
        assert!(!super::other_legacy_launcher("AhaKeyStudio.exe", 7, 7));
        assert!(super::other_legacy_launcher("AhaKeyStudio.exe", 8, 7));
        assert!(!super::other_legacy_launcher("unrelated.exe", 8, 7));
    }
    #[test]
    fn wechat_packet_matches_java_generic_modifier_order() {
        let events = super::external_events(true);
        let actual: Vec<_> = events
            .iter()
            .map(|e| unsafe { (e.Anonymous.ki.wVk, e.Anonymous.ki.dwFlags) })
            .collect();
        assert_eq!(
            actual,
            vec![
                (0x10, 0),
                (0x11, 0),
                (0x5b, 0),
                (0x5b, 2),
                (0x11, 2),
                (0x10, 2)
            ]
        );
    }
}
