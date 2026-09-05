package com.example.ahakey.service;

import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;

/** Resolves the BLE bridge from the packaged layout before development fallbacks. */
public final class BleDriverLocator {
    public static final String DRIVER_FILE_NAME = "BLE_tcp_driver.exe";

    private BleDriverLocator() {}

    public static Resolution resolve() {
        Path codeSource = codeSourcePath();
        return resolve(codeSource, Path.of(System.getProperty("user.dir", ".")));
    }

    static Resolution resolve(Path codeSource, Path userDirectory) {
        LinkedHashSet<Path> candidates = new LinkedHashSet<>();
        Path source = normalize(codeSource);
        Path userDir = normalize(userDirectory);
        Path appRoot = source == null ? userDir : Files.isDirectory(source)
            ? source : source.getParent();
        if (appRoot != null) {
            add(candidates, appRoot.resolve("ble-driver").resolve(DRIVER_FILE_NAME));
            // Compatibility with older app images that placed the exe beside the JAR.
            add(candidates, appRoot.resolve(DRIVER_FILE_NAME));
            add(candidates, appRoot.resolve("app").resolve("ble-driver")
                .resolve(DRIVER_FILE_NAME));
            add(candidates, appRoot.resolve("app").resolve(DRIVER_FILE_NAME));
        }
        if (userDir != null) {
            add(candidates, userDir.resolve("ble-driver").resolve(DRIVER_FILE_NAME));
            add(candidates, userDir.resolve(DRIVER_FILE_NAME));
        }

        // Development-only fallback: walk from the application/repository location,
        // never from a hard-coded drive or user directory.
        List<Path> fallbackBases = new java.util.ArrayList<>(2);
        if (appRoot != null) fallbackBases.add(appRoot);
        if (userDir != null && !userDir.equals(appRoot)) fallbackBases.add(userDir);
        for (Path base : fallbackBases) {
            Path cursor = base;
            for (int depth = 0; cursor != null && depth < 8; depth++, cursor = cursor.getParent()) {
                add(candidates, cursor.resolve("BLE_tcp_bridge").resolve("bin")
                    .resolve("Release").resolve(DRIVER_FILE_NAME));
            }
        }

        List<Path> attempted = List.copyOf(candidates);
        Optional<Path> selected = attempted.stream()
            .filter(path -> Files.isRegularFile(path))
            .map(BleDriverLocator::normalize)
            .filter(path -> path != null)
            .findFirst();
        return new Resolution(selected, attempted);
    }

    private static void add(LinkedHashSet<Path> candidates, Path candidate) {
        Path normalized = normalize(candidate);
        if (normalized != null) candidates.add(normalized);
    }

    private static Path normalize(Path path) {
        return path == null ? null : path.toAbsolutePath().normalize();
    }

    private static Path codeSourcePath() {
        try {
            URI location = BleDriverLocator.class.getProtectionDomain()
                .getCodeSource().getLocation().toURI();
            return Path.of(location);
        } catch (Exception ignored) {
            return null;
        }
    }

    public record Resolution(Optional<Path> selected, List<Path> attempted) {
        public Resolution {
            selected = selected == null ? Optional.empty() : selected;
            attempted = attempted == null ? List.of() : List.copyOf(attempted);
        }

        public String diagnosticMessage() {
            if (selected.isPresent()) return selected.get().toString();
            if (attempted.isEmpty()) return "未找到 BLE_tcp_driver.exe；没有可尝试的路径";
            return "未找到 BLE_tcp_driver.exe。已尝试路径：\n"
                + String.join("\n", attempted.stream().map(Path::toString).toList());
        }
    }
}
