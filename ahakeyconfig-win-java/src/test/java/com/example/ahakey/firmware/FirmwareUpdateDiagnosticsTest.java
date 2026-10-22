package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertTrue;

class FirmwareUpdateDiagnosticsTest {
    @TempDir Path temporary;

    @Test
    void sha256AndArtifactSourceAreDiagnosticOnly() throws Exception {
        Path first = temporary.resolve("AhaKey-X1-firmware.hex");
        Path second = temporary.resolve("local.hex");
        Files.writeString(first, ":00000001FF\n");
        Files.writeString(second, ":0400000001020304F2\n:00000001FF\n");
        FirmwareUpdateDiagnostics diagnostics =
            new FirmwareUpdateDiagnostics(temporary.resolve("diagnostics"));

        Path builtInOperation = diagnostics.begin(UUID.randomUUID(),
            new FirmwareUpdateRequest(first, FirmwareCapabilities.BUNDLED_VERSION,
                null, false, false, FirmwareUpdateRequest.Source.BUILTIN));
        Path localOperation = diagnostics.begin(UUID.randomUUID(),
            new FirmwareUpdateRequest(second, null, null, true, false,
                FirmwareUpdateRequest.Source.LOCAL));

        String builtIn = Files.readString(builtInOperation.resolve("operation.json"));
        String local = Files.readString(localOperation.resolve("operation.json"));
        assertTrue(builtIn.contains("\"SELECTED_HEX_SOURCE\": \"BUILTIN\""));
        assertTrue(local.contains("\"SELECTED_HEX_SOURCE\": \"LOCAL\""));
        assertTrue(builtIn.matches("(?s).*\"SELECTED_HEX_SHA256\": \"[0-9a-f]{64}\".*"));
        assertTrue(local.matches("(?s).*\"SELECTED_HEX_SHA256\": \"[0-9a-f]{64}\".*"));
    }
}
