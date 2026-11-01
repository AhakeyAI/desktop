package com.example.ahakey.service;

import com.example.ahakey.model.AiRuntimeSession;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Statement;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;

public class CursorSessionDiscoveryService {
    private static final Logger logger = LoggerFactory.getLogger(CursorSessionDiscoveryService.class);
    private static final int MAX_SCAN_FILES = 80;
    // Installed source verified: 3.27.22 additionally propagates child user waits to the exact parent header.
    private static final Set<String> WAITING_SCHEMA_VERSIONS = Set.of("3.14.7", "3.27.22");
    private final ObjectMapper mapper = new ObjectMapper();

    public enum Waiting { WAITING, NOT_WAITING, UNKNOWN }
    public record WaitingState(Waiting state, String reason, String generation) {
        public WaitingState(Waiting state, String reason) { this(state, reason, ""); }
    }
    public record CursorProcess(String generation, String version) {
        public boolean supported() { return !generation.isBlank() && WAITING_SCHEMA_VERSIONS.contains(version); }
    }

    /** Windows ProcessHandle.info().command() can be absent even for same-user processes.
     * Toolhelp + QUERY_LIMITED_INFORMATION reads only executable identity and creation time.
     */
    public CursorProcess runningCursor() {
        if (!System.getProperty("os.name", "").startsWith("Windows")) return new CursorProcess("", "");
        try {
            var kernel = com.sun.jna.platform.win32.Kernel32.INSTANCE;
            var snapshot = kernel.CreateToolhelp32Snapshot(com.sun.jna.platform.win32.Tlhelp32.TH32CS_SNAPPROCESS,
                new com.sun.jna.platform.win32.WinDef.DWORD(0));
            if (snapshot == null || com.sun.jna.platform.win32.WinBase.INVALID_HANDLE_VALUE.equals(snapshot))
                return new CursorProcess("", "");
            Map<Integer, Integer> cursorParents = new HashMap<>();
            try {
                var entry = new com.sun.jna.platform.win32.Tlhelp32.PROCESSENTRY32();
                boolean available = kernel.Process32First(snapshot, entry);
                int count = 0;
                while (available) {
                    if (++count > 65536) return new CursorProcess("", "");
                    if ("Cursor.exe".equalsIgnoreCase(com.sun.jna.Native.toString(entry.szExeFile)))
                        cursorParents.put(entry.th32ProcessID.intValue(), entry.th32ParentProcessID.intValue());
                    available = kernel.Process32Next(snapshot, entry);
                }
            } finally { kernel.CloseHandle(snapshot); }
            List<Integer> roots = cursorParents.keySet().stream()
                .filter(pid -> !cursorParents.containsKey(cursorParents.get(pid))).toList();
            if (roots.size() != 1) return new CursorProcess("", "");
            int pid = roots.get(0);
            var process = kernel.OpenProcess(0x1000, false, pid); // PROCESS_QUERY_LIMITED_INFORMATION
            if (process == null) return new CursorProcess("", "");
            try {
                char[] path = new char[32768];
                var length = new com.sun.jna.ptr.IntByReference(path.length);
                var created = new com.sun.jna.platform.win32.WinBase.FILETIME();
                if (!kernel.QueryFullProcessImageName(process, 0, path, length)
                        || !kernel.GetProcessTimes(process, created, new com.sun.jna.platform.win32.WinBase.FILETIME(),
                            new com.sun.jna.platform.win32.WinBase.FILETIME(), new com.sun.jna.platform.win32.WinBase.FILETIME()))
                    return new CursorProcess("", "");
                Path executable = Path.of(new String(path, 0, length.getValue())).toRealPath();
                if (!"Cursor.exe".equalsIgnoreCase(executable.getFileName().toString())) return new CursorProcess("", "");
                JsonNode identity = mapper.readTree(executable.getParent().resolve("resources/app/package.json").toFile());
                if (!"Cursor".equals(text(identity, "name"))) return new CursorProcess("", "");
                String started = Integer.toUnsignedString(created.dwHighDateTime) + ":" + Integer.toUnsignedString(created.dwLowDateTime);
                return new CursorProcess(pid + ":" + started + ":" + executable, text(identity, "version"));
            } finally { kernel.CloseHandle(process); }
        } catch (Exception | LinkageError e) { return new CursorProcess("", ""); }
    }

