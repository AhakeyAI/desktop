//! AhaKey BLE 通信 — 走 BLE_tcp_bridge_v2 (127.0.0.1:9000)
//!
//! 设计:不再用 btleplug 直连 Windows BLE API,改为 TCP client 调 v2 bridge
//! (C# .NET 8 WinForms)。AhaKey 5A93 设备要求走这层。

pub mod manager;

pub use manager::BleManager;
