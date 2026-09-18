package com.example.ahakey.service;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.file.Files;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AhaTypeServiceTest {
    @TempDir
    Path tempDir;

    @Test
    void postsTheStrictProcessEnvelopeAndUpdatesQuota() throws Exception {
        AtomicReference<String> method = new AtomicReference<>();
        AtomicReference<String> path = new AtomicReference<>();
        AtomicReference<String> auth = new AtomicReference<>();
        AtomicReference<String> contentType = new AtomicReference<>();
        AtomicReference<String> body = new AtomicReference<>();
        try (MockServer server = new MockServer(exchange -> {
            method.set(exchange.getRequestMethod());
            path.set(exchange.getRequestURI().getPath());
            auth.set(exchange.getRequestHeaders().getFirst("Authorization"));
            contentType.set(exchange.getRequestHeaders().getFirst("Content-Type"));
            body.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            respond(exchange, 200,
                "{\"code\":\"200\",\"data\":{\"result\":\"整理后的文本\","
                    + "\"token_valid_until\":\"2031-01-01T00:00:00Z\","
                    + "\"quota\":{\"limit_daily\":10,\"used_daily\":2}}}" );
        })) {
            AhaTypeService service = configuredService(server, true, "2030-01-01T00:00:00Z");
            assertEquals("整理后的文本", service.processIfEnabled("原始文本"));
            assertEquals("POST", method.get());
            assertEquals("/prod-api/api/v1/typeless/process", path.get());
            assertEquals("Bearer test-token", auth.get());
            assertEquals("application/json; charset=utf-8", contentType.get());
            assertTrue(body.get().contains("\"text\":\"原始文本\""));
            Map<String, Object> values = service.config().load();
            assertEquals(10, ((Number) values.get("limit_daily")).intValue());
            assertEquals(2, ((Number) values.get("used_daily")).intValue());
            assertEquals("2031-01-01T00:00:00Z", values.get(AhaTypeConfig.TOKEN_VALID_UNTIL));
        }
    }

    @Test
    void textResponsePreservesQuotaFieldsThatTheServerOmits() throws Exception {
        try (MockServer server = new MockServer(exchange -> respond(exchange, 200,
            "{\"code\":0,\"data\":{\"text\":\"整理文本\","
                + "\"quota\":{\"used_daily\":3}}}"))) {
            AhaTypeConfig config = new AhaTypeConfig(tempDir.resolve("partial-quota.json"));
            Map<String, Object> values = AhaTypeConfig.defaults();
            values.put(AhaTypeConfig.ENABLED, true);
            values.put(AhaTypeConfig.ACCESS_TOKEN, "test-token");
            values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, "2030-01-01T00:00:00Z");
            values.put("limit_daily", 20);
            values.put("used_weekly", 4);
            config.save(values);
            AhaTypeService service = new AhaTypeService(config, HttpClient.newHttpClient(),
                URI.create(server.baseUrl() + "/prod-api"), fixedClock());

            assertEquals("整理文本", service.processIfEnabled("原文"));
            Map<String, Object> saved = config.load();
            assertEquals(20, ((Number) saved.get("limit_daily")).intValue());
            assertEquals(4, ((Number) saved.get("used_weekly")).intValue());
            assertEquals(3, ((Number) saved.get("used_daily")).intValue());
        }
    }

    @Test
    void quotaPersistenceFailureDoesNotDiscardSuccessfulCloudText() throws Exception {
        Path path = tempDir.resolve("quota-save-failure.json");
        AhaTypeConfig config = new AhaTypeConfig(path);
        Map<String, Object> values = AhaTypeConfig.defaults();
        values.put(AhaTypeConfig.ENABLED, true);
        values.put(AhaTypeConfig.ACCESS_TOKEN, "test-token");
        values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, "2030-01-01T00:00:00Z");
        config.save(values);
        try (MockServer server = new MockServer(exchange -> respond(exchange, 200,
            "{\"code\":200,\"data\":{\"text\":\"仍然输出\","
                + "\"quota\":{\"used_daily\":5}}}"))) {
            AhaTypeService service = new AhaTypeService(config, HttpClient.newHttpClient(),
                URI.create(server.baseUrl() + "/prod-api"), fixedClock());
            Files.delete(path);
            Files.createDirectory(path);
            assertEquals("仍然输出", service.processIfEnabled("原文"));
            assertTrue(service.getStatusMessage().contains("保存失败"));
        }
    }

    @Test
    void failedTogglePersistenceKeepsTheLastSuccessfulState() throws Exception {
        Path path = tempDir.resolve("toggle-save-failure.json");
        AhaTypeConfig config = new AhaTypeConfig(path);
        Map<String, Object> values = AhaTypeConfig.defaults();
        values.put(AhaTypeConfig.ENABLED, false);
        values.put(AhaTypeConfig.ACCESS_TOKEN, "test-token");
        values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, "2030-01-01T00:00:00Z");
        config.save(values);
        AhaTypeService service = new AhaTypeService(config, HttpClient.newHttpClient(),
            URI.create("http://127.0.0.1/prod-api"), fixedClock());
        Files.delete(path);
        Files.createDirectory(path);

        assertTrue(!service.setEnabled(true));
        assertTrue(!service.isEnabled());
        assertTrue(service.getStatusMessage().contains("保存失败"));
    }

    @Test
    void failuresAndExpiredSessionsReturnTheOriginalTextWithoutLeakingDetails() throws Exception {
        AtomicInteger calls = new AtomicInteger();
        try (MockServer server = new MockServer(exchange -> {
            calls.incrementAndGet();
            respond(exchange, 500, "{\"secret\":\"must-not-be-logged\"}");
        })) {
            AhaTypeService service = configuredService(server, true, "2030-01-01T00:00:00Z");
            assertEquals("原始文本", service.processIfEnabled("原始文本"));
            assertEquals(1, calls.get());

            AhaTypeService expired = configuredService(server, true, "2020-01-01T00:00:00Z");
            assertEquals("原始文本", expired.processIfEnabled("原始文本"));
            assertEquals(1, calls.get());
        }
    }

    private AhaTypeService configuredService(MockServer server, boolean enabled, String validUntil) throws Exception {
        AhaTypeConfig config = new AhaTypeConfig(tempDir.resolve("typeless-" + System.nanoTime() + ".json"));
        Map<String, Object> values = AhaTypeConfig.defaults();
        values.put(AhaTypeConfig.ENABLED, enabled);
        values.put(AhaTypeConfig.ACCESS_TOKEN, "test-token");
        values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, validUntil);
        config.save(values);
        return new AhaTypeService(config, HttpClient.newHttpClient(),
            URI.create(server.baseUrl() + "/prod-api"),
            Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC));
    }

    private static Clock fixedClock() {
        return Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC);
    }

    private static void respond(com.sun.net.httpserver.HttpExchange exchange, int status, String body)
            throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(status, bytes.length);
        try (var output = exchange.getResponseBody()) {
            output.write(bytes);
        }
    }

    private static final class MockServer implements AutoCloseable {
        private final HttpServer server;

        MockServer(com.sun.net.httpserver.HttpHandler handler) throws IOException {
            server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            server.createContext("/", handler);
            server.start();
        }

        String baseUrl() {
            return "http://127.0.0.1:" + server.getAddress().getPort();
        }

        @Override
        public void close() {
            server.stop(0);
        }
    }
}
