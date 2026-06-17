package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Map;
import java.util.function.Consumer;

/**
 * Hook 安装器 - 独立于 UI 的 Hook 管理服务
 * 负责所有平台（Claude、Cursor、Codex、Kimi）的 Hook 安装、卸载和脚本生成
 */
public class HookInstaller {

    private final int dispatchPort;
    private final Consumer<String> logger;
    private final ObjectMapper mapper = new ObjectMapper();

    // 各平台 Hook 脚本名称 (Linux Bash 版本)
    private static final String CORE_SCRIPT_NAME   = "ahakey-core.sh";
    private static final String CLAUDE_SCRIPT_NAME = "ahakey-claude.sh";
    private static final String CODEX_SCRIPT_NAME  = "ahakey-codex.sh";
    private static final String KIMI_SCRIPT_NAME   = "ahakey-kimi.sh";
    private static final String CURSOR_SCRIPT_NAME = "ahakey-cursor.sh";

    private static final String CODEX_SIDECAR_NAME = ".ahakey_codex_hooks_v1";
    private static final String CODEX_HOOK_BLOCK_START = "# BEGIN AhaKey Codex Hooks";
    private static final String CODEX_HOOK_BLOCK_END = "# END AhaKey Codex Hooks";
    private static final String KIMI_HOOK_BLOCK_START = "# BEGIN AhaKey Kimi Hooks";
    private static final String KIMI_HOOK_BLOCK_END = "# END AhaKey Kimi Hooks";

    // Claude: 9 个事件
    private static final String[][] CLAUDE_EVENTS = {
        {"SessionStart", "10"}, {"SessionEnd", "10"}, {"PreToolUse", "10"},
        {"PostToolUse", "10"}, {"PermissionRequest", "60"}, {"Notification", "10"},
        {"TaskCompleted", "10"}, {"Stop", "10"}, {"UserPromptSubmit", "10"}
    };

    // Cursor: 5 个事件
    private static final String[][] CURSOR_EVENTS = {
        {"sessionStart", "10"}, {"sessionEnd", "10"}, {"preToolUse", "10"},
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
        this.dispatchPort = dispatchPort;
        this.logger = logger;
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
        log("[安装] 开始安装 " + platform + " Hook...");
        generateAllScripts();
        switch (platform) {
            case "Claude": installClaudeHooks(); break;
            case "Cursor": installCursorHooks(); break;
            case "Codex": installCodexHooks(); break;
            case "Kimi": installKimiHooks(); break;
            default: log("[错误] 未知 Hook 类型: " + platform);
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
                case "Claude": return content.contains("ahakey-claude.sh");
                case "Cursor": return content.contains("ahakey-cursor.sh");
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

    // ==================== 脚本生成 ====================

    private void generateCoreScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CORE_SCRIPT_NAME);
        String content =
            "#!/bin/bash\n" +
            "# AhaKey Core - Auto-generated, do not edit\n" +
            "# Contains TCP connection logic, sourced by platform-specific scripts\n" +
            "response=\"\"\n" +
            "exec 3<>/dev/tcp/127.0.0.1/" + dispatchPort + "\n" +
            "echo \"$EventName\" >&3\n" +
            "read response <&3\n" +
            "exec 3>&-\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        // 设置可执行权限
        scriptPath.toFile().setExecutable(true);
    }

