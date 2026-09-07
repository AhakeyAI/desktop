package com.example.ahakey.firmware;

import java.util.Optional;

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
    ValidationStatus validationStatus
) {
    public enum ValidationStatus { KNOWN, UNKNOWN, MISMATCH }

    public RuntimeIdentity {
        executableFileVersion = normalize(executableFileVersion);
        executableProductVersion = normalize(executableProductVersion);
        ch343FileVersion = normalize(ch343FileVersion);
        ispDllFileVersion = normalize(ispDllFileVersion);
        validationStatus = validationStatus == null ? ValidationStatus.UNKNOWN : validationStatus;
    }

    private static Optional<String> normalize(Optional<String> value) {
        return value == null ? Optional.empty() : value.filter(v -> !v.isBlank());
    }
}