    /** Raw observation, not proof of a live wait. The runtime service supplies process/Hook/epoch guards.
     * Only the canonical global header table is supported; old ItemTable discovery is not a live source.
     */
    public Map<String, WaitingState> readWaitingStates(Path dataDir, Set<String> composerIds, String cursorVersion) {
        return readWaitingStates(dataDir, composerIds, cursorVersion, false);
    }

    public Map<String, WaitingState> readRuntimeStates(Path dataDir, Set<String> composerIds, String cursorVersion) {
        return readWaitingStates(dataDir, composerIds, cursorVersion, true);
    }

    private Map<String, WaitingState> readWaitingStates(Path dataDir, Set<String> composerIds, String cursorVersion,
                                                       boolean requireGeneration) {
        Map<String, WaitingState> result = new HashMap<>();
        for (String id : composerIds) result.put(id, new WaitingState(Waiting.UNKNOWN, "unavailable"));
        if (!WAITING_SCHEMA_VERSIONS.contains(cursorVersion)
                || (requireGeneration && !"3.27.22".equals(cursorVersion))) {
            result.replaceAll((id, value) -> new WaitingState(Waiting.UNKNOWN, "unsupported-version"));
            return Map.copyOf(result);
        }
        if (dataDir == null || composerIds.isEmpty() || composerIds.size() > 4) return Map.copyOf(result);
        Path db = dataDir.resolve("globalStorage/state.vscdb");
        try (Connection connection = openReadOnly(db)) {
            // Bound VM work as well as lock waits. SQLite busy_timeout alone is not a query deadline.
            long deadline = System.nanoTime() + java.util.concurrent.TimeUnit.MILLISECONDS.toNanos(250);
            org.sqlite.ProgressHandler.setHandler(connection, 1000, new org.sqlite.ProgressHandler() {
                @Override protected int progress() {
                    return Thread.currentThread().isInterrupted() || System.nanoTime() >= deadline ? 1 : 0;
                }
            });
            // A read transaction is consistent, but independently saved header/identity rows may lag.
            connection.setAutoCommit(false);
            try (var statement = connection.prepareStatement(
                    "select composerId,isArchived,isSubagent,value from composerHeaders where composerId=? limit 2")) {
                statement.setQueryTimeout(1);
                for (String id : composerIds) {
                    if (id == null || id.isBlank() || id.length() > 128) continue;
                    statement.setString(1, id);
                    try (ResultSet rs = statement.executeQuery()) {
                        if (!rs.next()) { result.put(id, new WaitingState(Waiting.UNKNOWN, "missing-header")); continue; }
                        Object archived = rs.getObject("isArchived"), subagent = rs.getObject("isSubagent");
                        String value = rs.getString("value");
                        WaitingState state = new WaitingState(Waiting.UNKNOWN, "invalid-header");
                        if (Integer.valueOf(0).equals(archived) && Integer.valueOf(0).equals(subagent)
                                && value != null && value.length() <= 262144) {
                            try {
                            JsonNode header = mapper.reader().with(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_TRAILING_TOKENS)
                                .with(com.fasterxml.jackson.core.JsonParser.Feature.STRICT_DUPLICATE_DETECTION).readTree(value);
                            JsonNode pending = header == null ? null : header.get("hasBlockingPendingActions");
                            if (header != null && header.isObject() && header.path("composerId").isTextual()
                                    && id.equals(header.path("composerId").textValue())
                                    && absentOrFalse(header, "isArchived") && absentOrFalse(header, "archived")
                                    && absentOrFalse(header, "isSubAgent") && absentOrFalse(header, "isSubagent")
                                    && !header.hasNonNull("subagentInfo")
                                    && pending != null && pending.isBoolean()) {
                                state = new WaitingState(pending.booleanValue() ? Waiting.WAITING : Waiting.NOT_WAITING, "header-boolean");
                            }
                            } catch (com.fasterxml.jackson.core.JsonProcessingException ignored) {
                                state = new WaitingState(Waiting.UNKNOWN, "invalid-json");
                            }
                        }
                        if (rs.next()) state = new WaitingState(Waiting.UNKNOWN, "duplicate-header");
                        result.put(id, state);
                    }
                }
            }
            if (requireGeneration) {
                for (String id : composerIds) {
                    WaitingState waiting = result.get(id);
                    if (waiting.state() == Waiting.UNKNOWN) continue;
                    try {
                        String generation = readGeneration(connection, id);
                        result.put(id, generation.isEmpty() ? new WaitingState(Waiting.UNKNOWN, "unconfirmed-generation")
                                : new WaitingState(waiting.state(), waiting.reason(), generation));
                    } catch (java.sql.SQLException invalidIdentity) {
                        result.put(id, new WaitingState(Waiting.UNKNOWN, "identity-read-failed"));
                    }
                }
            }
            connection.rollback();
        } catch (Exception e) {
            // Do not expose paths, headers or SQLite errors containing user data in logs.
            result.replaceAll((id, value) -> new WaitingState(Waiting.UNKNOWN, "read-failed"));
        }
        return Map.copyOf(result);
    }

