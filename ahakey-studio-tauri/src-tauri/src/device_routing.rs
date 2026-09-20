use crate::{backend::require_main, state::Runtime};
use ahakey_ble::routing::{Config, Details, ManagementAction, Status};
use tauri::Manager;

#[tauri::command]
pub async fn select_configuration_transport(
    window: tauri::WebviewWindow,
) -> Result<String, String> {
    require_main(&window)?;
    let state = window.state::<Runtime>();
    #[cfg(windows)]
    {
        let _gate = state.usb_gate.lock().await;
        let port = tokio::time::timeout(
            std::time::Duration::from_secs(4),
            ahakey_ble::usb_routing::UsbRouting::try_open(),
        )
        .await
        .map_err(|_| "USB 检测超时，未切换到蓝牙")??;
        if port.is_some() {
            return Ok("usb".into());
        }
    }
    if state
        .ble
        .lock()
        .await
        .as_ref()
        .is_some_and(|c| c.status().phase == ahakey_ble::ConnectionPhase::Ready)
    {
        Ok("ble".into())
    } else {
        Err("未检测到 USB 配置接口或已连接的客户端蓝牙".into())
    }
}
#[tauri::command]
pub async fn get_device_policy(
    window: tauri::WebviewWindow,
    transport: Option<String>,
) -> Result<ahakey_ble::reset::Policy, String> {
    require_main(&window)?;
    let state = window.state::<Runtime>();
    if use_usb(transport.as_deref())? {
        let _gate = state.usb_gate.lock().await;
        #[cfg(windows)]
        return tokio::time::timeout(std::time::Duration::from_secs(6), async {
            let mut port = ahakey_ble::usb_routing::UsbRouting::open().await?;
            port.read_policy().await
        })
        .await
        .map_err(|_| "USB 策略读取超时")?;
        #[cfg(not(windows))]
        return Err("此平台尚无 USB 配置支持".into());
    }
    let client = state.ble.lock().await.clone().ok_or("蓝牙未连接")?;
    client.read_policy().await.map_err(|e| e.to_string())
}
#[tauri::command]
pub async fn reset_device_pairing(
    window: tauri::WebviewWindow,
    target: u8,
) -> Result<ahakey_ble::reset::Policy, String> {
    require_main(&window)?;
    if target > 2 {
        return Err("无效的重置目标".into());
    }
    // Intentionally no transport parameter or BLE fallback.
    #[cfg(windows)]
    {
        let state = window.state::<Runtime>();
        let _gate = state.usb_gate.lock().await;
        tokio::time::timeout(std::time::Duration::from_secs(24), async {
            let mut port = ahakey_ble::usb_routing::UsbRouting::open().await?;
            port.reset_pairing(target).await
        })
        .await
        .map_err(|_| "USB 重置结果未知，请重新读取；不会自动重试")?
    }
    #[cfg(not(windows))]
    Err("客户端重置仅支持 Windows USB，请使用硬件选槽长按；不会通过蓝牙重置".into())
}

#[tauri::command]
pub fn get_host_aliases(window: tauri::WebviewWindow) -> Result<[String; 2], String> {
    require_main(&window)?;
    crate::host_notes::load(&window.state::<Runtime>().data_dir.join("host-notes.json"))
}
#[tauri::command]
pub async fn set_host_aliases(
    window: tauri::WebviewWindow,
    aliases: [String; 2],
) -> Result<[String; 2], String> {
    require_main(&window)?;
    let state = window.state::<Runtime>();
    let _gate = state.settings_gate.lock().await;
    let aliases = aliases.map(|s| s.trim().to_owned());
    crate::host_notes::save(&state.data_dir.join("host-notes.json"), &aliases)?;
    Ok(aliases)
}
#[tauri::command]
pub async fn get_device_hosts(
    window: tauri::WebviewWindow,
    transport: Option<String>,
) -> Result<[ahakey_ble::host_info::HostInfo; 2], String> {
    require_main(&window)?;
    let state = window.state::<Runtime>();
    if use_usb(transport.as_deref())? {
        let _gate = state.usb_gate.lock().await;
        #[cfg(windows)]
        return tokio::time::timeout(std::time::Duration::from_secs(26), async {
            let mut port = ahakey_ble::usb_routing::UsbRouting::open().await?;
            port.read_host_info().await
        })
        .await
        .map_err(|_| "USB 主机信息读取超时".to_owned())?;
        #[cfg(not(windows))]
        return Err("USB 配置仅支持 Windows".into());
    }
    let client = state.ble.lock().await.clone().ok_or("请先连接键盘")?;
    client.read_host_info().await.map_err(|e| e.to_string())
}
fn local_host() -> (String, u8) {
    #[cfg(windows)]
    let (name, system) = (std::env::var("COMPUTERNAME").unwrap_or_default(), 1);
    #[cfg(unix)]
    let (name, system) = {
        let mut bytes = [0u8; 256];
        let name = if unsafe { libc::gethostname(bytes.as_mut_ptr().cast(), bytes.len()) } == 0 {
            let end = bytes.iter().position(|b| *b == 0).unwrap_or(bytes.len());
            String::from_utf8_lossy(&bytes[..end]).into_owned()
        } else {
            String::new()
        };
        (name, if cfg!(target_os = "macos") { 2 } else { 3 })
    };
    (ahakey_ble::host_info::bounded_name(&name), system)
}
pub async fn report_local_host(client: &ahakey_ble::BleClient) -> Result<(), String> {
    let (name, system) = local_host();
    client
        .register_host(&name, system)
        .await
        .map_err(|e| e.to_string())
}
#[tauri::command]
pub async fn report_this_host(window: tauri::WebviewWindow) -> Result<(), String> {
    require_main(&window)?;
    let client = window
        .state::<Runtime>()
        .ble
        .lock()
        .await
        .clone()
        .ok_or("请先通过蓝牙连接本机；USB 不能代替蓝牙 A/B 上报名称")?;
    report_local_host(&client).await
}

