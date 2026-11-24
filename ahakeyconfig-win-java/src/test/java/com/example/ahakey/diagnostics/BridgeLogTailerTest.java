package com.example.ahakey.diagnostics;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.time.ZoneId;

class BridgeLogTailerTest {
    @Test void parsesTimestampLevelAndMessage() {
        var entry = BridgeLogTailer.parse("2026-11-24 13:05:07.123 WARN [TCP] TCP客户端已断开: 127.0.0.1:9000");
        assertEquals(ConnectionLog.Source.BRIDGE, entry.source());
        assertEquals(ConnectionLog.Level.WARN, entry.level());
        assertEquals("[TCP] TCP客户端已断开: 127.0.0.1:9000", entry.message());
        assertEquals(LocalDateTime.of(2026, 11, 24, 13, 5, 7, 123_000_000)
            .atZone(ZoneId.systemDefault()).toInstant(), entry.time());
        assertEquals(ConnectionLog.Category.GENERAL, entry.category());
    }

    @Test void mapsEveryDriverLevel() {
        assertEquals(ConnectionLog.Level.ERROR, BridgeLogTailer.parse("2026-11-24 13:05:07.123 ERROR x").level());
        assertEquals(ConnectionLog.Level.DEBUG, BridgeLogTailer.parse("2026-11-24 13:05:07.123 DEBUG x").level());
        assertEquals(ConnectionLog.Level.INFO, BridgeLogTailer.parse("2026-11-24 13:05:07.123 INFO x").level());
        assertEquals(ConnectionLog.Level.INFO, BridgeLogTailer.parse("2026-11-24 13:05:07.123 TRACE x").level());
    }

    @Test void keepsLinesInAnotherShapeWhole() {
        var entry = BridgeLogTailer.parse("not a driver line at all");
        assertEquals(ConnectionLog.Level.INFO, entry.level());
        assertEquals("not a driver line at all", entry.message());

        var badDate = BridgeLogTailer.parse("2026-13-99 25:00:00.000 ERROR broken");
        assertEquals(ConnectionLog.Level.INFO, badDate.level());
        assertEquals("2026-13-99 25:00:00.000 ERROR broken", badDate.message());
    }

    @Test void marksWinRtConnectionStatusChanges() {
        var dropped = BridgeLogTailer.parse("2026-11-24 13:05:07.123 WARN [BLE] ConnectionStatus changed: "
            + "Disconnected (5321ms after connect) address: 0x0000AABBCCDD");
        assertEquals(ConnectionLog.Category.DISCONNECTED, dropped.category());
        assertTrue(dropped.isConnectionChange());

        var connected = BridgeLogTailer.parse("2026-11-24 13:05:08.000 INFO [BLE] ConnectionStatus changed: "
            + "Connected (12ms after connect) address: 0x0000AABBCCDD");
        assertEquals(ConnectionLog.Category.CONNECTED, connected.category());

        var session = BridgeLogTailer.parse("2026-11-24 13:05:07.200 WARN [BLE] SessionStatus changed: Closed");
        assertEquals(ConnectionLog.Category.GENERAL, session.category());
        assertEquals(ConnectionLog.Level.WARN, session.level());
    }
}
