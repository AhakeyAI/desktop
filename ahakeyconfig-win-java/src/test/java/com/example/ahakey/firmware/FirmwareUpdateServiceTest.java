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
import java.util.UUID;
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
        FirmwareUpdateService service = service(probe, runner::run, ChipMatched.matched(), false);
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
    void diagnosticReadyUsesChipMatchAndKeepsUidAsOptionalEvidence() throws Exception {
        WchIspRunner runner = new WchIspRunner((command, cancellation) ->
            new WchIspRunner.WchIspProcessResult(command.operationId(), true, 1, 0,
                false, false, "Device UID:23-DF-93-5A-04-DC-BA-15", "stderr", "console",
                Duration.ofMillis(37), true, Map.of(), "PROCESS_EXIT", List.of(1L, 2L)));
        FirmwareUpdateService service = service(() -> true, runner::run, ChipMatched.matched(), false);
        try {
            FirmwareUpdateService.DiagnosticResult result = service.diagnose();
            assertTrue(result.runtimeReady());
            assertTrue(result.ispPresent());
            assertTrue(result.chipMatched());
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
        FirmwareUpdateService service = service(() -> true, runner::run, ChipMatched.matched(), false);
        try {
            FirmwareUpdateService.DiagnosticResult result = service.diagnose();
            assertFalse(result.uidConfirmed());
            assertNull(result.error(), "UID failure is diagnostic-only when chip is matched");
            assertTrue(result.ready());
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

    @Test
    void uidEmptyStillReachesReadyAndFlashes() throws Exception {
        AtomicReference<List<String>> flashArgs = new AtomicReference<>();
        AtomicReference<List<FirmwareUpdateState>> states = new AtomicReference<>(new java.util.ArrayList<>());
        WchIspRunner runner = new WchIspRunner((command, cancellation) -> {
            if (command.arguments().contains("download")) flashArgs.set(command.arguments());
            String output = command.arguments().contains("get")
                ? ""
                : "{\"Status\":\"Finished\",\"Code\":0,\"Message\":\"Succeed\"}";
            return new WchIspRunner.WchIspProcessResult(command.operationId(), true, 7, 0,
                false, false, output, "", output, Duration.ZERO, false, Map.of(), "PROCESS_EXIT");
        });
        FirmwareUpdateService service = service(() -> true, runner::run, ChipMatched.matched(), false);
        service.addListener(status -> states.get().add(status.state()));
        try {
            FirmwareUpdateResult result = service.start(request()).handle().completion()
                .get(5, TimeUnit.SECONDS);
            assertTrue(result.success(), result.detail());
            assertTrue(states.get().contains(FirmwareUpdateState.READY));
            assertTrue(states.get().contains(FirmwareUpdateState.WAITING_RECONNECT));
            assertTrue(states.get().contains(FirmwareUpdateState.VERIFYING));
            assertEquals(List.of("-c", "flash", "-o", "download", "-f", "firmware"),
                normalizeFlashArgs(flashArgs.get()));
        } finally {
            service.shutdown();
        }
    }

    @Test
    void flashTerminalTimeoutIsNeverReportedAsIspNotPresent() {
        UUID operationId = UUID.randomUUID();
        var timedOut = new WchIspRunner.WchIspProcessResult(operationId, true, 99, 124,
            true, false, "", "", "", Duration.ofMinutes(5), true,
            Map.of(), "FLASH_TERMINAL_RESULT_TIMEOUT", List.of(99L));
        var flash = new OfficialWchIspAdapter.FlashResult(false, "timeout", timedOut, null);

        assertEquals(FirmwareUpdateError.FLASH_TERMINAL_RESULT_TIMEOUT,
            FirmwareUpdateService.flashFailureError(flash));
        assertNotEquals(FirmwareUpdateError.ISP_NOT_PRESENT,
            FirmwareUpdateService.flashFailureError(flash));
    }

    @Test
    void uidQueryFailureStillAllowsFlashWithoutChangingFlashCommand() throws Exception {
        AtomicInteger flashRuns = new AtomicInteger();
        AtomicReference<List<String>> flashArgs = new AtomicReference<>();
        WchIspRunner runner = new WchIspRunner((command, cancellation) -> {
            if (command.arguments().contains("download")) {
                flashRuns.incrementAndGet();
                flashArgs.set(command.arguments());
                return new WchIspRunner.WchIspProcessResult(command.operationId(), true, 8, 0,
                    false, false, "{\"Status\":\"Finished\",\"Code\":0,\"Message\":\"Succeed\"}",
                    "", "", Duration.ZERO, false, Map.of(), "PROCESS_EXIT");
            }
            return new WchIspRunner.WchIspProcessResult(command.operationId(), true, 8, 1,
                false, false, "", "no uid", "", Duration.ZERO, false, Map.of(), "PROCESS_EXIT");
        });
        FirmwareUpdateService service = service(() -> true, runner::run, ChipMatched.matched(), false);
        try {
            FirmwareUpdateResult result = service.start(request()).handle().completion()
                .get(5, TimeUnit.SECONDS);
            assertTrue(result.success(), result.detail());
            assertEquals(1, flashRuns.get());
            assertEquals(List.of("-c", "flash", "-o", "download", "-f", "firmware"),
                normalizeFlashArgs(flashArgs.get()));
            assertTrue(result.detail().contains("UID_QUERY_WARNING="));
        } finally {
            service.shutdown();
        }
    }

    @Test
    void runtimeFailureBlocksBeforeIspOrFlash() throws Exception {
        AtomicInteger runnerCalls = new AtomicInteger();
        FirmwareUpdateService service = new FirmwareUpdateService(
            () -> { throw new java.io.IOException("runtime invalid"); },
            () -> true,
            new WchIspRunner((command, cancellation) -> {
                runnerCalls.incrementAndGet();
                throw new AssertionError("runtime failure must block WCHISP");
            }),
            null,
            new FirmwareUpdateDiagnostics(temporary.resolve("diagnostics-runtime-failure")), temporary,
            ChipMatched.matched(), false);
        try {
            FirmwareUpdateResult result = service.start(request()).handle().completion()
                .get(5, TimeUnit.SECONDS);
            assertEquals(FirmwareUpdateState.FAILED, result.state());
            assertTrue(result.error() == FirmwareUpdateError.RUNTIME_INVALID
                || result.error() == FirmwareUpdateError.RUNTIME_NOT_FOUND);
            assertEquals(0, runnerCalls.get());
        } finally {
            service.shutdown();
        }
    }

    @Test
    void chipMismatchBlocksBeforeUidAndFlash() throws Exception {
        AtomicInteger runnerCalls = new AtomicInteger();
        FirmwareUpdateService service = service(() -> true, (command, cancellation) -> {
            runnerCalls.incrementAndGet();
            throw new AssertionError("chip mismatch must block WCHISP");
        }, ChipMatched.mismatched("not CH582"), false);
        try {
            FirmwareUpdateResult result = service.start(request()).handle().completion()
                .get(5, TimeUnit.SECONDS);
            assertEquals(FirmwareUpdateState.FAILED, result.state());
            assertEquals(FirmwareUpdateError.CHIP_MISMATCH, result.error());
            assertEquals(0, runnerCalls.get());
        } finally {
            service.shutdown();
        }
    }

    @Test
    void unknownChipFailsClosedUnlessExplicitDevelopmentOverride() throws Exception {
        FirmwareUpdateService blocked = service(() -> true, (command, cancellation) -> {
            throw new AssertionError("unknown chip must fail closed");
        }, ChipMatched.unknown(), false);
        try {
            FirmwareUpdateResult result = blocked.start(request()).handle().completion()
                .get(5, TimeUnit.SECONDS);
            assertEquals(FirmwareUpdateError.CHIP_UNKNOWN, result.error());
        } finally {
            blocked.shutdown();
        }
    }

    @Test
    void unknownChipDevelopmentOverrideAllowsClosedLoopTestWithoutPretendingMatched() throws Exception {
        WchIspRunner runner = new WchIspRunner((command, cancellation) -> {
            String output = command.arguments().contains("download")
                ? "{\"Status\":\"Finished\",\"Code\":0,\"Message\":\"Succeed\"}" : "";
            return new WchIspRunner.WchIspProcessResult(command.operationId(), true, 11, 0,
                false, false, output, "", output, Duration.ZERO, false, Map.of(), "PROCESS_EXIT");
        });
        FirmwareUpdateService service = service(() -> true, runner::run, ChipMatched.unknown(), true);
        try {
            FirmwareUpdateResult result = service.start(request()).handle().completion()
                .get(5, TimeUnit.SECONDS);
            assertTrue(result.success(), result.detail());
            String chipEvidence = Files.readString(result.diagnosticDirectory().resolve("chip-match.txt"));
            assertTrue(chipEvidence.contains("CHIP_MATCH_STATUS=UNKNOWN"));
            assertTrue(chipEvidence.contains("CHIP_GATE_ALLOWED=YES"));
        } finally {
            service.shutdown();
        }
    }

    @Test
    void preparedOfficialSessionIsCompleteBeforeIspAndClickLaunchesOnce() throws Exception {
        RuntimeBundle runtime = runtimeBundle("prepared-official-runtime");
        Path hex = temporary.resolve("prepared-official.hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n");
        AtomicInteger runnerCalls = new AtomicInteger();
        AtomicReference<List<String>> flashArguments = new AtomicReference<>();
        WchIspRunner runner = new WchIspRunner((command, cancellation) -> {
            runnerCalls.incrementAndGet();
            flashArguments.set(command.arguments());
            return new WchIspRunner.WchIspProcessResult(command.operationId(), true, 23, 0,
                false, false, "", "",
                "{\"Status\":\"Finished\",\"Code\":0,\"Message\":\"Succeed\"}",
                Duration.ofMillis(4), false,
                Map.of(), "PROCESS_EXIT", List.of(23L));
        });
        DefaultOfficialWchIspAdapter adapter = new DefaultOfficialWchIspAdapter(
            () -> runtime, () -> true, runner);
        FirmwareUpdateService service = new FirmwareUpdateService(adapter, () -> runtime,
            verifier(), new FirmwareUpdateDiagnostics(temporary.resolve("prepared-diagnostics")), temporary);
        try {
            FirmwareUpdateService.PreparationResult preparation = service.prepareFlash(
                new FirmwareUpdateRequest(hex, null, null, true, false));
            assertTrue(preparation.prepared(), preparation.detail());
            FirmwareUpdateService.PreparedFirmwareOperation prepared = preparation.operation();
            assertNotNull(prepared);
            assertEquals(0, runnerCalls.get(), "preparation must not execute download");
            assertTrue(Files.isRegularFile(prepared.session().configPath()));
            assertEquals("-c", prepared.session().command().arguments().get(0));
            assertEquals("download", prepared.session().command().arguments().get(3));
            assertEquals("firmware-operation:" + prepared.session().operationId(),
                prepared.session().workerOwner());

            FirmwareUpdateService.DiagnosticResult detection = service.diagnose(prepared);
            assertTrue(detection.ready(), detection.detail());
            assertTrue(prepared.armed());
            assertEquals(0, runnerCalls.get(), "ISP detection must not execute download");

            FirmwareUpdateService.OperationStart start = service.startPrepared(prepared);
            FirmwareUpdateResult result = start.handle().completion().get(5, TimeUnit.SECONDS);
            assertTrue(result.success(), result.detail());
            assertEquals(1, runnerCalls.get());
            assertEquals(prepared.session().command().arguments(), flashArguments.get());
        } finally {
            service.shutdown();
        }
    }

    @Test
    void cancellingPreparedOfficialSessionDoesNotExecuteDownload() throws Exception {
        RuntimeBundle runtime = runtimeBundle("cancelled-official-runtime");
        Path hex = temporary.resolve("cancelled-official.hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n");
        AtomicInteger runnerCalls = new AtomicInteger();
        DefaultOfficialWchIspAdapter adapter = new DefaultOfficialWchIspAdapter(
            () -> runtime, () -> true,
            new WchIspRunner((command, cancellation) -> {
                runnerCalls.incrementAndGet();
                throw new AssertionError("cancelled prepared session must not execute");
            }));
        FirmwareUpdateService service = new FirmwareUpdateService(adapter, () -> runtime,
            verifier(), new FirmwareUpdateDiagnostics(temporary.resolve("cancelled-diagnostics")), temporary);
        try {
            FirmwareUpdateService.PreparedFirmwareOperation prepared = service.prepareFlash(
                new FirmwareUpdateRequest(hex, null, null, true, false)).operation();
            assertTrue(service.diagnose(prepared).ispPresent());
            assertTrue(prepared.cancel());
            FirmwareUpdateService.OperationStart start = service.startPrepared(prepared);
            assertFalse(start.accepted());
            assertEquals(0, runnerCalls.get());
        } finally {
            service.shutdown();
        }
    }

    private FirmwarePostVerifier verifier() {
        return new FirmwarePostVerifier(
            () -> new AhaKeyResponseParser.DeviceCapabilities(3, 2, 1, 4, 0,
                FirmwareCapabilities.REQUIRED_CAPABILITY_MASK, 7, 1),
            () -> true, millis -> { });
    }

    private RuntimeBundle runtimeBundle(String name) throws Exception {
        Path runtimeRoot = temporary.resolve(name);
        Files.createDirectories(runtimeRoot);
        Path exe = runtimeRoot.resolve(WchIspRuntimeProvider.EXECUTABLE_NAME);
        Files.write(exe, new byte[]{1});
        Files.write(runtimeRoot.resolve("CH343PT.DLL"), new byte[]{2});
        Files.write(runtimeRoot.resolve("WCH55xISPDLL.dll"), new byte[]{3});
        return new RuntimeBundle(runtimeRoot, exe,
            runtimeRoot.resolve("CH343PT.DLL"), runtimeRoot.resolve("WCH55xISPDLL.dll"),
            runtimeRoot.resolve("CONFIG_CH57X59X.WCH"), null,
            new RuntimeIdentity(Optional.empty(), Optional.empty(), Optional.empty(), Optional.empty(),
                "e", "c", "i", "g", RuntimeIdentity.ValidationStatus.UNKNOWN));
    }

    private FirmwareUpdateService service(IspDeviceProbe probe, WchIspRunner.Backend backend)
        throws Exception {
        return service(probe, backend, ChipMatched.matched(), false);
    }

    private FirmwareUpdateService service(IspDeviceProbe probe, WchIspRunner.Backend backend,
                                         ChipMatched chipMatched, boolean allowUnknownChip)
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
            new FirmwareUpdateDiagnostics(temporary.resolve("diagnostics")), temporary,
            chipMatched, allowUnknownChip);
    }

    private static List<String> normalizeFlashArgs(List<String> args) {
        if (args == null) return List.of();
        if (args.size() != 6) return args;
        return List.of(args.get(0), "flash", args.get(2), args.get(3), args.get(4), "firmware");
    }

    private FirmwareUpdateRequest request() throws Exception {
        Path hex = temporary.resolve("firmware-" + System.nanoTime() + ".hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n");
        return new FirmwareUpdateRequest(hex, null, null, true, false);
    }
}
