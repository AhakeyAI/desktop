package com.example.ahakey.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotEquals;

class DeviceStatusTest {
    @Test
    void switchLabelsDistinguishAutoManualDisconnectedAndUnknown() {
        DeviceStatus status = new DeviceStatus();
        String disconnected = status.getSwitchTitle();

        status.setConnected(true);
        status.setSwitchState(-1);
        String unknown = status.getSwitchTitle();
        status.setSwitchState(0);
        String automatic = status.getSwitchTitle();
        status.setSwitchState(1);
        String manual = status.getSwitchTitle();

        assertNotEquals(disconnected, unknown);
        assertNotEquals(unknown, automatic);
        assertNotEquals(automatic, manual);
        assertNotEquals(manual, disconnected);
    }
}
