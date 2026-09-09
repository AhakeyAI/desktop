package com.example.ahakey.platform.voice;

import java.time.Duration;
import java.util.Objects;

/**
 * Deterministic state machine for one physical F18 press.  Callers feed it
 * monotonic timestamps; the Windows adapter schedules {@link #onThreshold}
 * while the key is held.  No wall clock or sleeping is used for the decision.
 */
public final class VoiceButtonStateMachine {
    public static final long DEFAULT_THRESHOLD_MS = 350;

    public enum State { IDLE, PRESSED, LONG_ACTIVE }

    private final long thresholdNanos;
    private State state = State.IDLE;
    private long pressedAtNanos;

    public VoiceButtonStateMachine() {
        this(Duration.ofMillis(DEFAULT_THRESHOLD_MS));
    }

    public VoiceButtonStateMachine(Duration threshold) {
        Objects.requireNonNull(threshold, "threshold");
        long nanos = threshold.toNanos();
        if (nanos <= 0) throw new IllegalArgumentException("threshold must be positive");
        thresholdNanos = nanos;
    }

    public VoiceButtonStateMachine(long thresholdMs) {
        this(Duration.ofMillis(thresholdMs));
    }

    public synchronized State state() { return state; }
    public long thresholdNanos() { return thresholdNanos; }
    public synchronized long pressedAtNanos() { return pressedAtNanos; }

    public synchronized VoiceButtonEvent onKeyDown(long nowNanos) {
        if (state != State.IDLE) return null; // hardware repeat is ignored
        state = State.PRESSED;
        pressedAtNanos = nowNanos;
        return null;
    }

    /** Emits LONG_PRESS_START exactly once after the threshold. */
    public synchronized VoiceButtonEvent onThreshold(long nowNanos) {
        if (state != State.PRESSED || nowNanos - pressedAtNanos < thresholdNanos) return null;
        state = State.LONG_ACTIVE;
        return new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_START, nowNanos);
    }

    public synchronized VoiceButtonEvent onKeyUp(long nowNanos) {
        if (state == State.IDLE) return null; // isolated key-up
        VoiceButtonEvent event = state == State.LONG_ACTIVE
            ? new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_END, nowNanos)
            : new VoiceButtonEvent(VoiceButtonEvent.Type.SHORT_PRESS, nowNanos);
        state = State.IDLE;
        pressedAtNanos = 0;
        return event;
    }

    public synchronized void reset() {
        state = State.IDLE;
        pressedAtNanos = 0;
    }
}
