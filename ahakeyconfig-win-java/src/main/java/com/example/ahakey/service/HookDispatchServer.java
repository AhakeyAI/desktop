package com.example.ahakey.service;

import com.example.ahakey.model.IDEState;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.*;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.InetSocketAddress;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Hook 分发服务器 — 监听固定 TCP 端口，接收来自 Codex/Claude/Cursor/Kimi hook 的事件名，
 * 映射到 BLE 状态码后通过 BleManager 发送到键盘。
 *
 * <p>架构角色：
 * <pre>
 *   Codex/Claude/Cursor/Kimi  →  PowerShell hook  →  TCP:8765  →  HookDispatchServer  →  BleManager  →  BLE-TCP bridge:9000  →  键盘
 * </pre>
 *
 * <p>支持两种输入格式：
 * <ul>
 *   <li>纯文本事件名：{@code SessionStart}、{@code CodexSessionStart}、{@code KimiSessionStart}</li>
 *   <li>JSON：{@code {"cmd":"SessionStart"}}</li>
 * </ul>
 */
public class HookDispatchServer {
    private static final Logger logger = LoggerFactory.getLogger(HookDispatchServer.class);

    public static final int DEFAULT_PORT = 8765;

    /**
     * 手动批准确认回调 - 用于在手动模式下请求用户确认
     */
    @FunctionalInterface
    public interface ApprovalCallback {
        /**
         * 请求用户确认操作
         * @param platform 平台名称
         * @param eventName 事件名称
         * @return true 表示用户确认，false 表示用户拒绝
         */
        boolean requestApproval(String platform, String eventName);
    }

    private final BleManager bleManager;
    private final TaskActivityService taskActivityService;
    private final ApprovalService approvalService;
    private static final ObjectMapper JSON = new ObjectMapper();
    private final int port;
    private ServerSocket serverSocket;
    private ExecutorService executor;
    private volatile boolean running;
    private ApprovalCallback approvalCallback;
    private final Map<Platform, Long> lastRequestTimes = new ConcurrentHashMap<>();

    enum Platform { CLAUDE, CODEX, KIMI, CURSOR }

    private static final String SOURCE_HARDWARE_AUTO = "hardware-auto";
    private static final String SOURCE_USER_CONFIRMED = "user-confirmed";
    private static final String SOURCE_FAIL_CLOSED = "fail-closed";
    private static final String SOURCE_CODEX_FALLBACK = "codex-fallback";

    record EventEntry(Platform platform, IDEState state) {}

    /** 事件名 → (Platform, IDEState)，每个事件名唯一归属一个平台，无命名冲突风险。 */
    private static final Map<String, EventEntry> EVENT_MAP = new HashMap<>();

    static {
        // Claude（PascalCase）
        for (String[] e : new String[][]{
            {"SessionStart", "SESSION_START"}, {"SessionEnd", "SESSION_END"},
            {"PreToolUse", "PRE_TOOL_USE"}, {"PostToolUse", "POST_TOOL_USE"},
            {"Notification", "NOTIFICATION"}, {"TaskCompleted", "TASK_COMPLETED"},
            {"Stop", "STOP"}, {"UserPromptSubmit", "USER_PROMPT_SUBMIT"}
        }) EVENT_MAP.put(e[0], new EventEntry(Platform.CLAUDE, IDEState.valueOf(e[1])));
        EVENT_MAP.put("PermissionRequest", new EventEntry(Platform.CLAUDE, IDEState.PERMISSION_REQUEST));

        // Codex（Codex* 前缀）
        for (String[] e : new String[][]{
            {"CodexSessionStart", "SESSION_START"}, {"CodexSessionEnd", "SESSION_END"},
            {"CodexPreToolUse", "PRE_TOOL_USE"}, {"CodexPostToolUse", "POST_TOOL_USE"},
            {"CodexStop", "STOP"}, {"CodexUserPromptSubmit", "USER_PROMPT_SUBMIT"}
        }) EVENT_MAP.put(e[0], new EventEntry(Platform.CODEX, IDEState.valueOf(e[1])));
        EVENT_MAP.put("CodexPermissionRequest", new EventEntry(Platform.CODEX, IDEState.PERMISSION_REQUEST));

        // Kimi（Kimi* 前缀）
        for (String[] e : new String[][]{
            {"KimiNotification", "NOTIFICATION"}, {"KimiSessionStart", "SESSION_START"},
            {"KimiSessionEnd", "SESSION_END"}, {"KimiPreToolUse", "PRE_TOOL_USE"},
            {"KimiPostToolUse", "POST_TOOL_USE"}, {"KimiUserPromptSubmit", "USER_PROMPT_SUBMIT"},
            {"KimiStop", "STOP"}
        }) EVENT_MAP.put(e[0], new EventEntry(Platform.KIMI, IDEState.valueOf(e[1])));

        // Cursor（camelCase）
        for (String[] e : new String[][]{
            {"sessionStart", "SESSION_START"}, {"sessionEnd", "SESSION_END"},
            {"preToolUse", "PRE_TOOL_USE"}, {"postToolUse", "POST_TOOL_USE"},
            {"stop", "STOP"}
        }) EVENT_MAP.put(e[0], new EventEntry(Platform.CURSOR, IDEState.valueOf(e[1])));
    }

