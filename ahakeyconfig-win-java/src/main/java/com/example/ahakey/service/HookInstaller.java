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
import java.util.ArrayList;
import java.util.List;
import java.util.LinkedHashMap;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.regex.Pattern;
import java.util.regex.Matcher;
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
    private final ObjectMapper mapper = new ObjectMapper()
            .enable(com.fasterxml.jackson.core.JsonParser.Feature.STRICT_DUPLICATE_DETECTION)
            .enable(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_TRAILING_TOKENS);

    // 各平台 Hook 脚本名称
    private static final String CORE_SCRIPT_NAME   = "ahakey-core.ps1";
    private static final String CLAUDE_SCRIPT_NAME = "ahakey-claude.ps1";
    private static final String CODEX_SCRIPT_NAME  = "ahakey-codex.ps1";
    private static final String KIMI_SCRIPT_NAME   = "ahakey-kimi.ps1";
    private static final String CURSOR_SCRIPT_NAME = "ahakey-cursor.ps1";

    // Hook 配置路径常量
    public static final String CODEX_SIDECAR_NAME = ".ahakey_codex_hooks_v1";
    public static final String AHAKEY_HOOK_VERSION = "wd009-native-defer-v1";
    public enum HookStatus { DETECTING, APP_NOT_FOUND, NOT_INSTALLED, OUTDATED, LATEST, ERROR }
    public record HookWriteResult(boolean success, String reason) {}
    public record HookInspection(HookStatus status, String reason) {}
    private static final Object HOOK_FILES_LOCK = new Object();
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
        {"SessionEnd", "CodexSessionEnd", "10"},
        {"PostToolUse", "CodexPostToolUse", "10"},
        {"PreToolUse", "CodexPreToolUse", "20"},
        {"PermissionRequest", "CodexPermissionRequest", "20"},
        {"TaskCompleted", "CodexTaskCompleted", "10"},
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

    /**
     * 安装指定平台的 Hook
     */
    public void install(String platform) {
        installOrUpdate(platform);
    }

    public HookWriteResult installOrUpdate(String platform) {
        synchronized (HOOK_FILES_LOCK) {
            String step = "检查配置";
            try {
                scriptName(platform); // Validate before touching any file.
                LinkedHashMap<Path, byte[]> plan = installPlan(platform);
                step = "备份";
                for (Path path : plan.keySet()) backupFile(path);
                step = "写入";
                for (var entry : plan.entrySet()) writeManagedFile(entry.getKey(), entry.getValue());
                step = "回读核验";
                for (var entry : plan.entrySet()) {
                    if (!Arrays.equals(Files.readAllBytes(entry.getKey()), entry.getValue()))
                        throw new IOException("写后内容不一致: " + entry.getKey());
                }
                HookInspection actual = inspectHook(platform);
                if (actual.status() != HookStatus.LATEST) throw new IOException(actual.reason());
                log("[成功] " + platform + " 脚本与配置已回读核验");
                return new HookWriteResult(true, platform + "：已更新并核验本地脚本和配置");
            } catch (Exception e) {
                Throwable cause=e; while(cause.getCause()!=null)cause=cause.getCause();
                String reason=platform+"／"+step+"失败："+cause.getMessage()+"；已完成的备份保留";
                log("[错误] " + reason);
                return new HookWriteResult(false, reason);
            }
        }
    }

    public Map<String, HookWriteResult> installOrUpdateAll(List<String> platforms) {
        Map<String, HookWriteResult> results = new LinkedHashMap<>();
        for (String platform : platforms) results.put(platform, installOrUpdate(platform));
        return results;
    }

    /** Atomic file replacement; override only in isolated failure-injection checks. */
    protected void writeManagedFile(Path path, byte[] content) throws Exception {
        Files.createDirectories(path.getParent());
        Path temporary = Files.createTempFile(path.getParent(), ".ahakey-write-", ".tmp");
        try {
            Files.write(temporary, content);
            try { Files.move(temporary, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING); }
            catch (java.nio.file.AtomicMoveNotSupportedException unsupported) {
                Files.move(temporary, path, StandardCopyOption.REPLACE_EXISTING);
            }
        } finally { Files.deleteIfExists(temporary); }
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
        synchronized (HOOK_FILES_LOCK) {
            try { return hasManagedConfiguration(platform); }
            catch (Exception e) { return false; }
        }
    }

    public HookStatus getHookStatus(String platform) { return inspectHook(platform).status(); }

    public HookInspection inspectHook(String platform) {
        synchronized (HOOK_FILES_LOCK) {
            try {
                String scriptName=scriptName(platform);
                requirePort();
                if (!isAppDetected(platform)) return new HookInspection(HookStatus.APP_NOT_FOUND, "未检测到对应应用的本地目录");
                if (!hasManagedConfiguration(platform)) return new HookInspection(HookStatus.NOT_INSTALLED, "尚未找到本平台的 AhaKey 事件配置");
                Path dir=Paths.get(System.getProperty("user.home"),".ahakey","hooks");
                for (String name : List.of(scriptName, CORE_SCRIPT_NAME)) {
                    Path script=dir.resolve(name);
                    if (!Files.exists(script)) return new HookInspection(HookStatus.OUTDATED,"缺少脚本："+name);
                    String expected=name.equals(CORE_SCRIPT_NAME)?coreScriptContent():platformScriptContent(platform);
                    if (!normalizedScript(Files.readString(script,StandardCharsets.UTF_8)).equals(normalizedScript(expected)))
                        return new HookInspection(HookStatus.OUTDATED,(name.equals(CORE_SCRIPT_NAME)?"共享 core 内容或服务端口不匹配：":"平台脚本内容不匹配：")+name);
                }
                String mismatch=configurationMismatch(platform);
                if (mismatch!=null) return new HookInspection(HookStatus.OUTDATED,mismatch);
                String auxiliary="";
                if (platform.equals("Codex")) {
                    Path marker=Paths.get(System.getProperty("user.home"),".codex",CODEX_SIDECAR_NAME);
                    try {
                        if (!Files.exists(marker) || !Files.readString(marker,StandardCharsets.UTF_8).contains(AHAKEY_HOOK_VERSION))
                            auxiliary="；辅助安装记录缺失或较旧，无需因此重装";
                    } catch(IOException unreadable) { auxiliary="；辅助安装记录不可读取，不影响已核验内容"; }
                }
                return new HookInspection(HookStatus.LATEST,"当前软件所需的脚本与配置已匹配"+auxiliary);
            } catch(Exception e) {
                return new HookInspection(HookStatus.ERROR,platform+" 配置或脚本无法核验（"+managedConfigPath(platform).getParent()+"）："+e.getMessage());
            }
        }
    }

    // ==================== 脚本生成 ====================

    private void generateCoreScript(Path hooksDir) throws Exception {
        Files.write(hooksDir.resolve(CORE_SCRIPT_NAME), coreScriptContent().getBytes(StandardCharsets.UTF_8));
    }

    private String coreScriptContent() {
        String content =
            "# AhaKey Core - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "# Contains TCP connection logic, to be dot-sourced by platform-specific scripts\n" +
            "try {\n" +
            "    $stdinText = $null\n" +
            "    if ([Console]::IsInputRedirected) { $stdinText = [Console]::In.ReadToEnd() }\n" +
            "} catch { }\n" +
            "$payload = [ordered]@{ cmd = $EventName; ahakeyHookVersion = '" + AHAKEY_HOOK_VERSION + "'; cwd = (Get-Location).Path }\n" +
            "function Add-AhaKeyField([string]$Name) {\n" +
            "    $m = [regex]::Match($stdinText, '\"' + $Name + '\"\\s*:\\s*\"([^\"]*)\"')\n" +
            "    if ($m.Success) { $payload[$Name] = $m.Groups[1].Value }\n" +
            "}\n" +
            "if ($stdinText -and $stdinText.Trim().Length -gt 0) {\n" +
            "    try { $payload.hookInput = ($stdinText | ConvertFrom-Json) } catch {\n" +
            "        Add-AhaKeyField 'conversation_id'\n" +
            "        Add-AhaKeyField 'conversationId'\n" +
            "        Add-AhaKeyField 'session_id'\n" +
            "        Add-AhaKeyField 'sessionId'\n" +
            "        Add-AhaKeyField 'composerId'\n" +
            "        Add-AhaKeyField 'composer_id'\n" +
            "        Add-AhaKeyField 'transcript_path'\n" +
            "        Add-AhaKeyField 'transcriptPath'\n" +
            "        $payload.hookInputRawBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($stdinText))\n" +
            "    }\n" +
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
        return content;
    }

    private void generateClaudeScript(Path hooksDir) throws Exception {
        Files.write(hooksDir.resolve(CLAUDE_SCRIPT_NAME), claudeScriptContent().getBytes(StandardCharsets.UTF_8));
    }

    private String claudeScriptContent() {
        String content =
            "# AhaKey Claude Hook - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Claude PermissionRequest: output hookSpecificOutput in Claude format\n" +
            "if ($EventName -eq 'PermissionRequest') {\n" +
            "    $isAuto = $response -match '\"autoApproved\"\\s*:\\s*true'\n" +
            "    if ($isAuto) {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Claude lifecycle events: pass through server response\n" +
            "if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{\"ok\":true}') }\n" +
            "exit 0\n";
        return content;
    }

    private void generateCodexScript(Path hooksDir) throws Exception {
        Files.write(hooksDir.resolve(CODEX_SCRIPT_NAME), codexScriptContent().getBytes(StandardCharsets.UTF_8));
    }

    private String codexScriptContent() {
        String content =
            "# AhaKey Codex Hook - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Codex PreToolUse: defer to native unless explicit auto\n" +
            "if ($EventName -eq 'CodexPreToolUse') {\n" +
            "    if ($response -match '\"autoApproved\"\\s*:\\s*true') {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Codex PermissionRequest: defer to native unless explicit auto\n" +
            "if ($EventName -eq 'CodexPermissionRequest') {\n" +
            "    if ($response -match '\"autoApproved\"\\s*:\\s*true') {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Codex other lifecycle hooks must output exactly {} (Codex validates JSON schema)\n" +
            "[Console]::WriteLine('{}')\n" +
            "exit 0\n";
        return content;
    }

    private void generateKimiScript(Path hooksDir) throws Exception {
        Files.write(hooksDir.resolve(KIMI_SCRIPT_NAME), kimiScriptContent().getBytes(StandardCharsets.UTF_8));
    }

    private String kimiScriptContent() {
        String content =
            "# AhaKey Kimi Hook - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Kimi: pass through server response (Kimi 特有格式)\n" +
            "if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{\"ok\":true}') }\n" +
            "exit 0\n";
        return content;
    }

    private void generateCursorScript(Path hooksDir) throws Exception {
        Files.write(hooksDir.resolve(CURSOR_SCRIPT_NAME), cursorScriptContent().getBytes(StandardCharsets.UTF_8));
    }

    private String cursorScriptContent() {
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
        return content;
    }

    // ==================== 实际内容检查与最小更新 ====================

    private String scriptName(String platform) {
        return switch (platform) {
            case "Claude" -> CLAUDE_SCRIPT_NAME;
            case "Cursor" -> CURSOR_SCRIPT_NAME;
            case "Codex" -> CODEX_SCRIPT_NAME;
            case "Kimi" -> KIMI_SCRIPT_NAME;
            default -> throw new IllegalArgumentException("未知平台: " + platform);
        };
    }

    private String platformScriptContent(String platform) {
        return switch (platform) {
            case "Claude" -> claudeScriptContent();
            case "Cursor" -> cursorScriptContent();
            case "Codex" -> codexScriptContent();
            case "Kimi" -> kimiScriptContent();
            default -> throw new IllegalArgumentException("未知平台: " + platform);
        };
    }

    private String normalizedScript(String text) {
        return text.replace("\uFEFF", "").replace("\r\n", "\n").replace('\r', '\n').stripTrailing();
    }

    private Path managedConfigPath(String platform) {
        return platform.equals("Codex") ? Paths.get(System.getProperty("user.home"), ".codex", "hooks.json") : getHookConfigPath(platform);
    }

    private String readText(Path path) throws IOException {
        return Files.exists(path) ? Files.readString(path, StandardCharsets.UTF_8) : "";
    }

    private void requirePort() throws IOException {
        if (currentPort() < 1 || currentPort() > 65535) throw new IOException("Hook 服务尚未就绪（端口无效），请在服务启动后重试");
    }

    private LinkedHashMap<Path, byte[]> installPlan(String platform) throws Exception {
        requirePort();
        LinkedHashMap<Path, byte[]> plan = new LinkedHashMap<>();
        Path config = managedConfigPath(platform);
        if (platform.equals("Kimi")) {
            String content = readText(config);
            validateToml(content);
            int[] block = managedBlock(content, KIMI_HOOK_BLOCK_START, KIMI_HOOK_BLOCK_END);
            String replacement = buildKimiHookBlock().stripTrailing();
            String merged = block == null ? content + (content.endsWith("\n") || content.isEmpty() ? "" : "\n") + replacement + "\n"
                    : content.substring(0, block[0]) + replacement + content.substring(block[1]);
            validateToml(merged);
            addChanged(plan, config, merged);
        } else {
            ObjectNode root = checkedSettings(config, platform);
            ObjectNode hooks = root.has("hooks") ? (ObjectNode) root.get("hooks") : mapper.createObjectNode();
            ObjectNode cleaned = selectManaged(hooks, platform, false);
            ObjectNode expected = expectedHooks(platform);
            expected.fields().forEachRemaining(event -> {
                ArrayNode entries = cleaned.has(event.getKey()) ? (ArrayNode) cleaned.get(event.getKey()) : mapper.createArrayNode();
                event.getValue().forEach(entries::add);
                cleaned.set(event.getKey(), entries);
            });
            root.set("hooks", cleaned);
            if (platform.equals("Cursor")) root.put("version", 1);
            addChanged(plan, config, mapper.writerWithDefaultPrettyPrinter().writeValueAsString(root));
            if (platform.equals("Codex")) {
                Path toml = config.resolveSibling("config.toml");
                addChanged(plan, toml, codexFeature(readText(toml)));
                addChanged(plan, config.resolveSibling(CODEX_SIDECAR_NAME), AHAKEY_HOOK_VERSION + "\n");
            }
        }
        // The entire configuration is validated before any write or backup occurs.
        Path scripts = Paths.get(System.getProperty("user.home"), ".ahakey", "hooks");
        addChanged(plan, scripts.resolve(CORE_SCRIPT_NAME), coreScriptContent());
        addChanged(plan, scripts.resolve(scriptName(platform)), platformScriptContent(platform));
        return plan;
    }

    private void addChanged(Map<Path, byte[]> plan, Path path, String content) throws IOException {
        byte[] bytes = content.getBytes(StandardCharsets.UTF_8);
        if (!Files.exists(path) || !Arrays.equals(Files.readAllBytes(path), bytes)) plan.put(path, bytes);
    }

    private ObjectNode checkedSettings(Path path, String platform) throws Exception {
        ObjectNode root = loadJsonSettings(path);
        if (!root.has("hooks")) return root;
        if (!root.get("hooks").isObject()) throw new IOException(path + ": hooks 必须为对象，原文件未改动");
        var events = root.get("hooks").fields();
        while (events.hasNext()) {
            var event = events.next();
            if (!event.getValue().isArray()) throw new IOException(path + ": " + event.getKey() + " 必须为数组");
            for (JsonNode entry : event.getValue()) {
                if (!entry.isObject()) throw new IOException(path + ": 事件条目必须为对象");
                if (platform.equals("Cursor")) validateCommand(entry, path);
                else {
                    if (!entry.path("hooks").isArray()) throw new IOException(path + ": wrapper.hooks 必须为数组");
                    for (JsonNode command : entry.get("hooks")) validateCommand(command, path);
                }
            }
        }
        return root;
    }

    private void validateCommand(JsonNode entry, Path path) throws IOException {
        if (!entry.isObject() || (entry.has("command") && !entry.get("command").isTextual()))
            throw new IOException(path + ": command 条目格式无效");
        // Third-party non-command entries are retained without interpreting their schema.
    }

    private ObjectNode expectedHooks(String platform) {
        ObjectNode hooks = mapper.createObjectNode();
        String[][] events = platform.equals("Cursor") ? CURSOR_EVENTS : platform.equals("Codex") ? CODEX_EVENTS : CLAUDE_EVENTS;
        for (String[] event : events) {
            String argument = platform.equals("Codex") ? event[1] : event[0];
            String timeout = event[platform.equals("Codex") ? 2 : 1];
            ObjectNode command = mapper.createObjectNode();
            command.put("command", buildHookCommand(scriptName(platform), argument));
            command.put("timeout", Integer.parseInt(timeout));
            ArrayNode entries = mapper.createArrayNode();
            if (platform.equals("Cursor")) entries.add(command);
            else {
                command.put("type", "command");
                ObjectNode wrapper = mapper.createObjectNode();
                if (platform.equals("Claude")) wrapper.put("matcher", "");
                else if (event[0].equals("SessionStart")) wrapper.put("matcher", "startup|resume|clear");
                else if (!event[0].equals("Stop") && !event[0].equals("UserPromptSubmit")) wrapper.put("matcher", "*");
                wrapper.set("hooks", mapper.createArrayNode().add(command));
                entries.add(wrapper);
            }
            hooks.set(event[0], entries);
        }
        return hooks;
    }

    private boolean ownsCommand(JsonNode entry, String platform) {
        String command = entry.path("command").asText("").replace('\\', '/');
        // Own only a PowerShell -File invocation of this platform's script, not an incidental mention.
        Matcher executable = Pattern.compile("(?i)^\\s*(?:powershell(?:\\.exe)?|pwsh(?:\\.exe)?)\\s+").matcher(command);
        if (!executable.find()) return false;
        Matcher file = Pattern.compile("(?i)(?:^|\\s)-File\\s+(?:\"([^\"]+)\"|'([^']+)'|([^\\s]+))").matcher(command);
        if (!file.find()) return false;
        String path = file.group(1) != null ? file.group(1) : file.group(2) != null ? file.group(2) : file.group(3);
        String expected = Paths.get(System.getProperty("user.home"), ".ahakey", "hooks", scriptName(platform)).toString().replace('\\', '/');
        return path.equalsIgnoreCase(expected);
    }

    private ObjectNode selectManaged(ObjectNode hooks, String platform, boolean owned) {
        ObjectNode result = mapper.createObjectNode();
        hooks.fields().forEachRemaining(event -> {
            ArrayNode selected = mapper.createArrayNode();
            for (JsonNode entry : event.getValue()) {
                if (platform.equals("Cursor")) {
                    if (ownsCommand(entry, platform) == owned) selected.add(entry.deepCopy());
                } else {
                    ArrayNode commands = mapper.createArrayNode();
                    for (JsonNode command : entry.get("hooks")) if (ownsCommand(command, platform) == owned) commands.add(command.deepCopy());
                    if (!commands.isEmpty() || (!owned && entry.get("hooks").isEmpty())) {
                        ObjectNode wrapper = entry.deepCopy();
                        wrapper.set("hooks", commands);
                        selected.add(wrapper);
                    }
                }
            }
            if (!selected.isEmpty()) result.set(event.getKey(), selected);
        });
        return result;
    }

    private JsonNode normalizeCommands(JsonNode node) {
        JsonNode copy = node.deepCopy();
        if (copy.isObject()) {
            ObjectNode object = (ObjectNode) copy;
            List<String> fields = new ArrayList<>(); object.fieldNames().forEachRemaining(fields::add);
            for (String field : fields) {
                if (field.equals("command") && object.get(field).isTextual())
                    object.put(field, object.get(field).asText().replace('\\', '/').replace("\r\n", "\n").trim());
                else object.set(field, normalizeCommands(object.get(field)));
            }
        } else if (copy.isArray()) {
            ArrayNode array = (ArrayNode) copy;
            for (int i = 0; i < array.size(); i++) array.set(i, normalizeCommands(array.get(i)));
        }
        return copy;
    }

    private boolean hasManagedConfiguration(String platform) throws Exception {
        Path path = managedConfigPath(platform);
        if (!Files.exists(path)) return false;
        if (platform.equals("Kimi")) {
            String content = readText(path); validateToml(content);
            return managedBlock(content, KIMI_HOOK_BLOCK_START, KIMI_HOOK_BLOCK_END) != null;
        }
        ObjectNode root = checkedSettings(path, platform);
        return root.has("hooks") && !selectManaged((ObjectNode) root.get("hooks"), platform, true).isEmpty();
    }

    private String configurationMismatch(String platform) throws Exception {
        Path path = managedConfigPath(platform);
        if (platform.equals("Kimi")) {
            String content = readText(path);
            int[] block = managedBlock(content, KIMI_HOOK_BLOCK_START, KIMI_HOOK_BLOCK_END);
            return block == null || !normalizedScript(content.substring(block[0], block[1])).equals(normalizedScript(buildKimiHookBlock()))
                    ? "Kimi 已有事件配置不匹配：" + path : null;
        }
        ObjectNode root = checkedSettings(path, platform);
        JsonNode actual = selectManaged((ObjectNode) root.get("hooks"), platform, true);
        if (!normalizeCommands(actual).equals(normalizeCommands(expectedHooks(platform)))) return "事件、命令、匹配条件或超时配置不匹配：" + path;
        if (platform.equals("Cursor") && !root.path("version").isIntegralNumber()) return "Cursor 配置缺少有效 version：" + path;
        if (platform.equals("Cursor") && root.path("version").asInt() != 1) return "Cursor 配置 version 不匹配：" + path;
        if (platform.equals("Codex")) {
            Path toml = path.resolveSibling("config.toml");
            String content = readText(toml);
            if (!codexFeature(content).equals(content)) return "Codex [features].hooks 尚未启用：" + toml;
        }
        return null;
    }

    private int[] managedBlock(String text, String start, String end) throws IOException {
        // The fixed-version TOML lexer distinguishes actual comments from marker text inside strings.
        var lexer = new org.tomlj.internal.TomlLexer(org.antlr.v4.runtime.CharStreams.fromString(text));
        List<Integer> starts = new ArrayList<>(), ends = new ArrayList<>();
        for (org.antlr.v4.runtime.Token token = lexer.nextToken(); token.getType() != org.antlr.v4.runtime.Token.EOF; token = lexer.nextToken()) {
            if (token.getType() != org.tomlj.internal.TomlLexer.Comment) continue;
            int offset = text.offsetByCodePoints(0, token.getStartIndex());
            int lineStart = text.lastIndexOf('\n', Math.max(0, offset - 1)) + 1;
            if (!text.substring(lineStart, offset).isBlank()) continue;
            String comment = token.getText().stripTrailing();
            if (comment.equals(start)) starts.add(offset);
            if (comment.equals(end)) ends.add(offset + comment.length());
        }
        if (starts.isEmpty() && ends.isEmpty()) return null;
        if (starts.size() != 1 || ends.size() != 1 || starts.get(0) >= ends.get(0))
            throw new IOException("AhaKey 管理块不完整或重复，保留原配置，请先检查标记");
        return new int[]{starts.get(0), ends.get(0)};
    }

    private org.tomlj.TomlParseResult parseToml(String text) throws IOException {
        org.tomlj.TomlParseResult parsed = org.tomlj.Toml.parse(text);
        if (parsed.hasErrors()) {
            // Report position only: configuration values may contain credentials.
            throw new IOException("TOML 配置格式无效（" + parsed.errors().get(0).position() + "），原文件保留");
        }
        return parsed;
    }

    private void validateToml(String text) throws IOException { parseToml(text); }

    private int sourceOffset(String text, org.tomlj.TomlPosition position) throws IOException {
        int offset = 0;
        for (int line = 1; line < position.line(); line++) {
            int next = text.indexOf('\n', offset);
            if (next < 0) throw new IOException("TOML 源位置无法确认，原文件保留");
            offset = next + 1;
        }
        return text.offsetByCodePoints(offset, position.column() - 1);
    }

    /** Parse for truth, edit a single source span: never serialize unrelated TOML settings. */
    private String codexFeature(String text) throws IOException {
        var parsed = parseToml(text);
        Object existing = parsed.get("features.hooks");
        if (existing != null && !(existing instanceof Boolean)) throw new IOException("Codex features.hooks 必须为布尔值");
        if (Boolean.TRUE.equals(existing)) return text;
        String newline = text.contains("\r\n") ? "\r\n" : "\n";
        String updated;
        if (Boolean.FALSE.equals(existing)) {
            int start = sourceOffset(text, parsed.inputPositionOf("features.hooks"));
            Matcher assignment = Pattern.compile("[^=\\r\\n]*=\\s*(false)(?=\\s|[,}#]|$)").matcher(text);
            assignment.region(start, text.length());
            if (!assignment.lookingAt()) throw new IOException("Codex hooks 源位置无法确认，原文件保留");
            updated = text.substring(0, assignment.start(1)) + "true" + text.substring(assignment.end(1));
        } else if (parsed.contains("features")) {
            if (!parsed.isTable("features")) throw new IOException("Codex features 必须为表，原文件保留");
            int start = sourceOffset(text, parsed.inputPositionOf("features"));
            int end = text.indexOf('\n', start); if (end < 0) end = text.length(); else end++;
            String line = text.substring(start, end);
            if (line.matches("(?s)\\[\\s*(?:features|\"features\"|'features')\\s*\\]\\s*(?:#.*)?")) {
                updated = text.substring(0, end) + (end > 0 && text.charAt(end - 1) == '\n' ? "" : newline) + "hooks = true" + newline + text.substring(end);
            } else {
                Matcher inline = Pattern.compile("(?:features|\"features\"|'features')\\s*=\\s*\\{").matcher(text);
                inline.region(start, text.length());
                if (inline.lookingAt()) {
                    int brace = inline.end();
                    boolean empty = parsed.getTable("features").isEmpty();
                    updated = text.substring(0, brace) + " hooks = true" + (empty ? " " : ", ") + text.substring(brace);
                } else if (!line.stripLeading().startsWith("[")) {
                    // An existing dotted assignment has no explicit section to insert into.
                    updated = "features.hooks = true" + newline + text;
                } else {
                    // Parent table was implicit in [features.child]. TOML permits declaring it later.
                    updated = text + (text.endsWith("\n") ? "" : newline) + "[features]" + newline + "hooks = true" + newline;
                }
            }
        } else {
            updated = text + (text.endsWith("\n") || text.isEmpty() ? "" : newline) + "[features]" + newline + "hooks = true" + newline;
        }
        if (!Boolean.TRUE.equals(parseToml(updated).get("features.hooks"))) throw new IOException("Codex hooks 修改无法核验，原文件保留");
        return updated;
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
        throw new IOException(path + ": JSON 根必须为对象，原配置未修改");
    }

    private void backupFile(Path path) throws Exception {
        if (path.toFile().exists()) {
            Path backup = path.resolveSibling(path.getFileName() + ".ahakey-backup-" + java.time.Instant.now().toEpochMilli() + "-" + java.util.UUID.randomUUID() + ".bak");
            Files.copy(path, backup);
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

    private void log(String message) {
        if (logger != null) {
            logger.accept(message);
        }
    }
}
