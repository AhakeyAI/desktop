package com.example.ahakey.service;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LightOperationCoordinatorTest {
    @Test
    void brightnessFailureIsFinalAndSkipsEffectAndSuccess() {
        AtomicInteger effectWrites = new AtomicInteger();

        LightOperationCoordinator.Result result = LightOperationCoordinator.execute(
            "已发送",
            LightOperationCoordinator.step("亮度写入",
                () -> { throw new IOException("brightness transport down"); }),
            LightOperationCoordinator.step("灯效写入", effectWrites::incrementAndGet));

        assertFalse(result.success());
        assertEquals("亮度写入失败：brightness transport down", result.message());
        assertEquals(0, effectWrites.get());
    }

    @Test
    void effectFailureAfterSuccessfulBrightnessRemainsFailure() {
        AtomicInteger brightnessWrites = new AtomicInteger();

        LightOperationCoordinator.Result result = LightOperationCoordinator.execute(
            "已发送",
            LightOperationCoordinator.step("亮度写入", brightnessWrites::incrementAndGet),
            LightOperationCoordinator.step("灯效写入",
                () -> { throw new IOException("effect rejected"); }));

        assertFalse(result.success());
        assertEquals(1, brightnessWrites.get());
        assertEquals("灯效写入失败：effect rejected", result.message());
    }

    @Test
    void successIsPublishedOnlyAfterEveryStepSucceeds() {
        List<String> writes = new ArrayList<>();

        LightOperationCoordinator.Result result = LightOperationCoordinator.execute(
            "已发送灯光亮度：42",
            LightOperationCoordinator.step("亮度写入", () -> writes.add("brightness")),
            LightOperationCoordinator.step("灯效写入", () -> writes.add("effect")));

        assertTrue(result.success());
        assertEquals(List.of("brightness", "effect"), writes);
        assertEquals("已发送灯光亮度：42", result.message());
    }

    @Test
    void oneFinalPublicationCannotBeOverwrittenByQueuedSuccess() {
        AtomicReference<String> uiStatus = new AtomicReference<>();
        AtomicInteger publications = new AtomicInteger();
        LightOperationCoordinator.Result result = LightOperationCoordinator.execute(
            "成功消息",
            LightOperationCoordinator.step("灯效写入",
                () -> { throw new IOException("device timeout"); }));

        uiStatus.set(result.message());
        publications.incrementAndGet();

        assertEquals(1, publications.get());
        assertEquals("灯效写入失败：device timeout", uiStatus.get());
    }
}
