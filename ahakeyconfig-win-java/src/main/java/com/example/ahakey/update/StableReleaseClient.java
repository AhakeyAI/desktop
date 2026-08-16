package com.example.ahakey.update;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Objects;
import java.util.Optional;

/** Reads the mainland-friendly stable release manifest from ahakey.com. */
public final class StableReleaseClient {
    public static final URI DEFAULT_ENDPOINT =
        URI.create("https://ahakey.com/stable.json");
    private static final int SUPPORTED_SCHEMA_VERSION = 1;
    private static final int MAX_MANIFEST_CHARS = 256 * 1024;

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;
    private final URI endpoint;
    private final Duration requestTimeout;

    public StableReleaseClient() {
        this(CompatibleHttpClient.create(Duration.ofSeconds(10)),
            new ObjectMapper(), configuredEndpoint(), Duration.ofSeconds(20));
    }

    StableReleaseClient(
            HttpClient httpClient,
            ObjectMapper objectMapper,
            URI endpoint,
            Duration requestTimeout) {
        this.httpClient = Objects.requireNonNull(httpClient, "httpClient");
        this.objectMapper = Objects.requireNonNull(objectMapper, "objectMapper");
        this.endpoint = Objects.requireNonNull(endpoint, "endpoint");
        this.requestTimeout = Objects.requireNonNull(
            requestTimeout, "requestTimeout");
    }

    public Optional<StableRelease> fetchLatest()
            throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(endpoint)
            .timeout(requestTimeout)
            .header("Accept", "application/json")
            .header("User-Agent", "AhaKeyStudio-Updater")
            .GET()
            .build();
        HttpResponse<String> response =
            httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() == 404 || response.statusCode() == 204) {
            return Optional.empty();
        }
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            throw new IOException(
                "AhaKey stable update service failed with HTTP "
                    + response.statusCode());
        }
        if (response.body().length() > MAX_MANIFEST_CHARS) {
            throw new IOException("Stable release manifest is unexpectedly large");
        }
        return parse(response.body());
    }

    Optional<StableRelease> parse(String json) throws IOException {
        JsonNode root = objectMapper.readTree(json);
        if (root.path("schemaVersion").asInt(-1) != SUPPORTED_SCHEMA_VERSION) {
            throw new IOException("Unsupported stable release manifest schema");
        }
        if (!"stable".equalsIgnoreCase(root.path("channel").asText())) {
            throw new IOException("Release manifest is not the stable channel");
        }
        if (!root.path("available").asBoolean(false)) {
            return Optional.empty();
        }

        JsonNode app = requiredObject(root, "app");
        SemanticVersion appVersion = parseVersion(
            requiredText(app, "version"), "app.version");
        JsonNode windows = requiredObject(app, "windows");
        ReleaseAsset installer = parseAsset(
            windows,
            "AhaKeyStudio-" + appVersion + "-windows-x64.exe",
            "app.windows");

        Optional<StableRelease.FirmwareAsset> firmware = Optional.empty();
        JsonNode ch582 = root.path("firmware").path("ch582");
        if (!ch582.isMissingNode() && !ch582.isNull()) {
            if (!ch582.isObject()) {
                throw new IOException("firmware.ch582 must be an object");
            }
            SemanticVersion firmwareVersion = parseVersion(
                requiredText(ch582, "version"), "firmware.ch582.version");
            ReleaseAsset firmwareAsset = parseAsset(
                ch582,
                "AhaKey-X1-firmware-" + firmwareVersion + "-ch582.hex",
                "firmware.ch582");
            firmware = Optional.of(new StableRelease.FirmwareAsset(
                firmwareVersion, firmwareAsset));
        }

        return Optional.of(new StableRelease(
            appVersion,
            nullableText(app, "name"),
            nullableText(app, "notes"),
            installer,
            firmware));
    }

    private static ReleaseAsset parseAsset(
            JsonNode node, String expectedName, String path) throws IOException {
        String name = requiredText(node, "name");
        if (!expectedName.equals(name)) {
            throw new IOException(
                path + ".name must be " + expectedName);
        }
        try {
            URI url = URI.create(requiredText(node, "url"));
            return new ReleaseAsset(name, url);
        } catch (IllegalArgumentException exception) {
            throw new IOException("Invalid release asset at " + path, exception);
        }
    }

    private static SemanticVersion parseVersion(
            String value, String path) throws IOException {
        try {
            return SemanticVersion.parse(value);
        } catch (IllegalArgumentException exception) {
            throw new IOException("Invalid semantic version at " + path, exception);
        }
    }

    private static JsonNode requiredObject(JsonNode node, String field)
            throws IOException {
        JsonNode value = node.get(field);
        if (value == null || !value.isObject()) {
            throw new IOException("Missing required object: " + field);
        }
        return value;
    }

    private static String requiredText(JsonNode node, String field)
            throws IOException {
        String value = nullableText(node, field);
        if (value == null || value.isBlank()) {
            throw new IOException("Missing required field: " + field);
        }
        return value;
    }

    private static String nullableText(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value == null || value.isNull() ? "" : value.asText();
    }

    private static URI configuredEndpoint() {
        String override = System.getProperty(
            "ahakey.update.manifestUrl", "").trim();
        if (override.isBlank()) {
            return DEFAULT_ENDPOINT;
        }
        URI endpoint = URI.create(override);
        if (!"https".equalsIgnoreCase(endpoint.getScheme())) {
            throw new IllegalArgumentException(
                "ahakey.update.manifestUrl must use HTTPS");
        }
        return endpoint;
    }
}
