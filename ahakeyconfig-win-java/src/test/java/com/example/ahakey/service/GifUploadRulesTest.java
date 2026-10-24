package com.example.ahakey.service;

import org.junit.jupiter.api.Test;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class GifUploadRulesTest {
    @Test
    void timelineSamplingPreservesTotalDurationWithoutFixedFps() {
        int[] delays = {20, 30, 50, 100, 200, 300};
        GifUploadRules.OptimizationPlan plan = GifUploadRules.plan(delays, 3);

        assertEquals(3, plan.outputFrameCount());
        assertEquals(700, plan.sourceDurationMs());
        assertEquals(233, plan.frameIntervalMs());
        assertEquals(699, plan.outputDurationMs());
        assertArrayEquals(new int[]{3, 4, 5}, plan.sourceIndices());
    }

    @Test
    void zeroGifDelayUsesDocumentedDefault() {
        GifUploadRules.OptimizationPlan plan = GifUploadRules.plan(new int[]{0, 0}, 8);
        assertEquals(100, plan.frameIntervalMs());
        assertEquals(200, plan.sourceDurationMs());
    }

    @Test
    void unevenDelaysWithinLimitPreserveBothFramesInSourceOrder() {
        GifUploadRules.OptimizationPlan plan =
            GifUploadRules.plan(new int[]{100, 900}, 2);

        assertArrayEquals(new int[]{0, 1}, plan.sourceIndices());
        assertFalse(plan.dropsFrames(2));
    }

    @Test
    void sourceBelowLimitPreservesEveryFrameInSourceOrder() {
        GifUploadRules.OptimizationPlan plan =
            GifUploadRules.plan(new int[]{10, 500, 20}, 8);

        assertArrayEquals(new int[]{0, 1, 2}, plan.sourceIndices());
        assertFalse(plan.dropsFrames(3));
    }

    @Test
    void sourceEqualToLimitPreservesEveryFrameInSourceOrder() {
        GifUploadRules.OptimizationPlan plan =
            GifUploadRules.plan(new int[]{10, 500, 20}, 3);

        assertArrayEquals(new int[]{0, 1, 2}, plan.sourceIndices());
        assertFalse(plan.dropsFrames(3));
    }

    @Test
    void sourceAboveLimitIsSampledToStrictlyOrderedLegalIndices() {
        int[] delays = {10, 900, 10, 20, 30, 40};
        GifUploadRules.OptimizationPlan plan = GifUploadRules.plan(delays, 3);

        assertTrue(plan.dropsFrames(delays.length));
        assertTrue(plan.outputFrameCount() <= 3);
        int previous = -1;
        for (int index : plan.sourceIndices()) {
            assertTrue(index >= 0 && index < delays.length);
            assertTrue(index > previous);
            previous = index;
        }
        assertTrue(Math.abs(plan.outputDurationMs() - plan.sourceDurationMs())
            <= plan.outputFrameCount() / 2L);
    }

    @Test
    void preflightRequestsConfirmationOnlyForRealOptimization() {
        GifUploadRules.Preflight unchanged = new GifUploadRules.Preflight(
            Path.of("normal.gif"), 100, GifUploadRules.WIDTH, GifUploadRules.HEIGHT,
            2, 1_000, 2);
        GifUploadRules.Preflight resized = new GifUploadRules.Preflight(
            Path.of("large.gif"), 100, 320, 160, 2, 1_000, 2);
        GifUploadRules.Preflight sampled = new GifUploadRules.Preflight(
            Path.of("many.gif"), 100, GifUploadRules.WIDTH, GifUploadRules.HEIGHT,
            3, 1_000, 2);

        assertFalse(unchanged.needsOptimization());
        assertTrue(resized.needsOptimization());
        assertTrue(sampled.needsOptimization());
    }

    @Test
    void readbackMustMatchAllPersistedFields() {
        OledUploadService.AssetState actual =
            new OledUploadService.AssetState(0, 1, 20, 12, 83, 132);
        OledUploadService.verifyAssetState(actual, 20, 12, 83);
        assertThrows(IllegalStateException.class,
            () -> OledUploadService.verifyAssetState(actual, 20, 12, 84));
    }
}
