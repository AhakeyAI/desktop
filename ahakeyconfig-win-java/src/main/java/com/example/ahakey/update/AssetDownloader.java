package com.example.ahakey.update;

import java.io.IOException;
import java.io.InputStream;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.util.Objects;

/** Streams an HTTPS release attachment with lightweight format validation. */
public final class AssetDownloader {

    private final HttpClient httpClient;
    private final Duration timeout;

    public AssetDownloader() {
        this(CompatibleHttpClient.create(Duration.ofSeconds(15)),
                Duration.ofMinutes(10));
    }

    public AssetDownloader(HttpClient httpClient, Duration timeout) {
        this.httpClient = Objects.requireNonNull(httpClient, "httpClient");
        this.timeout = Objects.requireNonNull(timeout, "timeout");
    }

    public DownloadResult download(
            ReleaseAsset asset, Path destination, ProgressListener listener)
            throws IOException, InterruptedException {
        Objects.requireNonNull(asset, "asset");
        Objects.requireNonNull(destination, "destination");
        listener = listener == null ? ProgressListener.NONE : listener;

        Path absoluteDestination = destination.toAbsolutePath();
        Path parent = absoluteDestination.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        Path temporary = absoluteDestination.resolveSibling(
                absoluteDestination.getFileName() + ".part");
        Files.deleteIfExists(temporary);

        HttpRequest request = HttpRequest.newBuilder(asset.downloadUrl())
                .timeout(timeout)
                .header("User-Agent", "AhaKeyStudio-Updater")
                .GET()
                .build();
        HttpResponse<InputStream> response =
                httpClient.send(request, HttpResponse.BodyHandlers.ofInputStream());
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            response.body().close();
            throw new IOException("Asset download failed with HTTP " + response.statusCode());
        }

        long totalBytes = response.headers().firstValueAsLong("Content-Length").orElse(-1);
        long downloaded = 0;
        try (InputStream body = response.body();
             InputStream input = body;
             var output = Files.newOutputStream(temporary)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            listener.onProgress(0, totalBytes);
            while ((read = input.read(buffer)) >= 0) {
                if (read == 0) {
                    continue;
                }
                output.write(buffer, 0, read);
                downloaded += read;
                listener.onProgress(downloaded, totalBytes);
            }
        } catch (IOException | RuntimeException exception) {
            Files.deleteIfExists(temporary);
            throw exception;
        }

        if (downloaded <= 0) {
            Files.deleteIfExists(temporary);
            throw new IOException("Downloaded asset is empty");
        }
        if (totalBytes >= 0 && downloaded != totalBytes) {
            Files.deleteIfExists(temporary);
            throw new IOException("Incomplete download: expected " + totalBytes
                + " bytes, got " + downloaded);
        }
        try {
            validateFormat(asset.name(), temporary);
        } catch (IOException | RuntimeException exception) {
            Files.deleteIfExists(temporary);
            throw exception;
        }

        moveReplacingWithRetry(temporary, absoluteDestination);
        return new DownloadResult(absoluteDestination, downloaded);
    }

    static void validateFormat(String name, Path file) throws IOException {
        String lower = name.toLowerCase(java.util.Locale.ROOT);
        if (lower.endsWith(".exe")) {
            byte[] header = new byte[2];
            try (InputStream input = Files.newInputStream(file)) {
                if (input.read(header) != 2 || header[0] != 'M' || header[1] != 'Z') {
                    throw new IOException("Downloaded installer is not a valid Windows executable");
                }
            }
        } else if (lower.endsWith(".hex")) {
            boolean record = false;
            boolean eof = false;
            for (String line : Files.readAllLines(file,
                    java.nio.charset.StandardCharsets.US_ASCII)) {
                String trimmed = line.trim();
                if (trimmed.isEmpty()) continue;
                if (!trimmed.matches(":[0-9A-Fa-f]+") || (trimmed.length() & 1) == 0) {
                    throw new IOException("Downloaded firmware is not valid Intel HEX");
                }
                record = true;
                if (trimmed.equalsIgnoreCase(":00000001FF")) eof = true;
            }
            if (!record || !eof) {
                throw new IOException("Downloaded firmware is missing the Intel HEX end record");
            }
        }
    }

    private static void moveReplacingWithRetry(Path source, Path destination)
            throws IOException, InterruptedException {
        IOException last = null;
        for (int attempt = 1; attempt <= 4; attempt++) {
            try {
                try {
                    Files.move(source, destination, StandardCopyOption.REPLACE_EXISTING,
                        StandardCopyOption.ATOMIC_MOVE);
                } catch (AtomicMoveNotSupportedException exception) {
                    Files.deleteIfExists(destination);
                    Files.move(source, destination, StandardCopyOption.REPLACE_EXISTING);
                }
                return;
            } catch (IOException exception) {
                last = exception;
                if (attempt < 4) Thread.sleep(attempt * 200L);
            }
        }
        throw new IOException(source + " -> " + destination + ": "
            + (last == null ? "unable to finalize download" : last.getMessage()), last);
    }

    @FunctionalInterface
    public interface ProgressListener {
        ProgressListener NONE = (downloadedBytes, totalBytes) -> {
        };

        void onProgress(long downloadedBytes, long totalBytes);
    }

    public record DownloadResult(Path path, long bytes) {
    }
}
