package com.example.ahakey.update;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class StableReleaseClientTest {
    private HttpServer server;

    @AfterEach
    void stopServer() {
        if (server != null) {
            server.stop(0);
        }
    }

    @Test
    void parsesIndependentAppAndFirmwareVersions() throws Exception {
        StableRelease release = clientReturning(200, manifest(true))
            .fetchLatest().orElseThrow();

        assertEquals(new SemanticVersion(1, 2, 0), release.appVersion());
        assertEquals("AhaKey Studio 1.2.0", release.appName());
        StableRelease.FirmwareAsset firmware =
            release.ch582Firmware().orElseThrow();
        assertEquals(new SemanticVersion(1, 1, 0), firmware.version());
    }

    @Test
    void unavailableManifestMapsToEmpty() throws Exception {
        assertEquals(Optional.empty(),
            clientReturning(200, manifest(false)).fetchLatest());
    }

    @Test
    void ignoresLegacySha256Fields() throws Exception {
        String legacyManifest = manifest(true).replace(
            "\"url\": \"https://download.ahakey.com/releases/v1.2.0/AhaKeyStudio-1.2.0-windows-x64.exe\"",
            "\"url\": \"https://download.ahakey.com/releases/v1.2.0/AhaKeyStudio-1.2.0-windows-x64.exe\",\n                  \"sha256\": \"stale-value\""
        );
        StableRelease release = clientReturning(200, legacyManifest)
            .fetchLatest().orElseThrow();
        assertEquals(new SemanticVersion(1, 2, 0), release.appVersion());
    }

    @Test
    void rejectsFilenameVersionMismatch() throws Exception {
        String invalid = manifest(true).replace(
            "AhaKeyStudio-1.2.0-windows-x64.exe",
            "AhaKeyStudio-1.1.0-windows-x64.exe");
        assertThrows(Exception.class,
            () -> clientReturning(200, invalid).fetchLatest());
    }

    @Test
    void mapsMissingManifestToEmpty() throws Exception {
        assertEquals(Optional.empty(),
            clientReturning(404, "{}").fetchLatest());
    }

    private String manifest(boolean available) {
        return """
            {
              "schemaVersion": 1,
              "channel": "stable",
              "available": %s,
              "publishedAt": "2026-07-31T00:00:00Z",
              "app": {
                "version": "1.2.0",
                "name": "AhaKey Studio 1.2.0",
                "notes": "Release notes",
                "windows": {
                  "name": "AhaKeyStudio-1.2.0-windows-x64.exe",
                  "url": "https://download.ahakey.com/releases/v1.2.0/AhaKeyStudio-1.2.0-windows-x64.exe"
                }
              },
              "firmware": {
                "ch582": {
                  "version": "1.1.0",
                  "name": "AhaKey-X1-firmware-1.1.0-ch582.hex",
                  "url": "https://download.ahakey.com/releases/v1.2.0/AhaKey-X1-firmware-1.1.0-ch582.hex"
                }
              }
            }
            """.formatted(available);
    }

    private StableReleaseClient clientReturning(int status, String body)
            throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/stable.json", exchange -> {
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(status, bytes.length);
            exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        server.start();
        URI endpoint = URI.create(
            "http://127.0.0.1:" + server.getAddress().getPort()
                + "/stable.json");
        return new StableReleaseClient(
            HttpClient.newHttpClient(),
            new ObjectMapper(),
            endpoint,
            Duration.ofSeconds(2));
    }
}
