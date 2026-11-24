package com.example.ahakey.diagnostics;

import static com.example.ahakey.util.LanguageManager.text;

import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.BleTcpPacket;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.Consumer;
import java.util.function.Supplier;

/**
 * Connection diagnostics for the BLE/USB path: app log lines, raw frames sent to and
 * received from the keyboard, and the BLE driver's own log. Kept in memory for the
 * connection log window and appended to a daily file so earlier sessions stay readable.
 */
public final class ConnectionLog {
    public enum Source { APP, BRIDGE, TX, RX }
    public enum Level { DEBUG, INFO, WARN, ERROR }

    /**
     * Connection state changes are tagged explicitly so the window can count and
     * highlight them without matching words of any particular language.
     */
    public enum Category { GENERAL, CONNECTED, DISCONNECTED }

    public record Entry(Instant time, Source source, Level level, String transport,
                        String message, byte[] raw, Category category) {
        public Entry {
            transport = transport == null ? "" : transport;
            message = message == null ? "" : message;
            category = category == null ? Category.GENERAL : category;
        }

        public Entry(Instant time, Source source, Level level, String transport,
                     String message, byte[] raw) {
            this(time, source, level, transport, message, raw, Category.GENERAL);
        }

        public boolean isFrame() { return source == Source.TX || source == Source.RX; }

        public boolean isConnectionChange() { return category != Category.GENERAL; }
    }

    private static final int CAPACITY = 20_000;
    private static final DateTimeFormatter FILE_TIME =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS").withZone(ZoneId.systemDefault());
    private static final ConnectionLog INSTANCE = new ConnectionLog();

    private final ArrayDeque<Entry> entries = new ArrayDeque<>();
    private final List<Consumer<Entry>> listeners = new CopyOnWriteArrayList<>();
    private BufferedWriter writer;
    private LocalDate writerDate;
    private volatile boolean started;
    private static volatile Supplier<String> statusProvider = () -> "";

    private ConnectionLog() {}

    public static ConnectionLog get() { return INSTANCE; }

    /** Starts the logback capture, the daily file and the BLE driver log tail once per process. */
    public static synchronized void start() {
        if (INSTANCE.started) return;
        INSTANCE.started = true;
        LogbackCapture.install();
        BridgeLogTailer.start();
    }

    public static void setStatusProvider(Supplier<String> provider) {
        statusProvider = provider == null ? () -> "" : provider;
    }

    public static String statusSummary() {
        try {
            String summary = statusProvider.get();
            return summary == null ? "" : summary;
        } catch (RuntimeException e) {
            return "";
        }
    }

    /** Folder of the daily connection log files (shared with the BLE driver). */
    public static Path logDirectory() {
        String localAppData = System.getenv("LOCALAPPDATA");
        Path base = localAppData != null && !localAppData.isBlank()
            ? Path.of(localAppData, "AhaKeyStudio")
            : Path.of(System.getProperty("user.home"), ".ahakey");
        return base.resolve("logs");
    }

    public static Path todayFile() {
        return logDirectory().resolve("connection-" + LocalDate.now() + ".log");
    }

    public static void tx(String transport, byte tcpType, byte[] data) {
        INSTANCE.add(new Entry(Instant.now(), Source.TX, Level.DEBUG, transport,
            describe(transport, tcpType, data, true), copy(data)));
    }

    public static void rx(String transport, byte tcpType, byte[] data) {
        INSTANCE.add(new Entry(Instant.now(), Source.RX, Level.DEBUG, transport,
            describe(transport, tcpType, data, false), copy(data)));
    }

    public static void event(Level level, String message) {
        event(level, Category.GENERAL, message);
    }

    public static void event(Level level, Category category, String message) {
        INSTANCE.add(new Entry(Instant.now(), Source.APP, level, "", message, null, category));
    }

    void add(Entry entry) {
        synchronized (entries) {
            if (entries.size() >= CAPACITY) entries.removeFirst();
            entries.addLast(entry);
            writeToFile(entry);
        }
        for (Consumer<Entry> listener : listeners) {
            try { listener.accept(entry); } catch (RuntimeException ignored) { }
        }
    }

