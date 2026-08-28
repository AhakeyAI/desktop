package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import org.junit.jupiter.api.Test;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class HookDispatchServerTest {
    @Test
    void claudeCannotUseStaleAutoButCanUseFreshAuto() throws Exception {
        AtomicReference<ApprovalSnapshot> snapshot = new AtomicReference<>(
            new ApprovalSnapshot(ApprovalState.STALE, true, false, 1));
        ApprovalService approvals = new ApprovalService(
            ignored -> snapshot.get(), 50);
        BleManager ble = disconnectedBleManager();
        TaskActivityService tasks = new TaskActivityService(ble);
        HookDispatchServer server = new HookDispatchServer(ble, tasks, approvals, 0);
        server.start();
        try {
            assertEquals(canonical("claude", "PermissionRequest", false,
                "fail-closed"), send(server, "PermissionRequest"));

            snapshot.set(new ApprovalSnapshot(ApprovalState.AUTO, true, true, 2));
            assertEquals(canonical("claude", "PermissionRequest", true,
                "hardware-auto"), send(server, "PermissionRequest"));
        } finally {
            server.stop();
        }
    }

    @Test
    void cursorDeniesWhenApprovalStateIsUnavailable() throws Exception {
        ApprovalService approvals = new ApprovalService(
            ignored -> new ApprovalSnapshot(
                ApprovalState.DISCONNECTED, false, false, 0),
            50
        );
        BleManager ble = disconnectedBleManager();
        TaskActivityService tasks = new TaskActivityService(ble);
        HookDispatchServer server = new HookDispatchServer(ble, tasks, approvals, 0);
        server.start();
        try {
            assertEquals(canonical("cursor", "preToolUse", false,
                "fail-closed"), send(server, "preToolUse"));
        } finally {
            server.stop();
        }
    }

    @Test
    void manualApprovalUsesUserConfirmedAndKimiNeverBypassesSharedSource()
            throws Exception {
        ApprovalService approvals = new ApprovalService(
            ignored -> new ApprovalSnapshot(ApprovalState.MANUAL, true, true, 3), 50);
        BleManager ble = disconnectedBleManager();
        HookDispatchServer server = new HookDispatchServer(
            ble, new TaskActivityService(ble), approvals, 0);
        server.setApprovalCallback((platform, event) -> true);
        server.start();
        try {
            assertEquals(canonical("kimi", "KimiPreToolUse", true,
                "user-confirmed"), send(server, "KimiPreToolUse"));
            assertEquals(canonical("codex", "CodexPermissionRequest", true,
                "user-confirmed"), send(server, "CodexPermissionRequest"));
        } finally {
            server.stop();
        }
    }

    @Test
    void lifecycleEventIsCanonicalButCannotAllow() throws Exception {
        ApprovalService approvals = new ApprovalService(
            ignored -> new ApprovalSnapshot(ApprovalState.AUTO, true, true, 4), 50);
        BleManager ble = disconnectedBleManager();
        HookDispatchServer server = new HookDispatchServer(
            ble, new TaskActivityService(ble), approvals, 0);
        server.start();
        try {
            String response = send(server, "SessionStart");
            assertEquals(canonical("claude", "SessionStart", false,
                "fail-closed"), response);
            assertFalse(response.contains("\"allow\":true"));
        } finally {
            server.stop();
        }
    }

    private String canonical(String platform, String event, boolean allow,
                             String source) {
        return "{\"schemaVersion\":1,\"platform\":\"" + platform
            + "\",\"event\":\"" + event + "\",\"allow\":" + allow
            + ",\"approvalSource\":\"" + source + "\"}";
    }

    private BleManager disconnectedBleManager() {
        return new BleManager(new BleManager.BleCallback() {
            @Override public void onConnected() {}
            @Override public void onDisconnected() {}
            @Override public void onStatusReceived(DeviceStatus status) {}
            @Override public void onError(String message) {}
        });
    }

    private String send(HookDispatchServer server, String event) throws Exception {
        try (Socket socket = new Socket("127.0.0.1", server.getActualPort());
             PrintWriter writer = new PrintWriter(
                 socket.getOutputStream(), true, StandardCharsets.UTF_8);
             BufferedReader reader = new BufferedReader(new InputStreamReader(
                 socket.getInputStream(), StandardCharsets.UTF_8))) {
            socket.setSoTimeout(2_000);
            writer.println(event);
            return reader.readLine();
        }
    }
}
