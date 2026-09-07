package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
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
}
