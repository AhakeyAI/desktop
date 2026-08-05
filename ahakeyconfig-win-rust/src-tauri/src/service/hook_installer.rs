//! HookInstaller — 对齐 win-java 端 com.example.ahakey.service.HookInstaller
//!
//! 负责 4 个 IDE 平台(Claude/Cursor/Codex/Kimi)的 Hook 安装/卸载/检测。
//! PowerShell 脚本生成到 `~/.ahakey/hooks/`,配置写入各自 IDE 的 settings 文件。
//! 通过 `app_handle.emit("hook-log", line)` 推送实时日志给前端。
//!
//! 关键 Windows 路径:
//! - Claude: %USERPROFILE%\.claude\settings.json
//! - Cursor: %USERPROFILE%\.cursor\settings.json
//! - Codex:  %USERPROFILE%\.codex\hooks.json + config.toml ([features].hooks = true)
//! - Kimi:   %USERPROFILE%\.kimi\config.toml (BEGIN/END block)

use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tracing::{error, info};

/// 支持的 Hook 平台
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum HookPlatform {
    Claude,
    Cursor,
    Codex,
    Kimi,
}

impl HookPlatform {
    pub fn as_str(&self) -> &'static str {
        match self {
            HookPlatform::Claude => "Claude",
            HookPlatform::Cursor => "Cursor",
            HookPlatform::Codex => "Codex",
            HookPlatform::Kimi => "Kimi",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "Claude" => Some(HookPlatform::Claude),
            "Cursor" => Some(HookPlatform::Cursor),
            "Codex" => Some(HookPlatform::Codex),
            "Kimi" => Some(HookPlatform::Kimi),
            _ => None,
        }
    }
}

/// Hook 状态
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct HookStatus {
    pub platform: String,
    pub installed: bool,
    pub config_path: String,
    pub script_dir: String,
}

/// HookInstaller 主结构
pub struct HookInstaller {
    app_handle: AppHandle,
    /// Hook dispatch server 端口(供 PowerShell 脚本 TCP 连接)
    /// MVP 暂时写死 18900(后续可由 state 注入)
    dispatch_port: u16,
}

impl HookInstaller {
    pub fn new(app_handle: AppHandle) -> Self {
        Self {
            app_handle,
            dispatch_port: 18900,
        }
    }

    fn log(&self, line: &str) {
        info!("[hook] {}", line);
        let _ = self.app_handle.emit("hook-log", line.to_string());
    }

    fn err(&self, line: &str) {
        error!("[hook] {}", line);
        let _ = self.app_handle.emit("hook-log", format!("[错误] {}", line));
    }

    /// 获取 home 目录(Windows: %USERPROFILE%)
    fn home_dir() -> PathBuf {
        dirs::home_dir().unwrap_or_else(|| PathBuf::from("."))
    }

    /// 脚本输出目录 ~/.ahakey/hooks/
    fn script_dir() -> PathBuf {
        Self::home_dir().join(".ahakey").join("hooks")
    }

    /// 各 platform 配置文件路径
    fn config_path(platform: HookPlatform) -> PathBuf {
        let home = Self::home_dir();
        match platform {
            HookPlatform::Claude => home.join(".claude").join("settings.json"),
            HookPlatform::Cursor => home.join(".cursor").join("settings.json"),
            HookPlatform::Codex => home.join(".codex").join("hooks.json"),
            HookPlatform::Kimi => home.join(".kimi").join("config.toml"),
        }
    }

    fn codex_config_toml() -> PathBuf {
        Self::home_dir().join(".codex").join("config.toml")
    }

    fn codex_sidecar() -> PathBuf {
        Self::home_dir().join(".codex").join(".ahakey_codex_hooks_v1")
    }

    /// 备份原文件(加 .bak 后缀,如果不存在就不备份)
    fn backup_file(path: &Path) {
        if !path.exists() {
            return;
        }
        let bak = path.with_extension(format!(
            "{}.bak",
            path.extension().and_then(|s| s.to_str()).unwrap_or("")
        ));
        let _ = fs::copy(path, &bak);
    }

