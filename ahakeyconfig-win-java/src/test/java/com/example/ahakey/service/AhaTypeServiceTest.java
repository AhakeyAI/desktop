package com.example.ahakey.service;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
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
        AtomicReference<String> body = new AtomicReference<>();
        try (MockServer server = new MockServer(exchange -> {
            method.set(exchange.getRequestMethod());
            path.set(exchange.getRequestURI().getPath());
            auth.set(exchange.getRequestHeaders().getFirst("Authorization"));
            body.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            respond(exchange, 200,
                "{\"code\":\"200\",\"data\":{\"result\":\"整理后的文本\","
                    + "\"limit_daily\":10,\"used_daily\":2}}" );
        })) {
            AhaTypeService service = configuredService(server, true, "2030-01-01T00:00:00Z");
            assertEquals("整理后的文本", service.processIfEnabled("原始文本"));
            assertEquals("POST", method.get());
            assertEquals("/prod-api/api/v1/typeless/process", path.get());
            assertEquals("Bearer test-token", auth.get());
            assertTrue(body.get().contains("\"text\":\"原始文本\""));
            Map<String, Object> values = service.config().load();
            assertEquals(10, ((Number) values.get("limit_daily")).intValue());
            assertEquals(2, ((Number) values.get("used_daily")).intValue());
        }
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
