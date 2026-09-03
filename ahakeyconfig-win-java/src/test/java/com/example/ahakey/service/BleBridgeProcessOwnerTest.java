package com.example.ahakey.service;

import org.junit.jupiter.api.Test;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BleBridgeProcessOwnerTest {
    @Test
    void executableIdentityIsNormalizedCaseInsensitively() {
        assertTrue(BleBridgeProcessOwner.sameExecutable(
            Path.of("C:/Aha/BLE_tcp_driver.exe"),
            Path.of("c:/aha/./BLE_tcp_driver.exe")));
        assertFalse(BleBridgeProcessOwner.sameExecutable(
            Path.of("C:/Aha/BLE_tcp_driver.exe"),
            Path.of("C:/Other/BLE_tcp_driver.exe")));
    }
}