    /// 4 个 PowerShell 脚本
    fn generate_scripts(&self) {
        let dir = Self::script_dir();
        if let Err(e) = fs::create_dir_all(&dir) {
            self.err(&format!("创建脚本目录失败: {}", e));
            return;
        }
        // 核心 TCP 通信脚本
        let core = format!(
            r#"# AhaKey Core - Auto-generated, do not edit
# Contains TCP connection logic, to be dot-sourced by platform-specific scripts
try {{
    if ([Console]::IsInputRedirected) {{ $null = [Console]::In.ReadToEnd() }}
}} catch {{ }}
try {{
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect('127.0.0.1', {port})
    $writer = New-Object System.IO.StreamWriter($tcp.GetStream())
    $writer.WriteLine($EventName)
    $writer.Flush()
    $reader = New-Object System.IO.StreamReader($tcp.GetStream())
    $response = $reader.ReadLine()
    $tcp.Close()
}} catch {{
    $response = $null
}}
"#,
            port = self.dispatch_port
        );
        if let Err(e) = fs::write(dir.join("ahakey-core.ps1"), core) {
            self.err(&format!("写 core 脚本失败: {}", e));
            return;
        }

        // Claude 脚本
        let claude = r#"# AhaKey Claude Hook - Auto-generated, do not edit
param([Parameter(Position=0)][string]$EventName)
. (Join-Path $env:USERPROFILE '.ahakey\hooks\ahakey-core.ps1')
if ($EventName -eq 'PermissionRequest') {
    $isAuto = $response -match '"autoApproved"\s*:\s*true'
    if ($isAuto) {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}')
    } else {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"ask"}}}')
    }
    exit 0
}
if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{"ok":true}') }
exit 0
"#;
        let _ = fs::write(dir.join("ahakey-claude.ps1"), claude);

        // Cursor 脚本
        let cursor = r#"# AhaKey Cursor Hook - Auto-generated, do not edit
param([Parameter(Position=0)][string]$EventName)
. (Join-Path $env:USERPROFILE '.ahakey\hooks\ahakey-core.ps1')
if ($response) {
    [Console]::WriteLine($response)
    if ($response -match '"permission"\s*:\s*"deny"') { exit 1 } else { exit 0 }
} else {
    [Console]::WriteLine('{"permission":"allow"}')
    exit 0
}
"#;
        let _ = fs::write(dir.join("ahakey-cursor.ps1"), cursor);

        // Codex 脚本
        let codex = r#"# AhaKey Codex Hook - Auto-generated, do not edit
param([Parameter(Position=0)][string]$EventName)
. (Join-Path $env:USERPROFILE '.ahakey\hooks\ahakey-core.ps1')
if ($EventName -eq 'CodexPreToolUse' -or $EventName -eq 'CodexPermissionRequest') {
    if ($response -match '"autoApproved"\s*:\s*true') {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PreToolUse","decision":{"behavior":"allow"}}}')
    } else {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PreToolUse","decision":{"behavior":"ask"}}}')
    }
    exit 0
}
[Console]::WriteLine('{}')
exit 0
"#;
        let _ = fs::write(dir.join("ahakey-codex.ps1"), codex);

        // Kimi 脚本
        let kimi = r#"# AhaKey Kimi Hook - Auto-generated, do not edit
