package com.example.ahakey.service;

import com.example.ahakey.model.IDEState;
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
    private final int port;
    private ServerSocket serverSocket;
    private ExecutorService executor;
    private volatile boolean running;
    private ApprovalCallback approvalCallback;

    enum Platform { CLAUDE, CODEX, KIMI, CURSOR }

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
        this(bleManager, DEFAULT_PORT);
    }

    public HookDispatchServer(BleManager bleManager, int port) {
        this.bleManager = bleManager;
        this.port = port;
    }

    /**
     * 设置手动批准确认回调
     */
    public void setApprovalCallback(ApprovalCallback callback) {
        this.approvalCallback = callback;
    }

    /**
     * 启动服务器。如果端口被占用，会自动递增端口号重试（最多 10 次）。
     */
    public void start() {
        if (running) return;
        executor = Executors.newCachedThreadPool(r -> {
            Thread t = new Thread(r, "hook-dispatch");
            t.setDaemon(true);
            return t;
        });

        int attempts = 0;
        int tryPort = port;
        while (attempts < 10) {
            try {
                serverSocket = new ServerSocket();
                serverSocket.setReuseAddress(true);
                serverSocket.bind(new InetSocketAddress("127.0.0.1", tryPort));
                running = true;
                logger.info("Hook 分发服务器已启动 - 127.0.0.1:{}", tryPort);
                break;
            } catch (IOException e) {
                logger.warn("端口 {} 被占用，尝试下一个...", tryPort);
                tryPort++;
                attempts++;
            }
        }

        if (!running) {
            logger.error("Hook 分发服务器启动失败，已尝试端口 {}-{}", port, tryPort - 1);
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

    /**
     * 检查自动批准状态。
     * @param forceRefresh 是否强制刷新设备状态（通过 BLE 查询）
     * @return true 表示自动批准模式，false 表示手动批准模式
     */
    private boolean checkAutoApproval(boolean forceRefresh) {
        if (forceRefresh) {
            bleManager.queryStatusAndWait(200);
        }
        return bleManager.getCachedStatus().isAutoApproval();
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
            boolean auto = checkAutoApproval(false);
            logger.info("[Claude] {} 拨杆={}", eventName, auto ? "自动" : "手动");
            if (!auto && approvalCallback != null) {
                boolean approved = approvalCallback.requestApproval("Claude", eventName);
                logger.info("[Claude] {} 用户操作={}", eventName, approved ? "允许" : "拒绝");
                writer.println("{\"ok\":true,\"event\":\"" + eventName + "\",\"autoApproved\":" + approved + "}");
            } else {
                writer.println("{\"ok\":true,\"event\":\"" + eventName + "\",\"autoApproved\":" + auto + "}");
            }
            return;
        }
        handleGeneric(writer, eventName, state, "Claude");
    }

    private void handleCodexEvent(PrintWriter writer, String eventName, IDEState state) {
        boolean needApproval = "CodexPreToolUse".equals(eventName) || state == IDEState.PERMISSION_REQUEST;
        if (needApproval) {
            boolean auto = checkAutoApproval(true);
            logger.info("[Codex] {} 拨杆={} switchState={}", eventName, auto ? "自动" : "手动", bleManager.getCachedStatus().getSwitchState());
            try { bleManager.updateState((byte) state.getCode()); }
            catch (Exception e) { logger.warn("[Codex] BLE 状态更新失败: {}", e.getMessage()); }

            boolean approved = auto || (approvalCallback != null && approvalCallback.requestApproval("Codex", eventName));
            logger.info("[Codex] {} 用户操作={}", eventName, approved ? "允许" : "拒绝");
            writer.println("{\"ok\":true,\"event\":\"" + eventName + "\",\"autoApproved\":" + approved + "}");
            return;
        }
        handleGeneric(writer, eventName, state, "Codex");
    }

    private void handleKimiEvent(PrintWriter writer, String eventName, IDEState state) {
        if ("KimiPreToolUse".equals(eventName)) {
            boolean auto = checkAutoApproval(true);
            logger.info("[Kimi] {} 拨杆={} switchState={}", eventName, auto ? "自动" : "手动", bleManager.getCachedStatus().getSwitchState());
            try { bleManager.updateState((byte) state.getCode()); }
            catch (Exception e) { logger.warn("[Kimi] BLE 状态更新失败: {}", e.getMessage()); }
            
            if (auto) {
                writer.println("{}");
            } else if (approvalCallback != null && approvalCallback.requestApproval("Kimi", eventName)) {
                writer.println("{}");
                logger.info("[Kimi] {} 用户操作=允许", eventName);
            } else {
                writer.println("{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"当前是手动模式，需要把拨杆切到自动后我才能执行操作\"}}");
                logger.info("[Kimi] {} 用户操作=拒绝", eventName);
            }
            return;
        }
        handleGeneric(writer, eventName, state, "Kimi");
    }

    private void handleCursorEvent(PrintWriter writer, String eventName, IDEState state) {
        if ("preToolUse".equals(eventName)) {
            int switchState = bleManager.getCachedStatus().getSwitchState();
            boolean auto = checkAutoApproval(true);
            logger.info("[Cursor] {} 拨杆={} switchState={} callback={}", eventName, auto ? "自动" : "手动", switchState, approvalCallback != null);
            try { bleManager.updateState((byte) state.getCode()); }
            catch (Exception e) { logger.warn("[Cursor] BLE 状态更新失败: {}", e.getMessage()); }
            
            if (auto) {
                logger.info("[Cursor] {} 自动放行", eventName);
                writer.println("{\"permission\":\"allow\"}");
            } else if (approvalCallback != null && approvalCallback.requestApproval("Cursor", eventName)) {
                logger.info("[Cursor] {} 用户操作=允许", eventName);
                writer.println("{\"permission\":\"allow\"}");
            } else {
                String reason = approvalCallback == null ? "回调未注册" : "用户拒绝";
                logger.info("[Cursor] {} 用户操作=拒绝({})", eventName, reason);
                writer.println("{\"permission\":\"deny\",\"user_message\":\"手动模式，" + reason + "\"}");
            }
            return;
        }
        handleGeneric(writer, eventName, state, "Cursor");
    }

    private void handleGeneric(PrintWriter writer, String eventName, IDEState state, String platform) {
        try {
            bleManager.updateState((byte) state.getCode());
            logger.info("[{}] {} → {} (code={})", platform, eventName, state.name(), state.getCode());
            writer.println("{\"ok\":true,\"event\":\"" + eventName + "\",\"state\":" + state.getCode() + "}");
        } catch (Exception e) {
            logger.error("[{}] BLE 状态更新失败: {}", platform, e.getMessage());
            writer.println("{\"ok\":false,\"error\":\"BLE update failed\"}");
        }
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
        logger.info("Hook 分发服务器已停止");
    }
}
