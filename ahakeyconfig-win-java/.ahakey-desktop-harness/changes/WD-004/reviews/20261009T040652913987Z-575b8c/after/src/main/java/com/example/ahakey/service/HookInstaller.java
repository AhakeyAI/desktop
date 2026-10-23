package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Arrays;
import java.util.Map;
import java.util.function.Consumer;
import java.util.function.IntSupplier;

/**
 * Hook 安装器 - 独立于 UI 的 Hook 管理服务
 * 负责所有平台（Claude、Cursor、Codex、Kimi）的 Hook 安装、卸载和脚本生成
 */
public class HookInstaller {

    private final IntSupplier portSupplier;
    private final Consumer<String> logger;
    private final ObjectMapper mapper = new ObjectMapper();

    // 各平台 Hook 脚本名称
    private static final String CORE_SCRIPT_NAME   = "ahakey-core.ps1";
    private static final String CLAUDE_SCRIPT_NAME = "ahakey-claude.ps1";
    private static final String CODEX_SCRIPT_NAME  = "ahakey-codex.ps1";
    private static final String KIMI_SCRIPT_NAME   = "ahakey-kimi.ps1";
    private static final String CURSOR_SCRIPT_NAME = "ahakey-cursor.ps1";

    // Hook 配置路径常量
    public static final String CODEX_SIDECAR_NAME = ".ahakey_codex_hooks_v1";
    public static final String AHAKEY_HOOK_VERSION = "ws3-cp1-v1";
    public enum HookStatus { DETECTING, APP_NOT_FOUND, NOT_INSTALLED, OUTDATED, LATEST, ERROR }
    public record HookWriteResult(boolean success, String reason) {}
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
        this(() -> dispatchPort, logger);
    }

    public HookInstaller(IntSupplier portSupplier, Consumer<String> logger) {
        this.portSupplier = portSupplier;
        this.logger = logger;
    }

    private int currentPort() {
        return portSupplier.getAsInt();
    }

    /**
     * 生成所有 Hook 脚本（core + 各平台专属）
     */
    public void generateAllScripts() {
        String home = System.getProperty("user.home");
        Path hooksDir = Paths.get(home, ".ahakey", "hooks");
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

    private void generateAllScriptsStrict() throws Exception {
        String home = System.getProperty("user.home");
        Path hooksDir = Paths.get(home, ".ahakey", "hooks");
        Files.createDirectories(hooksDir);
        generateCoreScript(hooksDir);
        generateClaudeScript(hooksDir);
        generateCodexScript(hooksDir);
        generateKimiScript(hooksDir);
        generateCursorScript(hooksDir);
        log("[安装] 已生成所有 Hook 脚本");
    }

    /**
     * 安装指定平台的 Hook
     */
    public void install(String platform) {
        installOrUpdate(platform);
    }

    public HookWriteResult installOrUpdate(String platform) {
        log("[安装] 开始安装 " + platform + " Hook...");
        try {
            generateAllScriptsStrict();
            switch (platform) {
                case "Claude": installClaudeHooks(); break;
                case "Cursor": installCursorHooks(); break;
                case "Codex": installCodexHooks(); break;
                case "Kimi": installKimiHooks(); break;
                default: throw new IllegalArgumentException("未知 Hook 类型: " + platform);
            }
            return new HookWriteResult(true, "");
        } catch (Exception e) {
            String reason = classifyFailure(e);
            log("[错误] " + platform + " 安装失败: " + reason + " - " + e.getMessage());
            return new HookWriteResult(false, reason);
        }
    }

    /**
     * 卸载指定平台的 Hook
     */
    public void uninstall(String platform) {
        switch (platform) {
            case "Claude": uninstallClaudeHooks(); break;
            case "Cursor": uninstallCursorHooks(); break;
            case "Codex": uninstallCodexHooks(); break;
            case "Kimi": uninstallKimiHooks(); break;
            default: log("[错误] 未知 Hook 类型: " + platform);
        }
    }

    /**
     * 检查指定平台的 Hook 是否已安装
     */
    public boolean isInstalled(String platform) {
        try {
            Path path = getHookConfigPath(platform);
            if (!path.toFile().exists()) return false;
            String content = new String(Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
            switch (platform) {
                case "Claude": return content.contains("ahakey-claude.ps1");
                case "Cursor": return content.contains("\"command\"") && content.contains("ahakey-cursor.ps1");
                case "Codex": {
                    Path sidecar = Paths.get(System.getProperty("user.home"), ".codex", CODEX_SIDECAR_NAME);
                    return sidecar.toFile().exists();
                }
                case "Kimi": return content.contains(KIMI_HOOK_BLOCK_START) && content.contains(KIMI_HOOK_BLOCK_END);
                default: return false;
            }
        } catch (Exception e) {
            log("[错误] 检查 " + platform + " Hook 状态失败: " + e.getMessage());
            return false;
        }
    }

    public HookStatus getHookStatus(String platform) {
        try {
            if (!isAppDetected(platform)) {
                return HookStatus.APP_NOT_FOUND;
            }
            Path script = Paths.get(System.getProperty("user.home"), ".ahakey", "hooks", switch (platform) {
                case "Codex" -> CODEX_SCRIPT_NAME;
                case "Cursor" -> CURSOR_SCRIPT_NAME;
                case "Claude" -> CLAUDE_SCRIPT_NAME;
                case "Kimi" -> KIMI_SCRIPT_NAME;
                default -> "";
            });
            if (!isInstalled(platform)) {
                return HookStatus.NOT_INSTALLED;
            }
            if (!Files.exists(script)) {
                return HookStatus.OUTDATED;
            }
            String scriptContent = Files.readString(script, java.nio.charset.StandardCharsets.UTF_8);
            if (!scriptContent.contains(AHAKEY_HOOK_VERSION)) {
                return HookStatus.OUTDATED;
            }
            if ("Codex".equals(platform)) {
                Path sidecar = Paths.get(System.getProperty("user.home"), ".codex", CODEX_SIDECAR_NAME);
                String sidecarContent = Files.exists(sidecar)
                    ? Files.readString(sidecar, java.nio.charset.StandardCharsets.UTF_8)
                    : "";
                return sidecarContent.contains(AHAKEY_HOOK_VERSION) ? HookStatus.LATEST : HookStatus.OUTDATED;
            }
            if ("Cursor".equals(platform)) {
                String config = Files.readString(getHookConfigPath("Cursor"), java.nio.charset.StandardCharsets.UTF_8);
                return config.contains(CURSOR_SCRIPT_NAME) ? HookStatus.LATEST : HookStatus.OUTDATED;
            }
            return HookStatus.LATEST;
        } catch (Exception e) {
            log("[错误] 检查 " + platform + " Hook 状态失败: " + e.getMessage());
            return HookStatus.ERROR;
        }
    }

    // ==================== 脚本生成 ====================

    private void generateCoreScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CORE_SCRIPT_NAME);
        String content =
            "# AhaKey Core - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "# Contains TCP connection logic, to be dot-sourced by platform-specific scripts\n" +
            "try {\n" +
            "    $stdinText = $null\n" +
            "    if ([Console]::IsInputRedirected) { $stdinText = [Console]::In.ReadToEnd() }\n" +
            "} catch { }\n" +
            "$payload = [ordered]@{ cmd = $EventName; ahakeyHookVersion = '" + AHAKEY_HOOK_VERSION + "' }\n" +
            "if ($stdinText -and $stdinText.Trim().Length -gt 0) {\n" +
            "    try { $payload.hookInput = ($stdinText | ConvertFrom-Json) } catch { $payload.hookInputRaw = $stdinText }\n" +
            "}\n" +
            "$jsonLine = ($payload | ConvertTo-Json -Depth 20 -Compress)\n" +
            "try {\n" +
            "    $tcp = New-Object System.Net.Sockets.TcpClient\n" +
            "    $tcp.Connect('127.0.0.1', " + currentPort() + ")\n" +
            "    $writer = New-Object System.IO.StreamWriter($tcp.GetStream())\n" +
            "    $writer.WriteLine($jsonLine)\n" +
            "    $writer.Flush()\n" +
            "    $reader = New-Object System.IO.StreamReader($tcp.GetStream())\n" +
            "    $response = $reader.ReadLine()\n" +
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
            "    $isAuto = $response -match '\"autoApproved\"\\s*:\\s*true'\n" +
            "    if ($isAuto) {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"ask\"}}}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Claude lifecycle events: pass through server response\n" +
            "if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{\"ok\":true}') }\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    private void generateCodexScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CODEX_SCRIPT_NAME);
        String content =
            "# AhaKey Codex Hook - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Codex PreToolUse: 拨杆手动模式 → ask 用户确认\n" +
            "if ($EventName -eq 'CodexPreToolUse') {\n" +
            "    if ($response -match '\"autoApproved\"\\s*:\\s*true') {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"decision\":{\"behavior\":\"ask\"}}}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Codex PermissionRequest: 拨杆手动模式 → ask 用户确认\n" +
            "if ($EventName -eq 'CodexPermissionRequest') {\n" +
            "    if ($response -match '\"autoApproved\"\\s*:\\s*true') {\n" +
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
            "# Kimi: pass through server response (Kimi 特有格式)\n" +
            "if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{\"ok\":true}') }\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    private void generateCursorScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CURSOR_SCRIPT_NAME);
        String content =
            "# AhaKey Cursor Hook - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Cursor: only explicit auto-approval outputs allow; otherwise Cursor keeps native behavior\n" +
            "if ($response -and $response -match '\"permission\"\\s*:\\s*\"allow\"') {\n" +
            "    [Console]::WriteLine('{\"permission\":\"allow\"}')\n" +
            "}\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    // ==================== 安装方法 ====================

    private void installClaudeHooks() {
        Path path = getHookConfigPath("Claude");
        try {
            Files.createDirectories(path.getParent());
            backupFile(path);
            ObjectNode settings = loadJsonSettings(path);
            ObjectNode hooks = settings.has("hooks") && settings.get("hooks").isObject()
                ? (ObjectNode) settings.get("hooks")
                : mapper.createObjectNode();
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
                ArrayNode outer = hooks.has(ev[0]) && hooks.get(ev[0]).isArray()
                    ? keepNonAhaKeyClaudeEntries((ArrayNode) hooks.get(ev[0]), CLAUDE_SCRIPT_NAME)
                    : mapper.createArrayNode();
                outer.add(wrapper);
                hooks.set(ev[0], outer);
            }
            settings.set("hooks", hooks);
            mapper.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
            log("[成功] 已注册 " + CLAUDE_EVENTS.length + " 个 Claude hook 事件");
            log("[成功] 配置文件: " + path);
        } catch (Exception e) { log("[错误] Claude 安装失败: " + e.getMessage()); throw new RuntimeException(e); }
    }

    private void installCursorHooks() {
        Path path = getHookConfigPath("Cursor");
        try {
            Files.createDirectories(path.getParent());
            backupFile(path);
            ObjectNode settings = loadJsonSettings(path);
            ObjectNode existingHooks = settings.has("hooks") ? (ObjectNode) settings.get("hooks") : mapper.createObjectNode();
            for (String[] ev : CURSOR_EVENTS) {
                ObjectNode entry = mapper.createObjectNode();
                entry.put("command", buildHookCommand(CURSOR_SCRIPT_NAME, ev[0]));
                entry.put("timeout", Integer.parseInt(ev[1]));
                ArrayNode arr = existingHooks.has(ev[0]) && existingHooks.get(ev[0]).isArray()
                    ? keepNonAhaKeyEntries((ArrayNode) existingHooks.get(ev[0]), CURSOR_SCRIPT_NAME)
                    : mapper.createArrayNode();
                arr.add(entry);
                existingHooks.set(ev[0], arr);
            }
            settings.set("hooks", existingHooks);
            settings.put("version", 1);
            mapper.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
            log("[成功] 已注册 " + CURSOR_EVENTS.length + " 个 Cursor hook 事件");
            log("[成功] 配置文件: " + path);
        } catch (Exception e) { log("[错误] Cursor 安装失败: " + e.getMessage()); throw new RuntimeException(e); }
    }

    private void installCodexHooks() {
        String home = System.getProperty("user.home");
        Path hooksJson = Paths.get(home, ".codex", "hooks.json");
        Path configToml = Paths.get(home, ".codex", "config.toml");
        Path sidecar = Paths.get(home, ".codex", CODEX_SIDECAR_NAME);
        try {
            Files.createDirectories(hooksJson.getParent());
            backupFile(hooksJson);
            ObjectNode root = loadJsonSettings(hooksJson);
            ObjectNode hooks = root.has("hooks") && root.get("hooks").isObject()
                ? (ObjectNode) root.get("hooks")
                : mapper.createObjectNode();
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
                ArrayNode outerArr = hooks.has(ev[0]) && hooks.get(ev[0]).isArray()
                    ? keepNonAhaKeyCodexEntries((ArrayNode) hooks.get(ev[0]), CODEX_SCRIPT_NAME)
                    : mapper.createArrayNode();
                outerArr.add(entry);
                hooks.set(ev[0], outerArr);
            }
            root.set("hooks", hooks);
            mapper.writerWithDefaultPrettyPrinter().writeValue(hooksJson.toFile(), root);
            log("[成功] 已写入 " + hooksJson);
            Files.write(sidecar, (AHAKEY_HOOK_VERSION + "\n" + java.time.LocalDateTime.now()).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            backupFile(configToml);
            String toml = configToml.toFile().exists()
                ? new String(Files.readAllBytes(configToml), java.nio.charset.StandardCharsets.UTF_8)
                : "";
            toml = removeCodexHookBlock(toml);
            toml = ensureCodexHooksFeature(toml);
            if (!toml.contains("AhaKey：生命周期 hooks")) {
                toml = toml.trim() + "\n\n# AhaKey：生命周期 hooks 由 hook_install 写入 ~/.codex/hooks.json\n";
            }
            Files.write(configToml, toml.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            log("[成功] 已更新 " + configToml + "（[features].hooks = true）");
            log("[成功] 已注册 " + CODEX_EVENTS.length + " 个 Codex hook 事件");
        } catch (Exception e) { log("[错误] Codex 安装失败: " + e.getMessage()); throw new RuntimeException(e); }
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
            Files.write(path, result.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            log("[成功] 已注册 " + KIMI_EVENTS.length + " 个 Kimi hook 事件");
            log("[成功] 配置文件: " + path);
        } catch (Exception e) { log("[错误] Kimi 安装失败: " + e.getMessage()); throw new RuntimeException(e); }
    }

    // ==================== 卸载方法 ====================

    private void uninstallClaudeHooks() {
        Path path = getHookConfigPath("Claude");
        try {
            if (!path.toFile().exists()) { log("[信息] Claude 配置文件不存在"); return; }
            ObjectNode settings = loadJsonSettings(path);
            if (settings.has("hooks")) {
                settings.remove("hooks");
                mapper.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
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
            if (settings.has("hooks")) {
                settings.remove("hooks");
                mapper.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
                log("[成功] Hook 配置已从 " + path + " 中移除");
            } else {
                log("[警告] 未找到 Cursor Hook 配置");
            }
        } catch (Exception e) { log("[错误] Cursor 卸载失败: " + e.getMessage()); }
    }

    private void uninstallCodexHooks() {
        String home = System.getProperty("user.home");
        Path hooksJson = Paths.get(home, ".codex", "hooks.json");
        Path configToml = Paths.get(home, ".codex", "config.toml");
        Path sidecar = Paths.get(home, ".codex", CODEX_SIDECAR_NAME);
        try {
            if (sidecar.toFile().exists()) {
                Files.delete(sidecar);
                log("[成功] 已删除 sidecar 标记");
            } else {
                log("[信息] sidecar 标记不存在");
            }
            if (hooksJson.toFile().exists()) {
                ObjectNode settings = loadJsonSettings(hooksJson);
                if (settings.has("hooks")) {
                    settings.remove("hooks");
                    mapper.writerWithDefaultPrettyPrinter().writeValue(hooksJson.toFile(), settings);
                    log("[成功] Hook 配置已从 " + hooksJson + " 中移除");
                }
            }
            if (configToml.toFile().exists()) {
                String content = new String(Files.readAllBytes(configToml), java.nio.charset.StandardCharsets.UTF_8);
                String cleaned = removeCodexHookBlock(content);
                if (!cleaned.equals(content)) {
                    Files.write(configToml, cleaned.getBytes(java.nio.charset.StandardCharsets.UTF_8));
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
                Files.write(path, cleaned.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                log("[成功] Hook 块已从配置文件中删除");
            } else {
                log("[警告] 未找到 AhaKey Hook 块");
            }
        } catch (Exception e) { log("[错误] Kimi 卸载失败: " + e.getMessage()); }
    }

    // ==================== 辅助方法 ====================

    private String buildHookCommand(String scriptName, String agentEvent) {
        String home = System.getProperty("user.home");
        Path scriptPath = Paths.get(home, ".ahakey", "hooks", scriptName);
        String ps = scriptPath.toString().replace("\\", "/");
        return "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + ps + "\" " + agentEvent;
    }

    public Path getHookConfigPath(String hookName) {
        String home = System.getProperty("user.home");
        return switch (hookName) {
            case "Claude" -> Paths.get(home, ".claude", "hooks", CLAUDE_SCRIPT_NAME);
            case "Cursor" -> Paths.get(home, ".cursor", "hooks.json");
            case "Codex" -> Paths.get(home, ".codex", CODEX_SIDECAR_NAME);
            case "Kimi" -> Paths.get(home, ".config", "kimi-cli", "hooks.json");
            default -> Paths.get(home, ".ahakey", "hooks", "ahakey-" + hookName.toLowerCase() + ".ps1");
        };
    }

    public boolean isAppDetected(String hookName) {
        String home = System.getProperty("user.home");
        return switch (hookName) {
            case "Claude" -> Files.isDirectory(Paths.get(home, ".claude"));
            case "Cursor" -> Files.isDirectory(defaultCursorUserDir()) || Files.isDirectory(Paths.get(home, ".cursor"));
            case "Codex" -> Files.isDirectory(Paths.get(home, ".codex"));
            case "Kimi" -> Files.isDirectory(Paths.get(home, ".config", "kimi-cli"));
            default -> false;
        };
    }

    private Path defaultCursorUserDir() {
        String appData = System.getenv("APPDATA");
        if (appData == null || appData.isBlank()) {
            return Paths.get(System.getProperty("user.home"), "AppData", "Roaming", "Cursor", "User");
        }
        return Paths.get(appData, "Cursor", "User");
    }

    private ObjectNode loadJsonSettings(Path path) throws Exception {
        if (!path.toFile().exists()) {
            return mapper.createObjectNode();
        }
        JsonNode node = mapper.readTree(path.toFile());
        if (node instanceof ObjectNode) {
            return (ObjectNode) node;
        }
        return mapper.createObjectNode();
    }

    private ArrayNode keepNonAhaKeyEntries(ArrayNode source, String scriptName) {
        ArrayNode result = mapper.createArrayNode();
        for (JsonNode entry : source) {
            String command = entry.path("command").asText("");
            if (!command.contains(scriptName) && !command.contains("ahakey-")) {
                result.add(entry);
            }
        }
        return result;
    }

    private ArrayNode keepNonAhaKeyCodexEntries(ArrayNode source, String scriptName) {
        ArrayNode result = mapper.createArrayNode();
        for (JsonNode entry : source) {
            boolean hasAhaKeyCommand = false;
            JsonNode hooks = entry.path("hooks");
            if (hooks.isArray()) {
                for (JsonNode hook : hooks) {
                    String command = hook.path("command").asText("");
                    if (command.contains(scriptName) || command.contains("ahakey-")) {
                        hasAhaKeyCommand = true;
                        break;
                    }
                }
            }
            if (!hasAhaKeyCommand) {
                result.add(entry);
            }
        }
        return result;
    }

    private ArrayNode keepNonAhaKeyClaudeEntries(ArrayNode source, String scriptName) {
        ArrayNode result = mapper.createArrayNode();
        for (JsonNode entry : source) {
            boolean hasAhaKeyCommand = false;
            JsonNode hooks = entry.path("hooks");
            if (hooks.isArray()) {
                for (JsonNode hook : hooks) {
                    String command = hook.path("command").asText("");
                    if (command.contains(scriptName) || command.contains("ahakey-")) {
                        hasAhaKeyCommand = true;
                        break;
                    }
                }
            }
            if (!hasAhaKeyCommand) {
                result.add(entry);
            }
        }
        return result;
    }

    private void backupFile(Path path) throws Exception {
        if (path.toFile().exists()) {
            Path backup = path.resolveSibling(path.getFileName() + ".bak");
            Files.copy(path, backup, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private String classifyFailure(Exception e) {
        Throwable root = e;
        while (root.getCause() != null) {
            root = root.getCause();
        }
        String message = root.getMessage() == null ? "" : root.getMessage();
        if (root instanceof java.nio.file.AccessDeniedException || message.contains("being used by another process")) {
            return "文件不可写";
        }
        if (root instanceof com.fasterxml.jackson.core.JsonProcessingException) {
            return "配置无法读取";
        }
        if (message.contains(".bak") || message.contains("copy")) {
            return "备份失败";
        }
        return "未知错误";
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
        if (toml.contains("[features]")) {
            if (toml.contains("hooks")) {
                return toml.replaceAll("hooks\\s*=\\s*false", "hooks = true");
            } else {
                return toml.replace("[features]", "[features]\nhooks = true");
            }
        } else {
            return toml.trim() + "\n\n[features]\nhooks = true";
        }
    }

    private void log(String message) {
        if (logger != null) {
            logger.accept(message);
        }
    }
}
