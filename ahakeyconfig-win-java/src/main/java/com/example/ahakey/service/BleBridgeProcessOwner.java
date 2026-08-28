package com.example.ahakey.service;

import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Tracks only the BLE bridge process launched by this application instance. */
public final class BleBridgeProcessOwner {
    private static final AtomicReference<Process> OWNED = new AtomicReference<>();

    private BleBridgeProcessOwner() {}

    public static void register(Process process) {
        if (process != null) OWNED.set(process);
    }

    public static boolean stopOwned() {
        Process process = OWNED.getAndSet(null);
        if (process == null || !process.isAlive()) return false;
        process.destroy();
        try {
            if (!process.waitFor(2, TimeUnit.SECONDS)) process.destroyForcibly();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            process.destroyForcibly();
        }
        return true;
    }
}
