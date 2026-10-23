package com.example.ahakey.service;

import com.example.ahakey.model.AiRuntimeSession;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public class CodexSessionDiscoveryService {
    private static final Logger logger = LoggerFactory.getLogger(CodexSessionDiscoveryService.class);
    private final ObjectMapper mapper = new ObjectMapper();

    public List<AiRuntimeSession> discover(Path dataDir) {
        if (dataDir == null || !Files.isDirectory(dataDir)) {
            return List.of();
        }
        List<AiRuntimeSession> fromDb = discoverFromSqlite(dataDir.resolve("state_5.sqlite"));
        if (!fromDb.isEmpty()) {
            return fromDb;
        }
        return discoverFromSessionIndex(dataDir.resolve("session_index.jsonl"));
    }

    private List<AiRuntimeSession> discoverFromSqlite(Path db) {
        if (!Files.isRegularFile(db)) {
            return List.of();
        }
        List<AiRuntimeSession> sessions = new ArrayList<>();
        try {
            Class.forName("org.sqlite.JDBC");
            String url = "jdbc:sqlite:" + db.toAbsolutePath();
            try (Connection connection = DriverManager.getConnection(url);
                 Statement statement = connection.createStatement()) {
                statement.setQueryTimeout(2);
                String sql = """
                    select id, rollout_path, cwd, title, first_user_message, preview, updated_at_ms, recency_at_ms
                    from threads
                    order by coalesce(recency_at_ms, updated_at_ms, 0) desc
                    limit 400
                    """;
                try (ResultSet rs = statement.executeQuery(sql)) {
                    while (rs.next()) {
                        String id = value(rs.getString("id"));
                        String cwd = value(rs.getString("cwd"));
                        String title = firstNonBlank(
                            rs.getString("title"),
                            rs.getString("first_user_message"),
                            rs.getString("preview"),
                            id
                        );
                        long timestamp = Math.max(rs.getLong("recency_at_ms"), rs.getLong("updated_at_ms"));
                        sessions.add(new AiRuntimeSession(
                            "Codex",
                            id,
                            title,
                            AiRuntimeSession.projectFromCwd(cwd),
                            cwd,
                            value(rs.getString("rollout_path")),
                            toInstant(timestamp)
                        ));
                    }
                }
            }
        } catch (Exception e) {
            logger.info("Codex sqlite discovery skipped: {}", e.getMessage());
        }
        return sort(sessions);
    }

    private List<AiRuntimeSession> discoverFromSessionIndex(Path index) {
        if (!Files.isRegularFile(index)) {
            return List.of();
        }
        List<AiRuntimeSession> sessions = new ArrayList<>();
        try (BufferedReader reader = Files.newBufferedReader(index, StandardCharsets.UTF_8)) {
            String line;
            while ((line = reader.readLine()) != null && sessions.size() < 400) {
                if (line.isBlank()) {
                    continue;
                }
                JsonNode node = mapper.readTree(line);
                String id = text(node, "id");
                String title = firstNonBlank(text(node, "thread_name"), text(node, "title"), id);
                long updatedAt = longValue(node, "updated_at");
                sessions.add(new AiRuntimeSession(
                    "Codex",
                    id,
                    title,
                    "未归类",
                    "",
                    "",
                    toInstant(updatedAt)
                ));
            }
        } catch (Exception e) {
            logger.info("Codex session_index discovery skipped: {}", e.getMessage());
        }
        return sort(sessions);
    }

    private List<AiRuntimeSession> sort(List<AiRuntimeSession> sessions) {
        sessions.sort(Comparator.comparing(
            AiRuntimeSession::updatedAt,
            Comparator.nullsLast(Comparator.reverseOrder())
        ));
        return sessions;
    }

    private Instant toInstant(long value) {
        if (value <= 0) {
            return Instant.EPOCH;
        }
        return value > 10_000_000_000L ? Instant.ofEpochMilli(value) : Instant.ofEpochSecond(value);
    }

    private String text(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        return value == null || value.isNull() ? "" : value.asText("");
    }

    private long longValue(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        return value == null || !value.canConvertToLong() ? 0L : value.asLong();
    }

    private String value(String input) {
        return input == null ? "" : input;
    }

    private String firstNonBlank(String... values) {
        if (values != null) {
            for (String value : values) {
                if (value != null && !value.isBlank()) {
                    return value.strip();
                }
            }
        }
        return "未命名会话";
    }
}
