package com.example.ahakey.app;

import java.util.Objects;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Keeps bounded physical status waits off JavaFX callbacks.
 */
final class StatusRefreshScheduler {
    private final Executor executor;
    private final ExecutorService ownedExecutor;

    StatusRefreshScheduler() {
        ExecutorService service = Executors.newSingleThreadExecutor(r -> {
            Thread thread = new Thread(r, "status-refresh");
            thread.setDaemon(true);
            return thread;
        });
        executor = service;
        ownedExecutor = service;
    }

    StatusRefreshScheduler(Executor executor) {
        this.executor = Objects.requireNonNull(executor, "executor");
        ownedExecutor = null;
    }

    void submit(Runnable refresh) {
        executor.execute(refresh);
    }

    void shutdown() {
        if (ownedExecutor != null) {
            ownedExecutor.shutdownNow();
        }
    }
}
