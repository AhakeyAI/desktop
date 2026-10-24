package com.example.ahakey.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BleDriverLocatorTest {
    @TempDir
    Path temporary;

    @Test
    void canonicalPackagedPathWins() throws Exception {
        Path app = temporary.resolve("app");
        Path canonical = app.resolve("ble-driver").resolve("BLE_tcp_driver.exe");
        Files.createDirectories(canonical.getParent());
        Files.write(canonical, new byte[]{1});
        Path dev = temporary.resolve("BLE_tcp_bridge/bin/Release/BLE_tcp_driver.exe");
        Files.createDirectories(dev.getParent());
        Files.write(dev, new byte[]{2});

        var result = BleDriverLocator.resolve(app.resolve("ahakey-studio.jar"), app);

        assertEquals(canonical.toAbsolutePath().normalize(), result.selected().orElseThrow());
    }

    @Test
    void developmentSourceLayoutIsAControlledFallback() throws Exception {
        Path project = temporary.resolve("desktop").resolve("ahakeyconfig-win-java");
        Path dev = project.getParent().resolve("BLE_tcp_bridge/bin/Release/BLE_tcp_driver.exe");
        Files.createDirectories(dev.getParent());
        Files.write(dev, new byte[]{1});

        var result = BleDriverLocator.resolve(project.resolve("target/app.jar"), project);

        assertEquals(dev.toAbsolutePath().normalize(), result.selected().orElseThrow());
    }

    @Test
    void missingDriverReportsEveryAttemptedPath() {
        var result = BleDriverLocator.resolve(
            temporary.resolve("app/ahakey-studio.jar"), temporary.resolve("app"));

        assertTrue(result.selected().isEmpty());
        assertTrue(result.diagnosticMessage().contains("已尝试路径"));
        assertTrue(result.diagnosticMessage().contains("BLE_tcp_driver.exe"));
    }
}
