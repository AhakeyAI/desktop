package com.example.ahakey.service;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Locale;
import java.util.Objects;
import java.util.UUID;

/** Owns local copies of successfully uploaded screen assets. */
public final class ScreenAnimationAssetStore {
    private final Path root;

    public ScreenAnimationAssetStore() {
        this(Path.of(System.getProperty("user.home"), ".ahakey", "screen-assets"));
    }

    public ScreenAnimationAssetStore(Path root) {
        this.root = Objects.requireNonNull(root).toAbsolutePath().normalize();
    }

    public StoredAsset store(Path source, ModeSlot mode, int asset,
                             int frameCount, int width, int height) throws IOException {
        if (source == null || !Files.isRegularFile(source)) {
            throw new IOException("屏幕资源文件不存在");
        }
        if (mode == null || asset < 0 || asset >= 4) {
            throw new IOException("屏幕资源分区无效");
        }
        String extension = extension(source);
        String sha256 = sha256(source);
        Path modeDir = root.resolve("mode-" + mode.getIndex());
        Files.createDirectories(modeDir);
        Path destination = modeDir.resolve("asset-" + asset + "-" + sha256.substring(0, 16)
            + extension);
        Path temporary = modeDir.resolve("." + destination.getFileName() + "."
            + UUID.randomUUID() + ".tmp");
        try {
            Files.copy(source, temporary, StandardCopyOption.REPLACE_EXISTING);
            try {
                Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING);
            } catch (java.nio.file.AtomicMoveNotSupportedException unsupported) {
                Files.move(temporary, destination, StandardCopyOption.REPLACE_EXISTING);
            }
        } finally {
            Files.deleteIfExists(temporary);
        }
        StudioState.PersistedDraft.ScreenAssetMetadata metadata =
            new StudioState.PersistedDraft.ScreenAssetMetadata();
        metadata.originalFileName = source.getFileName().toString();
        metadata.originalSourcePath = source.toAbsolutePath().normalize().toString();
        metadata.managedCachePath = destination.toString();
        metadata.mediaType = extension.equals(".gif") ? "gif" : "static";
        metadata.frameCount = Math.max(1, frameCount);
        metadata.width = Math.max(0, width);
        metadata.height = Math.max(0, height);
        metadata.fileSize = Files.size(destination);
        metadata.sha256 = sha256;
        metadata.updatedAt = Instant.now().toString();
        return new StoredAsset(destination, metadata);
    }

    public static boolean isUsable(StudioState.PersistedDraft.ScreenAssetMetadata metadata) {
        return metadata != null && metadata.managedCachePath != null
            && Files.isRegularFile(Path.of(metadata.managedCachePath));
    }

    private static String extension(Path source) throws IOException {
        String name = source.getFileName().toString().toLowerCase(Locale.ROOT);
        if (name.endsWith(".gif")) return ".gif";
        if (name.endsWith(".png")) return ".png";
        if (name.endsWith(".jpg") || name.endsWith(".jpeg")) return ".jpg";
        throw new IOException("仅支持 GIF、PNG 或 JPG 屏幕资源");
    }

    private static String sha256(Path source) throws IOException {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(source));
            StringBuilder result = new StringBuilder(64);
            for (byte value : digest) result.append(String.format("%02x", value & 0xFF));
            return result.toString();
        } catch (java.security.NoSuchAlgorithmException impossible) {
            throw new IOException("JVM 缺少 SHA-256", impossible);
        }
    }

    public record StoredAsset(Path path, StudioState.PersistedDraft.ScreenAssetMetadata metadata) {}
}
