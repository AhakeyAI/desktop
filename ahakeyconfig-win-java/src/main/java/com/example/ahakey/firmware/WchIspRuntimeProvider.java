package com.example.ahakey.firmware;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

/**
 * Resolves one WCHISP runtime and records binary identity.  Production
 * jpackage resolution is rooted at {@code <app>/tools/wchisp}; an explicit
 * system property is supported for development and tests only.
 */
public final class WchIspRuntimeProvider implements RuntimeProvider {
    public static final String EXECUTABLE_NAME = "WCHISPTool_CH57x-59x.exe";
    public static final String EXPLICIT_PATH_PROPERTY = "ahakey.wchisp.path";
    private static final ObjectMapper JSON = new ObjectMapper();
    private final BinaryVersionReader versionReader;

    public WchIspRuntimeProvider() {
        this(WchIspRuntimeProvider::readWindowsVersion);
    }

    WchIspRuntimeProvider(BinaryVersionReader versionReader) {
        this.versionReader = versionReader == null
            ? path -> new BinaryVersion(Optional.empty(), Optional.empty())
            : versionReader;
    }

    public RuntimeBundle resolve() throws IOException {
        String override = System.getProperty(EXPLICIT_PATH_PROPERTY, "").trim();
        boolean packaged = !System.getProperty("jpackage.app-path", "").isBlank();
        List<Path> candidates = new ArrayList<>();
        if (!override.isBlank()) {
            candidates.add(Path.of(override));
        }
        String appPath = System.getProperty("jpackage.app-path", "").trim();
        if (!appPath.isBlank()) {
            Path launcher = Path.of(appPath).toAbsolutePath().normalize();
            Path appRoot = launcher.getParent();
            if (appRoot != null) {
                candidates.add(appRoot.resolve("tools").resolve("wchisp"));
                candidates.add(appRoot.resolve("app").resolve("tools").resolve("wchisp"));
            }
        }
        if (!packaged) {
            candidates.addAll(developmentCandidates(Path.of(System.getProperty("user.dir", "."))));
        }
        IOException last = null;
        for (Path candidate : candidates) {
            try {
                return load(candidate);
            } catch (IOException failure) {
                last = failure;
            }
        }
        throw new IOException("WCHISP runtime not found; attempted: " + candidates, last);
    }

    public RuntimeBundle resolve(Path explicit) throws IOException {
        return load(explicit);
    }

    private RuntimeBundle load(Path candidate) throws IOException {
        if (candidate == null) {
            throw new IOException("runtime path is null");
        }
        Path normalized = candidate.toAbsolutePath().normalize();
        Path root = Files.isDirectory(normalized) ? normalized : normalized.getParent();
        if (root == null) throw new IOException("runtime root is missing: " + candidate);
        Path executable = Files.isDirectory(normalized)
            ? root.resolve(EXECUTABLE_NAME) : normalized;
        Path ch343 = root.resolve("CH343PT.DLL");
        Path ispDll = root.resolve("WCH55xISPDLL.dll");
        Path config = root.resolve("CONFIG_CH57X59X.WCH");
        Path metadata = root.resolve(WchIspRuntimeContract.METADATA_FILE);
        if (!Files.isRegularFile(executable) || !Files.isRegularFile(ch343)
            || !Files.isRegularFile(ispDll) || !Files.isRegularFile(config)) {
            throw new IOException("runtime bundle is incomplete: " + root);
        }
        WchIspRuntimeContract.Validation validation =
            WchIspRuntimeContract.validate(root);
        if (!validation.supported()) {
            throw new IOException(validation.summary());
        }
        return new RuntimeBundle(root, executable, ch343, ispDll, config,
            Files.isRegularFile(metadata) ? metadata : null,
            identity(executable, ch343, ispDll, config, metadata, versionReader));
    }

    static List<Path> developmentCandidates(Path workingDirectory) {
        List<Path> candidates = new ArrayList<>();
        Path current = (workingDirectory == null ? Path.of(".") : workingDirectory)
            .toAbsolutePath().normalize();
        for (Path cursor = current; cursor != null; cursor = cursor.getParent()) {
            candidates.add(cursor.resolve("tools").resolve("wchisp"));
            candidates.add(cursor.resolve("wchisp"));
            candidates.add(cursor.resolve("WCHISPTool_CH57x-59x"));
        }
        return candidates;
    }

