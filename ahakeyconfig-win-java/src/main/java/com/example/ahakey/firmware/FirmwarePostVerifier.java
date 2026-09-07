package com.example.ahakey.firmware;

import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.update.SemanticVersion;

import java.time.Duration;
import java.util.function.BooleanSupplier;

/** Verifies a normally reconnected device against the 0x9F contract. */
public final class FirmwarePostVerifier {
    private final CapabilityReader reader;
    private final BooleanSupplier connected;
    private final Sleeper sleeper;

    public FirmwarePostVerifier(BleManager manager) {
        this(manager::queryDeviceCapabilities, manager::isTransportSessionActive,
            millis -> Thread.sleep(millis));
    }

    public FirmwarePostVerifier(CapabilityReader reader, BooleanSupplier connected) {
        this(reader, connected, millis -> Thread.sleep(millis));
    }

    public FirmwarePostVerifier(CapabilityReader reader, BooleanSupplier connected,
                                Sleeper sleeper) {
        this.reader = reader;
        this.connected = connected == null ? () -> true : connected;
        this.sleeper = sleeper == null ? millis -> Thread.sleep(millis) : sleeper;
    }

    public Verification verify(SemanticVersion expectedVersion, Duration timeout)
        throws Exception {
        return verify(expectedVersion, timeout, () -> false);
    }

    /** Waits for the transport to report a post-flash reconnect before reading capabilities. */
    public boolean awaitReconnect(Duration timeout, BooleanSupplier cancellation) throws Exception {
        Duration effective = timeout == null || timeout.isNegative() ? Duration.ZERO : timeout;
        BooleanSupplier stop = cancellation == null ? () -> false : cancellation;
        long deadline = System.nanoTime() + effective.toNanos();
        while (System.nanoTime() < deadline) {
            if (stop.getAsBoolean()) throw new InterruptedException("reconnect wait cancelled");
            if (connected.getAsBoolean()) return true;
            sleep(50);
        }
        if (stop.getAsBoolean()) throw new InterruptedException("reconnect wait cancelled");
        return connected.getAsBoolean();
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
            try {
                capabilities = reader.read();
                if (stop.getAsBoolean()) throw new InterruptedException("post-flash verification cancelled");
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
        return new Verification(true, null, "设备已重连并通过 0x9F 合同校验", capabilities);
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
