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

/// 切换工作模式(mode 0-3)。
/// 先更新本地 state(UI 立即响应),再发 set_work_mode 协议帧到设备。
#[tauri::command]
pub async fn set_active_mode(mode: u8, state: State<'_, AppState>) -> AppResult<()> {
    state.set_active_mode(mode)?;
    let frame = crate::protocol::set_work_mode(mode);
    state.ble.send_frame(&frame).await?;
    Ok(())
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

/// 把指定 mode 的所有键位配置发到设备。
/// 对每个 key_index 调一次 set_key_mapping。
/// bindings 转 HID 字节的策略:
///   - "Ctrl"/"Shift"/"Alt"/"GUI"(大小写不敏感)作为 modifier → 按 ROL 顺序合并成首字节
///   - 其它字符串当 hex (e.g. "0x04") 或十进制数字 parse → 后续字节
///   - 空 bindings 发空 payload(等同于清除键位)
#[tauri::command]
pub async fn apply_keys_to_device(mode: u8, state: State<'_, AppState>) -> AppResult<()> {
    let keys = state.get_keys_for_mode(mode);
    for (idx, key) in keys.iter().enumerate() {
        let hid_codes = parse_bindings_to_hid(&key.bindings);
        let frame = crate::protocol::set_key_mapping(mode, idx as u8, &hid_codes);
        state.ble.send_frame(&frame).await?;
    }
    Ok(())
}

// ====================== 设备控制(发到 BLE 设备) ======================

/// 修改设备蓝牙名称。持久化需要用户随后调 save_config。
#[tauri::command]
pub async fn change_name(name: String, state: State<'_, AppState>) -> AppResult<()> {
    if name.is_empty() {
        return Err(AppError::Other("device name is empty".into()));
    }
    let frame = crate::protocol::change_name(&name);
    state.ble.send_frame(&frame).await?;
    Ok(())
}

/// 触发设备把当前配置写入 Flash。
/// 与 `change_name` / `set_brightness` / `apply_keys_to_device` 配合使用:
/// 这些命令只更新 RAM,save_config 之后才落盘。
#[tauri::command]
pub async fn save_config(state: State<'_, AppState>) -> AppResult<()> {
    let frame = crate::protocol::save_config();
    state.ble.send_frame(&frame).await?;
    Ok(())
}

/// 全局 WS2812 灯条亮度 1-100。超界由 `protocol::builder` 自动 clamp。
#[tauri::command]
pub async fn set_brightness(brightness: u8, state: State<'_, AppState>) -> AppResult<()> {
    let frame = crate::protocol::set_brightness(brightness);
    state.ble.send_frame(&frame).await?;
    Ok(())
}

/// 预览灯效(不落盘,与 setLightEffect 对应)。
/// Swift 命名 `previewLightEffect`,Java 命名 `setLightEffect`,命令码同为 0x91。
#[tauri::command]
pub async fn preview_light_effect(effect: u8, state: State<'_, AppState>) -> AppResult<()> {
    let frame = crate::protocol::preview_light_effect(effect);
    state.ble.send_frame(&frame).await?;
    Ok(())
}
///
/// 返回字节格式(modifier 风格的简化):
/// - 第 1 个字节:modifier mask (LCtrl=0x01, LShift=0x02, LAlt=0x04, LGUI=0x08,
///                        RCtrl=0x10, RShift=0x20, RAlt=0x40, RGui=0x80)
///   如果没有任何 modifier,首字节填 0x00。
/// - 后续字节:按 binding 顺序,把 `code` 字段当十进制数字 parse。
///
/// 注:这是简化的"modifier + 数字码"方案,完整 HID 键盘报告需要
/// 包含 reserved byte (0x00) 和具体 usage table。当前为最简可用,
/// 后续如果用户报按键不对应,可以再扩。
fn parse_bindings_to_hid(bindings: &[crate::model::KeyCodeBinding]) -> Vec<u8> {
    let mut modifier: u8 = 0;
    let mut codes: Vec<u8> = Vec::new();
    for b in bindings {
        let key_upper = b.key.to_uppercase();
        match key_upper.as_str() {
            "LCTRL" | "CTRL" | "CONTROL" => modifier |= 0x01,
            "LSHIFT" | "SHIFT" => modifier |= 0x02,
            "LALT" | "ALT" => modifier |= 0x04,
            "LGUI" | "GUI" | "WIN" | "META" => modifier |= 0x08,
            "RCTRL" => modifier |= 0x10,
            "RSHIFT" => modifier |= 0x20,
            "RALT" => modifier |= 0x40,
            "RGUI" => modifier |= 0x80,
            _ => {
                // 其它 key 字段,尝试把 code 解析为 u8
                if let Ok(n) = b.code.parse::<u8>() {
                    codes.push(n);
                } else if let Some(hex) = b.code.strip_prefix("0x").or_else(|| b.code.strip_prefix("0X")) {
                    if let Ok(n) = u8::from_str_radix(hex, 16) {
                        codes.push(n);
                    }
                }
            }
        }
    }
    let mut out = Vec::with_capacity(1 + codes.len());
    out.push(modifier);
    out.extend(codes);
    out
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