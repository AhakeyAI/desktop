//! BLE 通信模块
//!
//! Path A: btleplug 进程内直连 — 完全去除 `BLE_tcp_driver.exe` 外部进程,
//! 与原 Java 项目中的 `BleManager.java` + `SocketServer.java` + `BLE_tcp_driver.exe` 组合对等。
//!
//! 模块组成:
//! - `manager`: btleplug 高级 API(扫描/连接/断开/notify 订阅/周期查询)
//! - `transport`: BLE 帧编解码(发送请求/解析响应)
//! - `winrt`: Windows-only — 直接调 WinRT API 拿已配对设备列表
//!           (解决隐私模式下 btleplug 扫描不到 AhaKey 的问题)
//! - `usb_hid`: Windows-only — 直接调 WinRT HID API 连接 AhaKey USB 设备
//!           (VID 0x1EA7, PID 0x0064 — 当 BLE 不可用时,通过 USB-C 直连)
//!
//! 设计原则:扫描用 WinRT(系统级),连接优先 USB(更可靠),fallback 到 btleplug。

pub mod manager;
pub mod transport;
#[cfg(windows)]
pub mod winrt;
#[cfg(windows)]
pub mod usb_hid;

pub use manager::BleManager;
pub use transport::BleTransport;