    public List<Entry> snapshot() {
        synchronized (entries) { return new ArrayList<>(entries); }
    }

    public void clear() {
        synchronized (entries) { entries.clear(); }
    }

    public void addListener(Consumer<Entry> listener) { listeners.add(listener); }

    public void removeListener(Consumer<Entry> listener) { listeners.remove(listener); }

    /** One line per entry, as written to the daily file and copied from the window. */
    public static String format(Entry entry) {
        StringBuilder line = new StringBuilder(FILE_TIME.format(entry.time()))
            .append(' ').append(entry.source()).append(' ').append(entry.level());
        if (!entry.transport().isEmpty()) line.append(' ').append(entry.transport());
        line.append(' ').append(entry.message().replace("\r", "").replace("\n", " | "));
        if (entry.raw() != null) line.append(" | ").append(hex(entry.raw()));
        return line.toString();
    }

    private void writeToFile(Entry entry) {
        // The BLE driver writes its own file; repeating its lines here would double them.
        if (entry.source() == Source.BRIDGE || !started) return;
        try {
            LocalDate today = LocalDate.now();
            if (writer == null || !today.equals(writerDate)) {
                if (writer != null) writer.close();
                Files.createDirectories(logDirectory());
                writer = Files.newBufferedWriter(todayFile(), StandardCharsets.UTF_8,
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND);
                writerDate = today;
            }
            writer.write(format(entry));
            writer.newLine();
            writer.flush();
        } catch (IOException ignored) {
            writer = null;
        }
    }

    // ------------------------------------------------------------------ decoding

    /** Resource keys of the TCP packet types exchanged with the BLE driver. */
    static final Map<Byte, String> TCP_TYPE_KEYS = Map.of(
        BleTcpPacket.WRITE_DATA, "connection-log.tcp.write-data",
        BleTcpPacket.WRITE_COMMAND, "connection-log.tcp.write-command",
        BleTcpPacket.QUERY_BLE_STATUS, "connection-log.tcp.query-ble-status",
        BleTcpPacket.QUERY_DEVICE_INFO, "connection-log.tcp.query-device-info",
        BleTcpPacket.BLE_NOTIFY, "connection-log.tcp.ble-notify",
        BleTcpPacket.BLE_STATUS_RESP, "connection-log.tcp.ble-status-response",
        BleTcpPacket.DEVICE_INFO_RESP, "connection-log.tcp.device-info-response");

