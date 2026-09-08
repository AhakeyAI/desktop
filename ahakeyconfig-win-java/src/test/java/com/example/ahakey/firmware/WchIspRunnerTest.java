package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WchIspRunnerTest {
    @Test
    void error740UsesInjectedRunAsBoundaryAndUnifiedResult() throws Exception {
        UUID operationId = UUID.randomUUID();
        WchIspRunner.WchIspCommand command = new WchIspRunner.WchIspCommand(
            Path.of("WCHISPTool_CH57x-59x.exe"), Path.of("."), List.of("-u", "get"),
            Duration.ofSeconds(2), operationId);
        WchIspRunner runner = new WchIspRunner(
            (ignored, token) -> { throw new WchIspRunner.ElevationRequiredException(
                new IOException("CreateProcess error=740")); },
            (ignored, token) -> new WchIspRunner.WchIspProcessResult(
                operationId, true, 17, 0, false, false, "Device UID: 01-02", "",
                "Device UID: 01-02", Duration.ofMillis(5), true, Map.of(), "ELEVATED_PROCESS_EXIT",
                List.of(17L, 18L)));

        WchIspRunner.WchIspProcessResult result = runner.run(command, () -> false);

        assertTrue(result.processStarted());
        assertTrue(result.elevationUsed());
        assertEquals(operationId, result.operationId());
        assertEquals(0, result.exitCode());
        assertEquals(List.of(17L, 18L), result.ownedProcessIds());
    }

    @Test
    void preparedElevatedWorkerIsReadyBeforeGoAndReportsActualChildStart() throws Exception {
        UUID operationId = UUID.randomUUID();
        Path commandPath = Path.of("WCHISPTool_CH57x-59x.exe");
        WchIspRunner.WchIspCommand command = new WchIspRunner.WchIspCommand(
            commandPath, Path.of("."), List.of("-c", "flash.ini", "-o", "download", "-f", "firmware.hex"),
            Duration.ofSeconds(2), operationId);
        AtomicFlags flags = new AtomicFlags();
        Instant childStarted = Instant.now();
        WchIspRunner.WchIspProcessResult process = new WchIspRunner.WchIspProcessResult(
            operationId, true, 303, 0, false, false, "ok", "", "ok", Duration.ofMillis(4),
            true, Map.of(), "PROCESS_EXIT", List.of(101L, 202L, 303L), childStarted);
        WchIspRunner.ElevatedBackend elevated = new WchIspRunner.ElevatedBackend() {
            @Override public WchIspRunner.WchIspProcessResult run(
                WchIspRunner.WchIspCommand ignored, WchIspRunner.CancellationToken token) {
                throw new AssertionError("legacy elevated path must not be used");
            }
            @Override public PreparedLaunchContext prepare(WchIspRunner.WchIspCommand ignored) {
                flags.prepared = true;
                return new PreparedLaunchContext(operationId, Path.of("control"), "nonce",
                    Instant.now(), 101, 202, true,
                    token -> { flags.launched = true; return process; },
                    () -> flags.cancelled = true);
            }
        };
        WchIspRunner runner = new WchIspRunner((ignored, token) -> {
            throw new AssertionError("direct path must not be used");
        }, elevated, true);

        PreparedLaunchContext prepared = runner.prepareElevatedLaunch(command);
        assertTrue(flags.prepared);
        assertTrue(prepared.ready());
        assertTrue(prepared.workerRunning());
        assertFalse(flags.launched);
        WchIspRunner.WchIspProcessResult result = prepared.launch(() -> false);
        assertTrue(flags.launched);
        assertEquals(childStarted, result.actualProcessStartTime());
        assertEquals(PreparedLaunchContext.State.COMPLETED, prepared.state());
        assertThrows(IllegalStateException.class, () -> prepared.launch(() -> false));
    }

    @Test
    void uacCancellationDuringPreparationFailsClosed() {
        UUID operationId = UUID.randomUUID();
        WchIspRunner.WchIspCommand command = new WchIspRunner.WchIspCommand(
            Path.of("tool.exe"), Path.of("."), List.of("-o", "download"),
            Duration.ofSeconds(1), operationId);
        WchIspRunner.ElevatedBackend elevated = new WchIspRunner.ElevatedBackend() {
            @Override public WchIspRunner.WchIspProcessResult run(
                WchIspRunner.WchIspCommand ignored, WchIspRunner.CancellationToken token) {
                throw new AssertionError();
            }
            @Override public PreparedLaunchContext prepare(WchIspRunner.WchIspCommand ignored)
                throws Exception {
                throw new IOException("UAC_CANCELLED");
            }
        };
        WchIspRunner runner = new WchIspRunner((ignored, token) -> {
            throw new AssertionError();
        }, elevated, true);
        assertThrows(IOException.class, () -> runner.prepareElevatedLaunch(command));
    }

    @Test
    void cancellingReadyWorkerSignalsOnlyItsOperationAndPreventsGo() {
        AtomicFlags flags = new AtomicFlags();
        PreparedLaunchContext prepared = new PreparedLaunchContext(UUID.randomUUID(),
            Path.of("control"), "nonce", Instant.now(), 401, 402, true,
            token -> { flags.launched = true; return null; },
            () -> flags.cancelled = true);
        assertTrue(prepared.cancel());
        assertTrue(flags.cancelled);
        assertFalse(prepared.workerRunning());
        assertThrows(IllegalStateException.class, () -> prepared.launch(() -> false));
        assertFalse(flags.launched);
    }

    @Test
    void generatedPreparedScriptsUseRealNewlinesAndPassPowerShellParser() throws Exception {
        Path directory = Files.createTempDirectory("wchisp-script-parse-");
        Path worker = directory.resolve("worker.ps1");
        Path wrapper = directory.resolve("runas-wrapper.ps1");
        String workerText = WchIspRunner.preparedWorkerScriptForTests();
        String wrapperText = WchIspRunner.preparedWrapperScriptForTests();
        String literalBacktickN = String.valueOf((char) 96) + "n";
        assertFalse(workerText.contains(literalBacktickN));
        assertFalse(wrapperText.contains(literalBacktickN));
        assertTrue(workerText.contains(System.lineSeparator()));
        assertTrue(wrapperText.contains(System.lineSeparator()));
        Files.writeString(worker, workerText, StandardCharsets.UTF_8);
        Files.writeString(wrapper, wrapperText, StandardCharsets.UTF_8);
        assertPowerShellParses(worker);
        assertPowerShellParses(wrapper);

        Path legacyWorker = directory.resolve("legacy-worker.ps1");
        Path legacyWrapper = directory.resolve("legacy-wrapper.ps1");
        String legacyWorkerText = WchIspRunner.workerScriptForTests();
        String legacyWrapperText = WchIspRunner.wrapperScriptForTests();
        assertFalse(legacyWorkerText.contains(literalBacktickN));
        assertFalse(legacyWrapperText.contains(literalBacktickN));
        Files.writeString(legacyWorker, legacyWorkerText, StandardCharsets.UTF_8);
        Files.writeString(legacyWrapper, legacyWrapperText, StandardCharsets.UTF_8);
        assertPowerShellParses(legacyWorker);
        assertPowerShellParses(legacyWrapper);
    }

    @Test
    void invalidGeneratedScriptIsRejectedWithDedicatedReason() {
        String invalid = "param()" + String.valueOf((char) 96) + "n$broken=";
        IOException failure = assertThrows(IOException.class,
            () -> WchIspRunner.validateGeneratedScriptTextForTests(invalid));
        assertEquals("ELEVATED_WORKER_SCRIPT_INVALID", failure.getMessage());
    }

    @Test
    void preparationReadyFailureReasonsAreDistinct() {
        assertEquals("UAC_CANCELLED",
            WchIspRunner.preparationFailureReasonForTests(1223, false));
        assertEquals("ELEVATED_WORKER_START_FAILED",
            WchIspRunner.preparationFailureReasonForTests(1, false));
        assertEquals("ELEVATED_WORKER_NOT_READY",
            WchIspRunner.preparationFailureReasonForTests(-1, true));
    }

    private static void assertPowerShellParses(Path script) throws Exception {
        String shell = System.getProperty("os.name", "")
            .toLowerCase(Locale.ROOT).contains("win") ? "powershell.exe" : "pwsh";
        String path = script.toString().replace("'", "''");
        String command = "$tokens=$null;$errors=$null;"
            + "[System.Management.Automation.Language.Parser]::ParseFile('"
            + path + "',[ref]$tokens,[ref]$errors)|Out-Null;"
            + "if($errors.Count -gt 0){$errors|ForEach-Object{$_.Message};exit 1};exit 0";
        Process process = new ProcessBuilder(shell, "-NoProfile", "-NonInteractive",
            "-Command", command).redirectErrorStream(true).start();
        String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        assertTrue(process.waitFor(10, TimeUnit.SECONDS), "PowerShell parser timed out");
        assertEquals(0, process.exitValue(), output);
    }

    private static final class AtomicFlags {
        boolean prepared;
        boolean launched;
        boolean cancelled;
    }
}