param([Parameter(Position=0)][string]$EventName)
. (Join-Path $env:USERPROFILE '.ahakey\hooks\ahakey-core.ps1')
if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{"ok":true}') }
exit 0
"#;
        let _ = fs::write(dir.join("ahakey-kimi.ps1"), kimi);

        self.log("已生成 4 个 PowerShell 脚本 + 核心 TCP 脚本");
    }

    /// 检测是否已安装
    pub fn is_installed(&self, platform: HookPlatform) -> bool {
        let path = Self::config_path(platform);
        if !path.exists() {
            return false;
        }
        let content = match fs::read_to_string(&path) {
            Ok(c) => c,
            Err(_) => return false,
        };
        match platform {
            HookPlatform::Claude => content.contains("ahakey-claude.ps1"),
            HookPlatform::Cursor => content.contains("ahakey-cursor.ps1"),
            HookPlatform::Codex => Self::codex_sidecar().exists(),
            HookPlatform::Kimi => content.contains("# BEGIN AhaKey Kimi Hooks"),
        }
    }

    /// 检测所有 platform 状态
    pub fn detect_all(&self) -> Vec<HookStatus> {
        vec![
            HookPlatform::Claude,
            HookPlatform::Cursor,
            HookPlatform::Codex,
            HookPlatform::Kimi,
        ]
        .into_iter()
        .map(|p| HookStatus {
            platform: p.as_str().to_string(),
            installed: self.is_installed(p),
            config_path: Self::config_path(p).to_string_lossy().to_string(),
            script_dir: Self::script_dir().to_string_lossy().to_string(),
        })
        .collect()
    }

    /// 安装指定 platform
    pub fn install(&self, platform: HookPlatform) {
        self.log(&format!("开始安装 {} Hook...", platform.as_str()));
        self.generate_scripts();
        match platform {
            HookPlatform::Claude => self.install_claude(),
            HookPlatform::Cursor => self.install_cursor(),
            HookPlatform::Codex => self.install_codex(),
            HookPlatform::Kimi => self.install_kimi(),
        }
    }

    /// 卸载指定 platform
    pub fn uninstall(&self, platform: HookPlatform) {
        self.log(&format!("开始卸载 {} Hook...", platform.as_str()));
        match platform {
            HookPlatform::Claude => self.uninstall_claude(),
            HookPlatform::Cursor => self.uninstall_cursor(),
            HookPlatform::Codex => self.uninstall_codex(),
            HookPlatform::Kimi => self.uninstall_kimi(),
        }
    }

    // ======================== Claude ========================

    fn install_claude(&self) {
        let path = Self::config_path(HookPlatform::Claude);
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        Self::backup_file(&path);

        let mut settings = self.load_json(&path);
        let mut hooks = serde_json::Map::new();
        // Claude 9 个事件
        let events: &[(&str, u32)] = &[
            ("SessionStart", 10),
            ("SessionEnd", 10),
            ("PreToolUse", 10),
            ("PostToolUse", 10),
            ("PermissionRequest", 60),
            ("Notification", 10),
            ("TaskCompleted", 10),
            ("Stop", 10),
            ("UserPromptSubmit", 10),
        ];
        for (event, timeout) in events {
            let inner = json!([{
                "type": "command",
                "command": self.build_hook_command("ahakey-claude.ps1", event),
                "timeout": timeout,
            }]);
            let wrapper = json!({
                "matcher": "",
                "hooks": inner,
            });
            hooks.insert(event.to_string(), json!([wrapper]));
        }
        settings["hooks"] = Value::Object(hooks);
        match self.save_json(&path, &settings) {
            Ok(_) => {
                self.log(&format!("已注册 {} 个 Claude hook 事件", events.len()));
                self.log(&format!("配置文件: {}", path.display()));
            }
            Err(e) => self.err(&format!("写 Claude 配置文件失败: {}", e)),
        }
    }

    fn uninstall_claude(&self) {
        let path = Self::config_path(HookPlatform::Claude);
        if !path.exists() {
            self.log("Claude 配置文件不存在");
            return;
        }
        let mut settings = self.load_json(&path);
        if settings.as_object_mut().map(|o| o.remove("hooks")).is_some() {
            match self.save_json(&path, &settings) {
                Ok(_) => self.log(&format!("Hook 配置已从 {} 中移除", path.display())),
                Err(e) => self.err(&format!("写 Claude 配置文件失败: {}", e)),
            }
        } else {
            self.log("未找到 Claude Hook 配置");
        }
    }

    // ======================== Cursor ========================

    fn install_cursor(&self) {
        let path = Self::config_path(HookPlatform::Cursor);
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        Self::backup_file(&path);

        let mut settings = self.load_json(&path);
        let events: &[(&str, u32)] = &[
            ("sessionStart", 10),
            ("sessionEnd", 10),
            ("preToolUse", 120),
            ("postToolUse", 10),
            ("stop", 10),
        ];
        let hooks_obj = settings
            .as_object_mut()
            .and_then(|o| o.get_mut("hooks"))
            .and_then(|v| v.as_object_mut());
        let mut hooks_map: serde_json::Map<String, Value> = hooks_obj.cloned().unwrap_or_default();
        for (event, timeout) in events {
            let entry = json!([{
                "command": self.build_hook_command("ahakey-cursor.ps1", event),
                "timeout": timeout,
            }]);
            hooks_map.insert(event.to_string(), entry);
        }
        settings["hooks"] = Value::Object(hooks_map);
        settings["version"] = json!(1);
        match self.save_json(&path, &settings) {
            Ok(_) => {
                self.log(&format!("已注册 {} 个 Cursor hook 事件", events.len()));
                self.log(&format!("配置文件: {}", path.display()));
            }
            Err(e) => self.err(&format!("写 Cursor 配置文件失败: {}", e)),
        }
    }

    fn uninstall_cursor(&self) {
        let path = Self::config_path(HookPlatform::Cursor);
        if !path.exists() {
            self.log("Cursor 配置文件不存在");
            return;
        }
        let mut settings = self.load_json(&path);
        if settings.as_object_mut().map(|o| o.remove("hooks")).is_some() {
            match self.save_json(&path, &settings) {
                Ok(_) => self.log(&format!("Hook 配置已从 {} 中移除", path.display())),
                Err(e) => self.err(&format!("写 Cursor 配置文件失败: {}", e)),
            }
        } else {
            self.log("未找到 Cursor Hook 配置");
        }
    }

    // ======================== Codex ========================

    fn install_codex(&self) {
        let home = Self::home_dir();
        let hooks_json = home.join(".codex").join("hooks.json");
        let config_toml = Self::codex_config_toml();
        let sidecar = Self::codex_sidecar();

        if let Some(parent) = hooks_json.parent() {
            let _ = fs::create_dir_all(parent);
        }
        Self::backup_file(&hooks_json);

        let events: &[(&str, &str, u32)] = &[
            ("SessionStart", "CodexSessionStart", 10),
            ("PostToolUse", "CodexPostToolUse", 10),
            ("PreToolUse", "CodexPreToolUse", 20),
            ("PermissionRequest", "CodexPermissionRequest", 20),
            ("UserPromptSubmit", "CodexUserPromptSubmit", 10),
            ("Stop", "CodexStop", 10),
        ];
        let mut hooks = serde_json::Map::new();
        for (event, internal, timeout) in events {
            let inner = json!([{
                "type": "command",
                "command": self.build_hook_command("ahakey-codex.ps1", internal),
                "timeout": timeout,
            }]);
            let mut entry = serde_json::Map::new();
            // matcher 规则对齐 java 端:SessionStart=startup|resume|clear,UserPromptSubmit/Stop 无,其它=*
            match *event {
                "SessionStart" => {
                    entry.insert("matcher".to_string(), json!("startup|resume|clear"));
                }
                "UserPromptSubmit" | "Stop" => {}
                _ => {
                    entry.insert("matcher".to_string(), json!("*"));
                }
            }
            entry.insert("hooks".to_string(), Value::Array(inner.as_array().unwrap().clone()));
            hooks.insert(event.to_string(), json!([entry]));
        }
        let root = json!({ "hooks": hooks });
        match self.save_json(&hooks_json, &root) {
            Ok(_) => self.log(&format!("已写入 {}", hooks_json.display())),
            Err(e) => {
                self.err(&format!("写 Codex hooks.json 失败: {}", e));
                return;
            }
        }
        // sidecar
        let _ = fs::write(&sidecar, chrono::Local::now().to_string().as_bytes());

        // config.toml 改 [features].hooks = true
        Self::backup_file(&config_toml);
        let existing = if config_toml.exists() {
            fs::read_to_string(&config_toml).unwrap_or_default()
        } else {
            String::new()
        };
        let updated = ensure_features_hooks(&existing);
        if !updated.contains("AhaKey：生命周期 hooks") {
            let final_content = format!(
                "{}\n\n# AhaKey：生命周期 hooks 由 hook_install 写入 ~/.codex/hooks.json\n",
                updated.trim_end()
            );
            if let Err(e) = fs::write(&config_toml, final_content) {
                self.err(&format!("写 Codex config.toml 失败: {}", e));
                return;
            }
            self.log(&format!(
                "已更新 {} ([features].hooks = true)",
                config_toml.display()
            ));
        }
        self.log(&format!("已注册 {} 个 Codex hook 事件", events.len()));
    }

    fn uninstall_codex(&self) {
        let hooks_json = Self::home_dir().join(".codex").join("hooks.json");
        if hooks_json.exists() {
            if let Err(e) = fs::remove_file(&hooks_json) {
                self.err(&format!("删除 hooks.json 失败: {}", e));
            } else {
                self.log(&format!("已删除 {}", hooks_json.display()));
            }
        }
        let sidecar = Self::codex_sidecar();
        if sidecar.exists() {
            let _ = fs::remove_file(&sidecar);
        }
        self.log("已卸载 Codex Hook");
    }

    // ======================== Kimi ========================

    fn install_kimi(&self) {
        let path = Self::config_path(HookPlatform::Kimi);
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        Self::backup_file(&path);
        let existing = if path.exists() {
            fs::read_to_string(&path).unwrap_or_default()
        } else {
            String::new()
        };
        let cleaned = remove_kimi_block(&existing).trim_end().to_string();
        let block = build_kimi_block();
        let result = if cleaned.is_empty() {
            format!("{}\n", block)
        } else {
            format!("{}\n\n{}\n", cleaned, block)
        };
        match fs::write(&path, result) {
            Ok(_) => {
                self.log("已注册 7 个 Kimi hook 事件");
                self.log(&format!("配置文件: {}", path.display()));
            }
            Err(e) => self.err(&format!("写 Kimi config.toml 失败: {}", e)),
        }
    }

    fn uninstall_kimi(&self) {
        let path = Self::config_path(HookPlatform::Kimi);
        if !path.exists() {
            self.log("Kimi 配置文件不存在");
            return;
        }
        let content = match fs::read_to_string(&path) {
            Ok(c) => c,
            Err(e) => {
                self.err(&format!("读 Kimi config.toml 失败: {}", e));
                return;
            }
        };
        let cleaned = remove_kimi_block(&content);
        match fs::write(&path, cleaned) {
            Ok(_) => self.log(&format!("Hook 配置已从 {} 中移除", path.display())),
            Err(e) => self.err(&format!("写 Kimi config.toml 失败: {}", e)),
        }
    }

    // ======================== 工具 ========================

    fn build_hook_command(&self, script_name: &str, event_name: &str) -> String {
        format!(
            "powershell -ExecutionPolicy Bypass -File \"{}/{}\" \"{}\"",
            Self::script_dir().to_string_lossy().replace('\\', "/"),
            script_name,
            event_name
        )
    }

    fn load_json(&self, path: &Path) -> Value {
        if !path.exists() {
            return Value::Object(serde_json::Map::new());
        }
        let content = match fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => return Value::Object(serde_json::Map::new()),
        };
        serde_json::from_str(&content).unwrap_or_else(|_| Value::Object(serde_json::Map::new()))
    }

    fn save_json(&self, path: &Path, value: &Value) -> std::io::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let content = serde_json::to_string_pretty(value)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        fs::write(path, content)
    }
}