    private String readGeneration(Connection connection, String id) throws Exception {
        // Project only identity scalars from the exact bound key. Never return the composer value,
        // conversation, prompt, tool data or credentials to Java. Duplicate selected keys are invalid.
        String sql = "select j.key,j.type,j.atom from cursorDiskKV d, "
                + "json_each(case when length(cast(d.value as blob))<=1048576 then d.value else '{}' end) j "
                + "where d.key=? and j.key in ('composerId','chatGenerationUUID','latestChatGenerationUUID') limit 7";
        Map<String, String> fields = new HashMap<>();
        try (var statement = connection.prepareStatement(sql)) {
            statement.setQueryTimeout(1); statement.setString(1, "composerData:" + id);
            try (ResultSet rs = statement.executeQuery()) {
                while (rs.next()) {
                    String key = rs.getString(1), type = rs.getString(2), value = rs.getString(3);
                    // chatGenerationUUID is removed at completion; latest persists for valid stop attribution.
                    if ("chatGenerationUUID".equals(key) && "null".equals(type)) value = "";
                    else if (!"text".equals(type) || value == null || value.isBlank() || value.length() > 128) return "";
                    if (fields.put(key, value) != null) return "";
                }
            }
        }
        String latest = fields.getOrDefault("latestChatGenerationUUID", "");
        String active = fields.getOrDefault("chatGenerationUUID", "");
        return id.equals(fields.get("composerId")) && !latest.isEmpty()
                && (active.isEmpty() || active.equals(latest)) ? latest : "";
    }

    private boolean absentOrFalse(JsonNode header, String field) {
        // The canonical table's required flags remain authoritative when an optional JSON flag is absent.
        JsonNode value = header.get(field);
        return value == null || (value.isBoolean() && !value.booleanValue());
    }

    private Connection openReadOnly(Path db) throws Exception {
        if (!Files.isRegularFile(db)) throw new java.io.IOException("Missing Cursor database");
        Class.forName("org.sqlite.JDBC");
        var config = new org.sqlite.SQLiteConfig();
        config.setReadOnly(true);
        config.setBusyTimeout(250);
        // mode=ro honors WAL; immutable=1 would silently ignore live WAL updates.
        return DriverManager.getConnection("jdbc:sqlite:" + db.toAbsolutePath().toUri() + "?mode=ro", config.toProperties());
    }

    public List<AiRuntimeSession> discover(Path dataDir) {
        if (dataDir == null || !Files.isDirectory(dataDir)) {
            return List.of();
        }
        Map<String, TitleRecord> titles = readConversationTitles(dataDir);
        Map<String, WorkspaceRecord> workspaces = readWorkspaceRecords(dataDir.resolve("workspaceStorage"));
        ComposerTableResult tableResult = readComposerHeadersTable(dataDir, titles, workspaces);
        List<AiRuntimeSession> sessions = tableResult.tableFound()
            ? tableResult.sessions()
            : readComposerHeaders(dataDir, titles, workspaces);
        sessions.sort(Comparator.comparing(
            AiRuntimeSession::updatedAt,
            Comparator.nullsLast(Comparator.reverseOrder())
        ));
        return sessions;
    }

