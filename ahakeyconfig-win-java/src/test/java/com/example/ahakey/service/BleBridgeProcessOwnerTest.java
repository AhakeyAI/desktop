package com.example.ahakey.service;

import org.junit.jupiter.api.Test;

import java.net.ServerSocket;
import java.nio.file.Path;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BleBridgeProcessOwnerTest {
    @Test
    void executableIdentityIsNormalizedCaseInsensitively() {
        assertTrue(BleBridgeProcessOwner.sameExecutable(
            Path.of("C:/Aha/BLE_tcp_driver.exe"),
            Path.of("c:/aha/./BLE_tcp_driver.exe")));
        assertFalse(BleBridgeProcessOwner.sameExecutable(
            Path.of("C:/Aha/BLE_tcp_driver.exe"),
            Path.of("C:/Other/BLE_tcp_driver.exe")));
    }

    @Test
    void delayedPortStartIsObservedWithinBoundedWindow() throws Exception {
        int port;
        try (ServerSocket reservation = new ServerSocket(0)) {
            port = reservation.getLocalPort();
        }
        CountDownLatch allowBind = new CountDownLatch(1);
        CountDownLatch bound = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<Boolean> ready = executor.submit(
                () -> BleBridgeProcessOwner.waitForTcpPort("127.0.0.1", port, 2_000));
            Future<?> server = executor.submit(() -> {
                allowBind.await();
                try (ServerSocket socket = new ServerSocket(port)) {
                    bound.countDown();
                    release.await(2, TimeUnit.SECONDS);
                }
                return null;
            });
            allowBind.countDown();
            assertTrue(bound.await(1, TimeUnit.SECONDS));
            assertTrue(ready.get(3, TimeUnit.SECONDS));
            release.countDown();
            server.get(3, TimeUnit.SECONDS);
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void portThatNeverStartsFailsAtExplicitDeadline() throws Exception {
        int port;
        try (ServerSocket reservation = new ServerSocket(0)) {
            port = reservation.getLocalPort();
        }
        long started = System.nanoTime();
        assertFalse(BleBridgeProcessOwner.waitForTcpPort("127.0.0.1", port, 150));
        long elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started);
        assertTrue(elapsedMillis < 1_000, "readiness probe must remain bounded");
    }
}
