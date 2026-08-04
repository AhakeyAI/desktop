// AhaKey Studio - Rust rewrite entry point
// 替代原 Java + JavaFX 实现,目标:
//   - 内存 200MB+ -> 15-30MB
//   - 启动 1-2s -> < 200ms
//   - 进程数 2 -> 1 (消灭 BLE_tcp_driver.exe)

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    ahakey_studio_lib::run();
}

