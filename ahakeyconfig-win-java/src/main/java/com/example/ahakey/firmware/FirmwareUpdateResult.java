package com.example.ahakey.firmware;

import java.nio.file.Path;
import java.time.Instant;
import java.util.UUID;

/** Terminal result or immediate admission result for an operation. */
public record FirmwareUpdateResult(
    UUID operationId,
    FirmwareUpdateState state,
    FirmwareUpdateError error,
    String detail,
    Path diagnosticDirectory,
    Instant completedAt
) {
    public boolean success() {
        return state == FirmwareUpdateState.SUCCESS;
    }

    public boolean cancelled() {
        return state == FirmwareUpdateState.CANCELLED;
    }

    public static FirmwareUpdateResult busy() {
        return new FirmwareUpdateResult(
            null, FirmwareUpdateState.FAILED, FirmwareUpdateError.BUSY,
            "另一个固件操作正在执行", null, Instant.now());
    }
}
