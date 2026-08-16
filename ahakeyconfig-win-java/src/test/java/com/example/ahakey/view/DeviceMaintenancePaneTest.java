package com.example.ahakey.view;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class DeviceMaintenancePaneTest {
    @TempDir
    Path temporaryDirectory;

    @Test
    void locatesFirmwareInsideJpackageAppDirectory() throws Exception {
        Path launcher = temporaryDirectory.resolve("AhaKeyStudio.exe");
        Path firmware = temporaryDirectory.resolve("app")
            .resolve("firmware")
            .resolve(DeviceMaintenancePane.BUNDLED_FIRMWARE_NAME);
        Files.createDirectories(firmware.getParent());
        Files.writeString(firmware, ":00000001FF\n");

        assertEquals(
            firmware.toAbsolutePath().normalize(),
            DeviceMaintenancePane.bundledFirmwarePath(
                launcher.toString(),
                temporaryDirectory.resolve("development-fallback.hex")
            )
        );
    }

    @Test
    void flashPrerequisitesExplainWhyTheButtonIsDisabled() {
        var current = new com.example.ahakey.update.SemanticVersion(1, 1, 1);
        var newer = new com.example.ahakey.update.SemanticVersion(1, 1, 2);
        var older = new com.example.ahakey.update.SemanticVersion(1, 1, 0);

        assertEquals("FIRMWARE_REQUIRED", DeviceMaintenancePane.flashBlockReason(
            false, newer, current, false, false, false));
        assertEquals("CURRENT_VERSION_REQUIRED", DeviceMaintenancePane.flashBlockReason(
            true, newer, null, false, false, false));
        assertEquals("DOWNGRADE_CONFIRMATION_REQUIRED", DeviceMaintenancePane.flashBlockReason(
            true, older, current, false, false, false));
        assertEquals("", DeviceMaintenancePane.flashBlockReason(
            true, newer, current, false, false, false));
    }

    @Test
    void flashingRequiresBothVersionPrerequisitesAndARealIspDetection() {
        assertFalse(DeviceMaintenancePane.canStartFlash("FIRMWARE_REQUIRED", true));
        assertFalse(DeviceMaintenancePane.canStartFlash("", false));
        assertTrue(DeviceMaintenancePane.canStartFlash("", true));
    }
}
