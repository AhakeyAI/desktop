package com.example.ahakey.platform.voice;

import java.time.Duration;
import java.util.List;
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

    /**
     * Completes a press using the physical up timestamp as the source of
     * truth.  This compensates for a late scheduler callback: a held key can
     * still become LONG_START followed by LONG_END even when the threshold
     * task never ran before the UP event.
     */
    public synchronized List<VoiceButtonEvent> onKeyUp(long nowNanos) {
        if (state == State.IDLE) return List.of(); // isolated key-up
        long durationNanos = Math.max(0, nowNanos - pressedAtNanos);
        List<VoiceButtonEvent> events;
        if (state == State.LONG_ACTIVE) {
            events = List.of(new VoiceButtonEvent(
                VoiceButtonEvent.Type.LONG_PRESS_END, nowNanos));
        } else if (durationNanos >= thresholdNanos) {
            // The scheduled threshold may be late; preserve the semantic
            // ordering required by the press-to-talk integration.
            events = List.of(
                new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_START, nowNanos),
                new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_END, nowNanos));
            state = State.LONG_ACTIVE;
        } else {
            events = List.of(new VoiceButtonEvent(
                VoiceButtonEvent.Type.SHORT_PRESS, nowNanos));
        }
        state = State.IDLE;
        pressedAtNanos = 0;
        return events;
    }

    public synchronized void reset() {
        state = State.IDLE;
        pressedAtNanos = 0;
    }
}
