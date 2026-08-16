package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.IDEState;
import org.junit.jupiter.api.Test;

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
}
