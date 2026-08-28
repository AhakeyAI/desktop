package com.example.ahakey.app;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;
import org.junit.jupiter.api.Test;

import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WorkModeSynchronizerTest {
    @Test
    void disconnectedSelectionChangesOnlyTheEditingMode() {
        Fixture fixture = new Fixture();
        AtomicInteger sends = new AtomicInteger();

        assertEquals(WorkModeSynchronizer.SelectionResult.OFFLINE_UI_ONLY,
            fixture.sync.selectUserMode(ModeSlot.MODE2, false, () -> {
                sends.incrementAndGet();
                return true;
            }));

        assertEquals(0, sends.get());
        assertEquals(0, fixture.device.getWorkMode());
        assertEquals(ModeSlot.MODE2, fixture.studio.getSelectedMode());
        assertFalse(fixture.sync.hasPendingConfirmation());
    }

    @Test
    void failedSendNeverCreatesPendingConfirmation() {
        Fixture fixture = new Fixture();

        assertEquals(WorkModeSynchronizer.SelectionResult.SEND_FAILED,
            fixture.sync.selectUserMode(ModeSlot.MODE2, true, () -> false));

        assertEquals(0, fixture.device.getWorkMode());
        assertEquals(ModeSlot.MODE0, fixture.studio.getSelectedMode());
        assertFalse(fixture.sync.hasPendingConfirmation());
        assertEquals(WorkModeSynchronizer.Action.APPLY_DEVICE,
            fixture.sync.applyDeviceReport(0));
        assertEquals(ModeSlot.MODE0, fixture.studio.getSelectedMode());
    }

    @Test
    void rapidModeZeroOneTwoIgnoresDelayedReportsUntilLatestConfirmation() {
        Fixture fixture = new Fixture();
        assertEquals(WorkModeSynchronizer.SelectionResult.SENT_PENDING,
            fixture.sync.selectUserMode(ModeSlot.MODE1, true, () -> true));
        assertEquals(WorkModeSynchronizer.SelectionResult.SENT_PENDING,
            fixture.sync.selectUserMode(ModeSlot.MODE2, true, () -> true));

        assertEquals(WorkModeSynchronizer.Action.IGNORE_STALE,
            fixture.sync.applyDeviceReport(0));
        assertEquals(WorkModeSynchronizer.Action.IGNORE_STALE,
            fixture.sync.applyDeviceReport(1));
        assertEquals(2, fixture.device.getWorkMode());
        assertEquals(ModeSlot.MODE2, fixture.studio.getSelectedMode());

        assertEquals(WorkModeSynchronizer.Action.CONFIRM_PENDING,
            fixture.sync.applyDeviceReport(2));
        assertFalse(fixture.sync.hasPendingConfirmation());
    }

    @Test
    void transportSessionChangeInvalidatesPendingMode() {
        Fixture fixture = new Fixture();
        fixture.sync.selectUserMode(ModeSlot.MODE2, true, () -> true);
        assertTrue(fixture.sync.hasPendingConfirmation());

        fixture.sync.invalidateSession();
        assertFalse(fixture.sync.hasPendingConfirmation());
        assertEquals(WorkModeSynchronizer.Action.APPLY_DEVICE,
            fixture.sync.applyDeviceReport(1));
        assertEquals(1, fixture.device.getWorkMode());
        assertEquals(ModeSlot.MODE1, fixture.studio.getSelectedMode());
    }

    @Test
    void deviceWinsWhenConfirmationWindowExpires() {
        Fixture fixture = new Fixture();
        fixture.sync.selectUserMode(ModeSlot.MODE2, true, () -> true);
        fixture.clock.set(200);

        assertEquals(WorkModeSynchronizer.Action.APPLY_DEVICE,
            fixture.sync.applyDeviceReport(1));
        assertEquals(1, fixture.device.getWorkMode());
        assertEquals(ModeSlot.MODE1, fixture.studio.getSelectedMode());
    }

    private static final class Fixture {
        final AtomicLong clock = new AtomicLong(100);
        final DeviceStatus device = new DeviceStatus();
        final StudioState studio = new StudioState();
        final WorkModeSynchronizer sync = new WorkModeSynchronizer(
            device, studio, clock::get, 100);
    }
}
