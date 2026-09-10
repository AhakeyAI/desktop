#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod backend;
mod caption;
mod device;
mod device_routing;
mod hooks;
mod input;
mod keys;
mod platform;
mod quota;
mod recovery;
mod settings;
mod state;
mod tray;
mod voice;
#[cfg(windows)]
mod windows_voice_keys;
use backend::*;
use std::sync::atomic::Ordering;
use tauri::Manager;
use tray::{quick_action, tray_status};
fn main() {
    tauri::Builder::default()
        .manage(quota::Service::default())
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    key_event(
                        app,
                        shortcut.id(),
                        event.state() == tauri_plugin_global_shortcut::ShortcutState::Pressed,
                    );
                })
                .build(),
        )
        .setup(|app| {
            let path = app.path().app_config_dir()?.join("settings.json");
            let (settings, error) = match settings::load_for_launch(&path) {
                Ok(s) => (s, None),
                Err(e) => (settings::Settings::default(), Some(e)),
            };
            let restore_voice_keys = settings.start_voice_keys(error.is_some());
            app.manage(state::Runtime::new(
                settings,
                path,
                error,
                app.path().app_data_dir()?,
            ));
            initialize_keys(app.handle());
            app.state::<state::Runtime>()
                .foreground_hook
                .store(platform::watch_foreground() as u64, Ordering::SeqCst);
            if restore_voice_keys {
                let handle = app.handle().clone();
                tauri::async_runtime::spawn(async move {
                    if let Some(window) = handle.get_webview_window("main") {
                        if let Err(error) = set_key_test(window, true).await {
                            *handle
                                .state::<state::Runtime>()
                                .settings_notice
                                .lock()
                                .unwrap() = format!("语音键未开启：{error}");
                            pulse(&handle);
                        }
                    }
                });
            }
            tray::install(app)?;
            recovery::start(app.handle());
            device::start(app.handle());
            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() == "main" {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let state = window.state::<state::Runtime>();
                    if state.tray.load(Ordering::SeqCst)
                        && state.settings.lock().unwrap().minimize_to_tray
                    {
                        let _ = window.hide();
                    } else {
                        request_shutdown(window.app_handle());
                    }
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_snapshot,
            device_routing::get_device_routing,
            device_routing::set_device_routing,
            quota::get_cards,
            quota::save_cards,
            quota::save_quota_key,
            quota::clear_quota_key,
            quota::refresh_quota,
            save_settings,
            test_caption,
            caption_diagnostics,
            quick_action,
            tray_status,
            dismiss_caption,
            set_key_test,
            start_speech,
            finish_speech,
            cancel_speech,
            microphone_devices,
            prepare_model,
            cancel_model,
            save_cloud_token,
            clear_cloud_token,
            scan_devices,
            connect_device,
            disconnect_device,
            recovery::test_ble_link_loss,
            write_profiles,
            write_current_keys,
            test_light,
            set_hooks
        ])
        .run(tauri::generate_context!())
        .expect("Unable to launch AhaKey Studio");
}
