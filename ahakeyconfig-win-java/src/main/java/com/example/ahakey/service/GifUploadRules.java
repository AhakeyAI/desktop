package com.example.ahakey.service;

import com.example.ahakey.protocol.AhaKeyProtocol;

import java.nio.file.Path;
import java.util.Arrays;

/** Single authoritative source for GIF/OLED source and device limits. */
public final class GifUploadRules {
    public static final long MAX_SOURCE_BYTES = AhaKeyProtocol.OLED_MAX_SOURCE_FILE_BYTES;
    public static final long HARD_DECODE_LIMIT_BYTES = 20L * 1024 * 1024;
    public static final int WIDTH = AhaKeyProtocol.OLED_WIDTH;
    public static final int HEIGHT = AhaKeyProtocol.OLED_HEIGHT;
    public static final int MAX_DECODE_FRAMES = 500;
    public static final int DEFAULT_FRAME_DELAY_MS = 100;
    public static final int MIN_FRAME_INTERVAL_MS = 1;
    public static final int MAX_FRAME_INTERVAL_MS = 65_535;

    private GifUploadRules() {}

    public static int frameLimit(int asset) {
        return AhaKeyProtocol.gifAssetCapacity(asset);
    }

    public static OptimizationPlan plan(int[] sourceDelaysMs, int frameLimit) {
        if (sourceDelaysMs == null || sourceDelaysMs.length == 0) {
            throw new IllegalArgumentException("GIF has no frames");
        }
        if (sourceDelaysMs.length > MAX_DECODE_FRAMES) {
            throw new IllegalArgumentException("GIF exceeds safe decode frame limit");
        }
        if (frameLimit <= 0) {
            throw new IllegalArgumentException("GIF frame limit must be positive");
        }
        int outputCount = Math.min(sourceDelaysMs.length, frameLimit);
        long totalDuration = 0;
        int[] normalized = Arrays.copyOf(sourceDelaysMs, sourceDelaysMs.length);
        for (int i = 0; i < normalized.length; i++) {
            normalized[i] = normalized[i] > 0 ? normalized[i] : DEFAULT_FRAME_DELAY_MS;
            totalDuration += normalized[i];
        }
        int interval = (int) Math.max(MIN_FRAME_INTERVAL_MS,
            Math.min(MAX_FRAME_INTERVAL_MS, Math.round((double) totalDuration / outputCount)));
        int[] indices = new int[outputCount];
        if (sourceDelaysMs.length <= frameLimit) {
            for (int index = 0; index < outputCount; index++) {
                indices[index] = index;
            }
            return new OptimizationPlan(indices, interval, totalDuration);
        }
        long[] starts = new long[normalized.length];
        long cursor = 0;
        for (int i = 0; i < normalized.length; i++) {
            starts[i] = cursor;
            cursor += normalized[i];
        }
        for (int out = 0; out < outputCount; out++) {
            long target = Math.min(totalDuration - 1,
                Math.round((out + 0.5d) * totalDuration / outputCount));
            int selected = Arrays.binarySearch(starts, target);
            if (selected < 0) selected = Math.max(0, -selected - 2);
            int minimum = out == 0 ? 0 : indices[out - 1] + 1;
            int maximum = normalized.length - (outputCount - out);
            indices[out] = Math.max(minimum, Math.min(selected, maximum));
        }
        return new OptimizationPlan(indices, interval, totalDuration);
    }

    public record OptimizationPlan(
        int[] sourceIndices,
        int frameIntervalMs,
        long sourceDurationMs
    ) {
        public int outputFrameCount() {
            return sourceIndices.length;
        }

        public long outputDurationMs() {
            return (long) frameIntervalMs * sourceIndices.length;
        }

        public boolean dropsFrames(int sourceFrameCount) {
            return sourceIndices.length < sourceFrameCount;
        }
    }

    public record Preflight(
        Path path,
        long fileBytes,
        int width,
        int height,
        int sourceFrames,
        long sourceDurationMs,
        int targetFrameLimit
    ) {
        public boolean needsOptimization() {
            return fileBytes > MAX_SOURCE_BYTES || width != WIDTH || height != HEIGHT
                || sourceFrames > targetFrameLimit;
        }
    }
}
