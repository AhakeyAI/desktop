package com.example.ahakey.update;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RemoteClientConfigServiceTest {

    @TempDir
    Path tempDirectory;

    private HttpServer server;

    @AfterEach
    void stopServer() {
        if (server != null) {
            server.stop(0);
        }
    }

    @Test
    void refreshesOncePerDayAndUsesPersistentCache() throws Exception {
        AtomicInteger requests = new AtomicInteger();
        URI endpoint = serve(exchangeBody("""
                {"supportUrl":"https://support.example.com/contact"}
                """), requests);
        Path cache = tempDirectory.resolve("client-config-cache.json");
        Clock clock = Clock.fixed(Instant.parse("2026-07-27T01:00:00Z"), ZoneOffset.UTC);
        RemoteClientConfigService service = service(endpoint, cache, clock);

        RemoteClientConfigService.RefreshResult first = service.refreshIfDue();
        RemoteClientConfigService.RefreshResult second = service.refreshIfDue();

        assertTrue(first.networkAttempted());
        assertTrue(first.successful());
        assertFalse(second.networkAttempted());
        assertEquals(1, requests.get());
        assertEquals("https://support.example.com/contact",
                second.config().supportUrl().orElseThrow().toString());
        assertEquals(second.config(), service(endpoint, cache, clock).loadCached());
    }

    @Test
    void invalidNonHttpsRemoteValueFallsBackAndIsRateLimited() throws Exception {
        AtomicInteger requests = new AtomicInteger();
        URI endpoint = serve(exchangeBody("""
                {"supportUrl":"http://unsafe.example.com/contact"}
                """), requests);
        Path cache = tempDirectory.resolve("client-config-cache.json");
        Clock clock = Clock.fixed(Instant.parse("2026-07-27T01:00:00Z"), ZoneOffset.UTC);
        RemoteClientConfigService service = service(endpoint, cache, clock);

        RemoteClientConfigService.RefreshResult failed = service.refreshIfDue();
        RemoteClientConfigService.RefreshResult gated = service.refreshIfDue();

        assertFalse(failed.successful());
        assertEquals(ClientConfig.EMPTY, failed.config());
        assertFalse(gated.networkAttempted());
        assertEquals(1, requests.get());
    }

    @Test
    void forceRefreshBypassesDailyGate() throws Exception {
        AtomicInteger requests = new AtomicInteger();
        URI endpoint = serve(exchangeBody("{}"), requests);
        RemoteClientConfigService service = service(
                endpoint,
                tempDirectory.resolve("client-config-cache.json"),
                Clock.fixed(Instant.parse("2026-07-27T01:00:00Z"), ZoneOffset.UTC));

        service.refreshIfDue();
        service.forceRefresh();

        assertEquals(2, requests.get());
    }

    private RemoteClientConfigService service(URI endpoint, Path cache, Clock clock) {
        return new RemoteClientConfigService(
                HttpClient.newHttpClient(), new ObjectMapper(), endpoint, cache, clock,
                Duration.ofDays(1), Duration.ofSeconds(2));
    }

    private URI serve(String body, AtomicInteger requests) throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/client-config.json", exchange -> {
            requests.incrementAndGet();
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, bytes.length);
            exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        server.start();
        return URI.create("http://127.0.0.1:" + server.getAddress().getPort()
                + "/client-config.json");
    }

    private static String exchangeBody(String body) {
        return body;
    }
}
