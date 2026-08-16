package com.example.ahakey.update;

import java.util.Objects;
import java.util.Optional;

/** Parsed, platform-neutral representation of {@code ahakey.com/stable.json}. */
public record StableRelease(
        SemanticVersion appVersion,
        String appName,
        String appNotes,
        ReleaseAsset windowsInstaller,
        Optional<FirmwareAsset> ch582Firmware) {

    public StableRelease {
        appVersion = Objects.requireNonNull(appVersion, "appVersion");
        appName = appName == null ? "" : appName;
        appNotes = appNotes == null ? "" : appNotes;
        windowsInstaller = Objects.requireNonNull(
            windowsInstaller, "windowsInstaller");
        ch582Firmware = ch582Firmware == null
            ? Optional.empty() : ch582Firmware;
    }

    public record FirmwareAsset(
            SemanticVersion version,
            ReleaseAsset asset) {
        public FirmwareAsset {
            version = Objects.requireNonNull(version, "version");
            asset = Objects.requireNonNull(asset, "asset");
        }
    }
}
