package com.example.ahakey.firmware;

import java.time.Instant;
import java.util.UUID;

/** Immutable status event published to UI listeners. */
public record FirmwareUpdateStatus(
    UUID operationId,
    FirmwareUpdateState state,
    FirmwareUpdateError error,
    String detail,
    double progress,
    Instant at
) {
    public FirmwareUpdateStatus {
        detail = detail == null ? "" : detail;
        at = at == null ? Instant.now() : at;
    }
}