    private Map<String, TitleRecord> readConversationTitles(Path dataDir) {
        Map<String, TitleRecord> titles = new HashMap<>();
        for (Path db : findFiles(dataDir, "conversation-search.db", 6)) {
            try {
                Class.forName("org.sqlite.JDBC");
                try (Connection connection = openReadOnly(db);
                     Statement statement = connection.createStatement();
                     ResultSet rs = statement.executeQuery("select * from conversations limit 1000")) {
                    statement.setQueryTimeout(2);
                    ResultSetMetaData meta = rs.getMetaData();
                    Set<String> columns = columns(meta);
                    while (rs.next()) {
                        String id = firstColumn(rs, columns, "id", "conversation_id", "conversationId", "composerId", "composer_id");
                        if (id.isBlank()) {
                            continue;
                        }
                        String title = firstColumn(rs, columns, "title", "name", "summary");
                        long updated = longColumn(rs, columns, "lastUpdatedAt", "updated_at", "updatedAt", "timestamp", "createdAt");
                        titles.put(id, new TitleRecord(title, toInstant(updated)));
                    }
                }
            } catch (Exception e) {
                logger.info("Cursor conversation title discovery skipped for {}: {}", db, e.getMessage());
            }
        }
        return titles;
    }

    private Map<String, WorkspaceRecord> readWorkspaceRecords(Path workspaceStorage) {
        Map<String, WorkspaceRecord> records = new HashMap<>();
        if (!Files.isDirectory(workspaceStorage)) {
            return records;
        }
        try (Stream<Path> stream = Files.list(workspaceStorage)) {
            stream.filter(Files::isDirectory).forEach(dir -> {
                Path workspaceJson = dir.resolve("workspace.json");
                if (!Files.isRegularFile(workspaceJson)) {
                    return;
                }
                try {
                    JsonNode node = mapper.readTree(Files.readString(workspaceJson, StandardCharsets.UTF_8));
                    String folder = firstNonBlank(
                        text(node, "folder"),
                        text(node, "workspace"),
                        text(node, "workspaceFolder"),
                        text(node, "path"),
                        text(node.path("configuration"), "folder")
                    );
                    String project = AiRuntimeSession.projectFromCwd(folder);
                    records.put(dir.getFileName().toString(), new WorkspaceRecord(project, folder));
                } catch (Exception e) {
                    logger.info("Cursor workspace mapping skipped for {}: {}", workspaceJson, e.getMessage());
                }
            });
        } catch (Exception e) {
            logger.info("Cursor workspaceStorage discovery skipped: {}", e.getMessage());
        }
        return records;
    }

    private ComposerTableResult readComposerHeadersTable(
        Path dataDir,
        Map<String, TitleRecord> titles,
        Map<String, WorkspaceRecord> workspaces
    ) {
        Map<String, AiRuntimeSession> sessions = new HashMap<>();
        boolean tableFound = false;
        for (Path db : findFiles(dataDir, "state.vscdb", 5)) {
            try {
                Class.forName("org.sqlite.JDBC");
                try (Connection connection = openReadOnly(db)) {
                    if (!hasTable(connection, "composerHeaders")) {
                        continue;
                    }
                    tableFound = true;
                    try (Statement statement = connection.createStatement()) {
                        statement.setQueryTimeout(2);
                        try (ResultSet rs = statement.executeQuery("select * from composerHeaders limit 2000")) {
                            ResultSetMetaData meta = rs.getMetaData();
                            Set<String> columns = columns(meta);
                            while (rs.next()) {
                                addComposerHeaderRow(rs, columns, titles, workspaces, sessions);
                            }
                        }
                    }
                }
            } catch (Exception e) {
                logger.info("Cursor composerHeaders table discovery skipped for {}: {}", db, e.getMessage());
            }
        }
        return new ComposerTableResult(tableFound, new ArrayList<>(sessions.values()));
    }

    private boolean hasTable(Connection connection, String tableName) throws Exception {
        try (Statement statement = connection.createStatement()) {
            statement.setQueryTimeout(2);
            try (ResultSet rs = statement.executeQuery(
                "select name from sqlite_master where type='table' and name='" + tableName + "' limit 1"
            )) {
                return rs.next();
            }
        }
    }

