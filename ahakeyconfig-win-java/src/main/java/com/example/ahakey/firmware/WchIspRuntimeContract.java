package com.example.ahakey.firmware;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;

/** Validates the files and device scope required to run a packaged WCHISP bundle. */
public final class WchIspRuntimeContract {
    public static final String METADATA_FILE = "wchisp-runtime.json";

    private static final ObjectMapper JSON = new ObjectMapper();

    private WchIspRuntimeContract() {}

    public static Validation validate(Path bundleDirectory) {
        List<String> failures = new ArrayList<>();
        if (bundleDirectory == null || !Files.isDirectory(bundleDirectory)) {
            return new Validation(false, List.of("runtime bundle directory is missing"));
        }
        requireFile(bundleDirectory, WchIspRuntimeProvider.EXECUTABLE_NAME, failures);
        requireFile(bundleDirectory, "CH343PT.DLL", failures);
        requireFile(bundleDirectory, "WCH55xISPDLL.dll", failures);
        Path config = bundleDirectory.resolve("CONFIG_CH57X59X.WCH");
        if (!Files.isRegularFile(config)) failures.add("CONFIG_CH57X59X.WCH is missing");

        Path metadata = bundleDirectory.resolve(METADATA_FILE);
        if (!Files.isRegularFile(metadata)) {
            failures.add(METADATA_FILE + " is missing; mixed/unknown runtime is unsupported");
        } else {
            try {
                JsonNode root = JSON.readTree(Files.readString(metadata, StandardCharsets.UTF_8));
                require(root, "bundleId", failures);
                text(root, "toolVersion", failures);
                text(root, "ispDllVersion", failures);
                text(root, "driverDllVersion", failures);
                text(root, "configContractVersion", failures);
                text(root, "configLayoutFingerprint", failures);
                String chipFamily = text(root, "supportedChipFamily", failures);
                String model = text(root, "supportedModel", failures);
                require(root, "source", failures);
                require(root, "provenance", failures);
                if (chipFamily != null && !"CH57x/CH59x".equals(chipFamily)) {
                    failures.add("unsupported WCHISP chip family: " + chipFamily);
                }
                if (model != null && !"CH582".equals(model)) {
                    failures.add("unsupported WCHISP model: " + model);
                }
                verifyHash(root, "exeSha256",
                    bundleDirectory.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME), failures);
                verifyHash(root, "ch343Sha256",
                    bundleDirectory.resolve("CH343PT.DLL"), failures);
                verifyHash(root, "ispDllSha256",
                    bundleDirectory.resolve("WCH55xISPDLL.dll"), failures);
                verifyHash(root, "configSha256", config, failures);
            } catch (Exception exception) {
                failures.add("invalid " + METADATA_FILE + ": " + exception.getMessage());
            }
        }
        if (Files.isRegularFile(config)) {
            try {
                WchIspConfigLayout.inspect(Files.readAllBytes(config));
            } catch (IOException exception) {
                failures.add("invalid WCHISP config format: " + exception.getMessage());
            }
        }
        return new Validation(failures.isEmpty(), List.copyOf(failures));
    }

    private static void requireFile(Path directory, String name, List<String> failures) {
        if (!Files.isRegularFile(directory.resolve(name))) failures.add(name + " is missing");
    }

    private static void require(JsonNode root, String name, List<String> failures) {
        if (root == null || !root.hasNonNull(name) || !root.get(name).isTextual()
            || root.get(name).asText().isBlank()) {
            failures.add(METADATA_FILE + " field " + name + " is missing");
        }
    }

    private static String text(JsonNode root, String name, List<String> failures) {
        require(root, name, failures);
        return root != null && root.hasNonNull(name) && root.get(name).isTextual()
            ? root.get(name).asText() : null;
    }

    private static void verifyHash(JsonNode root, String name, Path file,
                                   List<String> failures) throws IOException {
        if (root == null || !root.hasNonNull(name)) return;
        if (!root.get(name).isTextual() || root.get(name).asText().isBlank()) {
            failures.add(METADATA_FILE + " field " + name + " is invalid");
            return;
        }
        String expected = root.get(name).asText().trim();
        if (!expected.equalsIgnoreCase(WchIspRuntimeProvider.sha256(file))) {
            failures.add("WCHISP runtime file hash mismatch: " + name);
        }
    }

    public static String configFingerprint(byte[] bytes) throws IOException {
        return WchIspConfigLayout.fingerprint(bytes);
    }

    public record Validation(boolean supported, List<String> failures) {
        public Validation {
            failures = failures == null ? List.of() : List.copyOf(failures);
        }

        public String summary() {
            return supported ? "WCHISP 运行环境兼容性检查：通过"
                : "WCHISP 运行环境兼容性检查失败：" + String.join("; ", failures);
        }
    }
}
