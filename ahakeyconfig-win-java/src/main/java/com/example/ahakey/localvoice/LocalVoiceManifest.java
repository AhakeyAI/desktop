package com.example.ahakey.localvoice;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.net.URI;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Download list for the local voice pack, published at
 * {@code https://ahakey.com/local-voice/manifest.json}.
 *
 * <pre>{@code
 * {
 *   "schema": 1,
 *   "packId": "paraformer-zh-en-int8-1",
 *   "files": [
 *     {"path": "models/encoder.int8.onnx", "url": "https://...", "size": 123, "sha256": "..."},
 *     ...
 *   ]
 * }
 * }</pre>
 *
 * Only the files the client actually loads are accepted, so a manifest can
 * never write anywhere else on disk.
 */
public record LocalVoiceManifest(String packId, List<FileEntry> files) {

    public static final int SCHEMA = 1;

    /** Files that must be present for recognition to start. */
    public static final Set<String> REQUIRED_PATHS = Set.of(
        "models/encoder.int8.onnx",
        "models/decoder.int8.onnx",
        "models/tokens.txt",
        "native/win-x64/onnxruntime.dll",
        "native/win-x64/sherpa-onnx-jni.dll");

    /** Files that may be present; anything else is rejected. */
    public static final Set<String> OPTIONAL_PATHS = Set.of(
        "models/silero_vad.onnx",
        "native/win-x64/onnxruntime_providers_shared.dll");

    private static final Pattern PACK_ID = Pattern.compile("[A-Za-z0-9][A-Za-z0-9._-]{0,63}");
    private static final Pattern SHA256 = Pattern.compile("[0-9a-f]{64}");
    /** Generous upper bound per file; the real pack is a few hundred MB. */
    private static final long MAX_FILE_BYTES = 2L * 1024 * 1024 * 1024;

    public record FileEntry(String path, URI url, long size, String sha256) {
    }

    public LocalVoiceManifest {
        files = List.copyOf(files);
    }

    public long totalBytes() {
        return files.stream().mapToLong(FileEntry::size).sum();
    }

    public static LocalVoiceManifest parse(String json) throws IOException {
        JsonNode root = new ObjectMapper().readTree(json);
        if (root == null || !root.isObject()) throw new IOException("manifest is not a JSON object");
        if (root.path("schema").asInt(-1) != SCHEMA) {
            throw new IOException("unsupported manifest schema: " + root.path("schema").asText());
        }
        String packId = root.path("packId").asText("");
        if (!PACK_ID.matcher(packId).matches()) throw new IOException("invalid packId");

        JsonNode filesNode = root.path("files");
        if (!filesNode.isArray() || filesNode.isEmpty()) throw new IOException("manifest has no files");
        List<FileEntry> files = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (JsonNode node : filesNode) {
            String path = node.path("path").asText("");
            if (!REQUIRED_PATHS.contains(path) && !OPTIONAL_PATHS.contains(path)) {
                throw new IOException("unexpected file in manifest: " + path);
            }
            if (!seen.add(path)) throw new IOException("duplicate file in manifest: " + path);
            URI url;
            try {
                url = URI.create(node.path("url").asText(""));
            } catch (IllegalArgumentException e) {
                throw new IOException("invalid url for " + path, e);
            }
            if (!isAllowedUrl(url)) throw new IOException("url must use https: " + path);
            long size = node.path("size").asLong(-1);
            if (size <= 0 || size > MAX_FILE_BYTES) throw new IOException("invalid size for " + path);
            String sha256 = node.path("sha256").asText("").toLowerCase(Locale.ROOT);
            if (!SHA256.matcher(sha256).matches()) throw new IOException("invalid sha256 for " + path);
            files.add(new FileEntry(path, url, size, sha256));
        }
        if (!seen.containsAll(REQUIRED_PATHS)) {
            Set<String> missing = new HashSet<>(REQUIRED_PATHS);
            missing.removeAll(seen);
            throw new IOException("manifest is missing required files: " + missing);
        }
        return new LocalVoiceManifest(packId, files);
    }

    /** HTTPS everywhere; plain HTTP is only accepted for a local test server. */
    static boolean isAllowedUrl(URI url) {
        if (url == null || url.getHost() == null) return false;
        String scheme = url.getScheme() == null ? "" : url.getScheme().toLowerCase(Locale.ROOT);
        if (scheme.equals("https")) return true;
        String host = url.getHost().toLowerCase(Locale.ROOT);
        return scheme.equals("http") && (host.equals("127.0.0.1") || host.equals("localhost"));
    }
}
