package com.example.ahakey.localvoice;

import com.example.ahakey.update.CompatibleHttpClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.HexFormat;
import java.util.Objects;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.function.BooleanSupplier;

/**
 * Fetches the manifest and downloads the local voice pack into
 * {@link LocalVoiceAssets}. Every file is checked against the manifest's size
 * and SHA-256 before anything is installed.
 */
public final class LocalVoiceInstaller {

    private static final Logger logger = LoggerFactory.getLogger(LocalVoiceInstaller.class);

    public static final URI DEFAULT_MANIFEST_URL =
        URI.create("https://ahakey.com/local-voice/manifest.json");
    static final String MANIFEST_URL_PROPERTY = "ahakey.localVoice.manifestUrl";
    static final String MANIFEST_URL_ENV = "AHAKEY_LOCAL_VOICE_MANIFEST_URL";
    private static final int MAX_MANIFEST_BYTES = 64 * 1024;
    private static final ScheduledExecutorService BODY_WATCHDOG =
        Executors.newSingleThreadScheduledExecutor(task -> {
            Thread thread = new Thread(task, "local-voice-http-cancellation");
            thread.setDaemon(true);
            return thread;
        });

    /** Overall progress across all files of the pack. */
    @FunctionalInterface
    public interface ProgressListener {
        ProgressListener NONE = (done, total, file) -> { };

        void onProgress(long bytesDone, long bytesTotal, String currentFile);
    }

    private final HttpClient httpClient;
    private final LocalVoiceAssets assets;
    private final Duration requestTimeout;

    public LocalVoiceInstaller(LocalVoiceAssets assets) {
        this(CompatibleHttpClient.create(Duration.ofSeconds(15), true), assets, Duration.ofMinutes(30));
    }

    public LocalVoiceInstaller(HttpClient httpClient, LocalVoiceAssets assets, Duration requestTimeout) {
        this.httpClient = Objects.requireNonNull(httpClient, "httpClient");
        this.assets = Objects.requireNonNull(assets, "assets");
        this.requestTimeout = Objects.requireNonNull(requestTimeout, "requestTimeout");
    }

    /** Manifest location; a property or environment variable can point at a test server. */
    public static URI manifestUrl() {
        String configured = System.getProperty(MANIFEST_URL_PROPERTY);
        if (configured == null || configured.isBlank()) configured = System.getenv(MANIFEST_URL_ENV);
        if (configured != null && !configured.isBlank()) {
            URI uri = URI.create(configured.trim());
            if (LocalVoiceManifest.isAllowedUrl(uri)) return uri;
            logger.warn("Ignoring local voice manifest override that is not HTTPS: {}", uri);
        }
        return DEFAULT_MANIFEST_URL;
    }

    public LocalVoiceManifest fetchManifest(URI url) throws IOException, InterruptedException {
        return fetchManifest(url, () -> false);
    }

