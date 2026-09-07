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

/** Validates that the WCHISP executable, DLLs and config are one supported bundle. */
public final class WchIspRuntimeContract {
    public static final String METADATA_FILE = "wchisp-runtime.json";
    public static final String EXPECTED_VERSION = "3.6.1";
    public static final String EXPECTED_CONFIG_FINGERPRINT =
        "4dd3ac5911ff428b92200745a26c34c674235c04ac40a77f7cfb61d6fb6241e8";

    private static final ObjectMapper JSON = new ObjectMapper();

    private WchIspRuntimeContract() {}

    public static Validation validate(Path bundleDirectory) {
        List<String> failures = new ArrayList<>();
        if (bundleDirectory == null || !Files.isDirectory(bundleDirectory)) {
            return new Validation(false, List.of("runtime bundle directory is missing"));
        }
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
                String tool = text(root, "toolVersion", failures);
                String ispDll = text(root, "ispDllVersion", failures);
                String driverDll = text(root, "driverDllVersion", failures);
                String configContract = text(root, "configContractVersion", failures);
                String fingerprint = text(root, "configLayoutFingerprint", failures);
                String chipFamily = text(root, "supportedChipFamily", failures);
                String model = text(root, "supportedModel", failures);
                require(root, "source", failures);
                require(root, "provenance", failures);
                if (tool != null && !EXPECTED_VERSION.equals(tool)) {
                    failures.add("unsupported WCHISP tool version: " + tool);
                }
                if (ispDll != null && !EXPECTED_VERSION.equals(ispDll)) {
                    failures.add("unsupported WCH ISP DLL version: " + ispDll);
                }
                if (driverDll != null && !EXPECTED_VERSION.equals(driverDll)) {
                    failures.add("unsupported WCH driver DLL version: " + driverDll);
                }
                if (configContract != null && !EXPECTED_VERSION.equals(configContract)) {
                    failures.add("unsupported WCHISP config contract: " + configContract);
                }
                if (fingerprint != null && !EXPECTED_CONFIG_FINGERPRINT.equals(fingerprint)) {
                    failures.add("unsupported WCHISP config layout fingerprint: " + fingerprint);
                }
                if (chipFamily != null && !"CH57x/CH59x".equals(chipFamily)) {
                    failures.add("unsupported WCHISP chip family: " + chipFamily);
                }
                if (model != null && !"CH582".equals(model)) {
                    failures.add("unsupported WCHISP model: " + model);
                }
            } catch (Exception exception) {
                failures.add("invalid " + METADATA_FILE + ": " + exception.getMessage());
            }
        }
        if (Files.isRegularFile(config)) {
            try {
                String fingerprint = configFingerprint(Files.readAllBytes(config));
                if (!EXPECTED_CONFIG_FINGERPRINT.equals(fingerprint)) {
                    failures.add("CONFIG_CH57X59X.WCH layout fingerprint mismatch");
                }
                WchIspConfigLayout.inspect(Files.readAllBytes(config));
            } catch (IOException exception) {
                failures.add("invalid WCHISP config layout: " + exception.getMessage());
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

    public static String configFingerprint(byte[] bytes) throws IOException {
        return WchIspConfigLayout.fingerprint(bytes);
    }

    public record Validation(boolean supported, List<String> failures) {
        public Validation {
            failures = failures == null ? List.of() : List.copyOf(failures);
        }

        public String summary() {
            return supported ? "WCHISP 运行环境版本合同：支持"
                : "WCHISP 运行环境版本不受支持：" + String.join("; ", failures);
        }
    }
}
