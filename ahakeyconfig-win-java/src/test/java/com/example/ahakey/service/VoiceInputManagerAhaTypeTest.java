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
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class VoiceInputManagerAhaTypeTest {
    @TempDir
    Path tempDir;

    @Test
    void cloudProcessingRunsOffTheSpeechCallbackAndInjectsOnce() throws Exception {
        CountDownLatch injected = new CountDownLatch(1);
        AtomicReference<String> injectedText = new AtomicReference<>();
        AtomicInteger requests = new AtomicInteger();
        HttpServer server = server(exchange -> {
            requests.incrementAndGet();
            try {
                Thread.sleep(250);
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
            }
            respond(exchange, 200, "{\"code\":0,\"data\":{\"text\":\"整理文本\"}}");
        });
        try {
            AhaTypeService ahaType = configuredService(server);
            FakeSpeechService speech = new FakeSpeechService();
            VoiceInputManager manager = new VoiceInputManager(speech, null, ahaType,
                value -> { injectedText.set(value); injected.countDown(); });
            CountDownLatch result = new CountDownLatch(1);
            manager.startVoiceInput(value -> result.countDown());
            manager.startRecording();

            long start = System.nanoTime();
            speech.emitFinal("原始文本");
            long callbackMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);

            assertTrue(callbackMillis < 150, "speech callback must not wait for cloud processing");
            assertTrue(result.await(3, TimeUnit.SECONDS));
            assertTrue(injected.await(3, TimeUnit.SECONDS));
            assertEquals("整理文本", injectedText.get());
            assertEquals(1, requests.get());
            manager.shutdown();
        } finally {
            server.stop(0);
        }
    }

    @Test
    void shutdownPreventsAQueuedResultFromBeingInjected() throws Exception {
        CountDownLatch requestStarted = new CountDownLatch(1);
        AtomicInteger injections = new AtomicInteger();
        HttpServer server = server(exchange -> {
            requestStarted.countDown();
            try {
                Thread.sleep(1000);
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
            }
            respond(exchange, 200, "{\"code\":0,\"data\":{\"text\":\"不应注入\"}}");
        });
        try {
            AhaTypeService ahaType = configuredService(server);
            FakeSpeechService speech = new FakeSpeechService();
            VoiceInputManager manager = new VoiceInputManager(speech, null, ahaType,
                value -> injections.incrementAndGet());
            manager.startVoiceInput();
            manager.startRecording();
            speech.emitFinal("原始文本");
            assertTrue(requestStarted.await(2, TimeUnit.SECONDS));

            manager.shutdown();
            Thread.sleep(150);
            assertEquals(0, injections.get());
        } finally {
            server.stop(0);
        }
    }

    private AhaTypeService configuredService(HttpServer server) throws Exception {
        AhaTypeConfig config = new AhaTypeConfig(tempDir.resolve("typeless-" + System.nanoTime() + ".json"));
        Map<String, Object> values = AhaTypeConfig.defaults();
        values.put(AhaTypeConfig.ENABLED, true);
        values.put(AhaTypeConfig.ACCESS_TOKEN, "test-token");
        values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, "2030-01-01T00:00:00Z");
        config.save(values);
        return new AhaTypeService(config, HttpClient.newHttpClient(),
            URI.create(baseUrl(server) + "/prod-api"),
            Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC));
    }

    private static HttpServer server(com.sun.net.httpserver.HttpHandler handler) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", handler);
        server.start();
        return server;
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

    private static final class FakeSpeechService extends SpeechService {
        private Consumer<String> finalCallback;

        @Override
        public void startListening(Consumer<String> partial, Consumer<String> finalResult) {
            finalCallback = finalResult;
        }

        @Override
        public void stopListening() {
            // no blocking microphone in this fake
        }

        void emitFinal(String value) {
            finalCallback.accept(value);
        }

        @Override
        public void release() {
            // no native resources in this fake
        }
    }
}
