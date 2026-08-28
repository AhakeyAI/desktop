package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.nio.file.Files;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;
import java.util.function.IntSupplier;

/**
 * Hook 安装器 - 独立于 UI 的 Hook 管理服务
 * 负责所有平台（Claude、Cursor、Codex、Kimi）的 Hook 安装、卸载和脚本生成
 */
public class HookInstaller {

    private final IntSupplier portSupplier;
    private final Consumer<String> logger;
    private final Path userHome;
    private final ObjectMapper mapper = new ObjectMapper();

    // 各平台 Hook 脚本名称
    private static final String CORE_SCRIPT_NAME   = "ahakey-core.ps1";
    private static final String CLAUDE_SCRIPT_NAME = "ahakey-claude.ps1";
    private static final String CODEX_SCRIPT_NAME  = "ahakey-codex.ps1";
    private static final String KIMI_SCRIPT_NAME   = "ahakey-kimi.ps1";
    private static final String CURSOR_SCRIPT_NAME = "ahakey-cursor.ps1";

    // Hook 配置路径常量
    public static final String CODEX_SIDECAR_NAME = ".ahakey_codex_hooks_v1";
    public static final String CODEX_HOOK_BLOCK_START = "# BEGIN AhaKey Codex Hooks";
    public static final String CODEX_HOOK_BLOCK_END = "# END AhaKey Codex Hooks";
    public static final String KIMI_HOOK_BLOCK_START = "# BEGIN AhaKey Kimi Hooks";
    public static final String KIMI_HOOK_BLOCK_END = "# END AhaKey Kimi Hooks";

    // Claude: 9 个事件
    private static final String[][] CLAUDE_EVENTS = {
        {"SessionStart", "10"}, {"SessionEnd", "10"}, {"PreToolUse", "10"},
        {"PostToolUse", "10"}, {"PermissionRequest", "60"}, {"Notification", "10"},
        {"TaskCompleted", "10"}, {"Stop", "10"}, {"UserPromptSubmit", "10"}
    };

    // Cursor: 5 个事件（preToolUse 需要长超时，因为手动模式弹出用户确认对话框）
    private static final String[][] CURSOR_EVENTS = {
        {"sessionStart", "10"}, {"sessionEnd", "10"}, {"preToolUse", "120"},
        {"postToolUse", "10"}, {"stop", "10"}
    };

    // Codex: 6 个事件（与 Python CODEX_HOOK_EVENTS 完全一致）
    private static final String[][] CODEX_EVENTS = {
        {"SessionStart", "CodexSessionStart", "10"},
        {"PostToolUse", "CodexPostToolUse", "10"},
        {"PreToolUse", "CodexPreToolUse", "20"},
        {"PermissionRequest", "CodexPermissionRequest", "20"},
        {"UserPromptSubmit", "CodexUserPromptSubmit", "10"},
        {"Stop", "CodexStop", "10"}
    };

    // Kimi: 7 个事件（与 TopBar.java 及 HookDispatchServer.java 保持一致）
    // 第一列：标准事件名（写入 Kimi 配置文件，必须是 Kimi CLI 支持的值）
    // 第二列：内部事件名（传递给 HookDispatchServer，用于映射到 IDEState）
    private static final String[][] KIMI_EVENTS = {
        {"Notification", "KimiNotification", "10"},
        {"SessionStart", "KimiSessionStart", "10"},
        {"SessionEnd", "KimiSessionEnd", "10"},
        {"PreToolUse", "KimiPreToolUse", "20"},
        {"PostToolUse", "KimiPostToolUse", "10"},
        {"UserPromptSubmit", "KimiUserPromptSubmit", "10"},
        {"Stop", "KimiStop", "10"}
    };

    public HookInstaller(int dispatchPort, Consumer<String> logger) {
        this(Paths.get(System.getProperty("user.home")), () -> dispatchPort, logger);
    }

    public HookInstaller(IntSupplier portSupplier, Consumer<String> logger) {
        this(Paths.get(System.getProperty("user.home")), portSupplier, logger);
    }

    HookInstaller(Path userHome, IntSupplier portSupplier, Consumer<String> logger) {
        this.userHome = userHome.toAbsolutePath().normalize();
        this.portSupplier = portSupplier;
        this.logger = logger;
    }

