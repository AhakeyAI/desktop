package com.example.ahakey.service;

import com.example.ahakey.model.IDEState;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class HookDispatchServer {
    private static final Logger logger = LoggerFactory.getLogger(HookDispatchServer.class);
    public static final int DEFAULT_PORT = 8765;

    @FunctionalInterface
    public interface ApprovalCallback {
        boolean requestApproval(String platform, String eventName);
    }

    enum Platform { CLAUDE, CODEX, KIMI, CURSOR }
    record EventEntry(Platform platform, IDEState state) {}
    record HookPayload(String eventName, JsonNode json) {}

    private static final Map<String, EventEntry> EVENT_MAP = new HashMap<>();

    static {
        for (String[] e : new String[][]{
            {"SessionStart", "SESSION_START"}, {"SessionEnd", "SESSION_END"},
            {"PreToolUse", "PRE_TOOL_USE"}, {"PostToolUse", "POST_TOOL_USE"},
            {"Notification", "NOTIFICATION"}, {"TaskCompleted", "TASK_COMPLETED"},
            {"Stop", "STOP"}, {"UserPromptSubmit", "USER_PROMPT_SUBMIT"}
        }) EVENT_MAP.put(e[0], new EventEntry(Platform.CLAUDE, IDEState.valueOf(e[1])));
        EVENT_MAP.put("PermissionRequest", new EventEntry(Platform.CLAUDE, IDEState.PERMISSION_REQUEST));

        for (String[] e : new String[][]{
            {"CodexSessionStart", "SESSION_START"}, {"CodexSessionEnd", "SESSION_END"},
            {"CodexPreToolUse", "PRE_TOOL_USE"}, {"CodexPostToolUse", "POST_TOOL_USE"},
            {"CodexStop", "STOP"}, {"CodexTaskCompleted", "TASK_COMPLETED"},
            {"CodexUserPromptSubmit", "USER_PROMPT_SUBMIT"}
        }) EVENT_MAP.put(e[0], new EventEntry(Platform.CODEX, IDEState.valueOf(e[1])));
        EVENT_MAP.put("CodexPermissionRequest", new EventEntry(Platform.CODEX, IDEState.PERMISSION_REQUEST));

        for (String[] e : new String[][]{
            {"KimiNotification", "NOTIFICATION"}, {"KimiSessionStart", "SESSION_START"},
            {"KimiSessionEnd", "SESSION_END"}, {"KimiPreToolUse", "PRE_TOOL_USE"},
            {"KimiPostToolUse", "POST_TOOL_USE"}, {"KimiUserPromptSubmit", "USER_PROMPT_SUBMIT"},
            {"KimiStop", "STOP"}
        }) EVENT_MAP.put(e[0], new EventEntry(Platform.KIMI, IDEState.valueOf(e[1])));

        for (String[] e : new String[][]{
            {"sessionStart", "SESSION_START"}, {"sessionEnd", "SESSION_END"},
            {"preToolUse", "PRE_TOOL_USE"}, {"postToolUse", "POST_TOOL_USE"},
            {"stop", "STOP"}
        }) EVENT_MAP.put(e[0], new EventEntry(Platform.CURSOR, IDEState.valueOf(e[1])));
    }

    private final BleManager bleManager;
    private final AiRuntimeDisplayService runtimeDisplayService;
    private final ObjectMapper mapper = new ObjectMapper();
    private final int port;
    private ServerSocket serverSocket;
    private ExecutorService executor;
    private volatile boolean running;
    private ApprovalCallback approvalCallback;

    public HookDispatchServer(BleManager bleManager) {
        this(bleManager, null, DEFAULT_PORT);
    }

    public HookDispatchServer(BleManager bleManager, int port) {
        this(bleManager, null, port);
    }

    public HookDispatchServer(BleManager bleManager, AiRuntimeDisplayService runtimeDisplayService) {
        this(bleManager, runtimeDisplayService, DEFAULT_PORT);
    }

    public HookDispatchServer(BleManager bleManager, AiRuntimeDisplayService runtimeDisplayService, int port) {
        this.bleManager = bleManager;
        this.runtimeDisplayService = runtimeDisplayService;
        this.port = port;
    }

    public void setApprovalCallback(ApprovalCallback callback) {
        this.approvalCallback = callback;
    }

    public void start() {
        if (running) {
            return;
        }
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
                logger.info("Hook dispatch server started - 127.0.0.1:{}", tryPort);
                break;
            } catch (IOException e) {
                logger.warn("Hook dispatch port {} is busy, trying next port", tryPort);
                tryPort++;
                attempts++;
            }
        }

        if (!running) {
            logger.error("Hook dispatch server failed to start");
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
                    logger.warn("Hook dispatch accept failed: {}", e.getMessage());
                }
            }
        }
    }

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

            HookPayload payload = parsePayload(line.trim());
            EventEntry entry = EVENT_MAP.get(payload.eventName());
            if (entry == null) {
                logger.warn("Unknown hook event rejected; raw input omitted");
                writer.println("{\"ok\":false,\"error\":\"unknown event\"}");
                return;
            }

            switch (entry.platform()) {
                case CLAUDE -> handleClaudeEvent(writer, payload.eventName(), entry.state(), payload.json());
                case CODEX -> handleCodexEvent(writer, payload.eventName(), entry.state(), payload.json());
                case KIMI -> handleKimiEvent(writer, payload.eventName(), entry.state(), payload.json());
                case CURSOR -> handleCursorEvent(writer, payload.eventName(), entry.state(), payload.json());
            }
        } catch (IOException e) {
            logger.debug("Hook client handling failed: {}", e.getMessage());
        }
    }

    private void handleClaudeEvent(PrintWriter writer, String eventName, IDEState state, JsonNode payload) {
        if (state == IDEState.PERMISSION_REQUEST) {
            boolean auto = checkAutoApproval(false);
            sendRuntimeState("Claude", state, payload);
            boolean approved = auto || (approvalCallback != null && approvalCallback.requestApproval("Claude", eventName));
            writer.println("{\"ok\":true,\"event\":\"" + eventName + "\",\"autoApproved\":" + approved + "}");
            return;
        }
        handleGeneric(writer, eventName, state, "Claude", payload);
    }

    private void handleCodexEvent(PrintWriter writer, String eventName, IDEState state, JsonNode payload) {
        boolean needApproval = "CodexPreToolUse".equals(eventName) || state == IDEState.PERMISSION_REQUEST;
        if (needApproval) {
            boolean auto = checkAutoApproval(true);
            sendRuntimeState("Codex", state, payload);
            boolean approved = auto || (approvalCallback != null && approvalCallback.requestApproval("Codex", eventName));
            writer.println("{\"ok\":true,\"event\":\"" + eventName + "\",\"autoApproved\":" + approved + "}");
            return;
        }
        handleGeneric(writer, eventName, state, "Codex", payload);
    }

    private void handleKimiEvent(PrintWriter writer, String eventName, IDEState state, JsonNode payload) {
        if ("KimiPreToolUse".equals(eventName)) {
            boolean auto = checkAutoApproval(true);
            sendRuntimeState("Kimi", state, payload);
            if (auto || (approvalCallback != null && approvalCallback.requestApproval("Kimi", eventName))) {
                writer.println("{}");
            } else {
                writer.println("{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"当前是手动模式，需要把拨杆切到自动后我才能执行操作\"}}");
            }
            return;
        }
        handleGeneric(writer, eventName, state, "Kimi", payload);
    }

    private void handleCursorEvent(PrintWriter writer, String eventName, IDEState state, JsonNode payload) {
        if ("preToolUse".equals(eventName)) {
            boolean auto = checkAutoApproval(true);
            sendRuntimeState("Cursor", state, payload);
            if (auto) {
                writer.println("{\"permission\":\"allow\"}");
            } else {
                writer.println("{\"ok\":true,\"cursorPermission\":\"defer_to_native\"}");
            }
            return;
        }
        handleGeneric(writer, eventName, state, "Cursor", payload);
    }

    private void handleGeneric(PrintWriter writer, String eventName, IDEState state, String platform, JsonNode payload) {
        AiRuntimeDisplayService.Delivery delivery = runtimeDisplayService == null
                ? (sendRuntimeState(platform, state, payload) ? AiRuntimeDisplayService.Delivery.SENT : AiRuntimeDisplayService.Delivery.FAILED)
                : runtimeDisplayService.handleHookEventResult(platform, state, payload);
        boolean displayUpdated = delivery == AiRuntimeDisplayService.Delivery.SENT;
        writer.println("{\"ok\":true,\"event\":\"" + eventName + "\",\"state\":" + state.getCode()
            + ",\"displayUpdated\":" + displayUpdated + ",\"delivery\":\"" + delivery.name() + "\"}");
    }

    private boolean sendRuntimeState(String platform, IDEState state, JsonNode payload) {
        try {
            if (runtimeDisplayService != null) {
                return runtimeDisplayService.handleHookEvent(platform, state, payload);
            }
            return bleManager.sendRuntimeState((byte) state.getCode());
        } catch (Exception e) {
            logger.warn("[{}] runtime state update failed: {}", platform, e.getMessage());
            return false;
        }
    }

    private HookPayload parsePayload(String line) {
        if (line.startsWith("{")) {
            try {
                JsonNode node = mapper.readTree(line);
                String eventName = node.path("cmd").asText("");
                if (eventName.isBlank()) {
                    eventName = node.path("hook_event_name").asText("");
                }
                if (!eventName.isBlank()) {
                    return new HookPayload(eventName, node);
                }
            } catch (Exception e) {
                logger.debug("Hook JSON parse failed: {}", e.getClass().getSimpleName());
                HookPayload fallback = parseMalformedJsonPayload(line);
                if (fallback != null && !fallback.eventName().isBlank()) {
                    return fallback;
                }
            }
        }
        return new HookPayload(line, null);
    }

    private HookPayload parseMalformedJsonPayload(String line) {
        ObjectNode node = mapper.createObjectNode();
        copyJsonStringField(line, node, "cmd");
        copyJsonStringField(line, node, "hook_event_name");
        copyJsonStringField(line, node, "conversation_id");
        copyJsonStringField(line, node, "conversationId");
        copyJsonStringField(line, node, "session_id");
        copyJsonStringField(line, node, "sessionId");
        copyJsonStringField(line, node, "composerId");
        copyJsonStringField(line, node, "composer_id");
        copyJsonStringField(line, node, "transcript_path");
        copyJsonStringField(line, node, "transcriptPath");
        copyJsonStringField(line, node, "cwd");
        copyJsonStringField(line, node, "current_working_directory");
        copyJsonStringField(line, node, "currentWorkingDirectory");

        String eventName = node.path("cmd").asText("");
        if (eventName.isBlank()) {
            eventName = node.path("hook_event_name").asText("");
        }
        return eventName.isBlank() ? null : new HookPayload(eventName, node);
    }

    private void copyJsonStringField(String source, ObjectNode target, String fieldName) {
        Matcher matcher = Pattern.compile("\\\\?\"" + Pattern.quote(fieldName) + "\\\\?\"\\s*:\\s*\\\\?\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)")
            .matcher(source);
        if (matcher.find()) {
            target.put(fieldName, unescapeLooseJsonString(matcher.group(1)));
        }
    }

    private String unescapeLooseJsonString(String value) {
        if (value == null || value.isBlank()) {
            return "";
        }
        return value
            .replace("\\\\", "\\")
            .replace("\\/", "/")
            .replace("\\\"", "\"");
    }

    public void stop() {
        running = false;
        try {
            if (serverSocket != null && !serverSocket.isClosed()) {
                serverSocket.close();
            }
        } catch (IOException e) {
            logger.warn("Hook dispatch close failed: {}", e.getMessage());
        }
        if (executor != null) {
            executor.shutdownNow();
        }
        logger.info("Hook dispatch server stopped");
    }
}