    private void addComposerHeaderRow(
        ResultSet rs,
        Set<String> columns,
        Map<String, TitleRecord> titles,
        Map<String, WorkspaceRecord> workspaces,
        Map<String, AiRuntimeSession> sessions
    ) throws Exception {
        String id = firstColumn(rs, columns, "composerId", "composer_id", "id");
        if (id.isBlank()
            || booleanColumn(rs, columns, "isArchived", "archived")
            || booleanColumn(rs, columns, "isSubagent", "isSubAgent", "subagent")) {
            return;
        }
        JsonNode value = parseJson(firstColumn(rs, columns, "value"));
        String kind = firstNonBlank(
            firstColumn(rs, columns, "type", "composerType"),
            text(value, "type"),
            text(value, "composerType")
        );
        if (kind.toLowerCase(Locale.ROOT).contains("subagent")) {
            return;
        }
        String workspaceId = firstNonBlank(
            firstColumn(rs, columns, "workspaceId", "workspace_id"),
            text(value, "workspaceId"),
            text(value, "workspace_id")
        );
        WorkspaceRecord workspace = workspaces.getOrDefault(workspaceId, new WorkspaceRecord("未归类", ""));
        TitleRecord title = titles.getOrDefault(id, new TitleRecord("", Instant.EPOCH));
        String displayTitle = firstNonBlank(
            title.title(),
            firstColumn(rs, columns, "title", "name", "summary"),
            text(value, "title"),
            text(value, "name"),
            text(value, "summary")
        );
        Instant updatedAt = maxInstant(
            title.updatedAt(),
            toInstant(longColumn(rs, columns, "lastUpdatedAt", "updated_at", "updatedAt")),
            toInstant(longColumn(rs, columns, "recency")),
            toInstant(longColumn(rs, columns, "checkpointAt")),
            toInstant(longColumn(rs, columns, "createdAt")),
            toInstant(longValue(value, "lastUpdatedAt")),
            toInstant(longValue(value, "updatedAt")),
            toInstant(longValue(value, "createdAt"))
        );
        sessions.put(id, new AiRuntimeSession(
            "Cursor",
            id,
            displayTitle,
            workspace.projectName(),
            workspace.cwd(),
            "",
            updatedAt
        ));
    }

    private List<AiRuntimeSession> readComposerHeaders(
        Path dataDir,
        Map<String, TitleRecord> titles,
        Map<String, WorkspaceRecord> workspaces
    ) {
        Map<String, AiRuntimeSession> sessions = new HashMap<>();
        for (Path db : findFiles(dataDir, "state.vscdb", 5)) {
            try {
                Class.forName("org.sqlite.JDBC");
                try (Connection connection = openReadOnly(db);
                     Statement statement = connection.createStatement();
                     ResultSet rs = statement.executeQuery("select key, value from ItemTable")) {
                    statement.setQueryTimeout(2);
                    int read = 0;
                    while (rs.next() && read++ < 1200) {
                        String key = rs.getString("key");
                        if (key == null || !key.toLowerCase(Locale.ROOT).contains("composer")) {
                            continue;
                        }
                        String value = rs.getString("value");
                        if (value == null || !value.contains("composerHeaders")) {
                            continue;
                        }
                        collectComposerHeaders(mapper.readTree(value), titles, workspaces, sessions);
                    }
                }
            } catch (Exception e) {
                logger.info("Cursor composer metadata skipped for {}: {}", db, e.getMessage());
            }
        }
        return new ArrayList<>(sessions.values());
    }

    private void collectComposerHeaders(
        JsonNode node,
        Map<String, TitleRecord> titles,
        Map<String, WorkspaceRecord> workspaces,
        Map<String, AiRuntimeSession> sessions
    ) {
        if (node == null || node.isNull()) {
            return;
        }
        JsonNode headers = node.get("composerHeaders");
        if (headers != null && headers.isObject()) {
            addHeader(headers, titles, workspaces, sessions);
        } else if (headers != null && headers.isArray()) {
            for (JsonNode header : headers) {
                addHeader(header, titles, workspaces, sessions);
            }
        }
        if (node.isObject()) {
            node.fields().forEachRemaining(entry -> {
                String key = entry.getKey().toLowerCase(Locale.ROOT);
                if (!"messages".equals(key) && !"conversation".equals(key) && !"chat".equals(key)) {
                    collectComposerHeaders(entry.getValue(), titles, workspaces, sessions);
                }
            });
        } else if (node.isArray()) {
            for (JsonNode item : node) {
                collectComposerHeaders(item, titles, workspaces, sessions);
            }
        }
    }

