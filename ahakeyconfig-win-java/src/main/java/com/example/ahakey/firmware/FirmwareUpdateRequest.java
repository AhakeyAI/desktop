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
    boolean allowDowngrade,
    Source source
) {
    public FirmwareUpdateRequest {
        firmwareHex = Objects.requireNonNull(firmwareHex, "firmwareHex")
            .toAbsolutePath().normalize();
        source = source == null ? Source.LOCAL : source;
    }

    public FirmwareUpdateRequest(Path firmwareHex, SemanticVersion targetVersion,
                                 SemanticVersion currentVersion,
                                 boolean allowUnknownVersion, boolean allowDowngrade) {
        this(firmwareHex, targetVersion, currentVersion, allowUnknownVersion,
            allowDowngrade, Source.LOCAL);
    }

    public static FirmwareUpdateRequest of(Path firmwareHex, SemanticVersion targetVersion) {
        return new FirmwareUpdateRequest(firmwareHex, targetVersion, null, false, false,
            Source.LOCAL);
    }

    public enum Source {
        BUILTIN,
        LOCAL,
        REMOTE
    }
}
