//! Match the Java relay: consume only F17/F18 down/up using WH_KEYBOARD_LL.
//! Never poll global key state or execute speech/IPC inside the hook callback.
use std::{
    cell::RefCell,
    sync::{
        atomic::{AtomicBool, AtomicU32, Ordering},
        mpsc, Arc,
    },
    thread::{self, JoinHandle},
    time::Duration,
};
use tokio::sync::mpsc::{channel, Receiver, Sender};
use windows_sys::Win32::{
    System::{LibraryLoader::GetModuleHandleW, Threading::GetCurrentThreadId},
    UI::WindowsAndMessaging::*,
};

pub struct Event {
    pub vk: u32,
    pub pressed: bool,
    pub target: Option<usize>,
}
#[derive(Default)]
struct Edges(u8);
impl Edges {
    fn update(&mut self, vk: u32, pressed: bool) -> (bool, Option<bool>) {
        let bit = match vk {
            0x80 => 1,
            0x81 => 2,
            _ => return (false, None),
        };
        let held = self.0 & bit != 0;
        if pressed {
            self.0 |= bit;
            (true, (!held).then_some(true))
        } else {
            self.0 &= !bit;
            (held, held.then_some(false))
        }
    }
}
struct Context {
    edges: Edges,
    sink: Sender<Event>,
    stopped: Arc<AtomicBool>,
    fault: Arc<AtomicBool>,
}
thread_local! { static CONTEXT:RefCell<Option<Context>>=const{RefCell::new(None)}; }
unsafe extern "system" fn callback(code: i32, message: usize, data: isize) -> isize {
    if code >= 0
        && matches!(
            message as u32,
            WM_KEYDOWN | WM_KEYUP | WM_SYSKEYDOWN | WM_SYSKEYUP
        )
    {
        let event = unsafe { &*(data as *const KBDLLHOOKSTRUCT) };
        let consume = CONTEXT.with(|slot| {
            let Ok(mut slot) = slot.try_borrow_mut() else {
                return false;
            };
            let Some(ctx) = slot.as_mut() else {
                return false;
            };
            if ctx.stopped.load(Ordering::Acquire) {
                return false;
            }
            let pressed = event.flags & LLKHF_UP == 0;
            let (consume, edge) = ctx.edges.update(event.vkCode, pressed);
            if let Some(pressed) = edge {
                if ctx
                    .sink
                    .try_send(Event {
                        vk: event.vkCode,
                        pressed,
                        target: crate::platform::foreground(),
                    })
                    .is_err()
                {
                    ctx.fault.store(true, Ordering::Release);
                    ctx.stopped.store(true, Ordering::Release);
                }
            }
            consume
        });
        if consume {
            return 1;
        }
    }
    unsafe { CallNextHookEx(std::ptr::null_mut(), code, message, data) }
}