    private void addHeader(
        JsonNode header,
        Map<String, TitleRecord> titles,
        Map<String, WorkspaceRecord> workspaces,
        Map<String, AiRuntimeSession> sessions
    ) {
        String id = firstNonBlank(text(header, "composerId"), text(header, "composer_id"));
        if (id.isBlank() || booleanValue(header, "isArchived") || booleanValue(header, "archived") || booleanValue(header, "isSubAgent")) {
            return;
        }
        String kind = firstNonBlank(text(header, "type"), text(header, "composerType"));
        if (kind.toLowerCase(Locale.ROOT).contains("subagent")) {
            return;
        }
        String workspaceId = firstNonBlank(text(header, "workspaceId"), text(header, "workspace_id"));
        WorkspaceRecord workspace = workspaces.getOrDefault(workspaceId, new WorkspaceRecord("未归类", ""));
        TitleRecord title = titles.getOrDefault(id, new TitleRecord("", Instant.EPOCH));
        String displayTitle = firstNonBlank(title.title(), text(header, "title"), text(header, "name"), "未命名会话");
        Instant updatedAt = maxInstant(
            title.updatedAt(),
            toInstant(longValue(header, "lastUpdatedAt")),
            toInstant(longValue(header, "updated_at")),
            toInstant(longValue(header, "updatedAt"))
        );
        sessions.put(id, new AiRuntimeSession(
            "Cursor",
            id,
            displayTitle,
            workspace.projectName(),
            workspace.cwd(),
            "",
            updatedAt
        ));
    }

    private List<Path> findFiles(Path root, String fileName, int maxDepth) {
        List<Path> files = new ArrayList<>();
        try (Stream<Path> stream = Files.walk(root, maxDepth)) {
            stream.filter(Files::isRegularFile)
                .filter(path -> fileName.equalsIgnoreCase(path.getFileName().toString()))
                .limit(MAX_SCAN_FILES)
                .forEach(files::add);
        } catch (Exception e) {
            logger.info("Cursor file scan skipped: {}", e.getMessage());
        }
        return files;
    }

    private Set<String> columns(ResultSetMetaData meta) throws Exception {
        Set<String> columns = new HashSet<>();
        for (int i = 1; i <= meta.getColumnCount(); i++) {
            columns.add(meta.getColumnName(i));
        }
        return columns;
    }

    private String firstColumn(ResultSet rs, Set<String> columns, String... names) throws Exception {
        for (String name : names) {
            if (columns.contains(name)) {
                String value = rs.getString(name);
                if (value != null && !value.isBlank()) {
                    return value.strip();
                }
            }
        }
        return "";
    }

    private long longColumn(ResultSet rs, Set<String> columns, String... names) throws Exception {
        for (String name : names) {
            if (columns.contains(name)) {
                long value = rs.getLong(name);
                if (value > 0) {
                    return value;
                }
            }
        }
        return 0L;
    }

    private String text(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        return value == null || value.isNull() ? "" : value.asText("");
    }

    private JsonNode parseJson(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return mapper.readTree(value);
        } catch (Exception e) {
            return null;
        }
    }

    private boolean booleanValue(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        return value != null && value.asBoolean(false);
    }

    private boolean booleanColumn(ResultSet rs, Set<String> columns, String... names) throws Exception {
        for (String name : names) {
            if (!columns.contains(name)) {
                continue;
            }
            Object value = rs.getObject(name);
            if (value instanceof Boolean bool) {
                if (bool) {
                    return true;
                }
                continue;
            }
            if (value instanceof Number number) {
                if (number.longValue() != 0L) {
                    return true;
                }
                continue;
            }
            if (value != null) {
                String text = value.toString().strip().toLowerCase(Locale.ROOT);
                if ("1".equals(text) || "true".equals(text) || "yes".equals(text)) {
                    return true;
                }
            }
        }
        return false;
    }

    private long longValue(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        return value == null || !value.canConvertToLong() ? 0L : value.asLong();
    }

    private Instant toInstant(long value) {
        if (value <= 0) {
            return Instant.EPOCH;
        }
        return value > 10_000_000_000L ? Instant.ofEpochMilli(value) : Instant.ofEpochSecond(value);
    }

    private Instant maxInstant(Instant... values) {
        Instant result = Instant.EPOCH;
        for (Instant value : values) {
            if (value != null && value.isAfter(result)) {
                result = value;
            }
        }
        return result;
    }

    private String firstNonBlank(String... values) {
        if (values != null) {
            for (String value : values) {
                if (value != null && !value.isBlank()) {
                    return value.strip();
                }
            }
        }
        return "";
    }

    private record TitleRecord(String title, Instant updatedAt) {}
    private record WorkspaceRecord(String projectName, String cwd) {}
    private record ComposerTableResult(boolean tableFound, List<AiRuntimeSession> sessions) {}
}
