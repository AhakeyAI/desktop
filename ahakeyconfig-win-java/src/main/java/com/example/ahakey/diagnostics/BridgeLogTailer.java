package com.example.ahakey.diagnostics;

import static com.example.ahakey.util.LanguageManager.text;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;

/**
 * Follows the BLE driver's daily log file (written by BLE_tcp_driver.exe into the
 * same folder) so the connection log window shows Windows Bluetooth events too.
 * Line format: {@code yyyy-MM-dd HH:mm:ss.fff LEVEL message}.
 */
final class BridgeLogTailer {
    /** Markers the driver writes in English for WinRT connection state changes. */
    private static final String STATUS_DISCONNECTED = "ConnectionStatus changed: Disconnected";
    private static final String STATUS_CONNECTED = "ConnectionStatus changed: Connected";

    private BridgeLogTailer() {}

    static void start() {
        Thread thread = new Thread(BridgeLogTailer::run, "ble-driver-log-tail");
        thread.setDaemon(true);
        thread.start();
    }

    static Path todayFile() {
        return ConnectionLog.logDirectory().resolve("ble-driver-" + LocalDate.now() + ".log");
    }

    private static void run() {
        Path current = null;
        long position = 0;
        boolean first = true;
        while (!Thread.currentThread().isInterrupted()) {
            try {
                Path file = todayFile();
                if (!file.equals(current)) {
                    current = file;
                    // Lines written before this app started are history: show the last part only.
                    position = first && Files.exists(file) ? Math.max(0, Files.size(file) - 64 * 1024) : 0;
                    first = false;
                }
                if (Files.exists(file)) {
                    long size = Files.size(file);
                    if (size < position) position = 0;
                    if (size > position) position = readFrom(file, position);
                }
                Thread.sleep(500);
            } catch (InterruptedException e) {
                return;
            } catch (IOException ignored) {
                // The driver may hold the file briefly; try again on the next tick.
            }
        }
    }

    private static long readFrom(Path file, long position) throws IOException {
        try (RandomAccessFile in = new RandomAccessFile(file.toFile(), "r")) {
            in.seek(position);
            byte[] bytes = new byte[(int) Math.min(in.length() - position, 1 << 20)];
            in.readFully(bytes);
            int end = lastNewline(bytes);
            if (end < 0) return position;
            String chunk = new String(bytes, 0, end + 1, StandardCharsets.UTF_8);
            for (String line : chunk.split("\r?\n")) {
                if (!line.isBlank()) ConnectionLog.get().add(parse(line));
            }
            return position + end + 1;
        }
    }

    private static int lastNewline(byte[] bytes) {
        for (int i = bytes.length - 1; i >= 0; i--) if (bytes[i] == '\n') return i;
        return -1;
    }

    /** Parses one driver log line; lines in another shape are kept whole at INFO level. */
    static ConnectionLog.Entry parse(String line) {
        String message = line;
        ConnectionLog.Level level = ConnectionLog.Level.INFO;
        Instant time = Instant.now();
        String[] parts = line.split(" ", 4);
        if (parts.length == 4 && parts[0].length() == 10) {
            try {
                time = LocalDateTime.parse(parts[0] + "T" + parts[1])
                    .atZone(ZoneId.systemDefault()).toInstant();
                level = switch (parts[2]) {
                    case "ERROR" -> ConnectionLog.Level.ERROR;
                    case "WARN" -> ConnectionLog.Level.WARN;
                    case "DEBUG" -> ConnectionLog.Level.DEBUG;
                    default -> ConnectionLog.Level.INFO;
                };
                message = parts[3];
            } catch (DateTimeParseException ignored) {
                // Not a driver line: keep the read time and the whole text.
            }
        }
        return new ConnectionLog.Entry(time, ConnectionLog.Source.BRIDGE, level,
            text("connection-log.tag.driver"), message, null, category(message));
    }

    static ConnectionLog.Category category(String message) {
        if (message.contains(STATUS_DISCONNECTED)) return ConnectionLog.Category.DISCONNECTED;
        if (message.contains(STATUS_CONNECTED)) return ConnectionLog.Category.CONNECTED;
        return ConnectionLog.Category.GENERAL;
    }
}
