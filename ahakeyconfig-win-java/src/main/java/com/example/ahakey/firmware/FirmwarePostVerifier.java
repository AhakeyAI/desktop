package com.example.ahakey.firmware;

import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.update.SemanticVersion;

import java.time.Duration;
import java.util.function.BooleanSupplier;
import java.util.function.LongSupplier;
import java.util.function.Supplier;

/** Verifies a normally reconnected device against the 0x9F contract. */
public final class FirmwarePostVerifier {
    private final CapabilityReader reader;
    private final BooleanSupplier connected;
    private final Sleeper sleeper;
    /** Optional production signal proving a status frame arrived after the
     * post-flash reconnect wait began. Test-only callers may omit it. */
    private final LongSupplier statusUpdateSequence;
    private final Supplier<BleManager.TransportStatusSnapshot> transportSnapshot;
    private volatile BleManager.TransportStatusSnapshot verificationSession;

    public FirmwarePostVerifier(BleManager manager) {
        this(manager::queryDeviceCapabilities, manager::isReadyForPostFlashVerification,
            millis -> Thread.sleep(millis), manager::getTransportStatusSnapshot,
            manager::getStatusUpdateSequence);
    }

    public FirmwarePostVerifier(CapabilityReader reader, BooleanSupplier connected) {
        this(reader, connected, millis -> Thread.sleep(millis));
    }

    public FirmwarePostVerifier(CapabilityReader reader, BooleanSupplier connected,
                                Sleeper sleeper) {
        this(reader, connected, sleeper, null);
    }

    FirmwarePostVerifier(CapabilityReader reader, BooleanSupplier connected,
                         Sleeper sleeper, LongSupplier statusUpdateSequence) {
        this(reader, connected, sleeper, null, statusUpdateSequence);
    }

    FirmwarePostVerifier(CapabilityReader reader, BooleanSupplier connected,
                         Sleeper sleeper,
                         Supplier<BleManager.TransportStatusSnapshot> transportSnapshot,
                         LongSupplier statusUpdateSequence) {
        this.reader = reader;
        this.connected = connected == null ? () -> true : connected;
        this.sleeper = sleeper == null ? millis -> Thread.sleep(millis) : sleeper;
        this.statusUpdateSequence = statusUpdateSequence;
        this.transportSnapshot = transportSnapshot;
    }

    /** Captures the transport facts that existed before a flash operation. */
    public BleManager.TransportStatusSnapshot captureTransportStatusSnapshot() {
        return transportSnapshot == null ? null : transportSnapshot.get();
    }

    public Verification verify(SemanticVersion expectedVersion, Duration timeout)
        throws Exception {
        return verify(expectedVersion, timeout, () -> false);
    }

    /** Waits for the transport to report a post-flash reconnect before reading capabilities. */
    public boolean awaitReconnect(Duration timeout, BooleanSupplier cancellation) throws Exception {
        return awaitReconnect(timeout, cancellation, null, 0);
    }

    /**
     * Waits for a connected status from a new session, with a monotonic
     * completion boundary supplied by the successful WCHISP operation.
     */
    public boolean awaitReconnect(Duration timeout, BooleanSupplier cancellation,
                                  BleManager.TransportStatusSnapshot baseline,
                                  long flashCompletionNanos) throws Exception {
        Duration effective = timeout == null || timeout.isNegative() ? Duration.ZERO : timeout;
        BooleanSupplier stop = cancellation == null ? () -> false : cancellation;
        long deadline = System.nanoTime() + effective.toNanos();
        long waitStartedAtSequence = statusUpdateSequence == null
            ? 0 : statusUpdateSequence.getAsLong();
        while (System.nanoTime() < deadline) {
            if (stop.getAsBoolean()) throw new InterruptedException("reconnect wait cancelled");
            if (isReadyAfter(waitStartedAtSequence, baseline, flashCompletionNanos)) return true;
            sleep(50);
        }
        if (stop.getAsBoolean()) throw new InterruptedException("reconnect wait cancelled");
        return isReadyAfter(waitStartedAtSequence, baseline, flashCompletionNanos);
    }

    private boolean isReadyAfter(long waitStartedAtSequence,
                                 BleManager.TransportStatusSnapshot baseline,
                                 long flashCompletionNanos) {
        if (transportSnapshot != null && baseline != null) {
            BleManager.TransportStatusSnapshot current = transportSnapshot.get();
            boolean ready = current != null
                && current.connected()
                && current.statusSequence() > 0
                && (current.sessionEpoch() != baseline.sessionEpoch()
                    || current.receiverIdentity() != baseline.receiverIdentity())
                && current.lastStatusAtNanos() > flashCompletionNanos;
            if (ready) verificationSession = current;
            return ready;
        }
        if (!connected.getAsBoolean()) return false;
        return statusUpdateSequence == null
            || statusUpdateSequence.getAsLong() > waitStartedAtSequence;
    }

