mod model;
pub use model::{Account, Cards, Provider, Window};
use serde::Serialize;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    fs,
    path::Path,
    sync::Mutex,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::Manager;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use zeroize::Zeroizing;

const MAX_RESPONSE: usize = 1024 * 1024;
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaResult {
    pub account_id: String,
    pub state: String,
    pub windows: Vec<Window>,
    pub checked_at: i64,
    pub updated_at: Option<i64>,
    pub error: Option<String>,
}
#[derive(Default)]
pub struct Service {
    config_gate: tokio::sync::Mutex<()>,
    query_gate: tokio::sync::Mutex<()>,
    cache: Mutex<HashMap<String, (Account, QuotaResult)>>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CardsSnapshot {
    pub config: Cards,
    pub results: Vec<QuotaResult>,
}
fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
fn path(w: &tauri::WebviewWindow) -> Result<std::path::PathBuf, String> {
    crate::backend::require_main(w)?;
    Ok(w.state::<crate::state::Runtime>()
        .settings_path
        .parent()
        .ok_or("设置路径无效")?
        .join("display-cards.json"))
}
fn load(p: &Path) -> Result<Cards, String> {
    let bytes = match fs::read(p) {
        Ok(b) => b,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Cards::default()),
        Err(_) => return Err("无法读取卡片配置".into()),
    };
    if bytes.len() > 128 * 1024 {
        return Err("卡片配置过大，原文件已保留".into());
    }
    let c: Cards = serde_json::from_slice(&bytes).map_err(|_| "卡片配置格式错误，原文件已保留")?;
    c.validate()?;
    Ok(c)
}
fn store(p: &Path, cards: &Cards) -> Result<(), String> {
    cards.validate()?;
    load(p)?;
    let parent = p.parent().ok_or("设置路径无效")?;
    fs::create_dir_all(parent).map_err(|_| "无法创建卡片目录")?;
    let pending = p.with_extension("json.pending");
    let encoded = serde_json::to_vec_pretty(cards).map_err(|_| "卡片编码失败")?;
    {
        use std::io::Write;
        let mut file = fs::File::create(&pending).map_err(|_| "无法写入临时配置")?;
        file.write_all(&encoded)
            .and_then(|_| file.sync_all())
            .map_err(|_| "卡片保存失败")?;
    }
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        use windows_sys::Win32::Storage::FileSystem::{
            MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
        };
        let src: Vec<u16> = pending.as_os_str().encode_wide().chain(Some(0)).collect();
        let dst: Vec<u16> = p.as_os_str().encode_wide().chain(Some(0)).collect();
        if unsafe {
            MoveFileExW(
                src.as_ptr(),
                dst.as_ptr(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        } == 0
        {
            return Err("原卡片配置已保留，替换失败".into());
        }
    }
    #[cfg(not(windows))]
    fs::rename(&pending, p).map_err(|_| "原卡片配置已保留，替换失败")?;
    Ok(())
}
fn account_at(w: &tauri::WebviewWindow, id: &str) -> Result<Account, String> {
    load(&path(w)?)?
        .accounts
        .into_iter()
        .find(|a| a.id == id)
        .ok_or("找不到账户，请先保存卡片配置".into())
}
fn credential_namespace(identifier: &str) -> String {
    format!("{identifier}.quota")
}
fn entry(namespace: &str, a: &Account) -> Result<keyring::Entry, String> {
    keyring::Entry::new(namespace, &a.credential_id()).map_err(|_| "系统凭据库不可用".into())
}

#[tauri::command]
pub fn get_cards(window: tauri::WebviewWindow) -> Result<CardsSnapshot, String> {
    let config = load(&path(&window)?)?;
    let service = window.state::<Service>();
    let cache = service.cache.lock().unwrap();
    let results = config
        .accounts
        .iter()
        .filter_map(|a| {
            cache
                .get(&a.id)
                .filter(|(old, _)| old == a)
                .map(|(_, r)| r.clone())
        })
        .collect();
    Ok(CardsSnapshot { config, results })
}
#[tauri::command]
pub async fn save_cards(window: tauri::WebviewWindow, config: Cards) -> Result<(), String> {
    let p = path(&window)?;
    let service = window.state::<Service>();
    let _guard = service.config_gate.lock().await;
    store(&p, &config)?;
    service
        .cache
        .lock()
        .unwrap()
        .retain(|_, (a, _)| config.accounts.contains(a));
    Ok(())
}
#[tauri::command]
pub async fn save_quota_key(
    window: tauri::WebviewWindow,
    account_id: String,
    token: String,
) -> Result<(), String> {
    let token = Zeroizing::new(token);
    let a = account_at(&window, &account_id)?;
    if a.provider == Provider::Codex {
        return Err("Codex 使用本机官方登录，不在此保存令牌".into());
    }
    if token.is_empty() || token.len() > 8192 || !token.bytes().all(|b| b.is_ascii_graphic()) {
        return Err("密钥为空或格式无效".into());
    }
    let service = window.state::<Service>();
    let _guard = service.query_gate.lock().await;
    entry(
        &credential_namespace(&window.app_handle().config().identifier),
        &a,
    )?
    .set_password(&token)
    .map_err(|_| "无法保存到系统凭据库；没有写入明文")?;
    service.cache.lock().unwrap().remove(&account_id);
    Ok(())
}
#[tauri::command]
pub async fn clear_quota_key(
    window: tauri::WebviewWindow,
    account_id: String,
) -> Result<(), String> {
    let a = account_at(&window, &account_id)?;
    let service = window.state::<Service>();
    let _guard = service.query_gate.lock().await;
    match entry(
        &credential_namespace(&window.app_handle().config().identifier),
        &a,
    )?
    .delete_credential()
    {
        Ok(()) | Err(keyring::Error::NoEntry) => {}
        Err(_) => return Err("无法清除系统凭据".into()),
    }
    service.cache.lock().unwrap().remove(&account_id);
    Ok(())
}
async fn fetch_http(account: &Account, namespace: &str) -> Result<Value, String> {
    let token = Zeroizing::new(
        entry(namespace, account)?
            .get_password()
            .map_err(|_| "未配置密钥或系统凭据库已锁定")?,
    );
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|_| "无法建立额度查询客户端")?;
    let request = client
        .get(account.endpoint())
        .header("Accept", "application/json");
    let request = if account.provider == Provider::Glm {
        request.header("Authorization", token.as_str())
    } else {
        request.bearer_auth(token.as_str())
    };
    let mut response = request.send().await.map_err(|_| "额度查询网络失败或超时")?;
    match response.status().as_u16() {
        200..=299 => {}
        401 | 403 => return Err("认证失败，请检查账户地区、套餐和密钥".into()),
        429 => return Err("查询受到限流，请稍后刷新".into()),
        s => return Err(format!("额度接口返回 HTTP {s}")),
    }
    if response
        .content_length()
        .is_some_and(|n| n > MAX_RESPONSE as u64)
    {
        return Err("额度响应超过大小限制".into());
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "额度响应读取失败")? {
        if bytes.len() + chunk.len() > MAX_RESPONSE {
            return Err("额度响应超过大小限制".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&bytes).map_err(|_| "额度响应不是有效 JSON".into())
}
async fn fetch_codex() -> Result<Value, String> {
    #[cfg(windows)]
    let binary = "codex.exe";
    #[cfg(not(windows))]
    let binary = "codex";
    let mut cmd = tokio::process::Command::new(binary);
    cmd.arg("app-server")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true);
    #[cfg(windows)]
    cmd.creation_flags(0x08000000);
    let mut child = cmd
        .spawn()
        .map_err(|_| "找不到 Codex CLI；安装并完成官方登录后重试")?;
    let input = child.stdin.take().ok_or("Codex 输入通道不可用")?;
    let output = child.stdout.take().ok_or("Codex 输出通道不可用")?;
    let result = tokio::time::timeout(Duration::from_secs(20), codex_exchange(output, input))
        .await
        .unwrap_or_else(|_| Err("Codex 额度查询超时".into()));
    let _ = child.kill().await;
    let _ = child.wait().await;
    result
}
async fn codex_exchange(
    output: impl tokio::io::AsyncRead + Unpin,
    mut input: impl tokio::io::AsyncWrite + Unpin,
) -> Result<Value, String> {
    let mut lines = BufReader::new(output.take(MAX_RESPONSE as u64)).lines();
    let init = json!({"id":1,"method":"initialize","params":{"clientInfo":{"name":"ahakey-quota","version":"0.1.0"}}});
    input
        .write_all(format!("{init}\n").as_bytes())
        .await
        .map_err(|_| "Codex 初始化发送失败")?;
    let mut initialized = false;
    while let Some(line) = lines.next_line().await.map_err(|_| "Codex 响应读取失败")? {
        let v: Value = serde_json::from_str(&line).map_err(|_| "Codex 响应格式错误")?;
        if v["id"] == 1 {
            if initialized || v.get("error").is_some() || v.get("result").is_none() {
                return Err("Codex 初始化失败，请检查本机版本".into());
            }
            initialized = true;
            input.write_all(b"{\"method\":\"initialized\"}\n{\"id\":2,\"method\":\"account/rateLimits/read\"}\n")
                .await.map_err(|_| "Codex 额度请求发送失败")?;
        } else if initialized && v["id"] == 2 {
            return v
                .get("result")
                .filter(|v| v.is_object())
                .cloned()
                .ok_or("Codex 未返回额度，请确认官方登录和接口支持".into());
        }
    }
    Err("Codex 提前退出或响应超限".into())
}
fn finish(
    account: &Account,
    fetched: Result<Vec<Window>, String>,
    old: Option<&QuotaResult>,
    at: i64,
) -> QuotaResult {
    match fetched {
        Ok(windows) => QuotaResult {
            account_id: account.id.clone(),
            state: if windows.iter().any(|w| w.remaining_percent.is_some()) {
                "ready"
            } else {
                "unknown"
            }
            .into(),
            windows,
            checked_at: at,
            updated_at: Some(at),
            error: None,
        },
        Err(error) => QuotaResult {
            account_id: account.id.clone(),
            state: if old.and_then(|v| v.updated_at).is_some() {
                "stale"
            } else {
                "error"
            }
            .into(),
            windows: old.map(|v| v.windows.clone()).unwrap_or_default(),
            checked_at: at,
            updated_at: old.and_then(|v| v.updated_at),
            error: Some(error),
        },
    }
}
#[tauri::command]
pub async fn refresh_quota(
    window: tauri::WebviewWindow,
    account_id: String,
) -> Result<QuotaResult, String> {
    let account = account_at(&window, &account_id)?;
    account.validate()?;
    if !account.enabled {
        return Err("账户已停用".into());
    }
    let service = window.state::<Service>();
    let _guard = service
        .query_gate
        .try_lock()
        .map_err(|_| "另一额度查询正在进行")?;
    let body = if account.provider == Provider::Codex {
        fetch_codex().await
    } else {
        fetch_http(
            &account,
            &credential_namespace(&window.app_handle().config().identifier),
        )
        .await
    };
    let fetched = body.and_then(|body| model::parse(&account, &body));
    if account_at(&window, &account_id)? != account {
        return Err("查询期间配置已改变，旧结果已丢弃".into());
    }
    let mut cache = service.cache.lock().unwrap();
    let old = cache
        .get(&account_id)
        .filter(|(a, _)| *a == account)
        .map(|(_, r)| r);
    let result = finish(&account, fetched, old, now());
    cache.insert(account_id, (account, result.clone()));
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preview_credentials_are_isolated_from_daily_client() {
        assert_ne!(
            credential_namespace("ai.ahakey.studio.preview"),
            credential_namespace("ai.ahakey.studio.app006.preview")
        );
    }
    #[tokio::test]
    async fn codex_requests_only_initialization_and_readonly_quota() {
        let (client, server) = tokio::io::duplex(4096);
        let peer = tokio::spawn(async move {
            let (read, mut write) = tokio::io::split(server);
            let mut lines = BufReader::new(read).lines();
            let first: Value =
                serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
            assert_eq!(first["method"], "initialize");
            write
                .write_all(b"{\"id\":1,\"result\":{}}\n")
                .await
                .unwrap();
            let second: Value =
                serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
            let third: Value =
                serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
            assert_eq!(second["method"], "initialized");
            assert_eq!(third["method"], "account/rateLimits/read");
            write
                .write_all(
                    b"{\"id\":2,\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":25}}}}\n",
                )
                .await
                .unwrap();
            assert!(lines.next_line().await.unwrap().is_none());
        });
        let (read, write) = tokio::io::split(client);
        let response = codex_exchange(read, write).await.unwrap();
        assert_eq!(response["rateLimits"]["primary"]["usedPercent"], 25);
        peer.await.unwrap();
    }
    #[tokio::test]
    async fn codex_auth_error_does_not_expose_remote_details() {
        let (client, server) = tokio::io::duplex(4096);
        let peer = tokio::spawn(async move {
            let (read, mut write) = tokio::io::split(server);
            let mut lines = BufReader::new(read).lines();
            lines.next_line().await.unwrap();
            write
                .write_all(b"{\"id\":1,\"error\":{\"message\":\"never-echo-token\"}}\n")
                .await
                .unwrap();
            assert!(lines.next_line().await.unwrap().is_none());
        });
        let (read, write) = tokio::io::split(client);
        assert!(!codex_exchange(read, write)
            .await
            .unwrap_err()
            .contains("never-echo-token"));
        peer.await.unwrap();
    }
    #[test]
    fn card_storage_is_separate_and_rejects_corrupt_overwrite() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("display-cards.json");
        store(&p, &Cards::default()).unwrap();
        assert_eq!(load(&p).unwrap(), Cards::default());
        fs::write(&p, b"broken").unwrap();
        assert!(store(&p, &Cards::default()).is_err());
        assert_eq!(fs::read(&p).unwrap(), b"broken");
    }
    #[test]
    fn failed_refresh_keeps_age_not_fake_freshness() {
        let a = Cards::default().accounts[0].clone();
        let old = finish(&a, Ok(vec![]), None, 10);
        let next = finish(&a, Err("offline".into()), Some(&old), 20);
        assert_eq!(next.state, "stale");
        assert_eq!(next.updated_at, Some(10));
        assert_eq!(next.checked_at, 20);
    }
    #[test]
    fn endpoint_change_changes_credential_binding() {
        let mut a = Cards::default().accounts[0].clone();
        let id = a.credential_id();
        a.international = true;
        assert_ne!(id, a.credential_id());
    }
}
