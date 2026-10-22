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
    void missingChipDatabaseFailsWithItsRelativePath() throws Exception {
        createBundle("/wchisp/wchisp-runtime.json");
        Files.delete(temporary.resolve("ChipType").resolve("chiplist_CH57x_CH59x.wcfg"));

        var validation = WchIspRuntimeContract.validate(temporary);

        assertFalse(validation.supported());
        assertTrue(validation.summary().contains(
            WchIspRuntimeContract.CHIP_DATABASE_RELATIVE_PATH));
    }

    @Test
    void mixedRuntimeVersionsAreRecordedButDoNotBlockCompatibleBundle() throws Exception {
        createBundle("/wchisp/wchisp-runtime.json");
        Path metadata = temporary.resolve(WchIspRuntimeContract.METADATA_FILE);
        String mixed = Files.readString(metadata).replace("\"ispDllVersion\": \"3.8.0.0\"",
            "\"ispDllVersion\": \"3.8.0.1\"");
        Files.writeString(metadata, mixed);

        var validation = WchIspRuntimeContract.validate(temporary);

        assertTrue(validation.supported(), validation.summary());
    }

    @Test
    void missingMetadataIsNotTreatedAsSupportedRuntime() throws Exception {
        createBundle(null);

        var validation = WchIspRuntimeContract.validate(temporary);

        assertFalse(validation.supported());
        assertTrue(validation.summary().contains("wchisp-runtime.json"));
    }

    @Test
    void packagedFileHashDetectsReplacementWithoutPinningAVersion() throws Exception {
        createBundle("/wchisp/wchisp-runtime.json");
        Path executable = temporary.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME);
        Path metadata = temporary.resolve(WchIspRuntimeContract.METADATA_FILE);
        assertTrue(WchIspRuntimeContract.validate(temporary).supported());

        Files.write(executable, new byte[]{9, 9});
        var validation = WchIspRuntimeContract.validate(temporary);
        assertFalse(validation.supported());
        assertTrue(validation.summary().contains("hash mismatch"));
    }

    private void createBundle(String metadataResource) throws Exception {
        Files.write(temporary.resolve("WCHISPTool_CH57x-59x.exe"), new byte[]{1});
        Files.write(temporary.resolve("CH343PT.DLL"), new byte[]{1});
        Files.write(temporary.resolve("WCH55xISPDLL.dll"), new byte[]{1});
        Path chipType = Files.createDirectories(temporary.resolve("ChipType"));
        Files.write(chipType.resolve("chiplist_CH57x_CH59x.wcfg"), new byte[]{1});
        try (var config = getClass().getResourceAsStream(
            "/wchisp/CONFIG_CH57X59X-sanitized.WCH")) {
            Files.copy(config, temporary.resolve("CONFIG_CH57X59X.WCH"));
        }
        if (metadataResource != null) {
            try (var metadata = getClass().getResourceAsStream(metadataResource)) {
                Files.copy(metadata, temporary.resolve(WchIspRuntimeContract.METADATA_FILE));
            }
            Path metadataPath = temporary.resolve(WchIspRuntimeContract.METADATA_FILE);
            String json = Files.readString(metadataPath);
            int end = json.lastIndexOf('}');
            Files.writeString(metadataPath, json.substring(0, end)
                + ",\n  \"exeSha256\": \"" + WchIspRuntimeProvider.sha256(
                    temporary.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME))
                + "\",\n  \"ch343Sha256\": \"" + WchIspRuntimeProvider.sha256(
                    temporary.resolve("CH343PT.DLL"))
                + "\",\n  \"ispDllSha256\": \"" + WchIspRuntimeProvider.sha256(
                    temporary.resolve("WCH55xISPDLL.dll"))
                + "\",\n  \"configSha256\": \"" + WchIspRuntimeProvider.sha256(
                    temporary.resolve("CONFIG_CH57X59X.WCH"))
                + "\"\n}\n");
        }
    }
}