    static RuntimeIdentity identity(Path executable, Path ch343, Path ispDll,
                                    Path config, Path metadata,
                                    BinaryVersionReader versionReader) throws IOException {
        String exeHash = sha256(executable);
        String ch343Hash = sha256(ch343);
        String ispHash = sha256(ispDll);
        String configHash = sha256(config);
        RuntimeIdentity.ValidationStatus status = RuntimeIdentity.ValidationStatus.UNKNOWN;
        Map<String, String> expectedMetadata = new LinkedHashMap<>();
        BinaryVersion exe = versionReader.read(executable);
        BinaryVersion ch343Info = versionReader.read(ch343);
        BinaryVersion ispInfo = versionReader.read(ispDll);
        Optional<String> exeVersion = exe.fileVersion();
        Optional<String> productVersion = exe.productVersion();
        Optional<String> ch343Version = ch343Info.fileVersion();
        Optional<String> ispVersion = ispInfo.fileVersion();
        if (metadata != null && Files.isRegularFile(metadata)) {
            try {
                JsonNode root = JSON.readTree(Files.readString(metadata, StandardCharsets.UTF_8));
                String expectedTool = text(root, "toolVersion");
                String expectedIsp = text(root, "ispDllVersion");
                String expectedDriver = text(root, "driverDllVersion");
                putIfPresent(expectedMetadata, "toolVersion", expectedTool);
                putIfPresent(expectedMetadata, "ispDllVersion", expectedIsp);
                putIfPresent(expectedMetadata, "driverDllVersion", expectedDriver);
                // Version resources are optional on synthetic/test bundles.  When
                // unavailable, hashes remain authoritative evidence for review.
                boolean hashMismatch = mismatch(root, "exeSha256", exeHash)
                    || mismatch(root, "ch343Sha256", ch343Hash)
                    || mismatch(root, "ispDllSha256", ispHash)
                    || mismatch(root, "configSha256", configHash);
                boolean versionMismatch = mismatchVersion(expectedTool, exeVersion)
                    || mismatchVersion(expectedDriver, ch343Version)
                    || mismatchVersion(expectedIsp, ispVersion);
                if (hashMismatch || versionMismatch) status = RuntimeIdentity.ValidationStatus.MISMATCH;
                else if (expectedTool != null && expectedDriver != null && expectedIsp != null
                    && exeVersion.isPresent() && ch343Version.isPresent() && ispVersion.isPresent()) {
                    status = RuntimeIdentity.ValidationStatus.KNOWN;
                }
            } catch (Exception ignored) {
                status = RuntimeIdentity.ValidationStatus.MISMATCH;
            }
        }
        return new RuntimeIdentity(exeVersion, productVersion, ch343Version,
            ispVersion, exeHash, ch343Hash, ispHash, configHash, status, expectedMetadata);
    }

    private static void putIfPresent(Map<String, String> metadata, String name, String value) {
        if (value != null && !value.isBlank()) metadata.put(name, value);
    }

    private static boolean mismatchVersion(String expected, Optional<String> actual) {
        return expected != null && actual.isPresent() && !expected.equalsIgnoreCase(actual.get());
    }

    private static String text(JsonNode root, String name) {
        return root != null && root.hasNonNull(name) && root.get(name).isTextual()
            ? root.get(name).asText() : null;
    }

    private static boolean mismatch(JsonNode root, String name, String actual) {
        String expected = text(root, name);
        return expected != null && !expected.equalsIgnoreCase(actual);
    }

    static String sha256(Path file) throws IOException {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(Files.readAllBytes(file));
            StringBuilder result = new StringBuilder(digest.length * 2);
            for (byte value : digest) result.append(String.format(Locale.ROOT,
                "%02x", value & 0xFF));
            return result.toString();
        } catch (java.security.NoSuchAlgorithmException impossible) {
            throw new IOException("JVM lacks SHA-256", impossible);
        }
    }

    @FunctionalInterface
    interface BinaryVersionReader {
        BinaryVersion read(Path path);
    }

    record BinaryVersion(Optional<String> fileVersion, Optional<String> productVersion) {
        BinaryVersion {
            fileVersion = fileVersion == null ? Optional.empty() : fileVersion;
            productVersion = productVersion == null ? Optional.empty() : productVersion;
        }
    }

    private static BinaryVersion readWindowsVersion(Path path) {
        if (path == null || !System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("win")) {
            return new BinaryVersion(Optional.empty(), Optional.empty());
        }
        String escaped = path.toAbsolutePath().normalize().toString().replace("'", "''");
        try {
            Process process = new ProcessBuilder("powershell.exe", "-NoProfile", "-NonInteractive",
                "-Command", "$v=(Get-Item -LiteralPath '" + escaped
                    + "').VersionInfo; if($v){$v.FileVersion+'|'+$v.ProductVersion}")
                .redirectErrorStream(true).start();
            if (!process.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)) {
                process.destroyForcibly();
                return new BinaryVersion(Optional.empty(), Optional.empty());
            }
            String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8).trim();
            String[] values = output.split("\\|", -1);
            return new BinaryVersion(values.length > 0 && !values[0].isBlank()
                ? Optional.of(values[0].trim()) : Optional.empty(),
                values.length > 1 && !values[1].isBlank()
                    ? Optional.of(values[1].trim()) : Optional.empty());
        } catch (Exception ignored) {
            return new BinaryVersion(Optional.empty(), Optional.empty());
        }
    }
}
