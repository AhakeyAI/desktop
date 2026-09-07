package com.example.ahakey.firmware;

import java.util.Optional;
import java.util.Map;

/**
 * Observed binary identity of a WCHISP runtime.  Missing Windows version
 * resources are represented as UNKNOWN; hashes are always captured.
 */
public record RuntimeIdentity(
    Optional<String> executableFileVersion,
    Optional<String> executableProductVersion,
    Optional<String> ch343FileVersion,
    Optional<String> ispDllFileVersion,
    String executableSha256,
    String ch343Sha256,
    String ispDllSha256,
    String configSha256,
    ValidationStatus validationStatus,
    Map<String, String> expectedMetadata
) {
    public enum ValidationStatus { KNOWN, UNKNOWN, MISMATCH }

    public RuntimeIdentity {
        executableFileVersion = normalize(executableFileVersion);
        executableProductVersion = normalize(executableProductVersion);
        ch343FileVersion = normalize(ch343FileVersion);
        ispDllFileVersion = normalize(ispDllFileVersion);
        validationStatus = validationStatus == null ? ValidationStatus.UNKNOWN : validationStatus;
        expectedMetadata = expectedMetadata == null ? Map.of() : Map.copyOf(expectedMetadata);
    }

    /** Compatibility constructor for callers that do not have metadata yet. */
    public RuntimeIdentity(Optional<String> executableFileVersion,
                           Optional<String> executableProductVersion,
                           Optional<String> ch343FileVersion,
                           Optional<String> ispDllFileVersion,
                           String executableSha256,
                           String ch343Sha256,
                           String ispDllSha256,
                           String configSha256,
                           ValidationStatus validationStatus) {
        this(executableFileVersion, executableProductVersion, ch343FileVersion,
            ispDllFileVersion, executableSha256, ch343Sha256, ispDllSha256,
            configSha256, validationStatus, Map.of());
    }

    private static Optional<String> normalize(Optional<String> value) {
        return value == null ? Optional.empty() : value.filter(v -> !v.isBlank());
    }
}
