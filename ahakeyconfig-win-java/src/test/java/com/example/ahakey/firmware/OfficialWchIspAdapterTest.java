package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

class OfficialWchIspAdapterTest {
    @TempDir Path temporary;

    @Test
    void detectDeviceIsOneShotPresenceAndDoesNotRunUidCli() throws Exception {
        RuntimeBundle runtime = runtime();
        AtomicReference<Boolean> runnerCalled = new AtomicReference<>(false);
        DefaultOfficialWchIspAdapter adapter = new DefaultOfficialWchIspAdapter(
            () -> runtime, () -> true,
            new WchIspRunner((command, cancellation) -> {
                runnerCalled.set(true);
                throw new AssertionError("detection must not invoke -u get");
            }));

        OfficialWchIspAdapter.DeviceDetectionResult result = adapter.detectDevice();

        assertTrue(result.ispPresent());
        assertTrue(result.uid().isEmpty(), "UID is optional in the adapter first phase");
        assertTrue(result.detail().contains("UID=OPTIONAL_NOT_QUERIED"));
        assertFalse(runnerCalled.get());
    }

    @Test
    void flashFirmwareUsesOfficialDownloadArgumentsWithoutWorkspaceOrUidQuery() throws Exception {
        RuntimeBundle runtime = runtime();
        Path hex = temporary.resolve("firmware.hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n");
        AtomicReference<List<String>> arguments = new AtomicReference<>();
        DefaultOfficialWchIspAdapter adapter = new DefaultOfficialWchIspAdapter(
            () -> runtime, () -> true,
            new WchIspRunner((command, cancellation) -> {
                arguments.set(command.arguments());
                return new WchIspRunner.WchIspProcessResult(command.operationId(), true, 42, 0,
                    false, false, "", "", "", Duration.ofMillis(8), false,
                    Map.of(), "PROCESS_EXIT", List.of(42L));
            }));

        OfficialWchIspAdapter.FlashResult result = adapter.flashFirmware(hex);

        assertTrue(result.success());
        assertEquals(List.of("-o", "download", "-f", hex.toAbsolutePath().normalize().toString()),
            arguments.get());
        assertFalse(arguments.get().contains("-c"));
        assertFalse(arguments.get().contains("-u"));
        assertEquals(42, result.processResult().pid());
    }

    @Test
    void firmwareServiceProductionSeamUsesAdapterAndKeepsUidOptional() throws Exception {
        RuntimeBundle runtime = runtime();
        Path hex = temporary.resolve("service-firmware.hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n");
        AtomicReference<Integer> detectCalls = new AtomicReference<>(0);
        AtomicReference<Integer> flashCalls = new AtomicReference<>(0);
        OfficialWchIspAdapter adapter = new OfficialWchIspAdapter() {
            @Override public DeviceDetectionResult detectDevice() {
                detectCalls.updateAndGet(value -> value + 1);
                return DeviceDetectionResult.present(runtime, "official detection");
            }
            @Override public FlashResult flashFirmware(Path ignored) {
                flashCalls.updateAndGet(value -> value + 1);
                return new FlashResult(true, "official flash", null, runtime);
            }
        };
        FirmwarePostVerifier verifier = new FirmwarePostVerifier(
            () -> new com.example.ahakey.protocol.AhaKeyResponseParser.DeviceCapabilities(
                3, 2, 1, 4, 0, FirmwareCapabilities.REQUIRED_CAPABILITY_MASK, 7, 1),
            () -> true, millis -> { });
        FirmwareUpdateService service = new FirmwareUpdateService(adapter, () -> runtime,
            verifier, new FirmwareUpdateDiagnostics(temporary.resolve("service-diagnostics")), temporary);
        try {
            FirmwareUpdateRequest request = new FirmwareUpdateRequest(hex, null, null, true, false);
            FirmwareUpdateResult result = service.start(request).handle().completion()
                .get(5, TimeUnit.SECONDS);
            assertTrue(result.success(), result.detail());
            assertEquals(1, detectCalls.get());
            assertEquals(1, flashCalls.get());
            assertTrue(Files.isRegularFile(result.diagnosticDirectory().resolve("adapter-detection.txt")));
            assertFalse(result.detail().contains("UID_QUERY_FAILED"));
        } finally {
            service.shutdown();
        }
    }

    private RuntimeBundle runtime() {
        Path root = temporary.resolve("runtime");
        Path exe = root.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME);
        return new RuntimeBundle(root, exe, root.resolve("CH343PT.DLL"),
            root.resolve("WCH55xISPDLL.dll"), root.resolve("CONFIG_CH57X59X.WCH"), null,
            new RuntimeIdentity(Optional.empty(), Optional.empty(), Optional.empty(), Optional.empty(),
                "exe", "ch343", "isp", "config", RuntimeIdentity.ValidationStatus.UNKNOWN));
    }
}