    public HookDispatchServer(BleManager bleManager) {
        this(bleManager, new TaskActivityService(bleManager), DEFAULT_PORT);
    }

    public HookDispatchServer(BleManager bleManager, int port) {
        this(bleManager, new TaskActivityService(bleManager), port);
    }

    public HookDispatchServer(BleManager bleManager, TaskActivityService taskActivityService, int port) {
        this(bleManager, taskActivityService, new ApprovalService(bleManager), port);
    }

    public HookDispatchServer(
        BleManager bleManager,
        TaskActivityService taskActivityService,
        ApprovalService approvalService,
        int port
    ) {
        this.bleManager = bleManager;
        this.taskActivityService = taskActivityService;
        this.approvalService = approvalService;
        this.port = port;
    }

    public TaskActivityService getTaskActivityService() { return taskActivityService; }

    /**
     * 设置手动批准确认回调
     */
    public void setApprovalCallback(ApprovalCallback callback) {
        this.approvalCallback = callback;
    }

    /** Starts the configured stable endpoint; never silently migrates ports. */
    public void start() {
        if (running) return;
        executor = Executors.newCachedThreadPool(r -> {
            Thread t = new Thread(r, "hook-dispatch");
            t.setDaemon(true);
            return t;
        });

        try {
            serverSocket = new ServerSocket();
            serverSocket.setReuseAddress(true);
            serverSocket.bind(new InetSocketAddress("127.0.0.1", port));
            running = true;
            logger.info("HOOK_SERVER_STARTED address=127.0.0.1 port={}",
                serverSocket.getLocalPort());
        } catch (IOException failure) {
            logger.error("Hook 分发服务器固定端口 {} 启动失败: {}", port,
                failure.getMessage());
            return;
        }

        executor.submit(this::acceptLoop);
    }

    public int getActualPort() {
        return serverSocket != null ? serverSocket.getLocalPort() : -1;
    }

    public boolean isRunning() {
        return running;
    }

    public long getLastRequestTimeMillis(String platform) {
        try {
            return lastRequestTimes.getOrDefault(
                Platform.valueOf(platform.toUpperCase()), 0L);
        } catch (IllegalArgumentException exception) {
            return 0L;
        }
    }

    private void acceptLoop() {
        while (running && !serverSocket.isClosed()) {
            try {
                Socket client = serverSocket.accept();
                executor.submit(() -> handleClient(client));
            } catch (IOException e) {
                if (running) {
                    logger.warn("Hook 服务器 accept 异常: {}", e.getMessage());
                }
            }
        }
    }

    private void handleClient(Socket client) {
        try (client;
             BufferedReader reader = new BufferedReader(new InputStreamReader(client.getInputStream()));
             PrintWriter writer = new PrintWriter(client.getOutputStream(), true)) {

            String line = reader.readLine();
            if (line == null || line.isBlank()) {
                writer.println("{\"ok\":false,\"error\":\"empty\"}");
                return;
            }

            line = line.trim();
            String eventName = parseEventName(line);

            EventEntry entry = EVENT_MAP.get(eventName);
            if (entry == null) {
                logger.warn("未知 hook 事件: {} (原始: {})", eventName, line);
                writer.println("{\"ok\":false,\"error\":\"unknown event: " + eventName + "\"}");
                return;
            }
            logger.debug("[{}] 收到事件: {} (原始: {})", entry.platform(), eventName, line);
            lastRequestTimes.put(entry.platform(), System.currentTimeMillis());
            logger.info("HOOK_REQUEST_RECEIVED platform={} event={}",
                entry.platform(), eventName);

            HookMetadata metadata = parseMetadata(line);
            taskActivityService.accept(entry.platform().name(), profile(entry.platform()),
                metadata.taskId(), metadata.title(), entry.state());

            switch (entry.platform()) {
                case CLAUDE -> handleClaudeEvent(writer, eventName, entry.state());
                case CODEX  -> handleCodexEvent(writer, eventName, entry.state());
                case KIMI   -> handleKimiEvent(writer, eventName, entry.state());
                case CURSOR -> handleCursorEvent(writer, eventName, entry.state());
            }

        } catch (IOException e) {
            logger.debug("Hook 客户端处理异常: {}", e.getMessage());
        }
    }

