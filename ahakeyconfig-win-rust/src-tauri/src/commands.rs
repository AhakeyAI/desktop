// All Tauri commands, in one submodule to avoid __cmd__ macro reimport
use crate::error::{AppError, AppResult};
use crate::model::{
    IDEState, KeyCodeBinding, KeyConfig, LightBarPreviewState, OledModeDraft,
    ScanResult, StudioState, VoicePreset,
};
use crate::service::{device_info, voice_route};
use crate::state::AppState;
use serde::Deserialize;
use tauri::{AppHandle, Emitter, State};

// ====================== 状态查询 ======================

#[tauri::command]
pub fn get_studio_state(state: State<AppState>) -> StudioState {
    tracing::info!("[cmd] get_studio_state called");
    state.get_studio_state()
}

#[tauri::command]
pub fn get_ide_state(state: State<AppState>) -> IDEState {
    state.get_ide_state()
}

#[tauri::command]
pub fn get_oled_draft(state: State<AppState>) -> OledModeDraft {
    state.get_oled_draft()
}

#[tauri::command]
pub fn get_light_preview(state: State<AppState>) -> LightBarPreviewState {
    state.get_light_preview()
}

#[tauri::command]
pub fn get_keys_for_mode(mode: u8, state: State<AppState>) -> Vec<KeyConfig> {
    state.get_keys_for_mode(mode)
}

#[tauri::command]
pub fn get_all_keys(state: State<AppState>) -> Vec<KeyConfig> {
    let mode = state.get_studio_state().active_mode;
    state.get_keys_for_mode(mode)
}

// ====================== 设备 / BLE ======================

#[tauri::command]
pub async fn scan_devices(state: State<'_, AppState>) -> AppResult<Vec<ScanResult>> {
    tracing::info!("[cmd] scan_devices called");
    let _guard = state.ble_lock.lock().await;
    state.ble.scan().await
}

#[tauri::command]
pub async fn connect_device(
    address: String,
    name: String,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    tracing::info!("[cmd] connect_device called: address={}, name={}", address, name);
    let _guard = state.ble_lock.lock().await;
    if address.is_empty() {
        return Err(AppError::Other("device address is empty".to_string()));
    }
    // 真实 BLE 连接:subscribe notify + spawn 周期查询任务
    // connect() 返回从 GATT Device Name 特征读取的真实设备名
    let real_name = state.ble.connect(&address, &name).await?;
    tracing::info!("[cmd] connected, real device name: '{}'", real_name);
    // 更新 AppState 连接状态 + emit 前端(使用真实设备名)
    state.set_connected(address.clone(), real_name.clone());
    // 持久化最近连接设备 — 下次启动可一键重连
    let _ = crate::service::config_store::save_last_device(
        &crate::service::config_store::LastDevice {
            address: address.clone(),
            name: real_name.clone(),
        },
    );
    let _ = app.emit("device-status-changed", &*state.state.read().unwrap());
    Ok(())
}

/// 主动重连上次成功连接的设备。
/// 解决隐私模式设备扫描不到的问题 — 用持久化的 MAC 强制触发。
#[tauri::command]
pub async fn reconnect_last_device(
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    let last = crate::service::config_store::load_last_device()
        .ok_or_else(|| AppError::Other("no last device saved".to_string()))?;
    tracing::info!(
        "[cmd] reconnect_last_device: address={}, name={}",
        last.address,
        last.name
    );
    let _guard = state.ble_lock.lock().await;
    let real_name = state.ble.connect(&last.address, &last.name).await?;
    state.set_connected(last.address.clone(), real_name.clone());
    let _ = app.emit("device-status-changed", &*state.state.read().unwrap());
    Ok(())
}

/// 读取最近连接的设备(用于 UI 一键重连按钮)
#[tauri::command]
pub fn get_last_device() -> Option<crate::service::config_store::LastDevice> {
    crate::service::config_store::load_last_device()
}

#[tauri::command]
pub async fn disconnect_device(
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    let _guard = state.ble_lock.lock().await;
    state.ble.disconnect().await?;
    state.set_disconnected();
    let _ = app.emit("device-status-changed", &*state.state.read().unwrap());
    Ok(())
}

#[tauri::command]
pub async fn force_cleanup_ble(
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    let _guard = state.ble_lock.lock().await;
    state.ble.force_cleanup().await;
    state.set_disconnected();
    let _ = app.emit("device-status-changed", &*state.state.read().unwrap());
    Ok(())
}