    private void generateClaudeScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CLAUDE_SCRIPT_NAME);
        String content =
            "#!/bin/bash\n" +
            "# AhaKey Claude Hook - Auto-generated, do not edit\n" +
            "EventName=\"$1\"\n" +
            "source \"$HOME/.ahakey/hooks/ahakey-core.sh\"\n" +
            "# Claude PermissionRequest: output hookSpecificOutput in Claude format\n" +
            "if [ \"$EventName\" = \"PermissionRequest\" ]; then\n" +
            "    if echo \"$response\" | grep -q '\"autoApproved\":\\s*true'; then\n" +
            "        echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}'\n" +
            "    else\n" +
            "        echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"ask\"}}}'\n" +
            "    fi\n" +
            "    exit 0\n" +
            "fi\n" +
            "# Claude lifecycle events: pass through server response\n" +
            "if [ -n \"$response\" ]; then echo \"$response\"; else echo '{\"ok\":true}'; fi\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        scriptPath.toFile().setExecutable(true);
    }

    private void generateCodexScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CODEX_SCRIPT_NAME);
        String content =
            "#!/bin/bash\n" +
            "# AhaKey Codex Hook - Auto-generated, do not edit\n" +
            "EventName=\"$1\"\n" +
            "source \"$HOME/.ahakey/hooks/ahakey-core.sh\"\n" +
            "# Codex lifecycle hooks must output exactly {} (Codex validates JSON schema)\n" +
            "if [ \"$EventName\" != \"CodexPermissionRequest\" ]; then\n" +
            "    echo '{}'\n" +
            "    exit 0\n" +
            "fi\n" +
            "# Codex PermissionRequest: output hookSpecificOutput in Codex format\n" +
            "if echo \"$response\" | grep -q '\"autoApproved\":\\s*true'; then\n" +
            "    echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}'\n" +
            "else\n" +
            "    echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\"}}'\n" +
            "fi\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        scriptPath.toFile().setExecutable(true);
    }

    private void generateKimiScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(KIMI_SCRIPT_NAME);
        String content =
            "#!/bin/bash\n" +
            "# AhaKey Kimi Hook - Auto-generated, do not edit\n" +
            "EventName=\"$1\"\n" +
            "source \"$HOME/.ahakey/hooks/ahakey-core.sh\"\n" +
            "# Kimi: pass through server response (Kimi specific format)\n" +
            "if [ -n \"$response\" ]; then echo \"$response\"; else echo '{\"ok\":true}'; fi\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        scriptPath.toFile().setExecutable(true);
    }

    private void generateCursorScript(Path hooksDir) throws Exception {
        Path scriptPath = hooksDir.resolve(CURSOR_SCRIPT_NAME);
        String content =
            "#!/bin/bash\n" +
            "# AhaKey Cursor Hook - Auto-generated, do not edit\n" +
            "EventName=\"$1\"\n" +
            "source \"$HOME/.ahakey/hooks/ahakey-core.sh\"\n" +
            "# Cursor: pass through server response (Cursor specific format)\n" +
            "if [ -n \"$response\" ]; then echo \"$response\"; else echo '{\"ok\":true}'; fi\n" +
            "exit 0\n";
        Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        scriptPath.toFile().setExecutable(true);
    }

    // ==================== 安装方法 ====================

    private void installClaudeHooks() {
        Path path = getHookConfigPath("Claude");
        try {
            Files.createDirectories(path.getParent());
            backupFile(path);
            ObjectNode settings = loadJsonSettings(path);
            ObjectNode hooks = mapper.createObjectNode();
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
                ArrayNode outer = mapper.createArrayNode();
                outer.add(wrapper);
                hooks.set(ev[0], outer);
            }
            settings.set("hooks", hooks);
            mapper.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
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
            ObjectNode existingHooks = settings.has("hooks") ? (ObjectNode) settings.get("hooks") : mapper.createObjectNode();
            for (String[] ev : CURSOR_EVENTS) {
                ObjectNode entry = mapper.createObjectNode();
                entry.put("command", buildHookCommand(CURSOR_SCRIPT_NAME, ev[0]));
                entry.put("timeout", Integer.parseInt(ev[1]));
                ArrayNode arr = mapper.createArrayNode();
                arr.add(entry);
                existingHooks.set(ev[0], arr);
            }
            settings.set("hooks", existingHooks);
            settings.put("version", 1);
            mapper.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
            log("[成功] 已注册 " + CURSOR_EVENTS.length + " 个 Cursor hook 事件");
            log("[成功] 配置文件: " + path);
        } catch (Exception e) { log("[错误] Cursor 安装失败: " + e.getMessage()); }
    }

    private void installCodexHooks() {
        String home = System.getProperty("user.home");
        Path hooksJson = Paths.get(home, ".codex", "hooks.json");
        Path configToml = Paths.get(home, ".codex", "config.toml");
        Path sidecar = Paths.get(home, ".codex", CODEX_SIDECAR_NAME);
        try {
            Files.createDirectories(hooksJson.getParent());
            backupFile(hooksJson);
            ObjectNode hooks = mapper.createObjectNode();
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
                ArrayNode outerArr = mapper.createArrayNode();
                outerArr.add(entry);
                hooks.set(ev[0], outerArr);
            }
            ObjectNode root = mapper.createObjectNode();
            root.set("hooks", hooks);
            mapper.writerWithDefaultPrettyPrinter().writeValue(hooksJson.toFile(), root);
            log("[成功] 已写入 " + hooksJson);
            Files.write(sidecar, java.time.LocalDateTime.now().toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
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
            Files.write(path, result.getBytes(java.nio.charset.StandardCharsets.UTF_8));
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
        String sh = scriptPath.toString();
        return "bash \"" + sh + "\" " + agentEvent;
    }

    public Path getHookConfigPath(String hookName) {
        String home = System.getProperty("user.home");
        switch (hookName) {
            case "Claude": return Paths.get(home, ".claude", "settings.json");
            case "Cursor": return Paths.get(home, ".cursor", "hooks.json");
            case "Codex": return Paths.get(home, ".codex", "hooks.json");
            case "Kimi": return Paths.get(home, ".kimi", "config.toml");
            default: return Paths.get(home, "." + hookName.toLowerCase(), "config.json");
        }
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
