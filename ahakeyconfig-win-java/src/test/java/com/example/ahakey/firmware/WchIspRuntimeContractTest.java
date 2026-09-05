package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WchIspRuntimeContractTest {
    @TempDir
    Path temporary;

    @Test
    void supportedBundleRequiresAllMatchingRuntimeArtifacts() throws Exception {
        createBundle("/wchisp/wchisp-runtime.json");

        var validation = WchIspRuntimeContract.validate(temporary);

        assertTrue(validation.supported(), validation.summary());
    }

    @Test
    void mixedRuntimeMetadataFailsClosed() throws Exception {
        createBundle("/wchisp/wchisp-runtime.json");
        Path metadata = temporary.resolve(WchIspRuntimeContract.METADATA_FILE);
        String mixed = Files.readString(metadata).replace("\"ispDllVersion\": \"3.6.1\"",
            "\"ispDllVersion\": \"3.8.0\"");
        Files.writeString(metadata, mixed);

        var validation = WchIspRuntimeContract.validate(temporary);

        assertFalse(validation.supported());
        assertTrue(validation.summary().toLowerCase().contains("dll version"));
    }

    @Test
    void missingMetadataIsNotTreatedAsSupportedRuntime() throws Exception {
        createBundle(null);

        var validation = WchIspRuntimeContract.validate(temporary);

        assertFalse(validation.supported());
        assertTrue(validation.summary().contains("wchisp-runtime.json"));
    }

    private void createBundle(String metadataResource) throws Exception {
        Files.write(temporary.resolve("WCHISPTool_CH57x-59x.exe"), new byte[]{1});
        Files.write(temporary.resolve("CH343PT.DLL"), new byte[]{1});
        Files.write(temporary.resolve("WCH55xISPDLL.dll"), new byte[]{1});
        try (var config = getClass().getResourceAsStream(
            "/wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH")) {
            Files.copy(config, temporary.resolve("CONFIG_CH57X59X.WCH"));
        }
        if (metadataResource != null) {
            try (var metadata = getClass().getResourceAsStream(metadataResource)) {
                Files.copy(metadata, temporary.resolve(WchIspRuntimeContract.METADATA_FILE));
            }
        }
    }
}