/// Codex: 解析 config.toml,确保 [features].hooks = true
fn ensure_features_hooks(content: &str) -> String {
    // 用 toml crate 解析修改,简化:用正则定位 [features] 块
    let parsed: Result<toml::Value, _> = toml::from_str(content);
    let mut doc = parsed.unwrap_or_else(|_| toml::Value::Table(toml::map::Map::new()));
    if !doc.as_table().map(|t| t.contains_key("features")).unwrap_or(false) {
        doc["features"] = toml::Value::Table(toml::map::Map::new());
    }
    let features = doc["features"].as_table_mut().unwrap();
    features.insert("hooks".to_string(), toml::Value::Boolean(true));
    toml::to_string_pretty(&doc).unwrap_or_else(|_| content.to_string())
}

/// Kimi: 在 TOML 中插入 BEGIN/END block
fn build_kimi_block() -> String {
    let events: &[(&str, &str, u32)] = &[
        ("Notification", "KimiNotification", 10),
        ("SessionStart", "KimiSessionStart", 10),
        ("SessionEnd", "KimiSessionEnd", 10),
        ("PreToolUse", "KimiPreToolUse", 20),
        ("PostToolUse", "KimiPostToolUse", 10),
        ("UserPromptSubmit", "KimiUserPromptSubmit", 10),
        ("Stop", "KimiStop", 10),
    ];
    let mut s = String::from("# BEGIN AhaKey Kimi Hooks\n[hooks]\n");
    for (event, internal, timeout) in events {
        s.push_str(&format!(
            "[[hooks.event]]\nname = \"{}\"\ncommand = [\"powershell\", \"-ExecutionPolicy\", \"Bypass\", \"-File\", \"~/.ahakey/hooks/ahakey-kimi.ps1\", \"{}\"]\ntimeout = {}\n",
            event, internal, timeout
        ));
    }
    s.push_str("# END AhaKey Kimi Hooks\n");
    s
}

/// Kimi: 移除 BEGIN/END block
fn remove_kimi_block(content: &str) -> String {
    let start = "# BEGIN AhaKey Kimi Hooks";
    let end = "# END AhaKey Kimi Hooks";
    if let Some(i) = content.find(start) {
        if let Some(j) = content[i..].find(end) {
            let abs_end = i + j + end.len();
            // 也吃掉后面的换行
            let trim_end = content[abs_end..]
                .chars()
                .take_while(|c| *c == '\n' || *c == '\r')
                .count();
            let abs_end = abs_end + trim_end;
            let mut result = String::with_capacity(content.len());
            result.push_str(&content[..i]);
            result.push_str(&content[abs_end..]);
            return result;
        }
    }
    content.to_string()
}

/// 共享 Arc<HookInstaller>(在 state.rs 持有,commands 调)
pub type SharedHookInstaller = Arc<HookInstaller>;
