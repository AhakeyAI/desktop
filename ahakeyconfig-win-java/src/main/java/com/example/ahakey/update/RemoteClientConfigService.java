package com.example.ahakey.update;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Objects;

/**
 * Loads {@code client-config.json}, retaining the last valid response locally.
 * Automatic refreshes happen at most once per configured interval (normally one
 * day); callers can explicitly force a refresh from the support page.
 */
public final class RemoteClientConfigService {

    public static final URI DEFAULT_ENDPOINT = URI.create(
            "https://ahakey.com/client-config.json");

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;
    private final URI endpoint;
    private final Path cacheFile;
    private final Clock clock;
    private final Duration refreshInterval;
    private final Duration requestTimeout;

    public RemoteClientConfigService(Path cacheFile) {
        this(CompatibleHttpClient.create(Duration.ofSeconds(10)),
                new ObjectMapper(), DEFAULT_ENDPOINT, cacheFile, Clock.systemUTC(),
                Duration.ofDays(1), Duration.ofSeconds(20));
    }

    public RemoteClientConfigService(
            HttpClient httpClient,
            ObjectMapper objectMapper,
            URI endpoint,
            Path cacheFile,
            Clock clock,
            Duration refreshInterval,
            Duration requestTimeout) {
        this.httpClient = Objects.requireNonNull(httpClient, "httpClient");
        this.objectMapper = Objects.requireNonNull(objectMapper, "objectMapper");
        this.endpoint = Objects.requireNonNull(endpoint, "endpoint");
        this.cacheFile = Objects.requireNonNull(cacheFile, "cacheFile");
        this.clock = Objects.requireNonNull(clock, "clock");
        this.refreshInterval = Objects.requireNonNull(refreshInterval, "refreshInterval");
        this.requestTimeout = Objects.requireNonNull(requestTimeout, "requestTimeout");
        if (refreshInterval.isNegative() || refreshInterval.isZero()) {
            throw new IllegalArgumentException("refreshInterval must be positive");
        }
        if (!"https".equalsIgnoreCase(endpoint.getScheme())
                && !"http".equalsIgnoreCase(endpoint.getScheme())) {
            throw new IllegalArgumentException("Configuration endpoint must use HTTP(S)");
        }
    }

    /** Reads the last valid cached value, or the built-in empty default. */
    public ClientConfig loadCached() {
        return readCache().config();
    }

    /** Refreshes only when the previous attempt is at least one interval old. */
    public RefreshResult refreshIfDue() {
        CacheState state = readCache();
        Instant now = clock.instant();
        if (state.lastCheckedAt() != null
                && now.isBefore(state.lastCheckedAt().plus(refreshInterval))) {
            return new RefreshResult(state.config(), false, true, null);
        }
        return refresh(state, now);
    }

    /** Ignores the daily gate, for the user-facing "refresh" action. */
    public RefreshResult forceRefresh() {
        return refresh(readCache(), clock.instant());
    }

    private RefreshResult refresh(CacheState previous, Instant now) {
        try {
            HttpRequest request = HttpRequest.newBuilder(endpoint)
                    .timeout(requestTimeout)
                    .header("Accept", "application/json")
                    .header("User-Agent", "AhaKeyStudio-Config")
                    .GET()
                    .build();
            HttpResponse<String> response =
                    httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                String message = "Remote configuration request failed with HTTP "
                        + response.statusCode();
                writeCacheBestEffort(previous.config(), now);
                return new RefreshResult(previous.config(), true, false, message);
            }
            ClientConfig downloaded = parseConfig(response.body());
            writeCache(downloaded, now);
            return new RefreshResult(downloaded, true, true, null);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            writeCacheBestEffort(previous.config(), now);
            return new RefreshResult(previous.config(), true, false,
                    "Remote configuration request was interrupted");
        } catch (IOException | RuntimeException exception) {
            writeCacheBestEffort(previous.config(), now);
            return new RefreshResult(previous.config(), true, false, exception.getMessage());
        }
    }

    ClientConfig parseConfig(String json) throws IOException {
        JsonNode root = objectMapper.readTree(json);
        JsonNode supportUrl = root.get("supportUrl");
        if (supportUrl == null || supportUrl.isNull() || supportUrl.asText().isBlank()) {
            return ClientConfig.EMPTY;
        }
        try {
            return ClientConfig.ofSupportUrl(supportUrl.asText());
        } catch (IllegalArgumentException exception) {
            throw new IOException("Remote supportUrl is invalid", exception);
        }
    }

    private CacheState readCache() {
        if (!Files.isRegularFile(cacheFile)) {
            return CacheState.EMPTY;
        }
        try {
            JsonNode root = objectMapper.readTree(Files.readString(cacheFile));
            ClientConfig config = ClientConfig.ofSupportUrl(
                    root.path("config").path("supportUrl").asText(""));
            String checked = root.path("lastCheckedAt").asText("");
            Instant lastCheckedAt = checked.isBlank() ? null : Instant.parse(checked);
            return new CacheState(config, lastCheckedAt);
        } catch (IOException | RuntimeException exception) {
            return CacheState.EMPTY;
        }
    }

    private void writeCacheBestEffort(ClientConfig config, Instant checkedAt) {
        try {
            writeCache(config, checkedAt);
        } catch (IOException ignored) {
            // Cache failures must never make the desktop application unavailable.
        }
    }

    private void writeCache(ClientConfig config, Instant checkedAt) throws IOException {
        Path absolute = cacheFile.toAbsolutePath();
        Path parent = absolute.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        ObjectNode root = objectMapper.createObjectNode();
        root.put("lastCheckedAt", checkedAt.toString());
        ObjectNode configNode = root.putObject("config");
        config.supportUrl().ifPresentOrElse(
                uri -> configNode.put("supportUrl", uri.toString()),
                () -> configNode.putNull("supportUrl"));
        Path temporary = absolute.resolveSibling(absolute.getFileName() + ".tmp");
        objectMapper.writerWithDefaultPrettyPrinter().writeValue(temporary.toFile(), root);
        try {
            Files.move(temporary, absolute,
                    StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (AtomicMoveNotSupportedException exception) {
            Files.move(temporary, absolute, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private record CacheState(ClientConfig config, Instant lastCheckedAt) {
        private static final CacheState EMPTY = new CacheState(ClientConfig.EMPTY, null);
    }

    public record RefreshResult(
            ClientConfig config,
            boolean networkAttempted,
            boolean successful,
            String errorMessage) {
    }
}
