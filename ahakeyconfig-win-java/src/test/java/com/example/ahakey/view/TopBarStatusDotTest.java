package com.example.ahakey.view;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class TopBarStatusDotTest {
    @Test
    void connectionDotFollowsConnectionState() {
        assertEquals(AccentColor.GREEN, TopBar.connectionAccent(true, false));
        assertEquals(AccentColor.ORANGE, TopBar.connectionAccent(false, true));
        assertEquals(AccentColor.RED, TopBar.connectionAccent(false, false));
    }

    @Test
    void batteryDotFollowsLevel() {
        assertEquals(AccentColor.GRAY, TopBar.batteryAccent(false, "BLE", 80));
        assertEquals(AccentColor.GREEN, TopBar.batteryAccent(true, "USB", -1));
        assertEquals(AccentColor.GRAY, TopBar.batteryAccent(true, "BLE", -1));
        assertEquals(AccentColor.GREEN, TopBar.batteryAccent(true, "BLE", 51));
        assertEquals(AccentColor.ORANGE, TopBar.batteryAccent(true, "BLE", 50));
        assertEquals(AccentColor.ORANGE, TopBar.batteryAccent(true, "BLE", 21));
        assertEquals(AccentColor.RED, TopBar.batteryAccent(true, "BLE", 20));
    }
}
