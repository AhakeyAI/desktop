package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

class WchIspWorkspaceTest {
    @TempDir Path temporary;

    @Test
    void createsIsolatedWorkspaceAndEffectiveConfig() throws Exception {
        Path runtimeRoot = temporary.resolve("runtime");
        Files.createDirectories(runtimeRoot);
        Path exe = runtimeRoot.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME);
        Files.write(exe, new byte[]{1});
        RuntimeBundle runtime = new RuntimeBundle(runtimeRoot, exe,
            runtimeRoot.resolve("CH343PT.DLL"), runtimeRoot.resolve("WCH55xISPDLL.dll"),
            runtimeRoot.resolve("CONFIG_CH57X59X.WCH"), null,
            new RuntimeIdentity(Optional.empty(), Optional.empty(), Optional.empty(), Optional.empty(),
                "e", "c", "i", "g", RuntimeIdentity.ValidationStatus.UNKNOWN));
        Files.write(runtime.ch343Dll(), new byte[]{2});
        Files.write(runtime.ispDll(), new byte[]{3});
        Path hex = temporary.resolve("firmware.hex");
        Files.writeString(hex, ":00000001FF\n");

        WchIspWorkspace workspace = WchIspWorkspace.create(temporary, UUID.randomUUID());
        Path root = workspace.root();
        WchIspWorkspace.PreparedWorkspace prepared = workspace.prepare(runtime, hex);
        assertTrue(Files.isRegularFile(prepared.executable()));
        assertEquals(WchIspConfigLayout.CONFIG_SIZE, Files.size(prepared.effectiveConfig()));
        assertTrue(Files.isRegularFile(prepared.configIni()));
        workspace.close();
        assertFalse(Files.exists(root));
    }

    @Test
    void slotPatchPreservesLayoutAndRejectsOversizedPath() throws Exception {
        byte[] baseline;
        try (var input = getClass().getResourceAsStream("/wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH")) {
            baseline = input.readAllBytes();
        }
        byte[] patched = WchIspConfigLayout.patchSlot(baseline, 0, "C:\\firmware.hex");
        assertEquals(WchIspConfigLayout.CONFIG_SIZE, patched.length);
        assertThrows(Exception.class, () -> WchIspConfigLayout.patchSlot(
            baseline, 0, "x".repeat(400)));
    }

    @Test
    void detectUsesPlaceholderAndFlashUsesRealFirmwareWithoutConfigCopies() throws Exception {
        Path runtimeRoot = temporary.resolve("runtime-separated");
        Files.createDirectories(runtimeRoot);
        Path exe = runtimeRoot.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME);
        Files.write(exe, new byte[]{1});
        Files.write(runtimeRoot.resolve("CH343PT.DLL"), new byte[]{2});
        Files.write(runtimeRoot.resolve("WCH55xISPDLL.dll"), new byte[]{3});
        Files.write(runtimeRoot.resolve("CONFIG_CH57X59X.WCH"), new byte[]{9});
        Files.write(runtimeRoot.resolve("CONFIG_CH57X59X.WCH.excluded"), new byte[]{9});
        Files.write(runtimeRoot.resolve("CONFIG_CH57X59X.WCH.bak"), new byte[]{9});
        Files.write(runtimeRoot.resolve("CONFIG_CH57X59X-old.WCH"), new byte[]{9});
        RuntimeBundle runtime = new RuntimeBundle(runtimeRoot, exe,
            runtimeRoot.resolve("CH343PT.DLL"), runtimeRoot.resolve("WCH55xISPDLL.dll"),
            runtimeRoot.resolve("CONFIG_CH57X59X.WCH"), null,
            new RuntimeIdentity(Optional.empty(), Optional.empty(), Optional.empty(), Optional.empty(),
                "e", "c", "i", "g", RuntimeIdentity.ValidationStatus.UNKNOWN));
        Path hex = temporary.resolve("real-firmware.hex");
        Files.writeString(hex, ":00000001FF\n");
        try (WchIspWorkspace workspace = WchIspWorkspace.create(temporary, UUID.randomUUID())) {
            var detect = workspace.prepareForDetect(runtime);
            var flash = workspace.prepareForFlash(runtime, hex);
            assertEquals("unused.hex", detect.firmwareInput().getFileName().toString());
            assertEquals(hex.toAbsolutePath().normalize(), flash.firmwareInput());
            assertTrue(Files.readString(detect.configIni()).contains("unused.hex"));
            assertTrue(Files.readString(flash.configIni()).contains("real-firmware.hex"));
            assertFalse(Files.exists(workspace.toolDirectory().resolve("CONFIG_CH57X59X.WCH")));
            assertFalse(Files.exists(workspace.toolDirectory().resolve("CONFIG_CH57X59X-old.WCH")));
        }
    }
}
