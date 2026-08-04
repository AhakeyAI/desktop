// 完整 Tauri commands — 用子模块隔离避开 __cmd__ macro reimport 错误
mod commands;
mod error;
mod model;
mod service;
mod state;
mod ble;
mod hook;
mod protocol;

use crate::state::AppState;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // 初始化 tracing — 输出到 stderr,RUST_LOG=info 控制
    let _ = tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .with_writer(std::io::stderr)
        .try_init();

    tauri::Builder::default()
        .setup(|app| {
            let app_handle = app.handle().clone();
            let state = AppState::new(app_handle).unwrap_or_else(|e| {
                eprintln!("[fatal] AppState::new failed: {:?}", e);
                std::process::exit(1);
            });
            app.manage(state);

            // Path A: BleManager 通过 AppState 自动跟随 Tauri state 生命周期,
            // notify consumer / 周期查询 task 由 connect_device 触发启动,无需在 setup 里启动。

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_studio_state,
            commands::get_ide_state,
            commands::get_oled_draft,
            commands::get_light_preview,
            commands::get_keys_for_mode,
            commands::get_all_keys,
            commands::scan_devices,
            commands::connect_device,
            commands::reconnect_last_device,
            commands::get_last_device,
            commands::disconnect_device,
            commands::force_cleanup_ble,
            commands::get_device_info,
            commands::get_version_info,
            commands::set_active_mode,
            commands::set_keys_for_mode,
            commands::update_key,
            commands::reset_keys_for_mode,
            commands::reset_all_keys,
            commands::apply_keys_to_device,
            commands::simulate_keypress,
            commands::update_light_preview,
            commands::clear_oled_preview,
            commands::update_oled_draft,
            commands::get_voice_route,
            commands::get_all_voice_routes,
            commands::install_hook,
            commands::uninstall_hook,
            commands::is_hook_running,
            commands::toggle_aha_type,
            commands::get_aha_type_status,
            commands::set_language,
            commands::get_language,
            commands::change_name,
            commands::save_config,
            commands::set_brightness,
            commands::preview_light_effect,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}