    public Verification verify(SemanticVersion expectedVersion, Duration timeout,
                                BooleanSupplier cancellation) throws Exception {
        BooleanSupplier stop = cancellation == null ? () -> false : cancellation;
        long deadline = System.nanoTime() + (timeout == null ? Duration.ofSeconds(30) : timeout).toNanos();
        AhaKeyResponseParser.DeviceCapabilities capabilities = null;
        Exception last = null;
        while (System.nanoTime() < deadline) {
            if (stop.getAsBoolean()) throw new InterruptedException("post-flash verification cancelled");
            if (!connected.getAsBoolean()) {
                sleep(100);
                continue;
            }
            if (verificationSession != null && !sameSession(verificationSession)) {
                return Verification.failure(FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED,
                    "0x9F 验证期间 transport session 发生变化");
            }
            try {
                capabilities = reader.read();
                if (stop.getAsBoolean()) throw new InterruptedException("post-flash verification cancelled");
                if (verificationSession != null && !sameSession(verificationSession)) {
                    return Verification.failure(FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED,
                        "0x9F 响应来自已失效的 transport session");
                }
                if (capabilities != null) break;
            } catch (Exception failure) {
                if (failure instanceof InterruptedException) throw failure;
                last = failure;
            }
            sleep(100);
        }
        if (stop.getAsBoolean()) throw new InterruptedException("post-flash verification cancelled");
        if (capabilities == null) {
            return Verification.failure(FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED,
                last == null ? "设备未在时限内正常重连" : last.getMessage());
        }
        SemanticVersion actual = new SemanticVersion(capabilities.firmwareMajor(),
            capabilities.firmwareMinor(), capabilities.firmwarePatch());
        if (expectedVersion != null && !expectedVersion.equals(actual)) {
            return Verification.failure(FirmwareUpdateError.POST_FLASH_VERSION_MISMATCH,
                "期望固件 " + expectedVersion + "，设备返回 " + actual);
        }
        if (capabilities.protocolMajor() != FirmwareCapabilities.REQUIRED_PROTOCOL_MAJOR
            || capabilities.protocolMinor() != FirmwareCapabilities.REQUIRED_PROTOCOL_MINOR) {
            return Verification.failure(FirmwareUpdateError.POST_FLASH_PROTOCOL_MISMATCH,
                "协议版本不满足客户端合同");
        }
        if (capabilities.deviceModel() != FirmwareCapabilities.REQUIRED_DEVICE_MODEL) {
            return Verification.failure(FirmwareUpdateError.POST_FLASH_MODEL_MISMATCH,
                "设备型号不满足客户端合同");
        }
        if ((capabilities.capabilityBits() & FirmwareCapabilities.REQUIRED_CAPABILITY_MASK)
            != FirmwareCapabilities.REQUIRED_CAPABILITY_MASK) {
            return Verification.failure(FirmwareUpdateError.POST_FLASH_CAPABILITIES_MISMATCH,
                String.format("能力位 0x%X 不满足最低要求 0x%X",
                    capabilities.capabilityBits(), FirmwareCapabilities.REQUIRED_CAPABILITY_MASK));
        }
        if (stop.getAsBoolean()) throw new InterruptedException("post-flash verification cancelled");
        return new Verification(true, null, String.format(
            "设备已重连并通过 0x9F 合同校验%nFirmware=%s%nProtocol=%d.%d%nModel=%d%nCapabilities=0x%X",
            actual, capabilities.protocolMajor(), capabilities.protocolMinor(),
            capabilities.deviceModel(), capabilities.capabilityBits()), capabilities);
    }

    private boolean sameSession(BleManager.TransportStatusSnapshot expected) {
        BleManager.TransportStatusSnapshot current = transportSnapshot == null
            ? null : transportSnapshot.get();
        return current != null && current.connected()
            && current.sessionEpoch() == expected.sessionEpoch()
            && current.receiverIdentity() == expected.receiverIdentity();
    }

    private void sleep(long millis) throws InterruptedException {
        sleeper.sleep(millis);
    }

    @FunctionalInterface
    public interface CapabilityReader {
        AhaKeyResponseParser.DeviceCapabilities read() throws Exception;
    }

    @FunctionalInterface
    public interface Sleeper {
        void sleep(long millis) throws InterruptedException;
    }

    public record Verification(boolean success, FirmwareUpdateError error,
                               String detail,
                               AhaKeyResponseParser.DeviceCapabilities capabilities) {
        static Verification failure(FirmwareUpdateError error, String detail) {
            return new Verification(false, error, detail == null ? "" : detail, null);
        }
    }
}
