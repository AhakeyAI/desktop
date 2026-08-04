//! 键盘钩子模块
//!
//! 替代原 Java 项目的 `WindowsVoiceRelayService.java` + `WindowsVoiceTyping.java` + `HookClient.java` 等。
//!
//! 实现:
//! - `KeyboardHook`: 低级别键盘钩子 (WH_KEYBOARD_LL),通过 `windows-rs` 直接 FFI 调用
//! - `KeyboardInjector`: `SendInput` 模拟按键
//! - `VoiceRelay`: 路由匹配:按下语音键 → 触发 Win+H(HID 0x83 + GUI)
//!
//! 内存占用: 共享进程内存,无 JNA 跨语言边界。

pub mod hook;
pub mod injector;
pub mod relay;

pub use hook::{KeyboardHook, KeyEvent};
pub use injector::KeyboardInjector;
pub use relay::VoiceRelay;

