package com.example.ahakey.firmware;

import com.example.ahakey.protocol.AhaKeyResponseParser;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

class FirmwareUpdateServiceTest {
    @TempDir Path temporary;

    @Test
    void legalStateMachineRejectsSkippingPreparation() {
        assertTrue(FirmwareUpdateService.isLegalTransition(
            FirmwareUpdateState.IDLE, FirmwareUpdateState.PREFLIGHT));
        assertFalse(FirmwareUpdateService.isLegalTransition(
            FirmwareUpdateState.IDLE, FirmwareUpdateState.SUCCESS));
        assertFalse(FirmwareUpdateService.isLegalTransition(
            FirmwareUpdateState.FLASHING, FirmwareUpdateState.SUCCESS));
        assertTrue(FirmwareUpdateService.isLegalTransition(
            FirmwareUpdateState.VERIFYING, FirmwareUpdateState.SUCCESS));
    }

    @Test
    void concurrentStartReturnsBusyAndOnlyOneOperationRuns() throws Exception {
        AtomicInteger probes = new AtomicInteger();
        FirmwareUpdateService service = service(() -> { probes.incrementAndGet(); return false; },
            (command, cancellation) -> { throw new AssertionError("runner must not run"); });
        try {
            FirmwareUpdateService.OperationStart first = service.start(request());
            assertTrue(first.accepted());
            FirmwareUpdateService.OperationStart second = service.start(request());
            assertFalse(second.accepted());
            assertEquals(FirmwareUpdateError.BUSY, second.rejection().error());
            first.handle().cancel();
            assertEquals(FirmwareUpdateState.CANCELLED,
                first.handle().completion().get(2, TimeUnit.SECONDS).state());
            assertTrue(probes.get() >= 0);
        } finally {
            service.shutdown();
        }
    }

    @Test
    void endToEndUsesUidAndFlashRunnerThenPostVerifier() throws Exception {
        AtomicReference<String> commandSeen = new AtomicReference<>();
        AtomicInteger awaitCalls = new AtomicInteger();
        WchIspRunner runner = new WchIspRunner((command, cancellation) -> {
            commandSeen.set(String.join(" ", command.arguments()));
            String output = command.arguments().contains("get")
                ? "Device UID:23-DF-93-5A-04-DC-BA-15"
                : "{\"Status\":\"Finished\",\"Code\":0,\"Message\":\"Succeed\"}";
            return new WchIspRunner.WchIspProcessResult(command.operationId(), true, 1, 0,
                false, false, output, "", output, Duration.ZERO, false, Map.of(), "PROCESS_EXIT");
        });
        IspDeviceProbe probe = new IspDeviceProbe() {
            @Override public boolean isPresent() { return true; }
            @Override public boolean awaitPresent(Duration timeout,
                                                  java.util.function.BooleanSupplier cancelled) {
                awaitCalls.incrementAndGet();
                return true;
            }
        };
        FirmwareUpdateService service = service(probe, runner::run);
        try {
            FirmwareUpdateService.OperationStart start = service.start(request());
            FirmwareUpdateResult result = start.handle().completion().get(5, TimeUnit.SECONDS);
            assertTrue(result.success(), result.detail());
            assertTrue(commandSeen.get().contains("download") || commandSeen.get().contains("get"));
            assertNotNull(result.diagnosticDirectory());
            assertTrue(Files.isRegularFile(result.diagnosticDirectory().resolve("command.txt")));
            assertTrue(Files.isRegularFile(result.diagnosticDirectory().resolve("runtime.json")));
            assertEquals(1, awaitCalls.get());
        } finally {
            service.shutdown();
        }
    }

