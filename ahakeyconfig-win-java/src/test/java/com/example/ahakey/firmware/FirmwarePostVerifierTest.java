package com.example.ahakey.firmware;

import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.update.SemanticVersion;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

class FirmwarePostVerifierTest {
    private static final AhaKeyResponseParser.DeviceCapabilities GOOD =
        new AhaKeyResponseParser.DeviceCapabilities(3, 2, 1, 4, 0,
            FirmwareCapabilities.REQUIRED_CAPABILITY_MASK, 8, 1);

    @Test
    void officialBundleRequiresAllContractFields() throws Exception {
        var verifier = new FirmwarePostVerifier(() -> GOOD, () -> true, millis -> { });
        var result = verifier.verify(SemanticVersion.parse("1.4.8"), java.time.Duration.ofSeconds(1));
        assertTrue(result.success(), result.detail());
        assertTrue(result.detail().contains("Firmware=1.4.8"));
        assertTrue(result.detail().contains("Protocol=3.2"));
        assertTrue(result.detail().contains("Model=1"));
        assertTrue(result.detail().contains("Capabilities=0x7FF"));
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

    @Test
    void cancellationDuringReconnectNeverReadsOrSucceeds() {
        AtomicBoolean read = new AtomicBoolean();
        var verifier = new FirmwarePostVerifier(() -> { read.set(true); return GOOD; },
            () -> false, millis -> { });
        assertThrows(InterruptedException.class, () -> verifier.awaitReconnect(
            java.time.Duration.ofSeconds(1), () -> true));
        assertFalse(read.get());
    }

    @Test
    void cancellationAfterCapabilityReadCannotBecomeSuccess() {
        AtomicBoolean cancelled = new AtomicBoolean();
        var verifier = new FirmwarePostVerifier(() -> { cancelled.set(true); return GOOD; },
            () -> true, millis -> { });
        assertThrows(InterruptedException.class, () -> verifier.verify(
            SemanticVersion.parse("1.4.8"), java.time.Duration.ofSeconds(1), cancelled::get));
    }

    @Test
    void reconnectWaitRejectsStaleStatusUntilNewFrameArrives() throws Exception {
        AtomicLong statusSequence = new AtomicLong(1);
        AtomicInteger sleeps = new AtomicInteger();
        var verifier = new FirmwarePostVerifier(() -> GOOD, () -> true, millis -> {
            sleeps.incrementAndGet();
            statusSequence.incrementAndGet();
        }, statusSequence::get);

        assertTrue(verifier.awaitReconnect(java.time.Duration.ofSeconds(1), () -> false));
        assertEquals(1, sleeps.get(), "a stale pre-reconnect status must not satisfy the wait");
    }

    @Test
    void reconnectWaitDoesNotAcceptStaleStatusWhenTimeoutExpires() throws Exception {
        AtomicLong statusSequence = new AtomicLong(1);
        var verifier = new FirmwarePostVerifier(() -> GOOD, () -> true, millis -> { },
            statusSequence::get);

        assertFalse(verifier.awaitReconnect(java.time.Duration.ZERO, () -> false));
    }

    @Test
    void reconnectUsesNewSessionAndAcceptsFreshStatusSeenBeforeAwaitCall() throws Exception {
        AtomicReference<com.example.ahakey.service.BleManager.TransportStatusSnapshot> snapshot =
            new AtomicReference<>(new com.example.ahakey.service.BleManager.TransportStatusSnapshot(
                2, 4, 1, 2_001, true));
        var verifier = new FirmwarePostVerifier(() -> GOOD, () -> true, millis -> { },
            snapshot::get, () -> snapshot.get().statusSequence());

        assertTrue(verifier.awaitReconnect(java.time.Duration.ZERO, () -> false,
            new com.example.ahakey.service.BleManager.TransportStatusSnapshot(
                1, 3, 9, 1_000, true), 2_000));
    }

    @Test
    void reconnectRejectsSameSessionEvenWhenSequenceIncreases() throws Exception {
        AtomicReference<com.example.ahakey.service.BleManager.TransportStatusSnapshot> snapshot =
            new AtomicReference<>(new com.example.ahakey.service.BleManager.TransportStatusSnapshot(
                1, 3, 10, 2_001, true));
        var verifier = new FirmwarePostVerifier(() -> GOOD, () -> true, millis -> { },
            snapshot::get, () -> snapshot.get().statusSequence());

        assertFalse(verifier.awaitReconnect(java.time.Duration.ZERO, () -> false,
            new com.example.ahakey.service.BleManager.TransportStatusSnapshot(
                1, 3, 1, 1_000, true), 2_000));
    }

    @Test
    void reconnectRejectsStatusThatPredatesFlashCompletion() throws Exception {
        AtomicReference<com.example.ahakey.service.BleManager.TransportStatusSnapshot> snapshot =
            new AtomicReference<>(new com.example.ahakey.service.BleManager.TransportStatusSnapshot(
                2, 4, 1, 1_999, true));
        var verifier = new FirmwarePostVerifier(() -> GOOD, () -> true, millis -> { },
            snapshot::get, () -> snapshot.get().statusSequence());

        assertFalse(verifier.awaitReconnect(java.time.Duration.ZERO, () -> false,
            new com.example.ahakey.service.BleManager.TransportStatusSnapshot(
                1, 3, 1, 1_000, true), 2_000));
    }

    @Test
    void capabilityVerificationRetriesAfterTransientNineFFailure() throws Exception {
        AtomicInteger reads = new AtomicInteger();
        var verifier = new FirmwarePostVerifier(() -> {
            if (reads.incrementAndGet() == 1) throw new java.io.IOException("0x9F timeout");
            return GOOD;
        }, () -> true, millis -> { });

        var result = verifier.verify(SemanticVersion.parse("1.4.8"),
            java.time.Duration.ofSeconds(1));
        assertTrue(result.success(), result.detail());
        assertEquals(2, reads.get());
    }
}
