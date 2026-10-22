package com.example.ahakey.firmware;

import java.nio.file.Path;
import java.util.Objects;

/** Read-only, validated runtime assets selected for one operation. */
public record RuntimeBundle(
    Path root,
    Path executable,
    Path ch343Dll,
    Path ispDll,
    Path binaryConfig,
    Path metadata,
    RuntimeIdentity identity
) {
    public RuntimeBundle {
        root = normalize(root);
        executable = normalize(executable);
        ch343Dll = normalize(ch343Dll);
        ispDll = normalize(ispDll);
        binaryConfig = normalize(binaryConfig);
        metadata = metadata == null ? null : metadata.toAbsolutePath().normalize();
        identity = Objects.requireNonNull(identity, "identity");
    }

    private static Path normalize(Path value) {
        return Objects.requireNonNull(value, "runtime path").toAbsolutePath().normalize();
    }
}
