package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.IDEState;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;

class TaskActivityServiceTest {
    @Test
    void missingTaskIdNeverCreatesPhantomSlot() throws Exception {
        try (TaskActivityService service = new TaskActivityService(new OfflineBle())) {
            service.accept("codex", 2, "thread-a", "A", IDEState.SESSION_START);
            service.accept("codex", 2, "thread-b", "B", IDEState.SESSION_START);
            service.accept("claude", 0, "default", "", IDEState.TASK_COMPLETED);
            service.awaitIdleForTest();

            assertEquals(2, service.getVisibleTasks().size());
        }
    }

    @Test
    void completedTaskExpiresWithoutHeartbeatResettingItsTimer() throws Exception {
        try (TaskActivityService service = new TaskActivityService(new OfflineBle())) {
            service.accept("codex", 2, "thread-a", "A", IDEState.TASK_COMPLETED);
            service.awaitIdleForTest();
            long completedAt = service.getVisibleTasks().get(0).updatedAt();

            service.reconcileAtForTest(completedAt + TaskActivityService.COMPLETED_VISIBLE_MILLIS);

            assertEquals(0, service.getVisibleTasks().size());
        }
    }

    @Test
    void taskLightWriteFailureIsReportedToUiCallback() throws Exception {
        FailingBle ble = new FailingBle();
        try (TaskActivityService service = new TaskActivityService(ble)) {
            service.setMultiMode(true);
            service.awaitIdleForTest();
            service.accept("codex", 2, "thread-a", "A", IDEState.SESSION_START);
            service.awaitIdleForTest();

            assertEquals(
                com.example.ahakey.util.LanguageManager.text("task.light.sync")
                    + com.example.ahakey.util.LanguageManager.text("task.sync.failed")
                    + "slot transport failed",
                ble.reported.get());
        }
    }

    @Test
    void firmwareWithoutTaskLightsIsAskedOnlyOncePerConnection() throws Exception {
        RejectingBle ble = new RejectingBle();
        try (TaskActivityService service = new TaskActivityService(ble)) {
            for (int tick = 0; tick < 5; tick++) {
                service.reconcileAtForTest(System.currentTimeMillis());
            }

            assertEquals(1, ble.modeQueries.get(), "0x98 rejection stops the retries");
            assertEquals(0, ble.heartbeats.get());
            assertEquals(null, ble.reported.get(), "no device error is shown for missing task lights");

            // A finished task must not try to clear a hardware slot either.
            service.accept("codex", 2, "thread-a", "A", IDEState.TASK_COMPLETED);
            service.awaitIdleForTest();
            service.reconcileAtForTest(System.currentTimeMillis()
                + TaskActivityService.COMPLETED_VISIBLE_MILLIS);
            assertEquals(0, ble.slotUpdates.get());
            assertEquals(null, ble.reported.get());
        }
    }

    private static final class RejectingBle extends BleManager {
        private final DeviceStatus status = new DeviceStatus();
        private final java.util.concurrent.atomic.AtomicInteger modeQueries =
            new java.util.concurrent.atomic.AtomicInteger();
        private final java.util.concurrent.atomic.AtomicInteger heartbeats =
            new java.util.concurrent.atomic.AtomicInteger();
        private final java.util.concurrent.atomic.AtomicInteger slotUpdates =
            new java.util.concurrent.atomic.AtomicInteger();
        private final AtomicReference<String> reported = new AtomicReference<>();

        private RejectingBle() {
            super(new BleCallback() {
                @Override public void onConnected() {}
                @Override public void onDisconnected() {}
                @Override public void onStatusReceived(DeviceStatus status) {}
                @Override public void onError(String message) {}
            });
            status.setConnected(true);
        }

        @Override public DeviceStatus getCachedStatus() { return status; }
        @Override public int queryTaskDisplayMode() throws Exception {
            modeQueries.incrementAndGet();
            throw new DeviceCommandException(
                com.example.ahakey.protocol.AhaKeyProtocol.CMD_TASK_LIGHT_MODE, 1, "rejected");
        }
        @Override public void sendTaskHeartbeat() { heartbeats.incrementAndGet(); }
        @Override public void updateTaskSlot(int slot, int profile, int state, boolean foreground)
                throws Exception {
            slotUpdates.incrementAndGet();
            throw new DeviceCommandException(
                com.example.ahakey.protocol.AhaKeyProtocol.CMD_TASK_SLOT_UPDATE, 1, "rejected");
        }
        @Override void reportDeviceError(String message) { reported.set(message); }
    }

    private static final class OfflineBle extends BleManager {
        private final DeviceStatus status = new DeviceStatus();

        private OfflineBle() {
            super(new BleCallback() {
                @Override public void onConnected() {}
                @Override public void onDisconnected() {}
                @Override public void onStatusReceived(DeviceStatus status) {}
                @Override public void onError(String message) {}
            });
        }

        @Override public DeviceStatus getCachedStatus() {
            return status;
        }
    }

    private static final class FailingBle extends BleManager {
        private final DeviceStatus status = new DeviceStatus();
        private final AtomicReference<String> reported = new AtomicReference<>();

        private FailingBle() {
            super(new BleCallback() {
                @Override public void onConnected() {}
                @Override public void onDisconnected() {}
                @Override public void onStatusReceived(DeviceStatus status) {}
                @Override public void onError(String message) {}
            });
            status.setConnected(true);
        }

        @Override public DeviceStatus getCachedStatus() { return status; }
        @Override public void setTaskDisplayMode(int mode) {}
        @Override public void updateTaskSlot(
            int slot, int profile, int state, boolean foreground
        ) throws Exception {
            throw new IOException("slot transport failed");
        }
        @Override void reportDeviceError(String message) { reported.set(message); }
    }
}
