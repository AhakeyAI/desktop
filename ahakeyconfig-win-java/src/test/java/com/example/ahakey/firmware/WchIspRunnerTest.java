package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

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

    private static final class AtomicFlags {
        boolean prepared;
        boolean launched;
        boolean cancelled;
    }
}
