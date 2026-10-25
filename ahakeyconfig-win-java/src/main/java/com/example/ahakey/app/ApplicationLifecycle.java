package com.example.ahakey.app;

import java.util.concurrent.atomic.AtomicReference;

/** One exit/restart cleanup entry point shared by views and update flows. */
public final class ApplicationLifecycle {
    private static final AtomicReference<Runnable> EXIT = new AtomicReference<>();

    private ApplicationLifecycle() {}

    public static void registerExitHandler(Runnable handler) {
        EXIT.set(handler);
    }

    public static void requestExit() {
        Runnable handler = EXIT.get();
        if (handler != null) handler.run();
    }
}
