package com.example.ahakey.service;

import com.fasterxml.jackson.databind.ObjectMapper;
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
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

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
    void delayedResponseAfterLogoutCannotRestoreTheOldSession() throws Exception {
        CountDownLatch requestStarted = new CountDownLatch(1);
        CountDownLatch releaseResponse = new CountDownLatch(1);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/prod-api/api/v1/typeless/process", exchange -> {
            requestStarted.countDown();
            await(releaseResponse);
            respond(exchange, 200, "{\"code\":0,\"data\":{\"text\":\"迟到文本\","
                + "\"quota\":{\"used_daily\":99}}}");
        });
        ExecutorService serverExecutor = Executors.newCachedThreadPool();
        server.setExecutor(serverExecutor);
        server.start();
        ExecutorService executor = Executors.newSingleThreadExecutor();
        try {
            AhaTypeConfig config = new AhaTypeConfig(tempDir.resolve("logout-race.json"));
            Map<String, Object> values = AhaTypeConfig.defaults();
            values.put(AhaTypeConfig.ENABLED, true);
            values.put(AhaTypeConfig.ACCESS_TOKEN, "token-A");
            values.put(AhaTypeConfig.USER, Map.of("user_id", "user-A"));
            values.put(AhaTypeConfig.REMEMBER_PASSWORD, true);
            values.put(AhaTypeConfig.REMEMBERED_PHONE, "13800000000");
            values.put(AhaTypeConfig.REMEMBERED_PASSWORD, "password-A");
            values.put("used_daily", 3);
            config.save(values);
            AhaTypeService service = new AhaTypeService(config, HttpClient.newHttpClient(),
                URI.create(baseUrl(server) + "/prod-api"), fixedClock());
            CloudAccountManager manager = new CloudAccountManager(service, HttpClient.newHttpClient(),
                new ObjectMapper(), URI.create(baseUrl(server) + "/prod-api"), fixedClock());

            Future<String> result = executor.submit(() -> service.processIfEnabled("原文"));
            assertTrue(requestStarted.await(2, TimeUnit.SECONDS));
            assertEquals(null, manager.logout());
            releaseResponse.countDown();

            assertEquals("迟到文本", result.get(3, TimeUnit.SECONDS));
            Map<String, Object> saved = config.load();
            assertEquals("", saved.get(AhaTypeConfig.ACCESS_TOKEN));
            assertEquals(null, saved.get(AhaTypeConfig.USER));
            assertEquals(true, saved.get(AhaTypeConfig.ENABLED));
            assertEquals("13800000000", saved.get(AhaTypeConfig.REMEMBERED_PHONE));
            assertEquals("password-A", saved.get(AhaTypeConfig.REMEMBERED_PASSWORD));
            assertEquals(0, ((Number) saved.get("used_daily")).intValue());
            assertTrue(service.getStatusMessage().contains("未登录"));
        } finally {
            releaseResponse.countDown();
            executor.shutdownNow();
            serverExecutor.shutdownNow();
            server.stop(0);
        }
    }

    @Test
    void delayedResponseAfterLoginCannotOverwriteTheNewSession() throws Exception {
        CountDownLatch requestStarted = new CountDownLatch(1);
        CountDownLatch releaseResponse = new CountDownLatch(1);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/prod-api/api/v1/typeless/process", exchange -> {
            requestStarted.countDown();
            await(releaseResponse);
            respond(exchange, 200, "{\"code\":0,\"data\":{\"text\":\"迟到文本\","
                + "\"quota\":{\"used_daily\":99}}}");
        });
        server.createContext("/prod-api/api/v1/auth/login", exchange -> respond(exchange, 200,
            "{\"code\":0,\"data\":{\"access_token\":\"token-B\","
                + "\"user\":{\"user_id\":\"user-B\",\"phone\":\"13900000000\"},"
                + "\"quota\":{\"limit_daily\":20,\"used_daily\":4}}}"));
        ExecutorService serverExecutor = Executors.newCachedThreadPool();
        server.setExecutor(serverExecutor);
        server.start();
        ExecutorService executor = Executors.newSingleThreadExecutor();
        try {
            AhaTypeConfig config = new AhaTypeConfig(tempDir.resolve("login-race.json"));
            Map<String, Object> values = AhaTypeConfig.defaults();
            values.put(AhaTypeConfig.ENABLED, true);
            values.put(AhaTypeConfig.ACCESS_TOKEN, "token-A");
            values.put(AhaTypeConfig.USER, Map.of("user_id", "user-A"));
            values.put(AhaTypeConfig.REMEMBER_PASSWORD, true);
            values.put(AhaTypeConfig.REMEMBERED_PHONE, "13800000000");
            values.put(AhaTypeConfig.REMEMBERED_PASSWORD, "password-A");
            config.save(values);
            AhaTypeService service = new AhaTypeService(config, HttpClient.newHttpClient(),
                URI.create(baseUrl(server) + "/prod-api"), fixedClock());
            CloudAccountManager manager = new CloudAccountManager(service, HttpClient.newHttpClient(),
                new ObjectMapper(), URI.create(baseUrl(server) + "/prod-api"), fixedClock());

            Future<String> result = executor.submit(() -> service.processIfEnabled("原文"));
            assertTrue(requestStarted.await(2, TimeUnit.SECONDS));
            assertEquals(null, manager.login("13900000000", "password-B", false));
            releaseResponse.countDown();

            assertEquals("迟到文本", result.get(3, TimeUnit.SECONDS));
            Map<String, Object> saved = config.load();
            assertEquals("token-B", saved.get(AhaTypeConfig.ACCESS_TOKEN));
            assertEquals("user-B", ((Map<?, ?>) saved.get(AhaTypeConfig.USER)).get("user_id"));
            assertEquals(true, saved.get(AhaTypeConfig.ENABLED));
            assertEquals("13900000000", saved.get(AhaTypeConfig.REMEMBERED_PHONE));
            assertEquals(false, saved.get(AhaTypeConfig.REMEMBER_PASSWORD));
            assertEquals("", saved.get(AhaTypeConfig.REMEMBERED_PASSWORD));
            assertEquals(4, ((Number) saved.get("used_daily")).intValue());
            assertEquals(20, ((Number) saved.get("limit_daily")).intValue());
            assertTrue(service.getStatusMessage().contains("已启用"));
        } finally {
            releaseResponse.countDown();
            executor.shutdownNow();
            serverExecutor.shutdownNow();
            server.stop(0);
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

    @Test
    void classifiesLoginQuotaNetworkAndMalformedFailuresWhileReturningOriginalText() throws Exception {
        try (MockServer server = new MockServer(exchange -> respond(exchange, 401,
            "{\"code\":401,\"message\":\"token expired\"}"))) {
            AhaTypeService service = configuredService(server, true, "2030-01-01T00:00:00Z");
            assertEquals("原文", service.processIfEnabled("原文"));
            assertEquals(AhaTypeService.ProcessIssue.LOGIN_REQUIRED, service.getLastProcessIssue());
            assertTrue(service.getStatusMessage().contains("重新登录"));
            assertEquals("", service.getAccessToken());
        }
        try (MockServer server = new MockServer(exchange -> respond(exchange, 429,
            "{\"code\":429,\"message\":\"quota exceeded\"}"))) {
            AhaTypeService service = configuredService(server, true, "2030-01-01T00:00:00Z");
            assertEquals("原文", service.processIfEnabled("原文"));
            assertEquals(AhaTypeService.ProcessIssue.QUOTA_REQUIRED, service.getLastProcessIssue());
            assertTrue(service.getStatusMessage().contains("充值或兑换"));
        }
        try (MockServer server = new MockServer(exchange -> respond(exchange, 503,
            "{\"code\":503}"))) {
            AhaTypeService service = configuredService(server, true, "2030-01-01T00:00:00Z");
            assertEquals("原文", service.processIfEnabled("原文"));
            assertEquals(AhaTypeService.ProcessIssue.NETWORK, service.getLastProcessIssue());
            assertTrue(service.getStatusMessage().contains("暂时不可用"));
        }
        try (MockServer server = new MockServer(exchange -> respond(exchange, 200,
            "not-json"))) {
            AhaTypeService service = configuredService(server, true, "2030-01-01T00:00:00Z");
            assertEquals("原文", service.processIfEnabled("原文"));
            assertEquals(AhaTypeService.ProcessIssue.UNKNOWN, service.getLastProcessIssue());
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

    private static String baseUrl(HttpServer server) {
        return "http://127.0.0.1:" + server.getAddress().getPort();
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

    private static void await(CountDownLatch latch) {
        try {
            if (!latch.await(5, TimeUnit.SECONDS)) {
                throw new IllegalStateException("test response release timed out");
            }
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("test response wait interrupted", exception);
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
