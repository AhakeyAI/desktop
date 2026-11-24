package com.example.ahakey.diagnostics;

import static com.example.ahakey.util.LanguageManager.text;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.BleTcpPacket;
import org.junit.jupiter.api.Test;

import java.io.InputStreamReader;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Properties;

class ConnectionLogTest {
    private static final byte[] STATUS_QUERY = {(byte) 0xAA, (byte) 0xBB, 0x00, (byte) 0xCC, (byte) 0xDD};
    private static final byte[] CAPABILITY_QUERY = {(byte) 0xAA, (byte) 0xBB, (byte) 0x9F, (byte) 0xCC, (byte) 0xDD};

    @Test void frameCommandReadsTheByteAfterTheHeader() {
        assertEquals(AhaKeyProtocol.CMD_QUERY_STATUS, ConnectionLog.frameCommand(STATUS_QUERY));
        assertEquals(AhaKeyProtocol.CMD_QUERY_CAPABILITIES, ConnectionLog.frameCommand(CAPABILITY_QUERY));
        assertNull(ConnectionLog.frameCommand(new byte[] {(byte) 0xAA, (byte) 0xBB}));
        assertNull(ConnectionLog.frameCommand(new byte[] {0x01, 0x02, 0x03}));
        assertNull(ConnectionLog.frameCommand(new byte[0]));
    }

    @Test void everyProtocolCommandHasAName() throws Exception {
        List<Byte> missing = new ArrayList<>();
        for (Field field : AhaKeyProtocol.class.getFields()) {
            if (field.getName().startsWith("CMD_") && field.getType() == byte.class
                && Modifier.isStatic(field.getModifiers())) {
                byte command = field.getByte(null);
                if (!ConnectionLog.COMMAND_KEYS.containsKey(command)) missing.add(command);
            }
        }
        assertTrue(missing.isEmpty(), "commands without a connection-log name: " + missing);
    }

    @Test void commandAndPacketTypeKeysExistInEveryCatalog() throws Exception {
        List<String> keys = new ArrayList<>(ConnectionLog.COMMAND_KEYS.values());
        keys.addAll(ConnectionLog.TCP_TYPE_KEYS.values());
        for (String language : List.of("en", "ru", "zh")) {
            Properties catalog = catalog(language);
            for (String key : keys) assertNotNull(catalog.getProperty(key), language + ": " + key);
        }
    }

    @Test void describeNamesDirectionPacketTypeCommandAndLength() {
        String sent = ConnectionLog.describe("BLE", BleTcpPacket.WRITE_COMMAND, CAPABILITY_QUERY, true);
        assertEquals(text("connection-log.frame.sent") + " · " + text("connection-log.tcp.write-command")
            + " · " + text("connection-log.command.query-capabilities") + " (0x9F) · "
            + text("connection-log.frame.bytes", 5), sent);

        String received = ConnectionLog.describe("USB", BleTcpPacket.BLE_NOTIFY, STATUS_QUERY, false);
        assertTrue(received.startsWith(text("connection-log.frame.received") + " · "), received);
        assertFalse(received.contains(text("connection-log.tcp.ble-notify")), "USB frames have no TCP type");
        assertTrue(received.contains("(0x00)"), received);
    }

    @Test void describeFallsBackForUnknownTypesAndCommands() {
        byte[] unknown = {(byte) 0xAA, (byte) 0xBB, (byte) 0xEE};
        String line = ConnectionLog.describe("BLE", (byte) 0x7E, unknown, true);
        assertTrue(line.contains("TCP 0x7E"), line);
        assertTrue(line.contains(text("connection-log.command.unknown") + " (0xEE)"), line);
        String empty = ConnectionLog.describe("BLE", BleTcpPacket.QUERY_BLE_STATUS, null, true);
        assertTrue(empty.endsWith(text("connection-log.frame.bytes", 0)), empty);
    }

    @Test void statusPollDetectionOnlyMatchesStatusQueryFrames() {
        assertTrue(ConnectionLog.isStatusPoll(frame(ConnectionLog.Source.TX, STATUS_QUERY)));
        assertTrue(ConnectionLog.isStatusPoll(frame(ConnectionLog.Source.RX, STATUS_QUERY)));
        assertFalse(ConnectionLog.isStatusPoll(frame(ConnectionLog.Source.TX, CAPABILITY_QUERY)));
        assertFalse(ConnectionLog.isStatusPoll(new ConnectionLog.Entry(Instant.now(),
            ConnectionLog.Source.APP, ConnectionLog.Level.INFO, "", "x", STATUS_QUERY)));
        assertFalse(ConnectionLog.isStatusPoll(frame(ConnectionLog.Source.RX, null)));
    }

    @Test void formatAndHexKeepOneLinePerEntry() {
        assertEquals("AA BB 00 CC DD", ConnectionLog.hex(STATUS_QUERY));
        assertEquals("", ConnectionLog.hex(new byte[0]));
        String line = ConnectionLog.format(new ConnectionLog.Entry(Instant.EPOCH, ConnectionLog.Source.TX,
            ConnectionLog.Level.DEBUG, "USB", "first\r\nsecond", STATUS_QUERY));
        assertFalse(line.contains("\n"), line);
        assertTrue(line.contains(" TX DEBUG USB first | second | AA BB 00 CC DD"), line);
    }

    @Test void entriesDefaultToGeneralAndEventsKeepTheirCategory() {
        var plain = new ConnectionLog.Entry(Instant.now(), ConnectionLog.Source.APP,
            ConnectionLog.Level.WARN, null, null, null);
        assertEquals(ConnectionLog.Category.GENERAL, plain.category());
        assertFalse(plain.isConnectionChange());
        assertEquals("", plain.transport());
        assertEquals("", plain.message());

        ConnectionLog.event(ConnectionLog.Level.WARN, ConnectionLog.Category.DISCONNECTED, "test-disconnect");
        var snapshot = ConnectionLog.get().snapshot();
        var last = snapshot.get(snapshot.size() - 1);
        assertEquals("test-disconnect", last.message());
        assertEquals(ConnectionLog.Category.DISCONNECTED, last.category());
        assertTrue(last.isConnectionChange());
    }

    private static ConnectionLog.Entry frame(ConnectionLog.Source source, byte[] raw) {
        return new ConnectionLog.Entry(Instant.now(), source, ConnectionLog.Level.DEBUG, "BLE", "frame", raw);
    }

    private Properties catalog(String language) throws Exception {
        Properties properties = new Properties();
        try (var reader = new InputStreamReader(Objects.requireNonNull(
            getClass().getResourceAsStream("/messages_" + language + ".properties")), StandardCharsets.UTF_8)) {
            properties.load(reader);
        }
        return properties;
    }
}
