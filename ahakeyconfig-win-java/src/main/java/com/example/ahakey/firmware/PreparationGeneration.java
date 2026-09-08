package com.example.ahakey.firmware;

import java.util.concurrent.atomic.AtomicLong;

/**
 * Monotonic guard for asynchronous firmware preparation callbacks.  A result
 * may update the UI only while its generation remains current.
 */
public final class PreparationGeneration {
    private final AtomicLong latest = new AtomicLong();

    public long begin() { return latest.incrementAndGet(); }
    public boolean isCurrent(long generation) { return latest.get() == generation; }
    public long invalidate() { return latest.incrementAndGet(); }
}
