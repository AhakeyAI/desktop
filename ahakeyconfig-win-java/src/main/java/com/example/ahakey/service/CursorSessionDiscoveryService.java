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
    private final ObjectMapper mapper = new ObjectMapper();

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
                try (Connection connection = DriverManager.getConnection("jdbc:sqlite:" + db.toAbsolutePath());
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
                try (Connection connection = DriverManager.getConnection("jdbc:sqlite:" + db.toAbsolutePath())) {
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
                try (Connection connection = DriverManager.getConnection("jdbc:sqlite:" + db.toAbsolutePath());
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
