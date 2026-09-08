package com.example.ahakey.firmware;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.UUID;

/** Durable per-operation diagnostics; failures are retained for support review. */
public class FirmwareUpdateDiagnostics {
    private final Path root;

    public FirmwareUpdateDiagnostics() {
        this(Path.of(System.getProperty("user.home", "."), ".ahakey", "logs",
            "firmware-update"));
    }

    public FirmwareUpdateDiagnostics(Path root) {
        this.root = root.toAbsolutePath().normalize();
    }

    public Path begin(UUID operationId, FirmwareUpdateRequest request) throws IOException {
        Path directory = root.resolve(operationId.toString());
        Files.createDirectories(directory);
        write(directory, "operation.json", "{\n"
            + "  \"operationId\": \"" + operationId + "\",\n"
            + "  \"startedAt\": \"" + Instant.now() + "\",\n"
            + "  \"firmware\": \"" + escape(request.firmwareHex().toString()) + "\",\n"
            + "  \"SELECTED_HEX_PATH\": \"" + escape(request.firmwareHex().toString()) + "\",\n"
            + "  \"SELECTED_HEX_SOURCE\": \"" + request.source() + "\",\n"
            + "  \"SELECTED_HEX_SHA256\": \"" + sha256ForDiagnostics(request.firmwareHex()) + "\"\n"
            + "}\n");
        return directory;
    }

    /** Creates an isolated directory for a non-flashing environment/UID diagnostic. */
    public Path beginDiagnostic(UUID operationId) throws IOException {
        if (operationId == null) throw new IOException("diagnostic operation id is missing");
        Path directory = root.resolve(operationId.toString());
        Files.createDirectories(directory);
        write(directory, "operation.json", "{\n"
            + "  \"operationId\": \"" + operationId + "\",\n"
            + "  \"kind\": \"diagnostic\",\n"
            + "  \"startedAt\": \"" + Instant.now() + "\"\n"
            + "}\n");
        return directory;
    }

    public void write(Path directory, String name, String content) {
        if (directory == null || name == null) return;
        try {
            Files.createDirectories(directory);
            Files.writeString(directory.resolve(name), content == null ? "" : content,
                StandardCharsets.UTF_8);
        } catch (IOException ignored) {
            // Diagnostics must never mask the actual operation result.
        }
    }

    public void writeResult(Path directory, FirmwareUpdateResult result) {
        if (result == null) return;
        write(directory, "result.json", "{\n"
            + "  \"state\": \"" + result.state() + "\",\n"
            + "  \"error\": \"" + (result.error() == null ? "" : result.error()) + "\",\n"
            + "  \"detail\": \"" + escape(result.detail()) + "\"\n"
            + "}\n");
    }

    public Path root() { return root; }

    private static String sha256ForDiagnostics(Path file) {
        try {
            return HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(file)));
        } catch (Exception ignored) {
            return "unavailable";
        }
    }

    private static String escape(String value) {
        return value == null ? "" : value.replace("\\", "\\\\")
            .replace("\"", "\\\"").replace("\n", "\\n");
    }
}
