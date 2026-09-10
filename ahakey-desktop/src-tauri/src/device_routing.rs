use crate::{backend::require_main, state::Runtime};
use ahakey_ble::routing::{Config, Status};
use tauri::Manager;

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