pub struct VoiceKeyHook {
    stopped: Arc<AtomicBool>,
    pub fault: Arc<AtomicBool>,
    thread_id: Arc<AtomicU32>,
    done: mpsc::Receiver<()>,
    worker: Option<JoinHandle<()>>,
}
impl VoiceKeyHook {
    pub fn start() -> Result<(Self, Receiver<Event>), String> {
        let (sink, events) = channel(64);
        let stopped = Arc::new(AtomicBool::new(false));
        let fault = Arc::new(AtomicBool::new(false));
        let thread_id = Arc::new(AtomicU32::new(0));
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);
        let (done_tx, done) = mpsc::sync_channel(1);
        let (stop_worker, fault_worker, id_worker) =
            (stopped.clone(), fault.clone(), thread_id.clone());
        let worker = thread::Builder::new()
            .name("ahakey-voice-keys".into())
            .spawn(move || {
                unsafe {
                    id_worker.store(GetCurrentThreadId(), Ordering::Release);
                    let mut msg: MSG = std::mem::zeroed();
                    PeekMessageW(&mut msg, std::ptr::null_mut(), 0, 0, PM_NOREMOVE);
                    CONTEXT.with(|slot| {
                        *slot.borrow_mut() = Some(Context {
                            edges: Edges::default(),
                            sink,
                            stopped: stop_worker.clone(),
                            fault: fault_worker.clone(),
                        })
                    });
                    let hook = SetWindowsHookExW(
                        WH_KEYBOARD_LL,
                        Some(callback),
                        GetModuleHandleW(std::ptr::null()),
                        0,
                    );
                    if hook.is_null() {
                        let _ = ready_tx.send(Err(format!(
                            "无法安装 F17/F18 键盘钩子：{}",
                            std::io::Error::last_os_error()
                        )));
                    } else {
                        if ready_tx.send(Ok(())).is_err() {
                            stop_worker.store(true, Ordering::Release);
                        }
                        while !stop_worker.load(Ordering::Acquire) {
                            let result = GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0);
                            if result <= 0 {
                                if result < 0 {
                                    fault_worker.store(true, Ordering::Release);
                                }
                                break;
                            }
                            TranslateMessage(&msg);
                            DispatchMessageW(&msg);
                        }
                        UnhookWindowsHookEx(hook);
                    }
                    CONTEXT.with(|slot| {
                        slot.borrow_mut().take();
                    });
                }
                let _ = done_tx.send(());
            })
            .map_err(|e| e.to_string())?;
        let guard = Self {
            stopped,
            fault,
            thread_id,
            done,
            worker: Some(worker),
        };
        ready_rx
            .recv_timeout(Duration::from_secs(3))
            .map_err(|_| "键盘钩子启动超时".to_string())??;
        Ok((guard, events))
    }
}
impl Drop for VoiceKeyHook {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::Release);
        let id = self.thread_id.load(Ordering::Acquire);
        if id != 0 {
            unsafe {
                PostThreadMessageW(id, WM_QUIT, 0, 0);
            }
        }
        if self.done.recv_timeout(Duration::from_secs(1)).is_ok() {
            if let Some(worker) = self.worker.take() {
                let _ = worker.join();
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    #[ignore = "Controlled Windows F18 injection; no microphone or external shortcut is executed"]
    async fn native_hook_gets_physical_edges_and_consumes_async_fn_state() {
        use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
            keybd_event, GetAsyncKeyState, KEYEVENTF_KEYUP,
        };
        assert_eq!(
            unsafe { GetAsyncKeyState(0x81) } & i16::MIN,
            0,
            "Release F18 before this test"
        );
        let (hook, mut events) = VoiceKeyHook::start().unwrap();
        struct Release;
        impl Drop for Release {
            fn drop(&mut self) {
                unsafe { keybd_event(0x81, 0, KEYEVENTF_KEYUP, 0) }
            }
        }
        let release = Release;
        unsafe { keybd_event(0x81, 0, 0, 0) };
        let down = tokio::time::timeout(Duration::from_secs(2), events.recv())
            .await
            .unwrap()
            .unwrap();
        assert!(down.pressed);
        assert_eq!(down.vk, 0x81);
        tokio::time::sleep(Duration::from_millis(150)).await;
        assert!(events.try_recv().is_err(), "No release while still held");
        assert_eq!(
            unsafe { GetAsyncKeyState(0x81) } & i16::MIN,
            0,
            "Consumed F18 must not remain in the IME chord state"
        );
        drop(release);
        let up = tokio::time::timeout(Duration::from_secs(2), events.recv())
            .await
            .unwrap()
            .unwrap();
        assert!(!up.pressed);
        assert_eq!(up.vk, 0x81);
        assert!(!hook.fault.load(Ordering::Acquire));
        drop(hook);
    }
    #[test]
    fn consumes_one_press_and_real_release_without_repeat() {
        let mut e = Edges::default();
        assert_eq!(e.update(0x81, true), (true, Some(true)));
        assert_eq!(e.update(0x81, true), (true, None));
        assert_eq!(e.update(0x81, false), (true, Some(false)));
        assert_eq!(e.update(0x81, false), (false, None));
    }
    #[test]
    fn unrelated_typing_and_injected_wechat_modifiers_pass_through() {
        let mut e = Edges::default();
        for key in [0x41, 0x0d, 0x10, 0x11, 0x5b, 0xa0, 0xa2] {
            assert_eq!(e.update(key, true), (false, None));
        }
        assert_eq!(e.0, 0);
    }
    #[test]
    fn independent_voice_keys_do_not_lose_release() {
        let mut e = Edges::default();
        e.update(0x80, true);
        e.update(0x81, true);
        assert_eq!(e.update(0x80, false), (true, Some(false)));
        assert_eq!(e.update(0x81, false), (true, Some(false)));
    }
}
