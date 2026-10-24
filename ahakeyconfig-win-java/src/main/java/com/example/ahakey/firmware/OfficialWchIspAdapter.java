package com.example.ahakey.firmware;

import java.nio.file.Path;
import java.util.UUID;
import java.util.Optional;

/**
 * Narrow boundary to the vendor supplied WCHISP executable.
 *
 * <p>The Studio orchestration layer owns user flow and state transitions;
 * this adapter owns only invoking the official tool and returning evidence.
 * Device identity is optional during detection because the vendor control
 * process, rather than the CLI {@code -u get} mode, is the authoritative UID
 * source.</p>
 */
public interface OfficialWchIspAdapter {
    /** Performs a user-requested, one-shot device detection. */
    DeviceDetectionResult detectDevice() throws Exception;

    /** Invokes the official download command for one already validated HEX. */
    FlashResult flashFirmware(Path hex) throws Exception;

    /**
     * Prepares all command/configuration data before the device enters ISP.
     * Implementations that do not support the preparation seam retain the
     * legacy flash method and are used only by compatibility tests.
     */
    default PreparedFlashSession prepareFlash(Path hex, UUID operationId,
                                              Path operationDirectory,
                                              RuntimeBundle runtime) throws Exception {
        return null;
    }

    /** Uses an already prepared session; no runtime/configuration work is repeated. */
    default FlashResult flashPrepared(PreparedFlashSession session,
                                      WchIspRunner.CancellationToken cancellation)
        throws Exception {
        if (session == null) throw new IllegalArgumentException("prepared flash session is missing");
        return flashFirmware(session.hexPath(), cancellation);
    }

    /** Fast detection path using the runtime already captured by a prepared session. */
    default DeviceDetectionResult detectDevice(PreparedFlashSession session) throws Exception {
        return detectDevice();
    }

    /** Cancellation-aware form used by the background firmware operation. */
    default FlashResult flashFirmware(Path hex, WchIspRunner.CancellationToken cancellation)
        throws Exception {
        return flashFirmware(hex);
    }

    record DeviceDetectionResult(boolean ispPresent,
                                 Optional<String> uid,
                                 String detail,
                                 RuntimeBundle runtime) {
        public DeviceDetectionResult {
            uid = uid == null ? Optional.empty() : uid.filter(value -> !value.isBlank());
            detail = detail == null ? "" : detail;
        }

        public static DeviceDetectionResult notPresent(RuntimeBundle runtime, String detail) {
            return new DeviceDetectionResult(false, Optional.empty(), detail, runtime);
        }

        public static DeviceDetectionResult present(RuntimeBundle runtime, String detail) {
            return new DeviceDetectionResult(true, Optional.empty(), detail, runtime);
        }
    }

    record FlashResult(boolean success,
                       String detail,
                       WchIspRunner.WchIspProcessResult processResult,
                       RuntimeBundle runtime) {
        public FlashResult {
            detail = detail == null ? "" : detail;
        }
    }
}
