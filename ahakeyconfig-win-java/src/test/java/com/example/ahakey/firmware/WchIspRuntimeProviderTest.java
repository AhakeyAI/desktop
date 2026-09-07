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
    void explicitBundleCapturesHashesAndUnknownVersionResource() throws Exception {
        Path bundle = createBundle();
        RuntimeBundle result = new WchIspRuntimeProvider().resolve(bundle);
        assertEquals(bundle.toAbsolutePath().normalize(), result.root());
        assertEquals(64, result.identity().executableSha256().length());
        assertEquals(RuntimeIdentity.ValidationStatus.UNKNOWN, result.identity().validationStatus());
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
        var provider = new WchIspRuntimeProvider(path -> new WchIspRuntimeProvider.BinaryVersion(
            Optional.of("3.6.1"), Optional.of("3.6.1")));
        RuntimeBundle result = provider.resolve(bundle);
        assertEquals(RuntimeIdentity.ValidationStatus.KNOWN, result.identity().validationStatus());
        assertEquals("3.6.1", result.identity().expectedMetadata().get("toolVersion"));
    }

    @Test
    void metadataVersionMismatchIsNotKnown() throws Exception {
        Path bundle = createBundle();
        var provider = new WchIspRuntimeProvider(path -> new WchIspRuntimeProvider.BinaryVersion(
            Optional.of(path.getFileName().toString().endsWith(".exe") ? "3.9" : "3.6.1"),
            Optional.of("3.9")));
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
        try (var input = getClass().getResourceAsStream("/wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH")) {
            Files.copy(input, bundle.resolve("CONFIG_CH57X59X.WCH"));
        }
        try (var input = getClass().getResourceAsStream("/wchisp/wchisp-runtime.json")) {
            Files.copy(input, bundle.resolve(WchIspRuntimeContract.METADATA_FILE));
        }
        return bundle;
    }
}
