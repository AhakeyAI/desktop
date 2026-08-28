package com.example.ahakey.app;

import org.junit.jupiter.api.Test;

import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ApplicationLifecycleTest {
    @Test
    void allExitCallersUseRegisteredCleanupHandler() {
        AtomicInteger cleanup = new AtomicInteger();
        ApplicationLifecycle.registerExitHandler(cleanup::incrementAndGet);
        ApplicationLifecycle.requestExit();
        assertEquals(1, cleanup.get());
    }
}