    /** Resource keys of the keyboard commands carried in {@code AA BB cmd ... CC DD} frames. */
    static final Map<Byte, String> COMMAND_KEYS = Map.ofEntries(
        Map.entry(AhaKeyProtocol.CMD_QUERY_STATUS, "connection-log.command.query-status"),
        Map.entry(AhaKeyProtocol.CMD_CHANGE_NAME, "connection-log.command.change-name"),
        Map.entry(AhaKeyProtocol.CMD_CHANGE_APPEARANCE, "connection-log.command.change-appearance"),
        Map.entry(AhaKeyProtocol.CMD_SAVE_CONFIG, "connection-log.command.save-config"),
        Map.entry(AhaKeyProtocol.CMD_UPDATE_CUSTOM_KEY, "connection-log.command.update-custom-key"),
        Map.entry(AhaKeyProtocol.CMD_PREPARE_WRITE, "connection-log.command.prepare-write"),
        Map.entry(AhaKeyProtocol.CMD_WRITE_RESULT, "connection-log.command.write-result"),
        Map.entry(AhaKeyProtocol.CMD_UPDATE_PIC, "connection-log.command.update-pic"),
        Map.entry(AhaKeyProtocol.CMD_READ_PIC_STATE, "connection-log.command.read-pic-state"),
        Map.entry(AhaKeyProtocol.CMD_SET_AI_LIGHT_CONFIG, "connection-log.command.set-ai-light-config"),
        Map.entry(AhaKeyProtocol.CMD_SET_LIGHT_BRIGHTNESS, "connection-log.command.set-light-brightness"),
        Map.entry(AhaKeyProtocol.CMD_LEGACY_CONFLICT, "connection-log.command.legacy"),
        Map.entry(AhaKeyProtocol.CMD_UPDATE_STATE, "connection-log.command.update-state"),
        Map.entry(AhaKeyProtocol.CMD_SET_LIGHT_EFFECT, "connection-log.command.set-light-effect"),
        Map.entry(AhaKeyProtocol.CMD_SET_WORK_MODE, "connection-log.command.set-work-mode"),
        Map.entry(AhaKeyProtocol.CMD_SET_AI_OLED_CONFIG, "connection-log.command.set-ai-oled-config"),
        Map.entry(AhaKeyProtocol.CMD_READ_AI_OLED_CONFIG, "connection-log.command.read-ai-oled-config"),
        Map.entry(AhaKeyProtocol.CMD_STANDBY_TIMEOUT, "connection-log.command.standby-timeout"),
        Map.entry(AhaKeyProtocol.CMD_FACTORY_RESET, "connection-log.command.factory-reset"),
        Map.entry(AhaKeyProtocol.CMD_VOICE_KEY_CONFIG, "connection-log.command.voice-key-config"),
        Map.entry(AhaKeyProtocol.CMD_TASK_LIGHT_MODE, "connection-log.command.task-light-mode"),
        Map.entry(AhaKeyProtocol.CMD_TASK_SLOT_UPDATE, "connection-log.command.task-slot-update"),
        Map.entry(AhaKeyProtocol.CMD_TASK_HEARTBEAT, "connection-log.command.task-heartbeat"),
        Map.entry(AhaKeyProtocol.CMD_MODE_SYNC, "connection-log.command.mode-sync"),
        Map.entry(AhaKeyProtocol.CMD_GIF_LAYOUT, "connection-log.command.gif-layout"),
        Map.entry(AhaKeyProtocol.CMD_CONFIG_QUERY, "connection-log.command.config-query"),
        Map.entry(AhaKeyProtocol.CMD_QUERY_CAPABILITIES, "connection-log.command.query-capabilities"));

    /** True for frames sent or received by the periodic status poll. */
    public static boolean isStatusPoll(Entry entry) {
        if (!entry.isFrame() || entry.raw() == null) return false;
        Byte command = frameCommand(entry.raw());
        return command != null && command == AhaKeyProtocol.CMD_QUERY_STATUS;
    }

    static String describe(String transport, byte tcpType, byte[] data, boolean outgoing) {
        StringBuilder out = new StringBuilder(outgoing
            ? text("connection-log.frame.sent") : text("connection-log.frame.received"));
        if ("BLE".equals(transport)) {
            String typeKey = TCP_TYPE_KEYS.get(tcpType);
            out.append(" · ").append(typeKey != null
                ? text(typeKey) : String.format("TCP 0x%02X", tcpType & 0xFF));
        }
        Byte command = data == null ? null : frameCommand(data);
        if (command != null) {
            String commandKey = COMMAND_KEYS.get(command);
            out.append(" · ").append(commandKey != null
                    ? text(commandKey) : text("connection-log.command.unknown"))
                .append(String.format(" (0x%02X)", command & 0xFF));
        }
        out.append(" · ").append(text("connection-log.frame.bytes", data == null ? 0 : data.length));
        return out.toString();
    }

    /** Command byte of an {@code AA BB cmd ... CC DD} frame, or null. */
    static Byte frameCommand(byte[] data) {
        if (data.length >= 3 && (data[0] & 0xFF) == 0xAA && (data[1] & 0xFF) == 0xBB) return data[2];
        return null;
    }

    public static String hex(byte[] data) {
        StringBuilder out = new StringBuilder(data.length * 3);
        for (int i = 0; i < data.length; i++) {
            if (i > 0) out.append(' ');
            out.append(String.format("%02X", data[i] & 0xFF));
        }
        return out.toString();
    }

    private static byte[] copy(byte[] data) {
        return data == null ? new byte[0] : data.clone();
    }
}
