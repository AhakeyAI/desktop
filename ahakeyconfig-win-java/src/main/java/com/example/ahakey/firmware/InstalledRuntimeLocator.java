package com.example.ahakey.firmware;

import java.io.IOException;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Resolves the runtime shipped next to the installed Studio application.
 * Explicit developer paths and environment overrides remain available, but
 * no machine-specific directory is ever guessed or hard-coded.
 */
public final class InstalledRuntimeLocator implements RuntimeLocator {
    public static final String ENVIRONMENT_PATH = "AHAKEY_WCHISP_PATH";

    private final WchIspRuntimeProvider runtimeProvider;
    private final Path applicationRoot;
    private final Path workingDirectory;
    private final Map<String, String> environment;

    public InstalledRuntimeLocator() {
        this(new WchIspRuntimeProvider(), discoverApplicationRoot(),
            Path.of(System.getProperty("user.dir", ".")), System.getenv());
    }

    InstalledRuntimeLocator(WchIspRuntimeProvider runtimeProvider,
                            Path applicationRoot,
                            Path workingDirectory,
                            Map<String, String> environment) {
        this.runtimeProvider = runtimeProvider == null ? new WchIspRuntimeProvider() : runtimeProvider;
        this.applicationRoot = normalize(applicationRoot);
        this.workingDirectory = normalize(workingDirectory);
        this.environment = environment == null ? Map.of() : Map.copyOf(environment);
    }

    @Override
    public RuntimeBundle resolve() throws IOException {
        List<String> attempts = new ArrayList<>();

        Path installed = applicationRoot == null ? null : applicationRoot.resolve("wchisp");
        if (installed != null) {
            attempts.add("installed=" + installed);
            if (Files.isDirectory(installed)) {
                try {
                    // An installed bundle is a release candidate and remains
                    // subject to the existing metadata/config contract.
                    return runtimeProvider.resolveInstalled(installed);
                } catch (IOException ignored) {
                    // Try an explicit override so a developer can recover a
                    // broken installation without changing machine state.
                }
            }
        }

        String explicit = System.getProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY, "").trim();
        if (!explicit.isBlank()) {
            attempts.add("property=" + explicit);
            try {
                return runtimeProvider.resolve(Path.of(explicit));
            } catch (IOException failure) {
                throw new IOException("显式 WCHISP runtime 无效: " + explicit, failure);
            }
        }

        String environmentPath = environment.getOrDefault(ENVIRONMENT_PATH, "").trim();
        if (!environmentPath.isBlank()) {
            attempts.add("environment=" + environmentPath);
            try {
                return runtimeProvider.resolve(Path.of(environmentPath));
            } catch (IOException failure) {
                throw new IOException("环境变量 " + ENVIRONMENT_PATH
                    + " 指向的 WCHISP runtime 无效: " + environmentPath, failure);
            }
        }

        IOException last = null;
        for (Path candidate : WchIspRuntimeProvider.developmentCandidates(workingDirectory)) {
            attempts.add("development=" + candidate);
            try {
                return runtimeProvider.resolve(candidate);
            } catch (IOException failure) {
                last = failure;
            }
        }
        throw new IOException("WCHISP runtime not found; attempted: " + attempts, last);
    }

    static Path discoverApplicationRoot() {
        String jpackagePath = System.getProperty("jpackage.app-path", "").trim();
        if (!jpackagePath.isBlank()) {
            Path launcher = Path.of(jpackagePath).toAbsolutePath().normalize();
            Path parent = Files.isDirectory(launcher) ? launcher : launcher.getParent();
            if (parent != null && parent.getFileName() != null
                && "app".equalsIgnoreCase(parent.getFileName().toString())) {
                parent = parent.getParent();
            }
            if (parent != null) return parent;
        }
        try {
            URI location = InstalledRuntimeLocator.class.getProtectionDomain()
                .getCodeSource().getLocation().toURI();
            Path codeLocation = Path.of(location).toAbsolutePath().normalize();
            Path base = Files.isDirectory(codeLocation) ? codeLocation : codeLocation.getParent();
            if (base != null && base.getFileName() != null
                && "app".equalsIgnoreCase(base.getFileName().toString())) {
                base = base.getParent();
            }
            if (base != null && Files.isDirectory(base.resolve("wchisp"))) return base;
        } catch (Exception ignored) {
            // Fall through to the process working directory.
        }
        Path current = Path.of(System.getProperty("user.dir", "."))
            .toAbsolutePath().normalize();
        return current.getFileName() != null
            && "app".equalsIgnoreCase(current.getFileName().toString())
            && current.getParent() != null ? current.getParent() : current;
    }

    private static Path normalize(Path value) {
        return value == null ? null : value.toAbsolutePath().normalize();
    }
}
