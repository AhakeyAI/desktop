package com.example.ahakey.app;

import java.util.concurrent.atomic.AtomicBoolean;

/** One-shot decision gate that rejects timeout and ignores late UI actions. */
final class ManualApprovalGate {
    private final AtomicBoolean completed = new AtomicBoolean();
    private volatile boolean allowed;

    boolean complete(boolean allow) {
        if (!completed.compareAndSet(false, true)) return false;
        allowed = allow;
        return true;
    }

    boolean timeout() {
        return complete(false);
    }

    boolean isCompleted() {
        return completed.get();
    }

    boolean isAllowed() {
        return completed.get() && allowed;
    }
}
