use serde_json::json;
use std::{
    io::{BufRead, BufReader, Read, Write},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};
pub struct HookServer {
    pub port: u16,
    pub last: Arc<Mutex<Option<String>>>,
    stop: Arc<AtomicBool>,
    path: PathBuf,
    descriptor: Vec<u8>,
}
impl Drop for HookServer {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if std::fs::read(&self.path).is_ok_and(|data| data == self.descriptor) {
            let _ = std::fs::remove_file(&self.path);
        }
    }
}
pub fn state_for(name: &str) -> Option<u8> {
    let trimmed = name
        .trim()
        .trim_start_matches("Codex")
        .trim_start_matches("Kimi");
    match trimmed.to_ascii_lowercase().as_str() {
        "sessionstart" => Some(4),
        "userpromptsubmit" => Some(7),
        "pretooluse" => Some(3),
        "permissionrequest" => Some(1),
        "posttooluse" => Some(2),
        "stop" => Some(5),
        "notification" => Some(0),
        "taskcompleted" => Some(6),
        "sessionend" => Some(8),
        _ => None,
    }
}
fn atomic(path: &Path, data: &[u8]) -> Result<(), String> {
    let temp = path.with_extension("pending");
    std::fs::write(&temp, data).map_err(|_| "无法写入 Hook 状态")?;
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        use windows_sys::Win32::Storage::FileSystem::{
            MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
        };
        let a: Vec<u16> = temp.as_os_str().encode_wide().chain(Some(0)).collect();
        let b: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
        if unsafe {
            MoveFileExW(
                a.as_ptr(),
                b.as_ptr(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        } == 0
        {
            return Err("无法发布 Hook 状态".into());
        }
    }
    #[cfg(not(windows))]
    std::fs::rename(temp, path).map_err(|_| "无法发布 Hook 状态")?;
    Ok(())
}
pub fn start(
    directory: PathBuf,
    callback: impl Fn(String, u8) + Send + Sync + 'static,
) -> Result<HookServer, String> {
    std::fs::create_dir_all(&directory).map_err(|_| "无法创建 Hook 目录")?;
    let path = directory.join("active-endpoint.json");
    if let Ok(bytes) = std::fs::read(&path) {
        let value: serde_json::Value =
            serde_json::from_slice(&bytes).map_err(|_| "现有 Hook 记录无效，已保留")?;
        if let Some(pid) = value.get("processId").and_then(|p| p.as_u64()) {
            if pid != std::process::id() as u64 && crate::platform::process_alive(pid as u32) {
                return Err("另一客户端仍在管理 Hook，请先退出它".into());
            }
        }
    }
    let listener = (8769..8790)
        .find_map(|port| TcpListener::bind(("127.0.0.1", port)).ok())
        .ok_or("没有可用的 Hook 回环端口")?;
    listener.set_nonblocking(true).map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let descriptor=serde_json::to_vec(&json!({"schemaVersion":1,"host":"127.0.0.1","port":port,"processId":std::process::id(),"startedAt":format!("{:?}",std::time::SystemTime::now())})).unwrap();
    let script = directory.join("ahakey-hook.ps1");
    if !script.exists() {
        std::fs::write(&script, DISPATCHER).map_err(|_| "无法写入 Hook 分发脚本")?;
    }
    atomic(&path, &descriptor)?;
    let stop = Arc::new(AtomicBool::new(false));
    let last = Arc::new(Mutex::new(None));
    let stop_worker = stop.clone();
    let observed = last.clone();
    std::thread::spawn(move || {
        while !stop_worker.load(Ordering::SeqCst) {
            match listener.accept() {
                Ok((mut stream, _)) => {
                    let _ = stream.set_read_timeout(Some(Duration::from_millis(1000)));
                    let _ = stream.set_write_timeout(Some(Duration::from_millis(1000)));
                    if let Some(name) = read_event(&mut stream) {
                        if let Some(state) = state_for(&name) {
                            *observed.lock().unwrap() = Some(name.clone());
                            callback(name, state);
                            let _ = stream.write_all(b"{\"ok\":true,\"autoApproved\":false}\n");
                        } else {
                            let _ = stream.write_all(b"{\"ok\":false}\n");
                        }
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(50))
                }
                Err(_) => break,
            }
        }
    });
    Ok(HookServer {
        port,
        last,
        stop,
        path,
        descriptor,
    })
}
fn read_event(stream: &mut TcpStream) -> Option<String> {
    let mut line = String::new();
    BufReader::new(stream)
        .take(4097)
        .read_line(&mut line)
        .ok()?;
    if line.len() > 4096 {
        return None;
    }
    let line = line.trim();
    if line.starts_with('{') {
        let json: serde_json::Value = serde_json::from_str(line).ok()?;
        json.get("cmd")
            .or_else(|| json.get("event"))
            .or_else(|| json.get("eventName"))
            .and_then(|s| s.as_str())
            .map(str::to_owned)
    } else {
        Some(line.to_owned())
    }
}
const DISPATCHER: &str = r#"# AhaKey Hook Dispatcher - Auto-generated, do not edit
param([Parameter(Position=0)][string]$EventName)
try { if ([Console]::IsInputRedirected) { $null=[Console]::In.ReadToEnd() } } catch {}
try {
    $endpoint=Get-Content -Raw (Join-Path $PSScriptRoot 'active-endpoint.json')|ConvertFrom-Json
    if ($endpoint.host -ne '127.0.0.1') { throw 'Invalid endpoint' }
    if (-not (Get-Process -Id $endpoint.processId -ErrorAction SilentlyContinue)) { throw 'Offline' }
    $client=[Net.Sockets.TcpClient]::new()
    if (-not $client.ConnectAsync('127.0.0.1',[int]$endpoint.port).Wait(1500)) { throw 'Timeout' }
    $stream=$client.GetStream();$stream.ReadTimeout=1500
    $writer=[IO.StreamWriter]::new($stream);$writer.WriteLine($EventName);$writer.Flush()
    $reader=[IO.StreamReader]::new($stream);$null=$reader.ReadLine()
} catch {} finally { if ($client) {$client.Dispose()} }
if ($EventName -match 'PermissionRequest$') {
    [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest"}}')
} else { [Console]::WriteLine('{}') }
"#;
#[cfg(test)]
mod tests {
    #[test]
    fn event_mapping_does_not_execute_unknown_input() {
        assert_eq!(super::state_for("CodexPermissionRequest"), Some(1));
        for (event, code) in [
            ("Notification", 0),
            ("PreToolUse", 3),
            ("PostToolUse", 2),
            ("SessionStart", 4),
            ("Stop", 5),
            ("TaskCompleted", 6),
            ("UserPromptSubmit", 7),
        ] {
            assert_eq!(super::state_for(event), Some(code));
        }
        assert_eq!(super::state_for("SessionEnd"), Some(8));
        assert_eq!(super::state_for("exec arbitrary text"), None);
    }
}
