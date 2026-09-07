package com.example.ahakey.firmware;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Comparator;
import java.util.UUID;
import java.util.stream.Stream;

/** Isolated, per-operation WCHISP workspace and effective CONFIG builder. */
public final class WchIspWorkspace implements AutoCloseable {
    private static final String SANITIZED_CONFIG = "/wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH";
    private final Path root;
    private final Path toolDirectory;
    private final Path logsDirectory;
    private boolean closed;

    private WchIspWorkspace(Path root) throws IOException {
        this.root = root.toAbsolutePath().normalize();
        this.toolDirectory = this.root.resolve("tool");
        this.logsDirectory = this.root.resolve("logs");
        Files.createDirectories(toolDirectory);
        Files.createDirectories(logsDirectory);
    }

    public static WchIspWorkspace create(UUID operationId) throws IOException {
        return create(Path.of(System.getProperty("java.io.tmpdir")), operationId);
    }

    public static WchIspWorkspace create(Path parent, UUID operationId) throws IOException {
        if (operationId == null) throw new IOException("operation id is missing");
        Path root = parent.toAbsolutePath().normalize()
            .resolve("ahakey-firmware-" + operationId);
        if (Files.exists(root)) throw new IOException("workspace already exists: " + root);
        return new WchIspWorkspace(root);
    }

    public Path root() { return root; }
    public Path toolDirectory() { return toolDirectory; }
    public Path logsDirectory() { return logsDirectory; }

    /** Legacy alias; production callers should choose detect or flash explicitly. */
    public PreparedWorkspace prepare(RuntimeBundle runtime, Path firmwareHex) throws IOException {
        return prepareForFlash(runtime, firmwareHex);
    }

    public PreparedWorkspace prepareForDetect(RuntimeBundle runtime) throws IOException {
        ensureOpen();
        Path placeholder = toolDirectory.resolve("unused.hex");
        Files.writeString(placeholder, "", StandardCharsets.US_ASCII);
        return prepareInternal(runtime, placeholder, "detect");
    }

    public PreparedWorkspace prepareForFlash(RuntimeBundle runtime, Path firmwareHex)
        throws IOException {
        return prepareInternal(runtime, firmwareHex, "flash");
    }

    private PreparedWorkspace prepareInternal(RuntimeBundle runtime, Path firmwareHex,
                                              String profile) throws IOException {
        ensureOpen();
        if (runtime == null || firmwareHex == null) throw new IOException("workspace inputs are missing");
        copyRuntime(runtime.root(), toolDirectory);
        Path effectiveConfig = toolDirectory.resolve("CONFIG_CH57X59X-" + profile + ".WCH");
        copySanitizedConfig(effectiveConfig);
        byte[] bytes = Files.readAllBytes(effectiveConfig);
        String firmwarePath = firmwareHex.toAbsolutePath().normalize().toString();
        Files.write(effectiveConfig, WchIspConfigLayout.patchSlot(bytes,
            WchIspConfigLayout.CH582_SLOT_INDEX, firmwarePath));
        Path configIni = root.resolve(profile + "-config.ini");
        Files.writeString(configIni, WchIspConfig.forCh582(firmwareHex),
            StandardCharsets.UTF_8);
        Path executable = toolDirectory.resolve(runtime.executable().getFileName());
        if (!Files.isRegularFile(executable)) throw new IOException("runtime executable copy failed");
        return new PreparedWorkspace(executable, configIni, effectiveConfig, firmwareHex.toAbsolutePath().normalize());
    }

    private void copyRuntime(Path source, Path destination) throws IOException {
        try (Stream<Path> paths = Files.walk(source)) {
            for (Path sourcePath : paths.toList()) {
                Path name = sourcePath.getFileName();
                if (name == null) continue;
                if (Files.isRegularFile(sourcePath) && isConfigCopy(name.toString())) {
                    continue;
                }
                Path target = destination.resolve(source.relativize(sourcePath));
                if (Files.isDirectory(sourcePath)) {
                    Files.createDirectories(target);
                } else {
                    Files.createDirectories(target.getParent());
                    Files.copy(sourcePath, target, StandardCopyOption.REPLACE_EXISTING);
                }
            }
        }
    }

    private static boolean isConfigCopy(String name) {
        String upper = name.toUpperCase(java.util.Locale.ROOT);
        return upper.equals("CONFIG_CH57X59X.WCH")
            || upper.equals("CONFIG_CH57X59X.WCH.EXCLUDED")
            || upper.startsWith("CONFIG_CH57X59X.WCH.")
            || upper.startsWith("CONFIG_CH57X59X-") && upper.endsWith(".WCH");
    }

    private static void copySanitizedConfig(Path destination) throws IOException {
        try (InputStream input = WchIspWorkspace.class.getResourceAsStream(SANITIZED_CONFIG)) {
            if (input == null) throw new IOException("sanitized WCH config resource is missing");
            Files.copy(input, destination, StandardCopyOption.REPLACE_EXISTING);
        }
        byte[] bytes = Files.readAllBytes(destination);
        if (!WchIspConfigLayout.FINGERPRINT.equals(WchIspConfigLayout.fingerprint(bytes))) {
            throw new IOException("sanitized WCH config fingerprint mismatch");
        }
    }

    private void ensureOpen() throws IOException {
        if (closed) throw new IOException("workspace is already closed");
    }

    @Override
    public void close() {
        if (closed) return;
        closed = true;
        deleteQuietly(root);
    }

    private static void deleteQuietly(Path path) {
        if (path == null || !Files.exists(path)) return;
        try (Stream<Path> paths = Files.walk(path)) {
            paths.sorted(Comparator.reverseOrder()).forEach(item -> {
                try { Files.deleteIfExists(item); } catch (IOException ignored) { }
            });
        } catch (IOException ignored) { }
    }

    public record PreparedWorkspace(Path executable, Path configIni, Path effectiveConfig,
                                    Path firmwareInput) {
        public PreparedWorkspace(Path executable, Path configIni, Path effectiveConfig) {
            this(executable, configIni, effectiveConfig, null);
        }
    }
}
