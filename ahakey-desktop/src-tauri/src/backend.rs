use crate::{
    caption::{self, Caption},
    settings::{self, Settings},
    state::{DownloadStatus, Runtime, Snapshot},
};
use std::{
    sync::{atomic::Ordering, Arc},
    time::Duration,
};
use tauri::{Emitter, Manager};
#[cfg(not(windows))]
use tauri_plugin_global_shortcut::GlobalShortcutExt;
use tauri_plugin_global_shortcut::{Code, Shortcut};
pub fn require_main(w: &tauri::WebviewWindow) -> Result<(), String> {
    if w.label() == "main" {
        Ok(())
    } else {
        Err("仅主窗口允许此操作".into())
    }
}
pub fn pulse(app: &tauri::AppHandle) {
    crate::tray::sync(app);
    let _ = app.emit("runtime-update", ());
}
pub async fn snapshot(app: &tauri::AppHandle) -> Result<Snapshot, String> {
    let s = app.state::<Runtime>();
    let ble = s.ble.lock().await.as_ref().map(|b| b.status());
    let usb = s.usb.lock().unwrap().clone();
    let device = crate::device::DeviceView::from_transports(&usb, ble.as_ref());
    // Match the supervisor's lock order and drop both guards before assembling
    // the snapshot. Struct-field temporaries otherwise retain the error lock.
    let (ble_recovery, ble_error) = {
        let recovery = s.ble_recovery.lock().unwrap();
        let error = s.ble_error.lock().unwrap();
        (recovery.status(), error.clone())
    };
    let (settings, settings_change_id) = {
        let settings = s.settings.lock().unwrap();
        (
            settings.clone(),
            s.settings_change_id.lock().unwrap().clone(),
        )
    };
    let (hook_port, hook_last_event) = {
        let h = s.hook.lock().unwrap();
        (
            h.as_ref().map(|v| v.port),
            h.as_ref().and_then(|v| v.last.lock().unwrap().clone()),
        )
    };
    let result = Ok(Snapshot {
        version: app.package_info().version.to_string(),
        platform: std::env::consts::OS.into(),
        settings,
        settings_change_id,
        settings_path: s.settings_path.to_string_lossy().into_owned(),
        settings_error: s.settings_error.clone(),
        settings_notice: s.settings_notice.lock().unwrap().clone(),
        foreground_caption_supported: cfg!(windows),
        speech_engine_ready: true,
        model_installed: s.model_store().is_installed(),
        model_directory: s.model_store().directory().to_string_lossy().into_owned(),
        native_key_test_supported: true,
        native_key_test_enabled: s.key_enabled.load(Ordering::SeqCst),
        key_observation: s.key_observation.lock().unwrap().clone(),
        key_write_notice: s.key_write_notice.lock().unwrap().clone(),
        ble_ready: ble
            .as_ref()
            .is_some_and(|b| b.phase == ahakey_ble::ConnectionPhase::Ready),
        ble,
        usb,
        device,
        ble_error,
        ble_recovery,
        devices: s.devices.lock().unwrap().clone(),
        caption: s.caption.lock().unwrap().clone(),
        speech: s.speech.lock().unwrap().clone(),
        download: s.download.lock().unwrap().clone(),
        cloud_configured: s.credentials().has_token().unwrap_or(false),
        hook_port,
        hook_last_event,
        auto_insert_supported: cfg!(windows),
    });
    result
}
#[tauri::command]
pub async fn get_snapshot(app: tauri::AppHandle) -> Result<Snapshot, String> {
    snapshot(&app).await
}
#[tauri::command]
pub async fn save_settings(
    window: tauri::WebviewWindow,
    settings: Settings,
    base: Option<Settings>,
    change_id: Option<String>,
) -> Result<Settings, String> {
    require_main(&window)?;
    apply_settings(
        window.app_handle(),
        SettingsEdit::Ui {
            settings: Box::new(settings),
            base: base.map(Box::new),
            change_id,
        },
    )
    .await
}
pub enum SettingsEdit {
    Ui {
        settings: Box<Settings>,
        base: Option<Box<Settings>>,
        change_id: Option<String>,
    },
    Provider(settings::Provider),
    Profile(String),
    ToggleCaptions,
}
pub async fn apply_settings(
    app: &tauri::AppHandle,
    edit: SettingsEdit,
) -> Result<Settings, String> {
    let state = app.state::<Runtime>();
    let _gate = state.settings_gate.lock().await;
    let previous = state.settings.lock().unwrap().clone();
    let (mut settings, change_id) = match edit {
        SettingsEdit::Ui {
            settings,
            base,
            change_id,
        } => {
            settings.validate()?;
            if change_id.as_ref().is_some_and(|id| id.len() > 128) {
                return Err("无效设置请求标识".into());
            }
            let next = if let Some(base) = base {
                Settings::merge_changes(&settings, &base, &previous)?
            } else {
                *settings
            };
            (next, change_id)
        }
        SettingsEdit::Provider(provider) => {
            let mut next = previous.clone();
            next.provider = provider;
            (next, None)
        }
        SettingsEdit::Profile(profile) => {
            let mut next = previous.clone();
            next.active_profile = profile;
            (next, None)
        }
        SettingsEdit::ToggleCaptions => {
            let mut next = previous.clone();
            next.captions_enabled = !next.captions_enabled;
            (next, None)
        }
    };
    settings.validate()?;
    if previous.provider != settings.provider
        || previous.trigger_mode != settings.trigger_mode
        || previous.microphone != settings.microphone
    {
        invalidate_keys(app);
        crate::voice::cancel(app).await;
    }
    {
        let mut current = state.settings.lock().unwrap();
        settings.saved_device = current.saved_device.clone();
        settings.voice_keys_enabled = current.voice_keys_enabled;
        settings::save(&state.settings_path, &settings)?;
        *current = settings.clone();
        *state.settings_change_id.lock().unwrap() = change_id;
    }
    if !settings.captions_enabled {
        if let Some(caption) = app.get_webview_window("caption") {
            let _ = caption.hide();
        }
    } else if !previous.captions_enabled {
        let current = state.caption.lock().unwrap().clone();
        if current.phase != "idle" {
            let _ = display_caption(app, &current.phase, &current.text, false);
        }
    }
    let client = state.ble.lock().await.clone();
    let device_change = previous.active_profile != settings.active_profile
        || previous.light_brightness != settings.light_brightness;
    let mut notice = "本机偏好已自动保存并生效".to_string();
    if device_change {
        if let Some(client) =
            client.filter(|c| c.status().phase == ahakey_ble::ConnectionPhase::Ready)
        {
            let result = async {
                if previous.active_profile != settings.active_profile {
                    let mode = settings
                        .profiles
                        .iter()
                        .position(|p| p.id == settings.active_profile)
                        .unwrap_or(0) as u8;
                    client.set_work_mode(mode).await?;
                }
                if previous.light_brightness != settings.light_brightness {
                    client
                        .set_light_brightness(settings.light_brightness)
                        .await?;
                }
                client.query_status().await
            }
            .await;
            notice = match result {
                Ok(()) => "本机偏好已保存；模式 / 亮度已应用到键盘".into(),
                Err(e) => format!("本机已保存，但设备更新失败：{e}"),
            };
        } else {
            notice = "本机已保存；蓝牙写入通道未就绪，设备模式 / 亮度未更新。USB 状态读取不受影响"
                .into();
        }
    }
    *state.settings_notice.lock().unwrap() = notice;
    pulse(app);
    Ok(settings)
}
pub fn position_caption(app: &tauri::AppHandle, offset: u32) -> Result<(), String> {
    let window = app.get_webview_window("caption").ok_or("字幕窗口未就绪")?;
    let state = app.state::<Runtime>();
    #[cfg(windows)]
    let p = {
        use windows_sys::Win32::{
            Graphics::Gdi::{
                GetMonitorInfoW, MonitorFromPoint, MonitorFromWindow, MONITORINFO,
                MONITOR_DEFAULTTONEAREST,
            },
            UI::WindowsAndMessaging::{GetCursorPos, IsWindow},
        };
        let target = *state.caption_target.lock().unwrap();
        let monitor = if let Some(target) = target.filter(|h| unsafe { IsWindow(*h as _) != 0 }) {
            unsafe { MonitorFromWindow(target as _, MONITOR_DEFAULTTONEAREST) }
        } else {
            let mut cursor = windows_sys::Win32::Foundation::POINT { x: 0, y: 0 };
            if unsafe { GetCursorPos(&mut cursor) } == 0 {
                return Err("无法读取鼠标所在屏幕".into());
            }
            unsafe { MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST) }
        };
        let mut info: MONITORINFO = unsafe { std::mem::zeroed() };
        info.cbSize = std::mem::size_of::<MONITORINFO>() as u32;
        if unsafe { GetMonitorInfoW(monitor, &mut info) } == 0 {
            return Err("无法读取目标屏幕".into());
        }
        let scale = window
            .available_monitors()
            .map_err(|e| e.to_string())?
            .into_iter()
            .find(|m| m.position().x == info.rcMonitor.left && m.position().y == info.rcMonitor.top)
            .map(|m| m.scale_factor())
            .ok_or("无法读取目标屏幕缩放比例")?;
        caption::place(
            info.rcWork.left,
            info.rcWork.top,
            info.rcWork.right,
            info.rcWork.bottom,
            scale,
            offset,
        )
    };
    #[cfg(not(windows))]
    let p = {
        let m = window
            .primary_monitor()
            .map_err(|e| e.to_string())?
            .ok_or("无显示器")?;
        let a = m.work_area();
        caption::place(
            a.position.x,
            a.position.y,
            a.position.x + a.size.width as i32,
            a.position.y + a.size.height as i32,
            m.scale_factor(),
            offset,
        )
    };
    // Move first: WM_DPICHANGED may resize the window during a monitor change.
    window
        .set_position(tauri::PhysicalPosition::new(p.x, p.y))
        .map_err(|e| e.to_string())?;
    window
        .set_size(tauri::PhysicalSize::new(p.width, p.height))
        .map_err(|e| e.to_string())?;
    *state.caption_placement.lock().unwrap() = Some(p);
    Ok(())
}
pub fn display_caption(
    app: &tauri::AppHandle,
    phase: &str,
    text: &str,
    auto_hide: bool,
) -> Result<Caption, String> {
    let state = app.state::<Runtime>();
    if phase != "idle" {
        let offset = state.settings.lock().unwrap().caption_bottom_offset;
        position_caption(app, offset)?;
    }
    let next = {
        let mut c = state.caption.lock().unwrap();
        c.sequence += 1;
        c.phase = phase.into();
        c.text = text.into();
        c.clone()
    };
    app.emit("caption-update", &next)
        .map_err(|e| e.to_string())?;
    if let Some(w) = app.get_webview_window("caption") {
        if phase == "idle" || !state.settings.lock().unwrap().captions_enabled {
            let _ = w.hide();
        } else {
            let _ = w.set_ignore_cursor_events(true);
            let _ = w.show();
        }
    }
    if auto_hide {
        let app = app.clone();
        let sequence = next.sequence;
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(Duration::from_secs(6)).await;
            let state = app.state::<Runtime>();
            if state.caption.lock().unwrap().sequence == sequence {
                if let Some(w) = app.get_webview_window("caption") {
                    let _ = w.hide();
                }
            }
        });
    }
    Ok(next)
}
#[tauri::command]
pub fn test_caption(
    window: tauri::WebviewWindow,
    pressed: bool,
    target_window: Option<usize>,
) -> Result<Caption, String> {
    require_main(&window)?;
    let app = window.app_handle();
    if app.state::<Runtime>().recording.load(Ordering::SeqCst) {
        return Err("录音期间不运行字幕测试".into());
    }
    if pressed {
        #[cfg(windows)]
        {
            *app.state::<Runtime>().caption_target.lock().unwrap() =
                target_window.or_else(|| window.hwnd().ok().map(|h| h.0 as usize));
        }
        #[cfg(not(windows))]
        {
            let _ = target_window;
        }
        let offset = app
            .state::<Runtime>()
            .settings
            .lock()
            .unwrap()
            .caption_bottom_offset;
        position_caption(app, offset)?;
    }
    display_caption(
        app,
        if pressed { "preview" } else { "idle" },
        if pressed {
            "字幕位置测试 · 未录音"
        } else {
            "字幕测试完成"
        },
        pressed,
    )
}
pub fn preview_caption(app: &tauri::AppHandle) -> Result<(), String> {
    let state = app.state::<Runtime>();
    let existing = state.caption.lock().unwrap().clone();
    let active = state.recording.load(Ordering::SeqCst)
        || state.speech.lock().unwrap().phase == "transcribing";
    if active && existing.phase != "idle" {
        display_caption(app, &existing.phase, &existing.text, false)?;
    } else {
        if !active {
            *state.caption_target.lock().unwrap() = crate::platform::last_external_window();
        }
        display_caption(
            app,
            "preview",
            "字幕位置预览 · 本地 / 云端识别时跟随目标输入窗口",
            true,
        )?;
    }
    Ok(())
}
#[tauri::command]
pub fn caption_diagnostics(window: tauri::WebviewWindow) -> Result<serde_json::Value, String> {
    require_main(&window)?;
    let app = window.app_handle();
    let state = app.state::<Runtime>();
    let caption = app.get_webview_window("caption").ok_or("字幕窗口不可用")?;
    let requested = state.caption_placement.lock().unwrap().clone();
    #[cfg(windows)]
    let foreground =
        Some(
            unsafe { windows_sys::Win32::UI::WindowsAndMessaging::GetForegroundWindow() } as usize,
        );
    #[cfg(not(windows))]
    let foreground: Option<usize> = None;
    Ok(
        serde_json::json!({"requested":requested,"actualPosition":caption.outer_position().map_err(|e|e.to_string())?,"actualSize":caption.outer_size().map_err(|e|e.to_string())?,"focused":caption.is_focused().map_err(|e|e.to_string())?,"visible":caption.is_visible().map_err(|e|e.to_string())?,"foregroundWindow":foreground,"monitors":caption.available_monitors().map_err(|e|e.to_string())?.into_iter().map(|m|serde_json::json!({"position":m.position(),"size":m.size(),"scale":m.scale_factor()})).collect::<Vec<_>>()}),
    )
}
#[tauri::command]
pub fn dismiss_caption(window: tauri::WebviewWindow) -> Result<(), String> {
    require_main(&window)?;
    display_caption(window.app_handle(), "idle", "", false)?;
    Ok(())
}
#[tauri::command]
pub async fn start_speech(window: tauri::WebviewWindow) -> Result<(), String> {
    require_main(&window)?;
    crate::voice::start(window.app_handle().clone(), None, None, None).await
}
#[tauri::command]
pub async fn finish_speech(window: tauri::WebviewWindow) -> Result<(), String> {
    require_main(&window)?;
    crate::voice::finish(window.app_handle().clone()).await
}
#[tauri::command]
pub async fn cancel_speech(window: tauri::WebviewWindow) -> Result<(), String> {
    require_main(&window)?;
    invalidate_keys(window.app_handle());
    crate::voice::cancel(window.app_handle()).await;
    pulse(window.app_handle());
    Ok(())
}
#[tauri::command]
pub async fn set_key_test(window: tauri::WebviewWindow, enabled: bool) -> Result<(), String> {
    require_main(&window)?;
    let app = window.app_handle();
    let state = app.state::<Runtime>();
    let _settings_gate = state.settings_gate.lock().await;
    if state.key_enabled.load(Ordering::SeqCst) == enabled
        && state.settings.lock().unwrap().voice_keys_enabled == enabled
    {
        return Ok(());
    }
    if enabled && crate::platform::java_running() {
        return Err("JavaFX AhaKey 仍在运行，请退出它后启用 Rust 语音键，避免双重触发".into());
    }
    if enabled {
        if !state.key_enabled.load(Ordering::SeqCst) {
            register_voice_keys(app)?;
        }
    } else {
        state.key_enabled.store(false, Ordering::SeqCst);
        unregister_voice_keys(app);
        invalidate_keys(app);
        crate::voice::cancel(app).await;
    }
    state.key_enabled.store(enabled, Ordering::SeqCst);
    let persisted = {
        let mut settings = state.settings.lock().unwrap();
        let mut next = settings.clone();
        next.voice_keys_enabled = enabled;
        settings::save(&state.settings_path, &next).map(|()| {
            *settings = next;
        })
    };
    if let Err(error) = persisted {
        state.key_enabled.store(false, Ordering::SeqCst);
        unregister_voice_keys(app);
        crate::voice::cancel(app).await;
        pulse(app);
        return Err(format!("语音键已停用，但无法保存开关：{error}"));
    }
    pulse(app);
    Ok(())
}
fn unregister_voice_keys(app: &tauri::AppHandle) {
    #[cfg(windows)]
    {
        app.state::<Runtime>()
            .windows_voice_hook
            .lock()
            .unwrap()
            .take();
    }
    #[cfg(not(windows))]
    {
        let _ = app.global_shortcut().unregister_all();
    }
}
fn register_voice_keys(app: &tauri::AppHandle) -> Result<(), String> {
    #[cfg(windows)]
    {
        let (hook, mut events) = crate::windows_voice_keys::VoiceKeyHook::start()?;
        let fault = hook.fault.clone();
        *app.state::<Runtime>().windows_voice_hook.lock().unwrap() = Some(hook);
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            while let Some(event) = events.recv().await {
                if fault.load(Ordering::Acquire) {
                    break;
                }
                let code = if event.vk == 0x80 {
                    Code::F17
                } else {
                    Code::F18
                };
                key_event_target(
                    &app,
                    Shortcut::new(None, code).id(),
                    event.pressed,
                    event.target,
                );
            }
            if fault.load(Ordering::Acquire) {
                app.state::<Runtime>()
                    .key_enabled
                    .store(false, Ordering::SeqCst);
                invalidate_keys(&app);
                unregister_voice_keys(&app);
                crate::voice::cancel(&app).await;
                let _ = app.emit("native-error", "语音键监听中断，已停止语音；请重新启用监听");
                pulse(&app);
            }
        });
    }
    #[cfg(not(windows))]
    {
        for code in [Code::F17, Code::F18] {
            if let Err(error) = app.global_shortcut().register(Shortcut::new(None, code)) {
                unregister_voice_keys(app);
                return Err(error.to_string());
            }
        }
    }
    Ok(())
}
pub fn key_event(app: &tauri::AppHandle, id: u32, pressed: bool) {
    key_event_target(app, id, pressed, crate::platform::foreground());
}
fn key_event_target(app: &tauri::AppHandle, id: u32, pressed: bool, target: Option<usize>) {
    let state = app.state::<Runtime>();
    if !state.key_enabled.load(Ordering::SeqCst)
        || state.closing.load(Ordering::SeqCst)
        || state.key_write_busy.load(Ordering::SeqCst)
    {
        return;
    }
    {
        let mut observed = state.key_observation.lock().unwrap();
        observed.events += 1;
        observed.key = if id == Shortcut::new(None, Code::F17).id() {
            "F17"
        } else {
            "F18"
        }
        .into();
        observed.pressed = pressed;
    }
    pulse(app);
    let down = {
        let mut keys = state.keys_down.lock().unwrap();
        if pressed {
            keys.insert(id);
        } else {
            keys.remove(&id);
        }
        !keys.is_empty()
    };
    let mode = state.settings.lock().unwrap().trigger_mode.clone();
    let action = state.key_state.lock().unwrap().update(down, mode);
    if let Some(start) = action {
        let epoch = state.key_epoch.load(Ordering::SeqCst);
        let sequence = state.key_sequence.fetch_add(1, Ordering::SeqCst) + 1;
        let accepted = state
            .key_actions
            .lock()
            .unwrap()
            .as_ref()
            .is_some_and(|tx| tx.try_send((epoch, sequence, start, target)).is_ok());
        if !accepted {
            state.key_enabled.store(false, Ordering::SeqCst);
            invalidate_keys(app);
            let stop_app = app.clone();
            tauri::async_runtime::spawn(async move {
                crate::voice::cancel(&stop_app).await;
                pulse(&stop_app);
            });
            unregister_voice_keys(app);
            let _ = app.emit("native-error", "语音键队列已满，已安全停止，请重新启用");
        }
    }
}
pub fn invalidate_keys(app: &tauri::AppHandle) {
    let s = app.state::<Runtime>();
    s.key_epoch.fetch_add(1, Ordering::SeqCst);
    s.keys_down.lock().unwrap().clear();
    s.key_state.lock().unwrap().stop();
}
pub fn initialize_keys(app: &tauri::AppHandle) {
    let (tx, mut rx) = tokio::sync::mpsc::channel(32);
    *app.state::<Runtime>().key_actions.lock().unwrap() = Some(tx);
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        while let Some((epoch, sequence, start, target)) = rx.recv().await {
            let s = app.state::<Runtime>();
            if !s.key_enabled.load(Ordering::SeqCst) || s.key_epoch.load(Ordering::SeqCst) != epoch
            {
                continue;
            }
            let reject_stale_start = {
                let settings = s.settings.lock().unwrap();
                start
                    && settings.provider == settings::Provider::Wechat
                    && settings.trigger_mode == settings::TriggerMode::Hold
            };
            let result = if start {
                crate::voice::start(
                    app.clone(),
                    target,
                    Some(epoch),
                    reject_stale_start.then_some(sequence),
                )
                .await
            } else {
                crate::voice::finish(app.clone()).await
            };
            if let Err(error) = result {
                let _ = app.emit("native-error", error);
            }
        }
    });
}
#[tauri::command]
pub async fn microphone_devices(window: tauri::WebviewWindow) -> Result<Vec<String>, String> {
    require_main(&window)?;
    tauri::async_runtime::spawn_blocking(|| {
        ahakey_speech::input_devices().map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
pub async fn prepare_model(
    window: tauri::WebviewWindow,
    source: Option<String>,
) -> Result<(), String> {
    require_main(&window)?;
    let app = window.app_handle().clone();
    let state = app.state::<Runtime>();
    if state.recording.load(Ordering::SeqCst) {
        return Err("请先停止录音".into());
    }
    let cancel = ahakey_speech::CancellationToken::new();
    {
        let mut active = state.transfer.lock().unwrap();
        if active.is_some() {
            return Err("模型操作正在进行".into());
        }
        *active = Some(cancel.clone());
    }
    *state.download.lock().unwrap() = DownloadStatus {
        busy: true,
        progress: 0.0,
        message: "正在准备模型…".into(),
    };
    pulse(&app);
    let dir = state.model_store().directory().to_path_buf();
    let worker_app = app.clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        let store = ahakey_speech::ModelStore::new(dir);
        let progress = |fraction: f64| {
            let s = worker_app.state::<Runtime>();
            let mut p = s.download.lock().unwrap();
            let changed = (p.progress - fraction).abs() >= 0.01 || fraction >= 1.0;
            p.progress = fraction;
            drop(p);
            if changed {
                pulse(&worker_app)
            }
        };
        if let Some(path) = source {
            store.import_from(std::path::Path::new(&path), &cancel, progress)
        } else {
            store.download(&cancel, progress)
        }
    })
    .await
    .map_err(|e| e.to_string())
    .and_then(|r| r.map_err(|e| e.to_string()));
    state.transfer.lock().unwrap().take();
    {
        let mut p = state.download.lock().unwrap();
        p.busy = false;
        p.message = match &result {
            Ok(_) => "模型已校验，可开始识别".into(),
            Err(e) => format!("模型操作未完成：{e}"),
        };
    }
    pulse(&app);
    result.map(|_| ())
}
#[tauri::command]
pub fn cancel_model(window: tauri::WebviewWindow) -> Result<(), String> {
    require_main(&window)?;
    if let Some(token) = window.state::<Runtime>().transfer.lock().unwrap().as_ref() {
        token.cancel()
    }
    Ok(())
}
#[tauri::command]
pub fn save_cloud_token(window: tauri::WebviewWindow, token: String) -> Result<(), String> {
    require_main(&window)?;
    window
        .state::<Runtime>()
        .credentials()
        .save(&token)
        .map_err(|e| e.to_string())?;
    pulse(window.app_handle());
    Ok(())
}
#[tauri::command]
pub fn clear_cloud_token(window: tauri::WebviewWindow) -> Result<(), String> {
    require_main(&window)?;
    window
        .state::<Runtime>()
        .credentials()
        .clear()
        .map_err(|e| e.to_string())?;
    pulse(window.app_handle());
    Ok(())
}
pub async fn ble_client(app: &tauri::AppHandle) -> Result<Arc<ahakey_ble::BleClient>, String> {
    let state = app.state::<Runtime>();
    let _gate = state.ble_initialization.lock().await;
    if let Some(client) = state.ble.lock().await.as_ref() {
        return Ok(client.clone());
    }
    let client = ahakey_ble::BleClient::new().await.map_err(|e| {
        let m = e.to_string();
        *state.ble_error.lock().unwrap() = Some(m.clone());
        m
    })?;
    let mut events = client.subscribe();
    let app_events = app.clone();
    tauri::async_runtime::spawn(async move {
        loop {
            match events.recv().await {
                Ok(ahakey_ble::BleEvent::Devices(devices)) => {
                    *app_events.state::<Runtime>().devices.lock().unwrap() = devices;
                    pulse(&app_events);
                }
                Ok(ahakey_ble::BleEvent::State(_)) => pulse(&app_events),
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(_) => break,
            }
        }
    });
    *state.ble.lock().await = Some(client.clone());
    *state.ble_error.lock().unwrap() = None;
    Ok(client)
}
#[tauri::command]
pub async fn scan_devices(
    window: tauri::WebviewWindow,
) -> Result<Vec<ahakey_ble::DeviceInfo>, String> {
    require_main(&window)?;
    if crate::platform::java_running() {
        return Err("请先退出 JavaFX AhaKey，再由 Rust 管理蓝牙".into());
    }
    let state = window.state::<Runtime>();
    let _gate = state.ble_connection_gate.lock().await;
    ble_client(window.app_handle())
        .await?
        .scan(Duration::from_secs(4))
        .await
        .map_err(|e| e.to_string())
}
#[tauri::command]
pub async fn connect_device(window: tauri::WebviewWindow, id: String) -> Result<(), String> {
    require_main(&window)?;
    if id.is_empty() || id.len() > 4096 {
        return Err("设备标识无效".into());
    }
    crate::recovery::connect(window.app_handle(), id).await
}
pub async fn restore_device_preferences(app: &tauri::AppHandle, client: &ahakey_ble::BleClient) {
    let state = app.state::<Runtime>();
    let _gate = state.settings_gate.lock().await;
    let settings = state.settings.lock().unwrap().clone();
    let Some(status) = client.status().status else {
        return;
    };
    let mode = settings
        .profiles
        .iter()
        .position(|p| p.id == settings.active_profile)
        .unwrap_or(0) as u8;
    let result = async {
        if mode != status.work_mode {
            client.set_work_mode(mode).await?;
        }
        if settings.light_brightness != status.light_brightness {
            client
                .set_light_brightness(settings.light_brightness)
                .await?;
        }
        client.query_status().await
    }
    .await;
    *state.settings_notice.lock().unwrap() = match result {
        Ok(()) => "已连接；保存的模式 / 亮度已应用，未覆盖完整键位配置".into(),
        Err(e) => format!("已连接，但保存的设备偏好应用失败：{e}"),
    };
}
#[tauri::command]
pub async fn disconnect_device(window: tauri::WebviewWindow) -> Result<(), String> {
    require_main(&window)?;
    crate::recovery::disconnect(window.app_handle()).await
}
struct KeyWriteGuard<'a>(&'a std::sync::atomic::AtomicBool);
impl Drop for KeyWriteGuard<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::SeqCst);
    }
}

