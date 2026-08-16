package com.example.ahakey.update;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicLong;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AssetDownloaderTest {

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
    void downloadsWithProgressAndValidatesFirmwareFormat() throws Exception {
        byte[] content = ":00000001FF\n".getBytes(StandardCharsets.US_ASCII);
        URI url = serve(content);
        ReleaseAsset asset = new ReleaseAsset("firmware.hex", url);
        Path destination = tempDirectory.resolve("firmware.hex");
        AtomicLong finalProgress = new AtomicLong();

        AssetDownloader.DownloadResult result = new AssetDownloader(
                HttpClient.newHttpClient(), Duration.ofSeconds(2))
                .download(asset, destination, (downloaded, total) -> finalProgress.set(downloaded));

        assertEquals(":00000001FF\n", Files.readString(destination));
        assertEquals(content.length, finalProgress.get());
        assertEquals(content.length, result.bytes());
    }

    @Test
    void invalidFirmwareRemovesPartialFile() throws Exception {
        URI url = serve("bad".getBytes(StandardCharsets.UTF_8));
        ReleaseAsset asset = new ReleaseAsset("firmware.hex", url);
        Path destination = tempDirectory.resolve("firmware.hex");

        assertThrows(java.io.IOException.class,
                () -> new AssetDownloader(HttpClient.newHttpClient(), Duration.ofSeconds(2))
                        .download(asset, destination, null));

        assertFalse(Files.exists(destination));
        assertFalse(Files.exists(tempDirectory.resolve("firmware.hex.part")));
    }

    private URI serve(byte[] content) throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/asset", exchange -> {
            exchange.sendResponseHeaders(200, content.length);
            exchange.getResponseBody().write(content);
            exchange.close();
        });
        server.start();
        return URI.create("http://127.0.0.1:" + server.getAddress().getPort() + "/asset");
    }
}
