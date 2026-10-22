package com.example.ahakey.platform.voice;

/**
 * Decides when local voice recording starts and stops for the voice key.
 *
 * <ul>
 *   <li>Short press (toggle): first press starts recording, the next press stops it.</li>
 *   <li>Long press (push-to-talk): recording runs while the key is held.</li>
 * </ul>
 *
 * Any press while a toggle recording is running stops it; the release of a
 * long press that only stopped a recording does nothing.
 */
public final class LocalVoicePressHandler {

    public enum Command { START, STOP, NONE }

    /** {@code trigger} says which press started the recording (for per-trigger settings). */
    public record Decision(Command command, VoiceButtonEvent.Type trigger) {
        static final Decision NONE = new Decision(Command.NONE, null);
    }

    private VoiceButtonEvent.Type startedBy;
    private boolean swallowNextLongEnd;

    /**
     * @param type the press event
     * @param currentlyRecording whether the recorder is actually running; used
     *     to resynchronize if recording stopped on its own
     */
    public synchronized Decision onEvent(VoiceButtonEvent.Type type, boolean currentlyRecording) {
        if (!currentlyRecording) startedBy = null;
        switch (type) {
            case SHORT_PRESS -> {
                swallowNextLongEnd = false;
                if (currentlyRecording) {
                    startedBy = null;
                    return new Decision(Command.STOP, null);
                }
                startedBy = VoiceButtonEvent.Type.SHORT_PRESS;
                return new Decision(Command.START, VoiceButtonEvent.Type.SHORT_PRESS);
            }
            case LONG_PRESS_START -> {
                if (currentlyRecording) {
                    // Pressing the key again ends a toggle recording.
                    startedBy = null;
                    swallowNextLongEnd = true;
                    return new Decision(Command.STOP, null);
                }
                swallowNextLongEnd = false;
                startedBy = VoiceButtonEvent.Type.LONG_PRESS_START;
                return new Decision(Command.START, VoiceButtonEvent.Type.LONG_PRESS_START);
            }
            case LONG_PRESS_END -> {
                if (swallowNextLongEnd) {
                    swallowNextLongEnd = false;
                    return Decision.NONE;
                }
                if (currentlyRecording && startedBy == VoiceButtonEvent.Type.LONG_PRESS_START) {
                    startedBy = null;
                    return new Decision(Command.STOP, null);
                }
                return Decision.NONE;
            }
            default -> {
                return Decision.NONE;
            }
        }
    }

    public synchronized void reset() {
        startedBy = null;
        swallowNextLongEnd = false;
    }
}
