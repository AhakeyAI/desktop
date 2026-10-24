package com.example.ahakey.app;

import org.junit.jupiter.api.Test;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class StatusRefreshSchedulerTest {
    @Test
    void statusWaitRunsOffTheCallingThread() throws Exception {
        StatusRefreshScheduler scheduler = new StatusRefreshScheduler();
        try {
            Thread caller = Thread.currentThread();
            CountDownLatch ran = new CountDownLatch(1);
            AtomicReference<Thread> executionThread = new AtomicReference<>();
            scheduler.submit(() -> {
                executionThread.set(Thread.currentThread());
                ran.countDown();
            });

            assertTrue(ran.await(1, TimeUnit.SECONDS));
            assertNotEquals(caller, executionThread.get());
        } finally {
            scheduler.shutdown();
        }
    }
}
