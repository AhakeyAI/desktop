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
                "同步任务灯效失败；灯效/OLED 状态可能不同步：slot transport failed",
                ble.reported.get());
        }
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