    @Test
    void diagnosticReadyRequiresUidConfirmation() throws Exception {
        WchIspRunner runner = new WchIspRunner((command, cancellation) ->
            new WchIspRunner.WchIspProcessResult(command.operationId(), true, 1, 0,
                false, false, "Device UID:23-DF-93-5A-04-DC-BA-15", "stderr", "console",
                Duration.ofMillis(37), true, Map.of(), "PROCESS_EXIT", List.of(1L, 2L)));
        FirmwareUpdateService service = service(() -> true, runner::run);
        try {
            FirmwareUpdateService.DiagnosticResult result = service.diagnose();
            assertTrue(result.runtimeReady());
            assertTrue(result.ispPresent());
            assertTrue(result.uidConfirmed());
            assertTrue(result.ready());
            assertNotNull(result.operationId());
            assertNotNull(result.diagnosticDirectory());
            assertNotNull(result.processResult());
            assertEquals(1, result.processResult().pid());
            assertEquals(37, result.processResult().duration().toMillis());
            assertTrue(result.processResult().elevationUsed());
            assertEquals(List.of(1L, 2L), result.processResult().ownedProcessIds());
            for (String name : List.of("command.txt", "stdout.txt", "stderr.txt",
                "console.txt", "result.json", "timing.json", "runtime.json")) {
                assertTrue(Files.isRegularFile(result.diagnosticDirectory().resolve(name)), name);
            }
            String report = result.detail();
            assertTrue(report.contains("UID_QUERY_EXIT_CODE=0"));
            assertTrue(report.contains("UID_QUERY_DURATION_MS=37"));
            assertTrue(report.contains("WCHISP_PID=1"));
            assertTrue(report.contains("ELEVATION_USED=YES"));
            assertTrue(report.contains("TERMINATION_REASON=PROCESS_EXIT"));
            assertTrue(report.contains("STDOUT=Device UID:23-DF-93-5A-04-DC-BA-15"));
            assertTrue(report.contains("STDERR=stderr"));
            assertTrue(report.contains("CONSOLE=console"));
        } finally {
            service.shutdown();
        }
    }

    @Test
    void diagnosticFailureStillPersistsProcessEvidence() throws Exception {
        WchIspRunner runner = new WchIspRunner((command, cancellation) ->
            new WchIspRunner.WchIspProcessResult(command.operationId(), true, 9, 7,
                false, false, "", "driver error", "driver error",
                Duration.ofMillis(12), false, Map.of(), "PROCESS_EXIT", List.of(9L)));
        FirmwareUpdateService service = service(() -> true, runner::run);
        try {
            FirmwareUpdateService.DiagnosticResult result = service.diagnose();
            assertFalse(result.uidConfirmed());
            assertEquals(FirmwareUpdateError.UID_QUERY_FAILED, result.error());
            assertNotNull(result.processResult());
            assertTrue(result.detail().contains("UID_QUERY_EXIT_CODE=7"));
            assertTrue(result.detail().contains("STDERR=driver error"));
            assertEquals("driver error", Files.readString(
                result.diagnosticDirectory().resolve("stderr.txt")));
            assertTrue(Files.readString(result.diagnosticDirectory().resolve("result.json"))
                .contains("\"exitCode\": 7"));
        } finally {
            service.shutdown();
        }
    }

    private FirmwareUpdateService service(IspDeviceProbe probe, WchIspRunner.Backend backend)
        throws Exception {
        Path runtimeRoot = temporary.resolve("runtime-" + System.nanoTime());
        Files.createDirectories(runtimeRoot);
        Path exe = runtimeRoot.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME);
        Files.write(exe, new byte[]{1});
        Files.write(runtimeRoot.resolve("CH343PT.DLL"), new byte[]{2});
        Files.write(runtimeRoot.resolve("WCH55xISPDLL.dll"), new byte[]{3});
        RuntimeBundle bundle = new RuntimeBundle(runtimeRoot, exe,
            runtimeRoot.resolve("CH343PT.DLL"), runtimeRoot.resolve("WCH55xISPDLL.dll"),
            runtimeRoot.resolve("CONFIG_CH57X59X.WCH"), null,
            new RuntimeIdentity(Optional.empty(), Optional.empty(), Optional.empty(), Optional.empty(),
                "e", "c", "i", "g", RuntimeIdentity.ValidationStatus.UNKNOWN));
        return new FirmwareUpdateService(() -> bundle, probe, new WchIspRunner(backend),
            new FirmwarePostVerifier(() -> new AhaKeyResponseParser.DeviceCapabilities(3, 2, 1, 4, 0,
                FirmwareCapabilities.REQUIRED_CAPABILITY_MASK, 7, 1), () -> true, millis -> { }),
            new FirmwareUpdateDiagnostics(temporary.resolve("diagnostics")), temporary);
    }

    private FirmwareUpdateRequest request() throws Exception {
        Path hex = temporary.resolve("firmware-" + System.nanoTime() + ".hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n");
        return new FirmwareUpdateRequest(hex, null, null, true, false);
    }
}