fn profile_keys(
    profile: &settings::Profile,
    mode: usize,
) -> Result<[ahakey_ble::KeyConfig; 4], String> {
    let bindings = if profile.keys.is_empty() {
        crate::keys::defaults(&profile.accept, &profile.reject)
    } else {
        profile.keys.clone()
    };
    let keys: Vec<_> = bindings
        .iter()
        .map(|key| {
            Ok(ahakey_ble::KeyConfig {
                hid_codes: key.hid(mode)?,
                description: key.label.clone(),
            })
        })
        .collect::<Result<_, String>>()?;
    keys.try_into().map_err(|_| "需要四个按键定义".into())
}
#[tauri::command]
pub async fn write_current_keys(
    window: tauri::WebviewWindow,
    confirmed: bool,
) -> Result<(), String> {
    require_main(&window)?;
    if !confirmed {
        return Err("请先确认覆盖当前模式的四个按键；其他模式和灯效不会修改".into());
    }
    let app = window.app_handle();
    let state = app.state::<Runtime>();
    let settings = state.settings.lock().unwrap().clone();
    settings.validate()?;
    if state.recording.load(Ordering::SeqCst) {
        return Err("请先结束语音，再写入按键".into());
    }
    if state.key_write_busy.swap(true, Ordering::SeqCst) {
        return Err("按键写入正在进行".into());
    }
    let _write_guard = KeyWriteGuard(&state.key_write_busy);
    invalidate_keys(app);
    crate::voice::cancel(app).await;
    let mode = settings
        .profiles
        .iter()
        .position(|p| p.id == settings.active_profile)
        .ok_or("未选择模式")?;
    let keys = profile_keys(&settings.profiles[mode], mode)?;
    *state.key_write_notice.lock().unwrap() =
        format!("正在写入 {} 的四键…", settings.profiles[mode].name);
    pulse(app);
    let result = async {
        ble_client(app)
            .await?
            .save_keys(mode as u8, &keys)
            .await
            .map_err(|e| e.to_string())
    }
    .await;
    *state.key_write_notice.lock().unwrap() = match &result {
        Ok(()) => format!(
            "{} 四键已发送并保存；请按实物键验证。其他模式和灯效未修改",
            settings.profiles[mode].name
        ),
        Err(e) => format!("四键写入未完成，部分写入可能已生效：{e}；重连后可重试"),
    };
    pulse(app);
    result
}
#[tauri::command]
pub async fn write_profiles(window: tauri::WebviewWindow) -> Result<(), String> {
    require_main(&window)?;
    let app = window.app_handle();
    let state = app.state::<Runtime>();
    let settings = state.settings.lock().unwrap().clone();
    settings.validate()?;
    if state.recording.load(Ordering::SeqCst) {
        return Err("请先结束语音，再写入按键".into());
    }
    if state.key_write_busy.swap(true, Ordering::SeqCst) {
        return Err("按键写入正在进行".into());
    }
    let _write_guard = KeyWriteGuard(&state.key_write_busy);
    invalidate_keys(app);
    crate::voice::cancel(app).await;
    let profiles: Vec<_> = settings
        .profiles
        .iter()
        .enumerate()
        .map(|(i, p)| {
            Ok(ahakey_ble::ProfileConfig {
                keys: profile_keys(p, i)?,
                light_effects: p.light_effects.to_vec(),
            })
        })
        .collect::<Result<_, String>>()?;
    let profiles: [ahakey_ble::ProfileConfig; 4] =
        profiles.try_into().map_err(|_| "需要四个模式")?;
    let active = settings
        .profiles
        .iter()
        .position(|p| p.id == settings.active_profile)
        .unwrap_or(0) as u8;
    ble_client(app)
        .await?
        .save_profiles(&profiles, active, settings.light_brightness)
        .await
        .map_err(|e| e.to_string())
}
#[tauri::command]
pub async fn test_light(window: tauri::WebviewWindow, effect: u8) -> Result<(), String> {
    require_main(&window)?;
    if effect > 16 {
        return Err("不支持的灯效".into());
    }
    ble_client(window.app_handle())
        .await?
        .set_light_effect(effect)
        .await
        .map_err(|e| e.to_string())
}
#[tauri::command]
pub async fn set_hooks(window: tauri::WebviewWindow, enabled: bool) -> Result<(), String> {
    require_main(&window)?;
    let app = window.app_handle().clone();
    let state = app.state::<Runtime>();
    if !enabled {
        state.hook.lock().unwrap().take();
        pulse(&app);
        return Ok(());
    }
    if state.hook.lock().unwrap().is_some() {
        return Ok(());
    }
    let home = app
        .path()
        .home_dir()
        .map_err(|e| e.to_string())?
        .join(".ahakey/hooks");
    let target = app.clone();
    let server = crate::hooks::start(home, move |_name, event| {
        let app = target.clone();
        tauri::async_runtime::spawn(async move {
            let client = app.state::<Runtime>().ble.lock().await.clone();
            if let Some(client) = client {
                let _ = client.set_ide_state(event).await;
            }
            pulse(&app);
        });
    })?;
    *state.hook.lock().unwrap() = Some(server);
    pulse(&app);
    Ok(())
}
pub fn request_shutdown(app: &tauri::AppHandle) {
    let state = app.state::<Runtime>();
    if state.closing.swap(true, Ordering::SeqCst) {
        return;
    }
    state.ble_recovery.lock().unwrap().pause();
    state.key_enabled.store(false, Ordering::SeqCst);
    unregister_voice_keys(app);
    let foreground_hook = state.foreground_hook.swap(0, Ordering::SeqCst);
    let _ = app.run_on_main_thread(move || {
        crate::platform::stop_foreground_watch(foreground_hook as usize)
    });
    state.hook.lock().unwrap().take();
    if let Some(cancel) = state.transfer.lock().unwrap().as_ref() {
        cancel.cancel()
    }
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        crate::voice::cancel(&app).await;
        let client = app.state::<Runtime>().ble.lock().await.take();
        if let Some(client) = client {
            let _ = tokio::time::timeout(Duration::from_secs(10), client.disconnect()).await;
        }
        app.exit(0);
    });
}
