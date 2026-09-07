package com.example.ahakey.firmware;

import com.example.ahakey.update.SemanticVersion;

import java.nio.file.Path;
import java.util.Objects;

/** Immutable input to one firmware update operation. */
public record FirmwareUpdateRequest(
    Path firmwareHex,
    SemanticVersion targetVersion,
    SemanticVersion currentVersion,
    boolean allowUnknownVersion,
    boolean allowDowngrade
) {
    public FirmwareUpdateRequest {
        firmwareHex = Objects.requireNonNull(firmwareHex, "firmwareHex")
            .toAbsolutePath().normalize();
    }

    public static FirmwareUpdateRequest of(Path firmwareHex, SemanticVersion targetVersion) {
        return new FirmwareUpdateRequest(firmwareHex, targetVersion, null, false, false);
    }
}
