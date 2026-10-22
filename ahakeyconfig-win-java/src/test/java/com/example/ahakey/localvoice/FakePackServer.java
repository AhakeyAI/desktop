package com.example.ahakey.localvoice;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/** Local HTTP server that publishes a small fake local voice pack. */
final class FakePackServer implements AutoCloseable {

    final Map<String, byte[]> files = new LinkedHashMap<>();
    final AtomicInteger fileRequests = new AtomicInteger();
    final AtomicInteger rangeRequests = new AtomicInteger();
    /** When set, the manifest advertises this hash for every file (forces a mismatch). */
    volatile String forcedSha256;
    private final HttpServer server;

    FakePackServer() throws IOException {
        for (String path : LocalVoiceManifest.REQUIRED_PATHS) {
            byte[] content = new byte[64 * 1024 + path.length()];
            for (int i = 0; i < content.length; i++) content[i] = (byte) (i * 31 + path.hashCode());
            files.put(path, content);
        }
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/manifest.json", this::manifest);
        server.createContext("/files/", this::file);
        server.start();
    }

    URI manifestUrl() {
        return URI.create(base() + "/manifest.json");
    }

    String base() {
        return "http://127.0.0.1:" + server.getAddress().getPort();
    }

    String manifestJson() {
        StringBuilder json = new StringBuilder("{\"schema\":1,\"packId\":\"test-pack-1\",\"files\":[");
        boolean first = true;
        for (Map.Entry<String, byte[]> entry : files.entrySet()) {
            if (!first) json.append(',');
            first = false;
            String sha = forcedSha256 != null ? forcedSha256 : sha256(entry.getValue());
            json.append("{\"path\":\"").append(entry.getKey())
                .append("\",\"url\":\"").append(base()).append("/files/").append(entry.getKey())
                .append("\",\"size\":").append(entry.getValue().length)
                .append(",\"sha256\":\"").append(sha).append("\"}");
        }
        return json.append("]}").toString();
    }

    private void manifest(HttpExchange exchange) throws IOException {
        byte[] body = manifestJson().getBytes(StandardCharsets.UTF_8);
        exchange.sendResponseHeaders(200, body.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(body);
        }
    }

    private void file(HttpExchange exchange) throws IOException {
        fileRequests.incrementAndGet();
        String path = exchange.getRequestURI().getPath().substring("/files/".length());
        byte[] content = files.get(path);
        if (content == null) {
            exchange.sendResponseHeaders(404, -1);
            exchange.close();
            return;
        }
        int start = 0;
        String range = exchange.getRequestHeaders().getFirst("Range");
        if (range != null && range.startsWith("bytes=")) {
            rangeRequests.incrementAndGet();
            start = Integer.parseInt(range.substring(6, range.indexOf('-')));
            exchange.getResponseHeaders().set("Content-Range",
                "bytes " + start + "-" + (content.length - 1) + "/" + content.length);
            exchange.sendResponseHeaders(206, content.length - start);
        } else {
            exchange.sendResponseHeaders(200, content.length);
        }
        try (OutputStream out = exchange.getResponseBody()) {
            // Small chunks so a cancel during download leaves a partial file behind.
            for (int offset = start; offset < content.length; offset += 4096) {
                out.write(content, offset, Math.min(4096, content.length - offset));
                out.flush();
            }
        } catch (IOException clientWentAway) {
            exchange.close();
        }
    }

    static String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    @Override
    public void close() {
        server.stop(0);
    }
}