    public LocalVoiceManifest fetchManifest(URI url, BooleanSupplier cancelled)
            throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(url)
            .timeout(Duration.ofSeconds(20))
            .header("Accept", "application/json")
            .header("User-Agent", "AhaKeyStudio-LocalVoice")
            .GET()
            .build();
        HttpResponse<InputStream> response = send(request, cancelled);
        try (WatchedBody watched = new WatchedBody(response.body(), cancelled, Duration.ofSeconds(20))) {
            InputStream body = watched.stream;
            if (response.statusCode() != 200) {
                throw new IOException("manifest request failed with HTTP " + response.statusCode());
            }
            byte[] bytes = body.readNBytes(MAX_MANIFEST_BYTES + 1);
            if (bytes.length > MAX_MANIFEST_BYTES) throw new IOException("manifest is too large");
            watched.check();
            return LocalVoiceManifest.parse(new String(bytes, StandardCharsets.UTF_8));
        } catch (IOException exception) {
            if (cancelled.getAsBoolean()) throw new CancellationException();
            throw exception;
        }
    }

    /**
     * Downloads and verifies every file, then activates the pack. Throws
     * {@link CancellationException} when {@code cancelled} turns true; partial
     * files are kept so the next attempt resumes.
     */
    public LocalVoiceAssets.InstalledPack install(
        LocalVoiceManifest manifest, ProgressListener listener, BooleanSupplier cancelled
    ) throws IOException, InterruptedException {
        listener = listener == null ? ProgressListener.NONE : listener;
        cancelled = cancelled == null ? () -> false : cancelled;
        if (assets.isInstalled(manifest)) {
            listener.onProgress(manifest.totalBytes(), manifest.totalBytes(), null);
            return assets.installed().orElseThrow();
        }

        Path staging = assets.stagingDir(manifest.packId());
        Files.createDirectories(staging);
        long total = manifest.totalBytes();
        long completedBefore = 0;
        for (LocalVoiceManifest.FileEntry entry : manifest.files()) {
            Path target = staging.resolve(entry.path()).normalize();
            if (!target.startsWith(staging)) throw new IOException("unsafe path: " + entry.path());
            Files.createDirectories(target.getParent());
            if (!(Files.isRegularFile(target) && matches(target, entry))) {
                downloadFile(entry, target, completedBefore, total, listener, cancelled);
            }
            completedBefore += entry.size();
            listener.onProgress(completedBefore, total, entry.path());
        }
        if (cancelled.getAsBoolean()) throw new CancellationException();
        assets.commit(manifest, staging);
        logger.info("Local voice pack {} installed", manifest.packId());
        return assets.installed().orElseThrow(() -> new IOException("pack was not recorded"));
    }

    private void downloadFile(
        LocalVoiceManifest.FileEntry entry, Path target, long completedBefore, long total,
        ProgressListener listener, BooleanSupplier cancelled
    ) throws IOException, InterruptedException {
        Path part = target.resolveSibling(target.getFileName() + ".part");
        long existing = Files.isRegularFile(part) ? Files.size(part) : 0;
        if (existing > entry.size()) {
            Files.delete(part);
            existing = 0;
        }
        if (existing == entry.size()) {
            if (matches(part, entry)) {
                if (cancelled.getAsBoolean()) throw new CancellationException();
                Files.move(part, target, StandardCopyOption.REPLACE_EXISTING);
                return;
            }
            Files.delete(part);
            existing = 0;
        }

        HttpRequest.Builder builder = HttpRequest.newBuilder(entry.url())
            .timeout(requestTimeout)
            .header("User-Agent", "AhaKeyStudio-LocalVoice")
            .GET();
        if (existing > 0) builder.header("Range", "bytes=" + existing + "-");
        HttpResponse<InputStream> response = send(builder.build(), cancelled);

        MessageDigest digest = sha256();
        boolean append;
        if (existing > 0 && response.statusCode() == 206) {
            append = true;
            try (InputStream previous = Files.newInputStream(part)) {
                updateDigest(digest, previous);
            }
        } else if (response.statusCode() == 200) {
            append = false;
            existing = 0;
        } else {
            response.body().close();
            throw new IOException(entry.path() + ": HTTP " + response.statusCode());
        }

        long written = existing;
        try (WatchedBody watched = new WatchedBody(response.body(), cancelled, requestTimeout);
             OutputStream out = Files.newOutputStream(part, StandardOpenOption.CREATE,
                 StandardOpenOption.WRITE,
                 append ? StandardOpenOption.APPEND : StandardOpenOption.TRUNCATE_EXISTING)) {
            byte[] buffer = new byte[128 * 1024];
            int read;
            while ((read = watched.stream.read(buffer)) >= 0) {
                if (cancelled.getAsBoolean()) throw new CancellationException();
                if (read == 0) continue;
                written += read;
                if (written > entry.size()) throw new IOException(entry.path() + ": larger than expected");
                out.write(buffer, 0, read);
                digest.update(buffer, 0, read);
                listener.onProgress(completedBefore + written, total, entry.path());
            }
            watched.check();
        } catch (IOException exception) {
            if (cancelled.getAsBoolean()) throw new CancellationException();
            throw exception;
        }
        if (cancelled.getAsBoolean()) throw new CancellationException();
        if (written != entry.size()) {
            throw new IOException(entry.path() + ": incomplete download (" + written + "/" + entry.size() + ")");
        }
        String actual = HexFormat.of().formatHex(digest.digest());
        if (!actual.equals(entry.sha256())) {
            Files.deleteIfExists(part);
            throw new IOException(entry.path() + ": checksum mismatch");
        }
        Files.move(part, target, StandardCopyOption.REPLACE_EXISTING);
    }

    /** Cancel while waiting for headers as well as while consuming the body. */
    private HttpResponse<InputStream> send(HttpRequest request, BooleanSupplier cancelled)
            throws IOException, InterruptedException {
        if (cancelled.getAsBoolean()) throw new CancellationException();
        var pending = httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofInputStream());
        try {
            while (true) {
                if (cancelled.getAsBoolean()) throw new CancellationException();
                try {
                    HttpResponse<InputStream> response = pending.get(100, TimeUnit.MILLISECONDS);
                    if (cancelled.getAsBoolean()) {
                        response.body().close();
                        throw new CancellationException();
                    }
                    return response;
                } catch (TimeoutException ignored) {
                    // Poll cancellation while HttpClient enforces the header deadline.
                }
            }
        } catch (ExecutionException exception) {
            if (exception.getCause() instanceof IOException failure) throw failure;
            throw new IOException("local voice request failed", exception.getCause());
        } catch (InterruptedException | CancellationException exception) {
            // A completed header response may already own a body; close that too.
            pending.thenAccept(response -> {
                try { response.body().close(); } catch (IOException ignored) { }
            });
            pending.cancel(true);
            throw exception;
        }
    }

    /** HttpRequest.timeout ends at headers for ofInputStream; bound the body separately. */
    private static final class WatchedBody implements AutoCloseable {
        private final InputStream stream;
        private final BooleanSupplier cancelled;
        private final long deadline;
        private final ScheduledFuture<?> watcher;

        private WatchedBody(InputStream stream, BooleanSupplier cancelled, Duration timeout) {
            this.stream = stream;
            this.cancelled = cancelled;
            this.deadline = System.nanoTime() + timeout.toNanos();
            watcher = BODY_WATCHDOG.scheduleWithFixedDelay(() -> {
                if (cancelled.getAsBoolean() || System.nanoTime() >= deadline) {
                    try { stream.close(); } catch (IOException ignored) { }
                }
            }, 0, 100, TimeUnit.MILLISECONDS);
        }

        private void check() throws IOException {
            if (cancelled.getAsBoolean()) throw new CancellationException();
            if (System.nanoTime() >= deadline) throw new IOException("local voice response body timed out");
        }

        @Override public void close() throws IOException {
            watcher.cancel(false);
            stream.close();
        }
    }

    /** Size check first; the hash is only computed when the size already matches. */
    static boolean matches(Path file, LocalVoiceManifest.FileEntry entry) throws IOException {
        if (Files.size(file) != entry.size()) return false;
        MessageDigest digest = sha256();
        try (InputStream in = Files.newInputStream(file)) {
            updateDigest(digest, in);
        }
        return HexFormat.of().formatHex(digest.digest()).equals(entry.sha256());
    }

    private static void updateDigest(MessageDigest digest, InputStream in) throws IOException {
        byte[] buffer = new byte[128 * 1024];
        int read;
        while ((read = in.read(buffer)) >= 0) {
            digest.update(buffer, 0, read);
        }
    }

    private static MessageDigest sha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
