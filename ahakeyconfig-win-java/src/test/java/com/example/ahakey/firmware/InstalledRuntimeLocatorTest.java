package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class InstalledRuntimeLocatorTest {
    @TempDir Path temporary;

    @Test
    void installedApplicationRootRuntimeIsSelected() throws Exception {
        Path applicationRoot = temporary.resolve("AhaKeyStudio");
        Path installed = applicationRoot.resolve("wchisp");
        createBundle(installed, true);

        RuntimeBundle result = locator(applicationRoot, temporary.resolve("empty"), Map.of()).resolve();

        assertEquals(installed.toAbsolutePath().normalize(), result.root());
        assertEquals("PRESENT", result.identity().expectedMetadata().get("METADATA_STATUS"));
    }

    @Test
    void explicitJvmPathIsUsedWhenInstalledRuntimeIsUnavailable() throws Exception {
        Path explicit = temporary.resolve("explicit-runtime");
        createBundle(explicit, false);
        String previous = System.getProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY);
        try {
            System.setProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY, explicit.toString());
            RuntimeBundle result = locator(temporary.resolve("no-install"),
                temporary.resolve("empty"), Map.of()).resolve();
            assertEquals(explicit.toAbsolutePath().normalize(), result.root());
            assertEquals(RuntimeIdentity.ValidationStatus.UNKNOWN, result.identity().validationStatus());
        } finally {
            restoreProperty(WchIspRuntimeProvider.EXPLICIT_PATH_PROPERTY, previous);
        }
    }

    @Test
    void environmentPathIsUsedBeforeDevelopmentFallback() throws Exception {
        Path environmentRuntime = temporary.resolve("environment-runtime");
        createBundle(environmentRuntime, false);
        RuntimeBundle result = locator(temporary.resolve("no-install"), temporary.resolve("empty"),
            Map.of(InstalledRuntimeLocator.ENVIRONMENT_PATH, environmentRuntime.toString())).resolve();
        assertEquals(environmentRuntime.toAbsolutePath().normalize(), result.root());
    }

    @Test
    void missingRuntimeReportsAllResolutionAttempts() {
        IOException failure = assertThrows(IOException.class,
            () -> locator(temporary.resolve("no-install"), temporary.resolve("empty"), Map.of()).resolve());
        assertTrue(failure.getMessage().contains("WCHISP runtime not found"));
        assertTrue(failure.getMessage().contains("installed="));
    }

    private InstalledRuntimeLocator locator(Path applicationRoot, Path workingDirectory,
                                            Map<String, String> environment) {
        WchIspRuntimeProvider provider = new WchIspRuntimeProvider(path ->
            new WchIspRuntimeProvider.BinaryVersion(Optional.empty(), Optional.empty()));
        return new InstalledRuntimeLocator(provider, applicationRoot, workingDirectory, environment);
    }

    private void createBundle(Path root, boolean metadata) throws Exception {
        Files.createDirectories(root);
        Files.write(root.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME), new byte[]{1, 2, 3});
        Files.write(root.resolve("CH343PT.DLL"), new byte[]{4});
        Files.write(root.resolve("WCH55xISPDLL.dll"), new byte[]{5});
        try (var input = getClass().getResourceAsStream("/wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH")) {
            Files.copy(input, root.resolve("CONFIG_CH57X59X.WCH"));
        }
        if (metadata) {
            try (var input = getClass().getResourceAsStream("/wchisp/wchisp-runtime.json")) {
                Files.copy(input, root.resolve(WchIspRuntimeContract.METADATA_FILE));
            }
        }
    }

    private static void restoreProperty(String name, String value) {
        if (value == null) System.clearProperty(name);
        else System.setProperty(name, value);
    }
}
