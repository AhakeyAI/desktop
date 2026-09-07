package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

class WchIspResultParserTest {
    private static final UUID ID = UUID.randomUUID();

    @Test
    void uidRequiresARealDeviceUidLine() {
        var result = WchIspResultParser.parseUid(raw(0, false,
            "Device UID:23-DF-93-5A-04-DC-BA-15", ""));
        assertTrue(result.success());
        assertEquals("23-DF-93-5A-04-DC-BA-15", result.deviceUid());
    }

    @Test
    void exitZeroWithoutUidFailsClosed() {
        var result = WchIspResultParser.parseUid(raw(0, false, "Finished", ""));
        assertFalse(result.success());
        assertEquals(FirmwareUpdateError.UID_QUERY_FAILED, result.error());
    }

    @Test
    void exit100IsDistinctFromPnpPresence() {
        var result = WchIspResultParser.parseUid(raw(100, false, "", ""));
        assertEquals(FirmwareUpdateError.UID_EXIT_100, result.error());
    }

    @Test
    void flashRequiresFinishedCodeZeroAndSucceed() {
        var success = WchIspResultParser.parseFlash(raw(0, false,
            "{\"Status\":\"Finished\",\"Code\":0,\"Message\":\"Succeed\"}", ""));
        assertTrue(success.success());

        var progressOnly = WchIspResultParser.parseFlash(raw(0, false,
            "{\"Status\":\"Programming\",\"Progress\":100%}", ""));
        assertFalse(progressOnly.success());
        assertEquals(FirmwareUpdateError.FLASH_FAILED, progressOnly.error());
    }

    @Test
    void timeoutAndCancellationAreStructured() {
        var timeout = WchIspResultParser.parseFlash(raw(124, true, "", ""));
        assertEquals(FirmwareUpdateError.PROCESS_TIMEOUT, timeout.error());
        var cancelled = WchIspResultParser.parseUid(raw(1, false, "", "", true));
        assertEquals(FirmwareUpdateError.CANCELLED, cancelled.error());
    }

    private static WchIspRunner.WchIspProcessResult raw(int exit, boolean timedOut,
                                                          String stdout, String stderr) {
        return raw(exit, timedOut, stdout, stderr, false);
    }

    private static WchIspRunner.WchIspProcessResult raw(int exit, boolean timedOut,
                                                          String stdout, String stderr,
                                                          boolean cancelled) {
        return new WchIspRunner.WchIspProcessResult(ID, true, 42, exit, timedOut,
            cancelled, stdout, stderr, stdout, Duration.ZERO, false, Map.of(), "");
    }
}
