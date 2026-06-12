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

    private final BleManager bleManager;
    private final int port;
    private ServerSocket serverSocket;
    private ExecutorService executor;
    private volatile boolean running;

    /**
     * 所有平台 hook 事件名 → IDEState 映射。
     * 前缀 Codex* / Kimi* 以及无前缀的 Claude/Cursor 事件名均映射到相同的 BLE 状态码。
     */
    private static final Map<String, IDEState> EVENT_MAP = new HashMap<>();

    static {
        // Claude 事件名（PascalCase）
        EVENT_MAP.put("SessionStart", IDEState.SESSION_START);
        EVENT_MAP.put("SessionEnd", IDEState.SESSION_END);
        EVENT_MAP.put("PreToolUse", IDEState.PRE_TOOL_USE);
        EVENT_MAP.put("PostToolUse", IDEState.POST_TOOL_USE);
        EVENT_MAP.put("PermissionRequest", IDEState.PERMISSION_REQUEST);
        EVENT_MAP.put("Notification", IDEState.NOTIFICATION);
        EVENT_MAP.put("TaskCompleted", IDEState.TASK_COMPLETED);
        EVENT_MAP.put("Stop", IDEState.STOP);
        EVENT_MAP.put("UserPromptSubmit", IDEState.USER_PROMPT_SUBMIT);

        // Cursor 事件名（camelCase）
        EVENT_MAP.put("sessionStart", IDEState.SESSION_START);
        EVENT_MAP.put("sessionEnd", IDEState.SESSION_END);
        EVENT_MAP.put("preToolUse", IDEState.PRE_TOOL_USE);
        EVENT_MAP.put("postToolUse", IDEState.POST_TOOL_USE);
        EVENT_MAP.put("stop", IDEState.STOP);

        // Codex 事件名（Codex* 前缀）
        EVENT_MAP.put("CodexSessionStart", IDEState.SESSION_START);
        EVENT_MAP.put("CodexSessionEnd", IDEState.SESSION_END);
        EVENT_MAP.put("CodexPreToolUse", IDEState.PRE_TOOL_USE);
        EVENT_MAP.put("CodexPostToolUse", IDEState.POST_TOOL_USE);
        EVENT_MAP.put("CodexPermissionRequest", IDEState.PERMISSION_REQUEST);
        EVENT_MAP.put("CodexStop", IDEState.STOP);
        EVENT_MAP.put("CodexUserPromptSubmit", IDEState.USER_PROMPT_SUBMIT);

        // Kimi 事件名（Kimi* 前缀）
        EVENT_MAP.put("KimiNotification", IDEState.NOTIFICATION);
        EVENT_MAP.put("KimiSessionStart", IDEState.SESSION_START);
        EVENT_MAP.put("KimiSessionEnd", IDEState.SESSION_END);
        EVENT_MAP.put("KimiPreToolUse", IDEState.PRE_TOOL_USE);
        EVENT_MAP.put("KimiPostToolUse", IDEState.POST_TOOL_USE);
        EVENT_MAP.put("KimiUserPromptSubmit", IDEState.USER_PROMPT_SUBMIT);
        EVENT_MAP.put("KimiStop", IDEState.STOP);
    }

    public HookDispatchServer(BleManager bleManager) {
        this(bleManager, DEFAULT_PORT);
    }

    public HookDispatchServer(BleManager bleManager, int port) {
        this.bleManager = bleManager;
        this.port = port;
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
            logger.debug("Hook 事件: {} (原始: {})", eventName, line);

            IDEState state = EVENT_MAP.get(eventName);
            if (state == null) {
                logger.warn("未知 hook 事件: {}", eventName);
                writer.println("{\"ok\":false,\"error\":\"unknown event: " + eventName + "\"}");
                return;
            }

            // 检查 PermissionRequest 事件是否需要自动批准
            if (state == IDEState.PERMISSION_REQUEST) {
                boolean isAutoApproval = bleManager.getCachedStatus().isAutoApproval();
                if (isAutoApproval) {
                    logger.info("自动批准模式: 跳过 PermissionRequest 事件");
                    writer.println("{\"ok\":true,\"event\":\"" + eventName + "\",\"autoApproved\":true}");
                    return;
                }
                logger.debug("手动批准模式: 正常处理 PermissionRequest 事件");
            }

            // Kimi PreToolUse：刷新设备状态后直接返回 Kimi 决策格式，PS1 hook 原样透传
            if ("KimiPreToolUse".equals(eventName)) {
                bleManager.queryStatusAndWait(200);
                boolean isAuto = bleManager.getCachedStatus().isAutoApproval();
                logger.info("KimiPreToolUse: 拨杆={} (switchState={})",
                        isAuto ? "自动" : "手动", bleManager.getCachedStatus().getSwitchState());
                try {
                    bleManager.updateState((byte) state.getCode());
                } catch (Exception e) {
                    logger.warn("BLE 状态更新失败: {}", e.getMessage());
                }
                if (isAuto) {
                    writer.println("{}");
                } else {
                    writer.println("{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"AhaKey: manual mode, switch dial to auto\"}}");
                }
                return;
            }

            try {
                bleManager.updateState((byte) state.getCode());
                logger.info("Hook 分发成功: {} → {} (code={})", eventName, state.name(), state.getCode());
                writer.println("{\"ok\":true,\"event\":\"" + eventName + "\",\"state\":" + state.getCode() + "}");
            } catch (Exception e) {
                logger.error("BLE 状态更新失败: {}", e.getMessage());
                writer.println("{\"ok\":false,\"error\":\"BLE update failed\"}");
            }

        } catch (IOException e) {
            logger.debug("Hook 客户端处理异常: {}", e.getMessage());
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