#[tauri::command]
pub fn get_device_info(state: State<AppState>) -> AppResult<device_info::DeviceDetailInfo> {
    let s = state.get_studio_state();
    device_info::get_device_info(
        s.device.connected,
        &s.device.device_name,
        s.device.battery_level,
        s.device.signal_strength,
    )
}

#[tauri::command]
pub fn get_version_info() -> AppResult<device_info::AppVersionInfo> {
    device_info::get_version_info()
}

// ====================== 模式 / 键位 ======================

#[tauri::command]
pub fn set_active_mode(mode: u8, state: State<AppState>) -> AppResult<()> {
    state.set_active_mode(mode)
}

#[tauri::command]
pub fn set_keys_for_mode(mode: u8, keys: Vec<KeyConfig>, state: State<AppState>) -> AppResult<()> {
    state.set_keys_for_mode(mode, keys.clone())?;
    let mut m = std::collections::HashMap::new();
    m.insert(mode, keys);
    let _ = crate::service::config_store::save_keys(&m);
    Ok(())
}

#[derive(Debug, Deserialize)]
pub struct UpdateKeyArgs {
    pub mode: u8,
    pub key_id: u8,
    pub name: Option<String>,
    pub bindings: Option<Vec<KeyCodeBinding>>,
    pub voice_preset: Option<VoicePreset>,
}

#[tauri::command]
pub fn update_key(args: UpdateKeyArgs, state: State<AppState>) -> AppResult<KeyConfig> {
    let mut keys = state.get_keys_for_mode(args.mode);
    let k = keys
        .iter_mut()
        .find(|k| k.id == args.key_id)
        .ok_or_else(|| AppError::Other(format!("key {} not found in mode {}", args.key_id, args.mode)))?;

    if let Some(n) = args.name {
        k.name = n;
    }
    if let Some(b) = args.bindings {
        k.bindings = b;
    }
    if let Some(v) = args.voice_preset {
        k.voice_preset = v;
    }

    let updated = k.clone();
    state.set_keys_for_mode(args.mode, keys)?;

    let store = state.keys.read().unwrap();
    let _ = crate::service::config_store::save_keys(&store);

    Ok(updated)
}

#[tauri::command]
pub fn reset_keys_for_mode(mode: u8, state: State<AppState>) -> AppResult<Vec<KeyConfig>> {
    let defaults = crate::service::config_store::load_keys().unwrap_or_default();
    let keys = defaults.get(&mode).cloned().unwrap_or_default();
    state.set_keys_for_mode(mode, keys.clone())?;
    Ok(keys)
}

#[tauri::command]
pub fn reset_all_keys(state: State<AppState>) -> AppResult<Vec<Vec<KeyConfig>>> {
    let defaults = crate::service::config_store::load_keys().unwrap_or_default();
    let mut out = Vec::new();
    for m in 0..4 {
        let keys = defaults.get(&m).cloned().unwrap_or_default();
        state.set_keys_for_mode(m, keys.clone())?;
        out.push(keys);
    }
    Ok(out)
}

#[tauri::command]
pub fn apply_keys_to_device(mode: u8, state: State<AppState>) -> AppResult<()> {
    let _ = state.get_keys_for_mode(mode);
    Ok(())
}

// ====================== 模拟按键 ======================

#[tauri::command]
pub fn simulate_keypress(key_id: u8, state: State<AppState>) -> AppResult<()> {
    let mode = state.get_studio_state().active_mode;
    let keys = state.get_keys_for_mode(mode);
    let key = keys
        .iter()
        .find(|k| k.id == key_id)
        .ok_or_else(|| AppError::Other(format!("key {} not found", key_id)))?;
    println!(
        "[inject] simulate key: K{} ({}), bindings: {:?}",
        key.id, key.name, key.bindings
    );
    Ok(())
}

// ====================== 灯条 / OLED 预览 ======================

#[derive(Debug, Deserialize)]
pub struct UpdateLightArgs {
    pub enabled: Option<bool>,
    pub style: Option<String>,
    pub color: Option<String>,
    pub brightness: Option<u8>,
    pub segments: Option<Vec<u8>>,
}

