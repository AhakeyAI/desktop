package com.example.ahakey.firmware;

import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.update.SemanticVersion;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class FirmwarePostVerifierTest {
    private static final AhaKeyResponseParser.DeviceCapabilities GOOD =
        new AhaKeyResponseParser.DeviceCapabilities(3, 2, 1, 4, 0,
            FirmwareCapabilities.REQUIRED_CAPABILITY_MASK, 7, 1);

    @Test
    void officialBundleRequiresAllContractFields() throws Exception {
        var verifier = new FirmwarePostVerifier(() -> GOOD, () -> true, millis -> { });
        var result = verifier.verify(SemanticVersion.parse("1.4.7"), java.time.Duration.ofSeconds(1));
        assertTrue(result.success(), result.detail());
    }

    @Test
    void versionProtocolModelAndCapabilitiesFailSeparately() throws Exception {
        var version = new FirmwarePostVerifier(() -> GOOD, () -> true, millis -> { })
            .verify(SemanticVersion.parse("1.4.6"), java.time.Duration.ofSeconds(1));
        assertEquals(FirmwareUpdateError.POST_FLASH_VERSION_MISMATCH, version.error());
        var protocolCaps = new AhaKeyResponseParser.DeviceCapabilities(2, 0, 1, 4, 0,
            FirmwareCapabilities.REQUIRED_CAPABILITY_MASK, 7, 1);
        var protocol = new FirmwarePostVerifier(() -> protocolCaps, () -> true, millis -> { })
            .verify(null, java.time.Duration.ofSeconds(1));
        assertEquals(FirmwareUpdateError.POST_FLASH_PROTOCOL_MISMATCH, protocol.error());
    }

    @Test
    void disconnectedDeviceDoesNotBecomeVerified() throws Exception {
        var verifier = new FirmwarePostVerifier(() -> GOOD, () -> false, millis -> { });
        var result = verifier.verify(null, java.time.Duration.ZERO);
        assertEquals(FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED, result.error());
    }
}
