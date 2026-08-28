package com.example.ahakey.firmware;

import com.example.ahakey.update.SemanticVersion;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import org.junit.jupiter.api.Test;

import java.io.InputStream;
import java.util.Properties;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;

class FirmwareCapabilitiesTest {
    @Test
    void bundledFirmwareSatisfiesExposedGifCapability() {
        assertEquals(new SemanticVersion(1, 4, 3),
            FirmwareCapabilities.MINIMUM_GIF_VERSION);
        assertEquals(new SemanticVersion(1, 4, 7),
            FirmwareCapabilities.MINIMUM_STABILIZED_VERSION);
        assertEquals(new SemanticVersion(1, 4, 7),
            FirmwareCapabilities.BUNDLED_VERSION);
        assertEquals("AhaKey-X1-firmware-1.4.7-ch582.hex",
            FirmwareCapabilities.BUNDLED_FIRMWARE_NAME);
        assertTrue(FirmwareCapabilities.supportsGif(
            FirmwareCapabilities.BUNDLED_VERSION));
        assertTrue(FirmwareCapabilities.BUNDLED_VERSION.compareTo(
            FirmwareCapabilities.MINIMUM_GIF_VERSION) >= 0);
    }

    @Test
    void gifVersionComparisonIsNumeric() {
        assertFalse(FirmwareCapabilities.supportsGif(
            new SemanticVersion(1, 4, 2)));
        assertTrue(FirmwareCapabilities.supportsGif(
            new SemanticVersion(1, 4, 10)));
    }

    @Test
    void javaCapabilityUsesTheSharedReleaseProperties() throws Exception {
        Properties values = new Properties();
        try (InputStream input = getClass().getResourceAsStream(
            "/firmware-capabilities.properties")) {
            values.load(input);
        }
        assertTrue(FirmwareCapabilities.MINIMUM_GIF_VERSION.toString().equals(
            values.getProperty("minimumGifVersion")));
        assertTrue(FirmwareCapabilities.BUNDLED_VERSION.toString().equals(
            values.getProperty("expectedBundledVersion")));
        assertTrue(FirmwareCapabilities.MINIMUM_STABILIZED_VERSION.toString().equals(
            values.getProperty("minimumStabilizedFirmwareVersion")));
        assertEquals(3, FirmwareCapabilities.REQUIRED_PROTOCOL_MAJOR);
        assertEquals(2, FirmwareCapabilities.REQUIRED_PROTOCOL_MINOR);
        assertEquals(0x7FFL, FirmwareCapabilities.REQUIRED_CAPABILITY_MASK);
        assertEquals(AhaKeyProtocol.REQUIRED_STABILIZED_CAPABILITY_MASK,
            FirmwareCapabilities.REQUIRED_CAPABILITY_MASK);
        assertEquals(1, FirmwareCapabilities.REQUIRED_DEVICE_MODEL);
        assertEquals("AhaKey-X1", FirmwareCapabilities.REQUIRED_DEVICE_MODEL_NAME);
        assertEquals(0x0006FFFFL, FirmwareCapabilities.MAX_FIRMWARE_ADDRESS);
    }

    @Test
    void stabilizedContractRequiresModelProtocolFirmwareAndEveryCapability() {
        AhaKeyResponseParser.DeviceCapabilities valid = capabilities(
            3, 2, 1, 4, 7, 1, 0x7FFL);
        FirmwareCapabilities.requireStabilizedContract(valid);

        assertThrows(IllegalStateException.class, () ->
            FirmwareCapabilities.requireStabilizedContract(capabilities(
                3, 2, 1, 4, 7, 2, 0x7FFL)));
        assertThrows(IllegalStateException.class, () ->
            FirmwareCapabilities.requireStabilizedContract(capabilities(
                3, 1, 1, 4, 7, 1, 0x7FFL)));
        assertThrows(IllegalStateException.class, () ->
            FirmwareCapabilities.requireStabilizedContract(capabilities(
                3, 2, 1, 4, 6, 1, 0x7FFL)));
        assertThrows(IllegalStateException.class, () ->
            FirmwareCapabilities.requireStabilizedContract(capabilities(
                3, 2, 1, 4, 7, 1, 0x3FFL)));
    }

    private static AhaKeyResponseParser.DeviceCapabilities capabilities(
        int protocolMajor, int protocolMinor, int firmwareMajor,
        int firmwareMinor, int firmwarePatch, int model, long mask
    ) {
        return new AhaKeyResponseParser.DeviceCapabilities(
            protocolMajor, protocolMinor, firmwareMajor, firmwareMinor,
            1, mask, firmwarePatch, model);
    }
}