#[tauri::command]
pub fn update_light_preview(args: UpdateLightArgs, state: State<AppState>) -> AppResult<LightBarPreviewState> {
    let mut p = state.get_light_preview();
    if let Some(v) = args.enabled { p.enabled = v; }
    if let Some(v) = args.style { p.style = v; }
    if let Some(v) = args.color { p.color = v; }
    if let Some(v) = args.brightness { p.brightness = v.min(100); }
    if let Some(v) = args.segments { p.segments = v; }
    state.set_light_preview(p.clone())?;
    let _ = crate::service::config_store::save_light_preview(&p);
    Ok(p)
}

#[tauri::command]
pub fn clear_oled_preview(state: State<AppState>) -> AppResult<OledModeDraft> {
    let mode = state.get_studio_state().active_mode;
    let draft = OledModeDraft {
        mode,
        image_path: None,
        gif_path: None,
        text: String::new(),
    };
    state.set_oled_draft(draft.clone())?;
    let _ = crate::service::config_store::save_oled_draft(&draft);
    Ok(draft)
}

#[tauri::command]
pub fn update_oled_draft(mode: u8, image_path: Option<String>, gif_path: Option<String>, text: Option<String>, state: State<AppState>) -> AppResult<OledModeDraft> {
    let mut d = state.get_oled_draft();
    if d.mode == 0 && mode != 0 { d.mode = mode; }
    if let Some(p) = image_path { d.image_path = Some(p); }
    if let Some(p) = gif_path { d.gif_path = Some(p); }
    if let Some(t) = text { d.text = t; }
    state.set_oled_draft(d.clone())?;
    let _ = crate::service::config_store::save_oled_draft(&d);
    Ok(d)
}

// ====================== 语音路由 ======================

#[tauri::command]
pub fn get_voice_route(mode: u8, state: State<AppState>) -> voice_route::VoiceRouteSummary {
    let bindings = state.get_keys_for_mode(mode);
    let preset = bindings.first().map(|k| k.voice_preset.clone()).unwrap_or(VoicePreset::WindowsNative);
    voice_route::route_for_mode(mode, &preset)
}

#[tauri::command]
pub fn get_all_voice_routes(state: State<AppState>) -> Vec<voice_route::VoiceRouteSummary> {
    let mode = state.get_studio_state().active_mode;
    let bindings = state.get_keys_for_mode(mode);
    let preset = bindings.first().map(|k| k.voice_preset.clone()).unwrap_or(VoicePreset::WindowsNative);
    voice_route::all_routes_for_modes(&preset)
}

// ====================== Hook 控制 ======================

#[tauri::command]
pub fn install_hook(state: State<AppState>) -> AppResult<()> {
    if state.is_hook_running() {
        return Err(AppError::Other("hook already installed".to_string()));
    }
    state.set_hook_running(true);
    Ok(())
}

#[tauri::command]
pub fn uninstall_hook(state: State<AppState>) -> AppResult<()> {
    state.set_hook_running(false);
    Ok(())
}

#[tauri::command]
pub fn is_hook_running(state: State<AppState>) -> bool {
    state.is_hook_running()
}

// ====================== AhaType ======================

#[tauri::command]
pub fn toggle_aha_type(state: State<AppState>) -> AppResult<bool> {
    let mut s = state.state.write().unwrap();
    s.aha_type_enabled = !s.aha_type_enabled;
    s.aha_type_status = if s.aha_type_enabled {
        "已启用".to_string()
    } else {
        "未启用".to_string()
    };
    Ok(s.aha_type_enabled)
}

#[tauri::command]
pub fn get_aha_type_status(state: State<AppState>) -> (bool, String) {
    let s = state.get_studio_state();
    (s.aha_type_enabled, s.aha_type_status)
}

// ====================== 语言 ======================

#[tauri::command]
pub fn set_language(lang: String, state: State<AppState>) -> AppResult<()> {
    let mut s = state.state.write().unwrap();
    if lang != "zh-CN" && lang != "en" {
        return Err(AppError::Other(format!("unsupported language: {}", lang)));
    }
    s.language = lang;
    Ok(())
}

// ====================== 摇杆 ======================
// 摇杆档位只能由硬件 BLE notify 决定,UI 只读。
// 真实流程:硬件拨动 → BLE_tcp_bridge / btleplug 收 notify → ble/transport.rs 解析
//           → state.on_ble_notify() → emit("device-status-changed") → 前端 UI 更新

#[tauri::command]
pub fn get_language(state: State<AppState>) -> String {
    state.get_studio_state().language
}