package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

class WchIspRuntimeProviderTest {
    @TempDir Path temporary;

    @Test
    void explicitBundleWithoutMetadataIsAcceptedButUnknown() throws Exception {
        Path bundle = createBundleWithoutMetadata();
        String previous = System.getProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY);
        try {
            System.setProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY, bundle.toString());
            RuntimeBundle result = new WchIspRuntimeProvider().resolve();
            assertEquals(bundle.toAbsolutePath().normalize(), result.root());
            assertEquals(64, result.identity().executableSha256().length());
            assertEquals(RuntimeIdentity.ValidationStatus.UNKNOWN, result.identity().validationStatus());
            assertEquals("MISSING", result.identity().expectedMetadata().get("METADATA_STATUS"));
            assertEquals("UNVERIFIED", result.identity().expectedMetadata().get("HARDWARE_VERIFICATION"));
        } finally {
            restoreProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY, previous);
        }
    }

    @Test
    void incompleteBundleFailsClosed() throws Exception {
        Path bundle = temporary.resolve("incomplete");
        Files.createDirectories(bundle);
        assertThrows(Exception.class, () -> new WchIspRuntimeProvider().resolve(bundle));
    }

    @Test
    void matchingMetadataAndObservedVersionsAreKnown() throws Exception {
        Path bundle = createBundle();
        var provider = new WchIspRuntimeProvider(path -> {
            String name = path.getFileName().toString();
            String version = name.endsWith(".exe") ? "3.9.0.0"
                : name.equals("CH343PT.DLL") ? "1.40" : "3.8.0.0";
            return new WchIspRuntimeProvider.BinaryVersion(Optional.of(version),
                Optional.of(version));
        });
        RuntimeBundle result = provider.resolve(bundle);
        assertEquals(RuntimeIdentity.ValidationStatus.KNOWN, result.identity().validationStatus());
        assertEquals("3.9.0.0", result.identity().expectedMetadata().get("toolVersion"));
    }

    @Test
    void metadataVersionMismatchIsNotKnown() throws Exception {
        Path bundle = createBundle();
        var provider = new WchIspRuntimeProvider(path -> new WchIspRuntimeProvider.BinaryVersion(
            Optional.of(path.getFileName().toString().endsWith(".exe") ? "3.9.0.0" : "3.8.0.1"),
            Optional.of("3.8.0.1")));
        assertEquals(RuntimeIdentity.ValidationStatus.MISMATCH,
            provider.resolve(bundle).identity().validationStatus());
    }

    @Test
    void missingObservedVersionsRemainUnknown() throws Exception {
        Path bundle = createBundle();
        RuntimeBundle result = new WchIspRuntimeProvider(path ->
            new WchIspRuntimeProvider.BinaryVersion(Optional.empty(), Optional.empty())).resolve(bundle);
        assertEquals(RuntimeIdentity.ValidationStatus.UNKNOWN, result.identity().validationStatus());
    }

    @Test
    void packagedBundleWithoutMetadataIsRejected() throws Exception {
        Path appRoot = temporary.resolve("packaged-app");
        Path bundle = appRoot.resolve("tools").resolve("wchisp");
        copyRequiredFiles(createBundleWithoutMetadata(), bundle);
        Path launcher = appRoot.resolve("AhaKeyStudio.exe");
        Files.write(launcher, new byte[]{1});
        String previousAppPath = System.getProperty("jpackage.app-path");
        String previousOverride = System.getProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY);
        try {
            System.setProperty("jpackage.app-path", launcher.toString());
            System.clearProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY);
            assertThrows(Exception.class, () -> new WchIspRuntimeProvider().resolve());
        } finally {
            restoreProperty("jpackage.app-path", previousAppPath);
            restoreProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY, previousOverride);
        }
    }

    @Test
    void explicitBundleWithMetadataMismatchIsAcceptedAndMarkedMismatch() throws Exception {
        Path bundle = createBundle();
        var provider = new WchIspRuntimeProvider(path ->
            new WchIspRuntimeProvider.BinaryVersion(
                Optional.of(path.getFileName().toString().endsWith(".exe") ? "3.9.0.0" : "3.8.0.0"),
                Optional.of("3.9.0.0")));
        RuntimeBundle result = provider.resolve(bundle);
        assertEquals(RuntimeIdentity.ValidationStatus.MISMATCH, result.identity().validationStatus());
        assertEquals("PRESENT", result.identity().expectedMetadata().get("METADATA_STATUS"));
    }

    @Test
    void explicitBundleMissingRequiredBinaryIsRejected() throws Exception {
        Path bundle = createBundleWithoutMetadata();
        Files.delete(bundle.resolve("WCH55xISPDLL.dll"));
        assertThrows(Exception.class, () -> new WchIspRuntimeProvider().resolve(bundle));
    }

    @Test
    void developmentCandidatesContainOnlyWchispPaths() {
        assertTrue(WchIspRuntimeProvider.developmentCandidates(temporary)
            .stream().noneMatch(path -> path.toString().toUpperCase().contains("BLE_TCP_BRIDGE")));
    }

    private Path createBundle() throws Exception {
        Path bundle = temporary.resolve("runtime");
        Files.createDirectories(bundle);
        Files.write(bundle.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME), new byte[]{1, 2, 3});
        Files.write(bundle.resolve("CH343PT.DLL"), new byte[]{4});
        Files.write(bundle.resolve("WCH55xISPDLL.dll"), new byte[]{5});
        Path chipType = Files.createDirectories(bundle.resolve("ChipType"));
        Files.write(chipType.resolve("chiplist_CH57x_CH59x.wcfg"), new byte[]{6});
        try (var input = getClass().getResourceAsStream("/wchisp/CONFIG_CH57X59X-sanitized.WCH")) {
            Files.copy(input, bundle.resolve("CONFIG_CH57X59X.WCH"));
        }
        try (var input = getClass().getResourceAsStream("/wchisp/wchisp-runtime.json")) {
            Files.copy(input, bundle.resolve(WchIspRuntimeContract.METADATA_FILE));
        }
        return bundle;
    }

    private Path createBundleWithoutMetadata() throws Exception {
        Path bundle = temporary.resolve("runtime-no-metadata-" + System.nanoTime());
        Files.createDirectories(bundle);
        Files.write(bundle.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME), new byte[]{1, 2, 3});
        Files.write(bundle.resolve("CH343PT.DLL"), new byte[]{4});
        Files.write(bundle.resolve("WCH55xISPDLL.dll"), new byte[]{5});
        Path chipType = Files.createDirectories(bundle.resolve("ChipType"));
        Files.write(chipType.resolve("chiplist_CH57x_CH59x.wcfg"), new byte[]{6});
        try (var input = getClass().getResourceAsStream("/wchisp/CONFIG_CH57X59X-sanitized.WCH")) {
            Files.copy(input, bundle.resolve("CONFIG_CH57X59X.WCH"));
        }
        return bundle;
    }

    private static void copyRequiredFiles(Path source, Path target) throws Exception {
        Files.createDirectories(target);
        for (String name : new String[]{WchIspRuntimeProvider.EXECUTABLE_NAME,
            "CH343PT.DLL", "WCH55xISPDLL.dll", "CONFIG_CH57X59X.WCH"}) {
            Files.copy(source.resolve(name), target.resolve(name));
        }
        Path chipType = Files.createDirectories(target.resolve("ChipType"));
        Files.copy(source.resolve("ChipType").resolve("chiplist_CH57x_CH59x.wcfg"),
            chipType.resolve("chiplist_CH57x_CH59x.wcfg"));
    }

    private static void restoreProperty(String name, String value) {
        if (value == null) System.clearProperty(name);
        else System.setProperty(name, value);
    }
}