    private void handleClaudeEvent(PrintWriter writer, String eventName, IDEState state) {
        if (state == IDEState.PERMISSION_REQUEST) {
            ApprovalSnapshot snapshot = approvalService.refresh();
            boolean auto = snapshot.permitsAutomaticApproval();
            logger.info("[Claude] {} approvalState={} fresh={}",
                eventName, snapshot.state(), snapshot.fresh());
            if (!auto && approvalCallback != null) {
                boolean approved = approvalCallback.requestApproval("Claude", eventName);
                logger.info("[Claude] {} 用户操作={}", eventName, approved ? "允许" : "拒绝");
                writeCanonical(writer, Platform.CLAUDE, eventName, approved,
                    approved ? SOURCE_USER_CONFIRMED : SOURCE_FAIL_CLOSED);
            } else {
                writeCanonical(writer, Platform.CLAUDE, eventName, auto,
                    auto ? SOURCE_HARDWARE_AUTO : SOURCE_FAIL_CLOSED);
            }
            return;
        }
        handleGeneric(writer, eventName, state, "Claude");
    }

    private void handleCodexEvent(PrintWriter writer, String eventName, IDEState state) {
        boolean needApproval = "CodexPreToolUse".equals(eventName) || state == IDEState.PERMISSION_REQUEST;
        if (needApproval) {
            ApprovalSnapshot snapshot = approvalService.refresh();
            boolean auto = snapshot.permitsAutomaticApproval();
            String decision = auto ? "HARDWARE_AUTO"
                : isManualDialogEligible(snapshot) ? "MANUAL_DIALOG" : "CODEX_FALLBACK";
            logger.info("APPROVAL_STATE={} CONNECTED={} FRESH={} SWITCH_STATE={} POLICY_DECISION={}",
                snapshot.state(), snapshot.connected(), snapshot.fresh(),
                snapshot.state(), decision);
            try { bleManager.updateState((byte) state.getCode()); }
            catch (Exception e) { logger.warn("[Codex] BLE 状态更新失败: {}", e.getMessage()); }

            if (auto) {
                writeCanonical(writer, Platform.CODEX, eventName, true,
                    SOURCE_HARDWARE_AUTO);
            } else if (isManualDialogEligible(snapshot)) {
                boolean approved = approvalCallback != null
                    && approvalCallback.requestApproval("Codex", eventName);
                writeCanonical(writer, Platform.CODEX, eventName, approved,
                    approved ? SOURCE_USER_CONFIRMED : SOURCE_FAIL_CLOSED);
            } else {
                logger.info("FALLBACK_REASON={}", fallbackReason(snapshot));
                writeCanonical(writer, Platform.CODEX, eventName, false,
                    SOURCE_CODEX_FALLBACK);
            }
            return;
        }
        handleGeneric(writer, eventName, state, "Codex");
    }

    private void handleKimiEvent(PrintWriter writer, String eventName, IDEState state) {
        if ("KimiPreToolUse".equals(eventName)) {
            ApprovalSnapshot snapshot = approvalService.refresh();
            boolean auto = snapshot.permitsAutomaticApproval();
            logger.info("[Kimi] {} approvalState={} fresh={}",
                eventName, snapshot.state(), snapshot.fresh());
            try { bleManager.updateState((byte) state.getCode()); }
            catch (Exception e) { logger.warn("[Kimi] BLE 状态更新失败: {}", e.getMessage()); }
            
            if (auto) {
                writeCanonical(writer, Platform.KIMI, eventName, true,
                    SOURCE_HARDWARE_AUTO);
            } else if (approvalCallback != null && approvalCallback.requestApproval("Kimi", eventName)) {
                writeCanonical(writer, Platform.KIMI, eventName, true,
                    SOURCE_USER_CONFIRMED);
                logger.info("[Kimi] {} 用户操作=允许", eventName);
            } else {
                writeCanonical(writer, Platform.KIMI, eventName, false,
                    SOURCE_FAIL_CLOSED);
                logger.info("[Kimi] {} 用户操作=拒绝", eventName);
            }
            return;
        }
        handleGeneric(writer, eventName, state, "Kimi");
    }