    private int currentPort() {
        int supplied = portSupplier.getAsInt();
        return supplied > 0 ? supplied : HookDispatchServer.DEFAULT_PORT;
    }

    /**
     * 生成所有 Hook 脚本（core + 各平台专属）
     */
    public void generateAllScripts() {
        Path hooksDir = userHome.resolve(".ahakey").resolve("hooks");
        try {
            Files.createDirectories(hooksDir);
            generateCoreScript(hooksDir);
            generateClaudeScript(hooksDir);
            generateCodexScript(hooksDir);
            generateKimiScript(hooksDir);
            generateCursorScript(hooksDir);
            log("[安装] 已生成所有 Hook 脚本");
        } catch (Exception e) {
            log("[警告] 生成 Hook 脚本失败: " + e.getMessage());
        }
    }

    /**
     * 安装指定平台的 Hook
     */
    public boolean install(String platform) {
        log("[安装] 开始安装 " + platform + " Hook...");
        generateAllScripts();
        switch (platform) {
            case "Claude": installClaudeHooks(); break;
            case "Cursor": installCursorHooks(); break;
            case "Codex": installCodexHooks(); break;
            case "Kimi": installKimiHooks(); break;
            default: {
                log("[错误] 未知 Hook 类型: " + platform);
                return false;
            }
        }
        return isInstalled(platform);
    }

    /**
     * 卸载指定平台的 Hook
     */
    public boolean uninstall(String platform) {
        switch (platform) {
            case "Claude": uninstallClaudeHooks(); break;
            case "Cursor": uninstallCursorHooks(); break;
            case "Codex": uninstallCodexHooks(); break;
            case "Kimi": uninstallKimiHooks(); break;
            default: {
                log("[错误] 未知 Hook 类型: " + platform);
                return false;
            }
        }
        boolean removed = !isInstalled(platform);
        log(removed
            ? "[验证] " + platform + " Hook 已不在配置中"
            : "[错误] " + platform + " Hook 卸载后仍可检测到");
        return removed;
    }

    /**
     * 检查指定平台的 Hook 是否已安装
     */
    public boolean isInstalled(String platform) {
        try {
            Path path = getHookConfigPath(platform);
            Path script = scriptPath(platform);
            if (!Files.isRegularFile(path) || !Files.isRegularFile(script)) return false;
            String content = Files.readString(path, StandardCharsets.UTF_8);
            switch (platform) {
                case "Claude": return containsManagedCommand(
                    mapper.readTree(content), CLAUDE_SCRIPT_NAME);
                case "Cursor": return containsManagedCommand(
                    mapper.readTree(content), CURSOR_SCRIPT_NAME);
                case "Codex": return containsManagedCommand(
                    mapper.readTree(content), CODEX_SCRIPT_NAME);
                case "Kimi": return content.contains(KIMI_HOOK_BLOCK_START) && content.contains(KIMI_HOOK_BLOCK_END);
                default: return false;
            }
        } catch (Exception e) {
            log("[错误] 检查 " + platform + " Hook 状态失败: " + e.getMessage());
            return false;
        }
    }

    // ==================== 脚本生成 ====================

