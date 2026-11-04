package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.*;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public class SocketServer {
    private static final ObjectMapper mapper = new ObjectMapper();
    private final String socketPath;
    private final BleManager bleManager;
    private ServerSocket serverSocket;
    private ExecutorService executorService;
    private ScheduledExecutorService scheduler;

    private volatile Integer cachedSwitchState;
    private volatile Integer cachedLightMode;

    public SocketServer(String socketPath, BleManager bleManager) {
        this.socketPath = socketPath;
        this.bleManager = bleManager;
        this.executorService = Executors.newCachedThreadPool();
        this.scheduler = Executors.newScheduledThreadPool(1);
    }

    public void start() throws IOException {
        Path path = Paths.get(socketPath);
        Files.deleteIfExists(path);

        serverSocket = new ServerSocket(0);
        executorService.submit(this::acceptConnections);

        System.out.println("监听 Unix Socket: " + socketPath);
    }

    private void acceptConnections() {
        while (!serverSocket.isClosed()) {
            try {
                Socket client = serverSocket.accept();
                handleClient(client);
            } catch (IOException e) {
                if (!serverSocket.isClosed()) {
                    e.printStackTrace();
                }
            }
        }
    }

    private void handleClient(Socket client) {
        executorService.submit(() -> {
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(client.getInputStream()));
                 PrintWriter writer = new PrintWriter(client.getOutputStream(), true)) {

                String line = reader.readLine();
                if (line == null || line.trim().isEmpty()) {
                    return;
                }

                processCommand(line.trim(), writer);

            } catch (IOException e) {
                e.printStackTrace();
            } finally {
                try { client.close(); } catch (IOException ignored) {}
            }
        });
    }

    private void processCommand(String line, PrintWriter writer) {
        try {
            if (line.startsWith("{")) {
                JsonNode cmdNode = mapper.readTree(line);
                String cmd = cmdNode.get("cmd").asText();

                switch (cmd) {
                    case "state":
                        int value = cmdNode.get("value").asInt();
                        bleManager.updateState((byte) value);
                        sendResponse(writer, Map.of("ok", true));
                        break;

                    case "state_with_reset":
                        int stateValue = cmdNode.has("value") ? cmdNode.get("value").asInt() : 0;
                        int resetValue = cmdNode.has("resetValue") ? cmdNode.get("resetValue").asInt() : 4;
                        int delayMs = Math.max(0, cmdNode.has("delayMs") ? cmdNode.get("delayMs").asInt() : 1200);
                        bleManager.updateState((byte) stateValue);
                        scheduleStateReset((byte) resetValue, delayMs);
                        sendResponse(writer, Map.of("ok", true));
                        break;

                    case "permission":
                        handlePermission(cmdNode, writer);
                        break;

                    case "status":
                    case "approval_status":
                        handleStatusRequest(writer);
                        break;

                    default:
                        sendResponse(writer, Map.of("error", "unknown cmd: " + cmd));
                }
            } else {
                try {
                    byte state = Byte.parseByte(line);
                    bleManager.updateState(state);
                } catch (NumberFormatException ignored) {}
            }
        } catch (Exception e) {
            sendResponse(writer, Map.of("error", e.getMessage()));
        }
    }

    private void handlePermission(JsonNode cmdNode, PrintWriter writer) {
        int stateValue = cmdNode.has("value") ? cmdNode.get("value").asInt() : 1;
        bleManager.updateState((byte) stateValue);

        CompletableFuture.supplyAsync(() -> {
            bleManager.queryStatus();
            try { Thread.sleep(1500); } catch (InterruptedException e) {}
            return bleManager.getCachedStatus();
        }).thenAccept(status -> {
            Map<String, Object> response = buildStatusResponse(status);
            sendResponse(writer, response);
        }).exceptionally(e -> {
            sendResponse(writer, buildStatusResponse(null));
            return null;
        });
    }

    private void handleStatusRequest(PrintWriter writer) {
        if (cachedSwitchState != null) {
            sendResponse(writer, Map.of(
                "switchState", cachedSwitchState,
                "lightMode", cachedLightMode != null ? cachedLightMode : 0
            ));
        } else {
            CompletableFuture.supplyAsync(() -> {
                bleManager.queryStatus();
                try { Thread.sleep(1500); } catch (InterruptedException e) {}
                return bleManager.getCachedStatus();
            }).thenAccept(status -> {
                sendResponse(writer, buildStatusResponse(status));
            }).exceptionally(e -> {
                sendResponse(writer, buildStatusResponse(null));
                return null;
            });
        }
    }

    private Map<String, Object> buildStatusResponse(DeviceStatus status) {
        Map<String, Object> response = new HashMap<>();
        if (status != null) {
            response.put("switchState", status.getSwitchState());
            response.put("lightMode", status.getLightMode());
        } else {
            response.put("switchState", cachedSwitchState != null ? cachedSwitchState : "null");
            response.put("lightMode", cachedLightMode != null ? cachedLightMode : "null");
        }
        return response;
    }

    private void sendResponse(PrintWriter writer, Map<String, Object> data) {
        try {
            writer.println(mapper.writeValueAsString(data));
            writer.flush();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void scheduleStateReset(byte resetValue, int delayMs) {
        scheduler.schedule(() -> {
            bleManager.updateState(resetValue);
        }, delayMs, TimeUnit.MILLISECONDS);
    }

    public void updateStatus(DeviceStatus status) {
        this.cachedSwitchState = status.getSwitchState();
        this.cachedLightMode = status.getLightMode();
    }

    public void stop() throws IOException {
        executorService.shutdown();
        scheduler.shutdown();
        serverSocket.close();
    }
}