    private void handleCursorEvent(PrintWriter writer, String eventName, IDEState state) {
        if ("preToolUse".equals(eventName)) {
            ApprovalSnapshot snapshot = approvalService.refresh();
            boolean auto = snapshot.permitsAutomaticApproval();
            logger.info("[Cursor] {} approvalState={} fresh={} callback={}",
                eventName, snapshot.state(), snapshot.fresh(), approvalCallback != null);
            try { bleManager.updateState((byte) state.getCode()); }
            catch (Exception e) { logger.warn("[Cursor] BLE 状态更新失败: {}", e.getMessage()); }
            
            if (auto) {
                logger.info("[Cursor] {} 自动放行", eventName);
                writeCanonical(writer, Platform.CURSOR, eventName, true,
                    SOURCE_HARDWARE_AUTO);
            } else if (approvalCallback != null && approvalCallback.requestApproval("Cursor", eventName)) {
                logger.info("[Cursor] {} 用户操作=允许", eventName);
                writeCanonical(writer, Platform.CURSOR, eventName, true,
                    SOURCE_USER_CONFIRMED);
            } else {
                String reason = approvalCallback == null ? "回调未注册" : "用户拒绝";
                logger.info("[Cursor] {} 用户操作=拒绝({})", eventName, reason);
                writeCanonical(writer, Platform.CURSOR, eventName, false,
                    SOURCE_FAIL_CLOSED);
            }
            return;
        }
        handleGeneric(writer, eventName, state, "Cursor");
    }

    private void handleGeneric(PrintWriter writer, String eventName, IDEState state, String platform) {
        try {
            bleManager.updateState((byte) state.getCode());
            logger.info("[{}] {} → {} (code={})", platform, eventName, state.name(), state.getCode());
            writeCanonical(writer, Platform.valueOf(platform.toUpperCase()),
                eventName, false, SOURCE_FAIL_CLOSED);
        } catch (Exception e) {
            logger.error("[{}] BLE 状态更新失败: {}", platform, e.getMessage());
            writeCanonical(writer, Platform.valueOf(platform.toUpperCase()),
                eventName, false, SOURCE_FAIL_CLOSED);
        }
    }

    private boolean isManualDialogEligible(ApprovalSnapshot snapshot) {
        return snapshot.state() == ApprovalState.MANUAL
            && snapshot.connected() && snapshot.fresh();
    }

    private String fallbackReason(ApprovalSnapshot snapshot) {
        if (!snapshot.connected() || snapshot.state() == ApprovalState.DISCONNECTED) {
            return "DISCONNECTED";
        }
        if (!snapshot.fresh() || snapshot.state() == ApprovalState.STALE) {
            return "STALE";
        }
        return "UNKNOWN";
    }

    private static void writeCanonical(
        PrintWriter writer,
        Platform platform,
        String eventName,
        boolean allow,
        String approvalSource
    ) {
        writer.print("{\"schemaVersion\":1,\"platform\":\"");
        writer.print(platform.name().toLowerCase());
        writer.print("\",\"event\":\"");
        writer.print(eventName);
        writer.print("\",\"allow\":");
        writer.print(allow);
        writer.print(",\"approvalSource\":\"");
        writer.print(approvalSource);
        writer.println("\"}");
    }

    /**
     * 从输入行解析事件名。支持 JSON 和纯文本两种格式。
     */
    private String parseEventName(String line) {
        if (line.startsWith("{")) {
            // JSON 格式: {"cmd":"SessionStart"}
            try {
                // 简单解析，避免引入额外依赖
                int cmdIdx = line.indexOf("\"cmd\"");
                if (cmdIdx >= 0) {
                    int colonIdx = line.indexOf(':', cmdIdx);
                    int firstQuote = line.indexOf('"', colonIdx + 1);
                    int secondQuote = line.indexOf('"', firstQuote + 1);
                    if (firstQuote >= 0 && secondQuote > firstQuote) {
                        return line.substring(firstQuote + 1, secondQuote);
                    }
                }
            } catch (Exception e) {
                logger.debug("JSON 解析失败: {}", line);
            }
        }
        // 纯文本格式：直接返回事件名
        return line;
    }

    private record HookMetadata(String taskId, String title) {}

    private HookMetadata parseMetadata(String line) {
        if (!line.startsWith("{")) return new HookMetadata("", "");
        try {
            JsonNode root = JSON.readTree(line);
            return new HookMetadata(root.path("taskId").asText(""), root.path("title").asText(""));
        } catch (Exception ignored) {
            return new HookMetadata("", "");
        }
    }

    private int profile(Platform platform) {
        return switch (platform) {
            case CLAUDE -> 0;
            case CURSOR -> 1;
            case CODEX -> 2;
            case KIMI -> 3;
        };
    }

    public void stop() {
        running = false;
        try {
            if (serverSocket != null && !serverSocket.isClosed()) {
                serverSocket.close();
            }
        } catch (IOException e) {
            logger.warn("关闭 Hook 服务器异常: {}", e.getMessage());
        }
        if (executor != null) {
            executor.shutdownNow();
        }
        taskActivityService.close();
        logger.info("HOOK_SERVER_STOPPED");
    }
}
