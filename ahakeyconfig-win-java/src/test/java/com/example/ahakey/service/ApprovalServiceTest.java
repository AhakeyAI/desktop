package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ApprovalServiceTest {
    @Test
    void onlyFreshConnectedAutoCanApproveAutomatically() {
        DeviceStatus status = connectedStatus(0);
        ApprovalSnapshot snapshot = ApprovalService.fromDeviceStatus(status, true, 123);

        assertEquals(ApprovalState.AUTO, snapshot.state());
        assertTrue(snapshot.permitsAutomaticApproval());
    }

    @Test
    void staleCachedAutoCannotApproveAutomatically() {
        ApprovalSnapshot snapshot = ApprovalService.fromDeviceStatus(
            connectedStatus(0), false, 123);

        assertEquals(ApprovalState.STALE, snapshot.state());
        assertFalse(snapshot.permitsAutomaticApproval());
    }

    @Test
    void disconnectedCachedAutoCannotApproveAutomatically() {
        DeviceStatus status = connectedStatus(0);
        status.setConnected(false);

        ApprovalSnapshot snapshot = ApprovalService.fromDeviceStatus(status, true, 123);

        assertEquals(ApprovalState.DISCONNECTED, snapshot.state());
        assertFalse(snapshot.permitsAutomaticApproval());
    }

    @Test
    void manualAndUnknownStatesCannotApproveAutomatically() {
        assertEquals(ApprovalState.MANUAL,
            ApprovalService.fromDeviceStatus(connectedStatus(1), true, 1).state());
        assertEquals(ApprovalState.UNKNOWN,
            ApprovalService.fromDeviceStatus(connectedStatus(-1), true, 1).state());
        assertFalse(ApprovalService.fromDeviceStatus(
            connectedStatus(1), true, 1).permitsAutomaticApproval());
        assertFalse(ApprovalService.fromDeviceStatus(
            connectedStatus(7), true, 1).permitsAutomaticApproval());
    }

    @Test
    void providerFailureFailsClosed() {
        ApprovalService service = new ApprovalService(timeout -> {
            throw new IllegalStateException("device query failed");
        }, 50);

        ApprovalSnapshot snapshot = service.refresh();

        assertEquals(ApprovalState.UNKNOWN, snapshot.state());
        assertFalse(snapshot.permitsAutomaticApproval());
    }

    private DeviceStatus connectedStatus(int switchState) {
        DeviceStatus status = new DeviceStatus();
        status.setConnected(true);
        status.setSwitchState(switchState);
        return status;
    }
}