#[tauri::command]
pub async fn get_device_routing(
    window: tauri::WebviewWindow,
    transport: Option<String>,
) -> Result<Status, String> {
    require_main(&window)?;
    if use_usb(transport.as_deref())? {
        let state = window.state::<Runtime>();
        let _gate = state.usb_gate.lock().await;
        return usb_operation(None).await;
    }
    let client = window
        .state::<Runtime>()
        .ble
        .lock()
        .await
        .clone()
        .ok_or("请先连接键盘")?;
    client.read_routing().await.map_err(|e| e.to_string())
}
#[tauri::command]
pub async fn set_device_routing(
    window: tauri::WebviewWindow,
    config: Config,
    transport: Option<String>,
) -> Result<Status, String> {
    require_main(&window)?;
    if use_usb(transport.as_deref())? {
        let state = window.state::<Runtime>();
        let _gate = state.usb_gate.lock().await;
        return usb_operation(Some(config)).await;
    }
    let client = window
        .state::<Runtime>()
        .ble
        .lock()
        .await
        .clone()
        .ok_or("请先连接键盘")?;
    client.set_routing(&config).await.map_err(|e| e.to_string())
}
fn use_usb(transport: Option<&str>) -> Result<bool, String> {
    match transport {
        None | Some("ble") => Ok(false),
        Some("usb") => Ok(true),
        _ => Err("未知的配置连接类型".into()),
    }
}
#[tauri::command]
pub async fn get_device_pairing(
    window: tauri::WebviewWindow,
    transport: Option<String>,
) -> Result<Details, String> {
    require_main(&window)?;
    if use_usb(transport.as_deref())? {
        let state = window.state::<Runtime>();
        let _gate = state.usb_gate.lock().await;
        return usb_pairing(None).await;
    }
    let client = window
        .state::<Runtime>()
        .ble
        .lock()
        .await
        .clone()
        .ok_or("请先连接键盘")?;
    client.read_pairing().await.map_err(|e| e.to_string())
}
#[tauri::command]
pub async fn manage_device_pairing(
    window: tauri::WebviewWindow,
    transport: Option<String>,
    action: ManagementAction,
) -> Result<(), String> {
    require_main(&window)?;
    if use_usb(transport.as_deref())? {
        let state = window.state::<Runtime>();
        let _gate = state.usb_gate.lock().await;
        usb_manage(action).await?;
        return Ok(());
    }
    let client = window
        .state::<Runtime>()
        .ble
        .lock()
        .await
        .clone()
        .ok_or("请先连接键盘")?;
    client
        .manage_pairing(action)
        .await
        .map_err(|e| e.to_string())
}
#[cfg(windows)]
async fn usb_pairing(action: Option<ManagementAction>) -> Result<Details, String> {
    tokio::time::timeout(std::time::Duration::from_secs(14), async {
        let mut port = ahakey_ble::usb_routing::UsbRouting::open().await?;
        if let Some(action) = action {
            port.manage_pairing(action).await?;
        }
        port.read_pairing().await
    })
    .await
    .map_err(|_| "USB 配对管理超时，操作未确认，请重新读取而非重复提交".to_owned())?
}
#[cfg(not(windows))]
async fn usb_pairing(_: Option<ManagementAction>) -> Result<Details, String> {
    Err("此版本 USB 配置仅支持 Windows，请使用蓝牙配置".into())
}
#[cfg(windows)]
async fn usb_manage(action: ManagementAction) -> Result<(), String> {
    tokio::time::timeout(std::time::Duration::from_secs(12), async {
        let mut port = ahakey_ble::usb_routing::UsbRouting::open().await?;
        port.manage_pairing(action).await
    })
    .await
    .map_err(|_| "USB 操作超时，未确认执行，请先重新读取".to_owned())?
}
#[cfg(not(windows))]
async fn usb_manage(_: ManagementAction) -> Result<(), String> {
    Err("此版本 USB 配置仅支持 Windows".into())
}
#[cfg(windows)]
async fn usb_operation(config: Option<Config>) -> Result<Status, String> {
    tokio::time::timeout(std::time::Duration::from_secs(12), async {
        let mut port = ahakey_ble::usb_routing::UsbRouting::open().await?;
        match config {
            Some(config) => port.apply(&config).await,
            None => port.read().await,
        }
    })
    .await
    .map_err(|_| "USB 操作超时，请检查数据线和设备连接；未确认保存".to_owned())?
}
#[cfg(not(windows))]
async fn usb_operation(_: Option<Config>) -> Result<Status, String> {
    Err("此预览版的 USB 配置通道暂仅支持 Windows；蓝牙配置仍可使用".into())
}
#[cfg(test)]
mod tests {
    #[test]
    fn explicit_transport_never_silently_falls_back() {
        assert_eq!(super::use_usb(None), Ok(false));
        assert_eq!(super::use_usb(Some("ble")), Ok(false));
        assert_eq!(super::use_usb(Some("usb")), Ok(true));
        assert!(super::use_usb(Some("auto")).is_err());
    }
}
