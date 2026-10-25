package com.example.ahakey.app;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;

import java.util.concurrent.TimeUnit;
import java.util.function.LongSupplier;
import java.util.function.BooleanSupplier;

/** One stateful entry point for every device/user work-mode transition. */
final class WorkModeSynchronizer {
    static final long DEFAULT_CONFIRM_TIMEOUT_NANOS = TimeUnit.MILLISECONDS.toNanos(2500);

    enum Action { APPLY_DEVICE, CONFIRM_PENDING, IGNORE_STALE, INVALID }
    enum SelectionResult { OFFLINE_UI_ONLY, SENT_PENDING, SEND_FAILED }

    private final DeviceStatus deviceStatus;
    private final StudioState studioState;
    private final LongSupplier nanoTime;
    private final long confirmTimeoutNanos;
    private int pendingMode = -1;
    private long pendingDeadlineNanos;
    private int confirmedMode;

    WorkModeSynchronizer(DeviceStatus deviceStatus, StudioState studioState) {
        this(deviceStatus, studioState, System::nanoTime, DEFAULT_CONFIRM_TIMEOUT_NANOS);
    }

    WorkModeSynchronizer(
        DeviceStatus deviceStatus,
        StudioState studioState,
        LongSupplier nanoTime,
        long confirmTimeoutNanos
    ) {
        this.deviceStatus = deviceStatus;
        this.studioState = studioState;
        this.nanoTime = nanoTime;
        this.confirmTimeoutNanos = confirmTimeoutNanos;
        this.confirmedMode = Math.max(0, Math.min(
            ModeSlot.values().length - 1, deviceStatus.getWorkMode()));
    }

    synchronized SelectionResult selectUserMode(
        ModeSlot mode,
        boolean deviceConnected,
        BooleanSupplier sendDeviceCommand
    ) {
        studioState.setSelectedMode(mode);
        pendingMode = -1;
        if (!deviceConnected) {
            return SelectionResult.OFFLINE_UI_ONLY;
        }
        boolean sent;
        try {
            sent = sendDeviceCommand.getAsBoolean();
        } catch (RuntimeException exception) {
            sent = false;
        }
        if (!sent) {
            studioState.setSelectedMode(ModeSlot.fromIndex(confirmedMode));
            deviceStatus.setWorkMode(confirmedMode);
            return SelectionResult.SEND_FAILED;
        }
        pendingMode = mode.getIndex();
        pendingDeadlineNanos = nanoTime.getAsLong() + confirmTimeoutNanos;
        deviceStatus.setWorkMode(mode.getIndex());
        return SelectionResult.SENT_PENDING;
    }

    synchronized Action applyDeviceReport(int reportedMode) {
        if (reportedMode < 0 || reportedMode >= ModeSlot.values().length) {
            return Action.INVALID;
        }
        long now = nanoTime.getAsLong();
        if (pendingMode >= 0 && reportedMode != pendingMode
            && now < pendingDeadlineNanos) {
            return Action.IGNORE_STALE;
        }
        Action action = pendingMode == reportedMode
            ? Action.CONFIRM_PENDING : Action.APPLY_DEVICE;
        pendingMode = -1;
        confirmedMode = reportedMode;
        ModeSlot deviceMode = ModeSlot.fromIndex(reportedMode);
        deviceStatus.setWorkMode(reportedMode);
        studioState.setSelectedMode(deviceMode);
        return action;
    }

    synchronized void invalidateSession() {
        pendingMode = -1;
    }

    synchronized boolean hasPendingConfirmation() {
        return pendingMode >= 0;
    }
}
