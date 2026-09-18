package com.example.ahakey.service;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CloudAccountManagerTest {
    @TempDir
    Path tempDir;

    @Test
    void loginRefreshAndLogoutUseThePersistedSessionContract() throws Exception {
        AtomicReference<String> profileAuth = new AtomicReference<>();
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        try {
            server.createContext("/prod-api/api/v1/auth/login", exchange -> {
                exchange.getRequestBody().readAllBytes();
                respond(exchange, 200,
                    "{\"code\":0,\"data\":{\"access_token\":\"login-token\","
                        + "\"token_valid_until\":\"2030-01-01T00:00:00Z\","
                        + "\"user\":{\"user_id\":\"u1\",\"phone\":\"13800000000\"},"
                        + "\"quota\":{\"limit_daily\":12,\"used_daily\":1}}}");
            });
            server.createContext("/prod-api/api/v1/users/me", exchange -> {
                profileAuth.set(exchange.getRequestHeaders().getFirst("Authorization"));
                respond(exchange, 200,
                    "{\"code\":\"200\",\"data\":{\"user\":{\"userId\":\"u2\","
                        + "\"phone\":\"13800000000\",\"plan\":\"pro\"},"
                        + "\"quota\":{\"limit_daily\":20,\"used_daily\":3,"
                        + "\"token_valid_until\":\"2031-01-01T00:00:00Z\"}}}");
            });
            server.start();

            AhaTypeConfig config = new AhaTypeConfig(tempDir.resolve("typeless_config.json"));
            Map<String, Object> initial = AhaTypeConfig.defaults();
            initial.put(AhaTypeConfig.ENABLED, true);
            config.save(initial);
            AhaTypeService ahaType = new AhaTypeService(config, HttpClient.newHttpClient(),
                URI.create(baseUrl(server) + "/prod-api"), fixedClock());
            CloudAccountManager manager = new CloudAccountManager(ahaType, HttpClient.newHttpClient(),
                new ObjectMapper(), URI.create(baseUrl(server) + "/prod-api"), fixedClock());

            assertEquals(null, manager.login("13800000000", "fake-password", true));
            assertTrue(manager.isLoggedIn());
            assertEquals("13800000000", manager.getProfile().get("phone"));
            assertTrue(manager.rememberPassword());
            assertEquals("fake-password", manager.rememberedPassword());

            assertEquals(null, manager.refreshProfile());
            assertEquals("Bearer login-token", profileAuth.get());
            assertEquals("u2", manager.getProfile().get("user_id"));
            assertEquals(20, ((Number) ahaType.config().load().get("limit_daily")).intValue());
            assertEquals("2031-01-01T00:00:00Z",
                ahaType.config().load().get(AhaTypeConfig.TOKEN_VALID_UNTIL));

            manager.logout();
            assertFalse(manager.isLoggedIn());
            assertEquals("", ahaType.getAccessToken());
            assertEquals("13800000000", manager.rememberedPhone());
            assertEquals("fake-password", manager.rememberedPassword());
            assertTrue((Boolean) ahaType.config().load().get(AhaTypeConfig.ENABLED));
            assertEquals(0, ((Number) ahaType.config().load().get("limit_daily")).intValue());
            assertEquals("13800000000", manager.rememberedPhone());
        } finally {
            server.stop(0);
        }
    }

    @Test
    void phoneIsTrimmedAndRetainedWhenRememberPasswordIsDisabled() throws Exception {
        AhaTypeConfig config = new AhaTypeConfig(tempDir.resolve("credentials.json"));
        AhaTypeService ahaType = new AhaTypeService(config, HttpClient.newHttpClient(),
            URI.create("http://127.0.0.1/prod-api"), fixedClock());
        assertTrue(ahaType.saveRememberedCredentials(" 13800000000 ", "old-password", true));
        assertTrue(ahaType.saveRememberedCredentials(" 13900000000 ", "ignored", false));
        assertEquals("13900000000", ahaType.getRememberedPhone());
        assertEquals("", ahaType.getRememberedPassword());
        assertFalse(ahaType.isRememberPassword());
    }

    @Test
    void loginDoesNotReportSuccessWhenLocalPersistenceFails() throws Exception {
        Path path = tempDir.resolve("unwritable-config");
        Files.createDirectory(path);
        AhaTypeConfig config = new AhaTypeConfig(path);
        AhaTypeService ahaType = new AhaTypeService(config, HttpClient.newHttpClient(),
            URI.create("http://127.0.0.1/prod-api"), fixedClock());
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        try {
            server.createContext("/prod-api/api/v1/auth/login", exchange -> respond(exchange, 200,
                "{\"code\":0,\"data\":{\"access_token\":\"login-token\","
                    + "\"user\":{\"user_id\":\"u1\"}}}"));
            server.start();
            CloudAccountManager manager = new CloudAccountManager(ahaType, HttpClient.newHttpClient(),
                new ObjectMapper(), URI.create(baseUrl(server) + "/prod-api"), fixedClock());
            String error = manager.login("13800000000", "fake-password", false);
            assertTrue(error.contains("本地保存失败"));
            assertFalse(manager.isLoggedIn());
        } finally {
            server.stop(0);
        }
    }

    private static Clock fixedClock() {
        return Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC);
    }

    private static String baseUrl(HttpServer server) {
        return "http://127.0.0.1:" + server.getAddress().getPort();
    }

    private static void respond(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(status, bytes.length);
        try (var output = exchange.getResponseBody()) {
            output.write(bytes);
        }
    }
}