    private void generateCoreScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CORE_SCRIPT_NAME);
        String content =
            "# AhaKey Core - Auto-generated, do not edit\n" +
            "# Contains TCP connection logic, to be dot-sourced by platform-specific scripts\n" +
            "function Test-AhaKeyCanonicalResponse([string]$Text,[string]$ExpectedPlatform,[string]$ExpectedEvent) {\n" +
            "    if ($null -eq $Text) { return $false }\n" +
            "    try { $parsed = $Text | ConvertFrom-Json } catch { return $false }\n" +
            "    if ($null -eq $parsed -or $parsed -is [System.Array]) { return $false }\n" +
            "    $properties = @($parsed.PSObject.Properties)\n" +
            "    $expectedNames = @('schemaVersion','platform','event','allow','approvalSource')\n" +
            "    if ($properties.Count -ne 5) { return $false }\n" +
            "    for ($i=0; $i -lt 5; $i++) { if ($properties[$i].Name -cne $expectedNames[$i]) { return $false } }\n" +
            "    if (-not (($parsed.schemaVersion -is [int]) -or ($parsed.schemaVersion -is [long])) -or $parsed.schemaVersion -ne 1) { return $false }\n" +
            "    if ($parsed.platform -isnot [string] -or $parsed.platform -cne $ExpectedPlatform) { return $false }\n" +
            "    if ($parsed.event -isnot [string] -or $parsed.event -cne $ExpectedEvent) { return $false }\n" +
            "    if ($parsed.allow -isnot [bool]) { return $false }\n" +
            "    if ($parsed.approvalSource -isnot [string] -or @('hardware-auto','user-confirmed','fail-closed') -cnotcontains $parsed.approvalSource) { return $false }\n" +
            "    if ($parsed.allow -and $parsed.approvalSource -ceq 'fail-closed') { return $false }\n" +
            "    if (-not $parsed.allow -and $parsed.approvalSource -cne 'fail-closed') { return $false }\n" +
            "    return $true\n" +
            "}\n" +
            "function Test-AhaKeyCanonicalAllow([string]$Text,[string]$ExpectedPlatform,[string]$ExpectedEvent) {\n" +
            "    if (-not (Test-AhaKeyCanonicalResponse $Text $ExpectedPlatform $ExpectedEvent)) { return $false }\n" +
            "    $hardware = '{\"schemaVersion\":1,\"platform\":\"' + $ExpectedPlatform + '\",\"event\":\"' + $ExpectedEvent + '\",\"allow\":true,\"approvalSource\":\"hardware-auto\"}'\n" +
            "    $confirmed = '{\"schemaVersion\":1,\"platform\":\"' + $ExpectedPlatform + '\",\"event\":\"' + $ExpectedEvent + '\",\"allow\":true,\"approvalSource\":\"user-confirmed\"}'\n" +
            "    return [string]::Equals($Text,$hardware,[System.StringComparison]::Ordinal) -or [string]::Equals($Text,$confirmed,[System.StringComparison]::Ordinal)\n" +
            "}\n" +
            "try {\n" +
            "    if ([Console]::IsInputRedirected) { $hookInput = [Console]::In.ReadToEnd() } else { $hookInput = '' }\n" +
            "} catch { }\n" +
            "try {\n" +
            "    $tcp = New-Object System.Net.Sockets.TcpClient\n" +
            "    $tcp.Connect('127.0.0.1', " + currentPort() + ")\n" +
            "    $writer = New-Object System.IO.StreamWriter($tcp.GetStream())\n" +
            "    $taskId = ''; $title = ''\n" +
            "    try { $j = $hookInput | ConvertFrom-Json; $taskId = @($j.session_id,$j.sessionId,$j.conversation_id,$j.thread_id) | Where-Object { $_ } | Select-Object -First 1; $title = @($j.title,$j.window_title,$j.cwd) | Where-Object { $_ } | Select-Object -First 1 } catch { }\n" +
            "    $payload = @{ cmd=$EventName; taskId=[string]$taskId; title=[string]$title } | ConvertTo-Json -Compress\n" +
            "    $writer.WriteLine($payload)\n" +
            "    $writer.Flush()\n" +
            "    $stream = $tcp.GetStream(); $stream.ReadTimeout = 17000\n" +
            "    $buffer = New-Object byte[] 512; $count = 0; $terminated = $false\n" +
            "    while ($count -lt $buffer.Length) { $read = $stream.Read($buffer,$count,1); if ($read -eq 0) { break }; if ($buffer[$count] -eq 10) { $terminated = $true; break }; $count++ }\n" +
            "    if (-not $terminated) { throw 'AhaKey response exceeded 512 bytes or was truncated' }\n" +
            "    if ($count -gt 0 -and $buffer[$count-1] -eq 13) { $count-- }\n" +
            "    $response = [System.Text.Encoding]::UTF8.GetString($buffer,0,$count)\n" +
            "    $tcp.Close()\n" +
            "} catch {\n" +
            "    $response = $null\n" +
            "}\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    private void generateClaudeScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CLAUDE_SCRIPT_NAME);
        String content =
            "# AhaKey Claude Hook - Auto-generated, do not edit\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Claude PermissionRequest: output hookSpecificOutput in Claude format\n" +
            "if ($EventName -eq 'PermissionRequest') {\n" +
            "    if (Test-AhaKeyCanonicalAllow $response 'claude' 'PermissionRequest') {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"ask\"}}}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Claude lifecycle events never make approval decisions\n" +
            "[Console]::WriteLine('{}')\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    private void generateCodexScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CODEX_SCRIPT_NAME);
        String content =
            "# AhaKey Codex Hook - Auto-generated, do not edit\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Codex PreToolUse: 拨杆手动模式 → ask 用户确认\n" +
            "if ($EventName -eq 'CodexPreToolUse') {\n" +
            "    if (Test-AhaKeyCanonicalAllow $response 'codex' 'CodexPreToolUse') {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"decision\":{\"behavior\":\"ask\"}}}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Codex PermissionRequest: 拨杆手动模式 → ask 用户确认\n" +
            "if ($EventName -eq 'CodexPermissionRequest') {\n" +
            "    if (Test-AhaKeyCanonicalAllow $response 'codex' 'CodexPermissionRequest') {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"ask\"}}}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Codex 其他 lifecycle hooks must output exactly {} (Codex validates JSON schema)\n" +
            "[Console]::WriteLine('{}')\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    private void generateKimiScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(KIMI_SCRIPT_NAME);
        String content =
            "# AhaKey Kimi Hook - Auto-generated, do not edit\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Kimi PreToolUse: canonical internal allow is translated to Kimi's empty object\n" +
            "if ($EventName -eq 'KimiPreToolUse') {\n" +
            "    if (Test-AhaKeyCanonicalAllow $response 'kimi' 'KimiPreToolUse') { [Console]::WriteLine('{}'); exit 0 }\n" +
            "    [Console]::WriteLine('{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"AhaKey approval state is unavailable\"}}')\n" +
            "    exit 1\n" +
            "}\n" +
            "# Kimi lifecycle events do not make approval decisions\n" +
            "if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{\"ok\":false}') }\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    private void generateCursorScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CURSOR_SCRIPT_NAME);
        String content =
            "# AhaKey Cursor Hook - Auto-generated, do not edit\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Cursor: translate only an exact canonical internal allow\n" +
            "if ($EventName -eq 'preToolUse' -and (Test-AhaKeyCanonicalAllow $response 'cursor' 'preToolUse')) {\n" +
            "    [Console]::WriteLine('{\"permission\":\"allow\"}')\n" +
            "    exit 0\n" +
            "}\n";
        content +=
            "[Console]::WriteLine('{\"permission\":\"deny\",\"user_message\":\"AhaKey Desktop is unavailable or returned an invalid response; manual approval is required\"}')\n" +
            "exit 1\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    // ==================== 安装方法 ====================

    private void installClaudeHooks() {
        Path path = getHookConfigPath("Claude");
        try {
            Files.createDirectories(path.getParent());
            backupFile(path);
            ObjectNode settings = loadJsonSettings(path);
            ObjectNode hooks = hooksObject(settings);
            for (String[] ev : CLAUDE_EVENTS) {
                ObjectNode cmd = mapper.createObjectNode();
                cmd.put("type", "command");
                cmd.put("command", buildHookCommand(CLAUDE_SCRIPT_NAME, ev[0]));
                cmd.put("timeout", Integer.parseInt(ev[1]));
                ArrayNode inner = mapper.createArrayNode();
                inner.add(cmd);
                ObjectNode wrapper = mapper.createObjectNode();
                wrapper.put("matcher", "");
                wrapper.set("hooks", inner);
                ArrayNode outer = eventArray(hooks, ev[0]);
                removeManagedEntries(outer, CLAUDE_SCRIPT_NAME, true);
                outer.add(wrapper);
            }
            settings.set("hooks", hooks);
            writeJsonAtomically(path, settings);
            log("[成功] 已注册 " + CLAUDE_EVENTS.length + " 个 Claude hook 事件");
            log("[成功] 配置文件: " + path);
        } catch (Exception e) { log("[错误] Claude 安装失败: " + e.getMessage()); }
    }

    private void installCursorHooks() {
        Path path = getHookConfigPath("Cursor");
        try {
            Files.createDirectories(path.getParent());
            backupFile(path);
            ObjectNode settings = loadJsonSettings(path);
            ObjectNode existingHooks = hooksObject(settings);
            for (String[] ev : CURSOR_EVENTS) {
                ObjectNode entry = mapper.createObjectNode();
                entry.put("command", buildHookCommand(CURSOR_SCRIPT_NAME, ev[0]));
                entry.put("timeout", Integer.parseInt(ev[1]));
                ArrayNode arr = eventArray(existingHooks, ev[0]);
                removeManagedEntries(arr, CURSOR_SCRIPT_NAME, false);
                arr.add(entry);
            }
            settings.set("hooks", existingHooks);
            settings.put("version", 1);
            writeJsonAtomically(path, settings);
            log("[成功] 已注册 " + CURSOR_EVENTS.length + " 个 Cursor hook 事件");
            log("[成功] 配置文件: " + path);
        } catch (Exception e) { log("[错误] Cursor 安装失败: " + e.getMessage()); }
    }

    private void installCodexHooks() {
        Path hooksJson = userHome.resolve(".codex").resolve("hooks.json");
        Path configToml = userHome.resolve(".codex").resolve("config.toml");
        Path sidecar = userHome.resolve(".codex").resolve(CODEX_SIDECAR_NAME);
        try {
            Files.createDirectories(hooksJson.getParent());
            backupFile(hooksJson);
            ObjectNode root = loadJsonSettings(hooksJson);
            ObjectNode hooks = hooksObject(root);
            for (String[] ev : CODEX_EVENTS) {
                ObjectNode cmd = mapper.createObjectNode();
                cmd.put("type", "command");
                cmd.put("command", buildHookCommand(CODEX_SCRIPT_NAME, ev[1]));
                cmd.put("timeout", Integer.parseInt(ev[2]));
                ArrayNode innerArr = mapper.createArrayNode();
                innerArr.add(cmd);
                ObjectNode entry = mapper.createObjectNode();
                if ("SessionStart".equals(ev[0])) {
                    entry.put("matcher", "startup|resume|clear");
                } else if ("UserPromptSubmit".equals(ev[0]) || "Stop".equals(ev[0])) {
                    // no matcher
                } else {
                    entry.put("matcher", "*");
                }
                entry.set("hooks", innerArr);
                ArrayNode outerArr = eventArray(hooks, ev[0]);
                removeManagedEntries(outerArr, CODEX_SCRIPT_NAME, true);
                outerArr.add(entry);
            }
            root.set("hooks", hooks);
            writeJsonAtomically(hooksJson, root);
            log("[成功] 已写入 " + hooksJson);
            Files.write(sidecar, java.time.LocalDateTime.now().toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
            backupFile(configToml);
            String toml = configToml.toFile().exists()
                ? new String(Files.readAllBytes(configToml), java.nio.charset.StandardCharsets.UTF_8)
                : "";
            toml = removeCodexHookBlock(toml);
            toml = ensureCodexHooksFeature(toml);
            toml = toml.trim() + "\n\n" + CODEX_HOOK_BLOCK_START
                + "\n# AhaKey：生命周期 hooks 由 AhaKey Studio 写入 ~/.codex/hooks.json\n"
                + CODEX_HOOK_BLOCK_END + "\n";
            writeTextAtomically(configToml, toml);
            log("[成功] 已更新 " + configToml + "（[features].hooks = true）");
            log("[成功] 已注册 " + CODEX_EVENTS.length + " 个 Codex hook 事件");
        } catch (Exception e) { log("[错误] Codex 安装失败: " + e.getMessage()); }
    }

    private void installKimiHooks() {
        Path path = getHookConfigPath("Kimi");
        try {
            Files.createDirectories(path.getParent());
            backupFile(path);
            String existing = path.toFile().exists()
                ? new String(Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8)
                : "";
            String cleaned = removeKimiHookBlock(existing).trim();
            String hookBlock = buildKimiHookBlock();
            String result = (cleaned.isEmpty() ? "" : cleaned + "\n\n") + hookBlock + "\n";
            writeTextAtomically(path, result);
            log("[成功] 已注册 " + KIMI_EVENTS.length + " 个 Kimi hook 事件");
            log("[成功] 配置文件: " + path);
        } catch (Exception e) { log("[错误] Kimi 安装失败: " + e.getMessage()); }
    }

    // ==================== 卸载方法 ====================

    private void uninstallClaudeHooks() {
        Path path = getHookConfigPath("Claude");
        try {
            if (!path.toFile().exists()) { log("[信息] Claude 配置文件不存在"); return; }
            ObjectNode settings = loadJsonSettings(path);
            if (removeManagedHooks(settings, CLAUDE_SCRIPT_NAME, true)) {
                writeJsonAtomically(path, settings);
                log("[成功] Hook 配置已从 " + path + " 中移除");
            } else {
                log("[警告] 未找到 Claude Hook 配置");
            }
        } catch (Exception e) { log("[错误] Claude 卸载失败: " + e.getMessage()); }
    }

    private void uninstallCursorHooks() {
        Path path = getHookConfigPath("Cursor");
        try {
            if (!path.toFile().exists()) { log("[信息] Cursor 配置文件不存在"); return; }
            ObjectNode settings = loadJsonSettings(path);
            if (removeManagedHooks(settings, CURSOR_SCRIPT_NAME, false)) {
                writeJsonAtomically(path, settings);
                log("[成功] Hook 配置已从 " + path + " 中移除");
            } else {
                log("[警告] 未找到 Cursor Hook 配置");
            }
        } catch (Exception e) { log("[错误] Cursor 卸载失败: " + e.getMessage()); }
    }

    private void uninstallCodexHooks() {
        Path hooksJson = userHome.resolve(".codex").resolve("hooks.json");
        Path configToml = userHome.resolve(".codex").resolve("config.toml");
        Path sidecar = userHome.resolve(".codex").resolve(CODEX_SIDECAR_NAME);
        try {
            if (sidecar.toFile().exists()) {
                Files.delete(sidecar);
                log("[成功] 已删除 sidecar 标记");
            } else {
                log("[信息] sidecar 标记不存在");
            }
            if (hooksJson.toFile().exists()) {
                ObjectNode settings = loadJsonSettings(hooksJson);
                if (removeManagedHooks(settings, CODEX_SCRIPT_NAME, true)) {
                    writeJsonAtomically(hooksJson, settings);
                    log("[成功] Hook 配置已从 " + hooksJson + " 中移除");
                }
            }
            if (configToml.toFile().exists()) {
                String content = new String(Files.readAllBytes(configToml), java.nio.charset.StandardCharsets.UTF_8);
                String cleaned = removeCodexHookBlock(content);
                if (!cleaned.equals(content)) {
                    writeTextAtomically(configToml, cleaned);
                    log("[成功] Hook 块已从 " + configToml + " 中移除");
                }
            }
        } catch (Exception e) { log("[错误] Codex 卸载失败: " + e.getMessage()); }
    }

    private void uninstallKimiHooks() {
        Path path = getHookConfigPath("Kimi");
        try {
            if (!path.toFile().exists()) { log("[信息] Kimi 配置文件不存在"); return; }
            String content = new String(Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
            String cleaned = removeKimiHookBlock(content);
            if (!cleaned.equals(content)) {
                writeTextAtomically(path, cleaned);
                log("[成功] Hook 块已从配置文件中删除");
            } else {
                log("[警告] 未找到 AhaKey Hook 块");
            }
        } catch (Exception e) { log("[错误] Kimi 卸载失败: " + e.getMessage()); }
    }

    // ==================== 辅助方法 ====================

    private String buildHookCommand(String scriptName, String agentEvent) {
        Path scriptPath = userHome.resolve(".ahakey").resolve("hooks").resolve(scriptName);
        String ps = scriptPath.toString().replace("\\", "/");
        return "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + ps + "\" " + agentEvent;
    }

    public Path getHookConfigPath(String hookName) {
        return switch (hookName) {
            case "Claude" -> userHome.resolve(".claude").resolve("settings.json");
            case "Cursor" -> userHome.resolve(".cursor").resolve("hooks.json");
            case "Codex" -> userHome.resolve(".codex").resolve("hooks.json");
            case "Kimi" -> userHome.resolve(".config").resolve("kimi-cli").resolve("hooks.json");
            default -> userHome.resolve(".ahakey").resolve("hooks")
                .resolve("ahakey-" + hookName.toLowerCase() + ".ps1");
        };
    }

    private Path scriptPath(String platform) {
        String scriptName = switch (platform) {
            case "Claude" -> CLAUDE_SCRIPT_NAME;
            case "Cursor" -> CURSOR_SCRIPT_NAME;
            case "Codex" -> CODEX_SCRIPT_NAME;
            case "Kimi" -> KIMI_SCRIPT_NAME;
            default -> throw new IllegalArgumentException("Unknown Hook platform: " + platform);
        };
        return userHome.resolve(".ahakey").resolve("hooks").resolve(scriptName);
    }

    private ObjectNode hooksObject(ObjectNode settings) throws Exception {
        JsonNode existing = settings.get("hooks");
        if (existing == null || existing.isNull()) {
            ObjectNode hooks = mapper.createObjectNode();
            settings.set("hooks", hooks);
            return hooks;
        }
        if (!(existing instanceof ObjectNode hooks)) {
            throw new IllegalStateException("Existing hooks configuration is not an object");
        }
        return hooks;
    }

    private ArrayNode eventArray(ObjectNode hooks, String eventName) {
        JsonNode existing = hooks.get(eventName);
        if (existing == null || existing.isNull()) {
            ArrayNode events = mapper.createArrayNode();
            hooks.set(eventName, events);
            return events;
        }
        if (!(existing instanceof ArrayNode events)) {
            throw new IllegalStateException(
                "Existing hook event " + eventName + " is not an array");
        }
        return events;
    }

    private boolean removeManagedEntries(
        ArrayNode entries,
        String scriptName,
        boolean nestedHooks
    ) {
        boolean changed = false;
        for (int index = entries.size() - 1; index >= 0; index--) {
            JsonNode entry = entries.get(index);
            if (nestedHooks && entry instanceof ObjectNode wrapper
                && wrapper.get("hooks") instanceof ArrayNode commands) {
                boolean wrapperChanged = false;
                for (int commandIndex = commands.size() - 1;
                     commandIndex >= 0;
                     commandIndex--) {
                    if (isManagedCommand(commands.get(commandIndex), scriptName)) {
                        commands.remove(commandIndex);
                        changed = true;
                        wrapperChanged = true;
                    }
                }
                if (wrapperChanged && commands.isEmpty()) {
                    entries.remove(index);
                }
            } else if (isManagedCommand(entry, scriptName)) {
                entries.remove(index);
                changed = true;
            }
        }
        return changed;
    }

    private boolean removeManagedHooks(
        ObjectNode settings,
        String scriptName,
        boolean nestedHooks
    ) {
        JsonNode node = settings.get("hooks");
        if (!(node instanceof ObjectNode hooks)) {
            return false;
        }
        boolean changed = false;
        List<String> eventNames = new ArrayList<>();
        hooks.fieldNames().forEachRemaining(eventNames::add);
        for (String eventName : eventNames) {
            JsonNode eventNode = hooks.get(eventName);
            if (!(eventNode instanceof ArrayNode entries)) {
                continue;
            }
            boolean eventChanged = removeManagedEntries(
                entries, scriptName, nestedHooks);
            changed |= eventChanged;
            if (eventChanged && entries.isEmpty()) {
                hooks.remove(eventName);
            }
        }
        if (changed && hooks.isEmpty()) {
            settings.remove("hooks");
        }
        return changed;
    }

    private boolean containsManagedCommand(JsonNode node, String scriptName) {
        if (node == null) return false;
        if (isManagedCommand(node, scriptName)) return true;
        if (node.isContainerNode()) {
            for (JsonNode child : node) {
                if (containsManagedCommand(child, scriptName)) return true;
            }
        }
        return false;
    }

    private boolean isManagedCommand(JsonNode node, String scriptName) {
        if (!(node instanceof ObjectNode object)) return false;
        JsonNode command = object.get("command");
        if (command == null || !command.isTextual()) return false;
        String normalized = command.asText().replace('\\', '/').toLowerCase();
        return normalized.contains("/.ahakey/hooks/")
            && normalized.contains(scriptName.toLowerCase());
    }

    private void writeJsonAtomically(Path path, ObjectNode value) throws Exception {
        Files.createDirectories(path.getParent());
        Path temporary = Files.createTempFile(
            path.getParent(), path.getFileName().toString(), ".tmp");
        try {
            mapper.writerWithDefaultPrettyPrinter().writeValue(temporary.toFile(), value);
            replaceAtomically(temporary, path);
        } finally {
            Files.deleteIfExists(temporary);
        }
    }

    private void writeTextAtomically(Path path, String value) throws Exception {
        Files.createDirectories(path.getParent());
        Path temporary = Files.createTempFile(
            path.getParent(), path.getFileName().toString(), ".tmp");
        try {
            Files.writeString(temporary, value, StandardCharsets.UTF_8);
            replaceAtomically(temporary, path);
        } finally {
            Files.deleteIfExists(temporary);
        }
    }

    private void replaceAtomically(Path temporary, Path target) throws Exception {
        try {
            Files.move(temporary, target,
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING);
        } catch (AtomicMoveNotSupportedException exception) {
            Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private ObjectNode loadJsonSettings(Path path) throws Exception {
        if (!path.toFile().exists()) {
            return mapper.createObjectNode();
        }
        JsonNode node = mapper.readTree(path.toFile());
        if (node instanceof ObjectNode object) {
            return object;
        }
        throw new IllegalStateException(
            "Existing JSON configuration root is not an object: " + path);
    }

    private void backupFile(Path path) throws Exception {
        if (path.toFile().exists()) {
            Path backup = path.resolveSibling(path.getFileName() + ".bak");
            Files.copy(path, backup, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private String buildKimiHookBlock() {
        StringBuilder sb = new StringBuilder();
        sb.append(KIMI_HOOK_BLOCK_START).append("\n");
        sb.append("# Managed by AhaKey. Kimi CLI hooks run this installer with Kimi* event names.\n");
        sb.append("# Re-run Install Kimi Hooks after upgrading kimi-cli so the dial-control patch is restored.\n");
        for (String[] ev : KIMI_EVENTS) {
            sb.append("\n[[hooks]]\n");
            sb.append("event = \"").append(ev[0]).append("\"\n");
            sb.append("matcher = \"\"\n");
            sb.append("command = \"").append(tomlEscape(buildHookCommand(KIMI_SCRIPT_NAME, ev[1]))).append("\"\n");
            sb.append("timeout = ").append(ev[2]).append("\n");
        }
        sb.append("\n").append(KIMI_HOOK_BLOCK_END).append("\n");
        return sb.toString();
    }

    private String tomlEscape(String s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private String removeKimiHookBlock(String content) {
        return removeBlock(content, KIMI_HOOK_BLOCK_START, KIMI_HOOK_BLOCK_END);
    }

    private String removeCodexHookBlock(String content) {
        return removeBlock(content, CODEX_HOOK_BLOCK_START, CODEX_HOOK_BLOCK_END);
    }

    private String removeBlock(String content, String startMarker, String endMarker) {
        String result = content;
        while (true) {
            int start = result.indexOf(startMarker);
            if (start == -1) break;
            int end = result.indexOf(endMarker, start);
            if (end == -1) break;
            result = result.substring(0, start).trim() + "\n" + result.substring(end + endMarker.length()).trim();
        }
        return result.trim();
    }

    private String ensureCodexHooksFeature(String toml) {
        List<String> lines = new ArrayList<>(List.of(toml.split("\\R", -1)));
        int featuresStart = -1;
        for (int index = 0; index < lines.size(); index++) {
            if ("[features]".equals(lines.get(index).trim())) {
                featuresStart = index;
                break;
            }
        }
        if (featuresStart < 0) {
            String prefix = toml.trim();
            return (prefix.isEmpty() ? "" : prefix + "\n\n")
                + "[features]\nhooks = true";
        }

        int sectionEnd = lines.size();
        for (int index = featuresStart + 1; index < lines.size(); index++) {
            String line = lines.get(index).trim();
            if (line.startsWith("[") && line.endsWith("]")) {
                sectionEnd = index;
                break;
            }
        }
        for (int index = featuresStart + 1; index < sectionEnd; index++) {
            if (lines.get(index).matches("\\s*hooks\\s*=.*")) {
                lines.set(index, "hooks = true");
                return String.join("\n", lines);
            }
        }
        lines.add(featuresStart + 1, "hooks = true");
        return String.join("\n", lines);
    }

    private void log(String message) {
        if (logger != null) {
            logger.accept(message);
        }
    }
}
