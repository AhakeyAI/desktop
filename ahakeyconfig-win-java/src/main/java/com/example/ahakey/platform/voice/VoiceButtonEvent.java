package com.example.ahakey.platform.voice;

/** A semantic event emitted by {@link VoiceButtonStateMachine}. */
public record VoiceButtonEvent(Type type, long atNanos) {
    public enum Type {
        SHORT_PRESS,
        LONG_PRESS_START,
        LONG_PRESS_END
    }
}
