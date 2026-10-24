package com.example.ahakey.platform.voice;

import org.junit.jupiter.api.Test;

import static com.example.ahakey.platform.voice.LocalVoicePressHandler.Command.NONE;
import static com.example.ahakey.platform.voice.LocalVoicePressHandler.Command.START;
import static com.example.ahakey.platform.voice.LocalVoicePressHandler.Command.STOP;
import static com.example.ahakey.platform.voice.VoiceButtonEvent.Type.LONG_PRESS_END;
import static com.example.ahakey.platform.voice.VoiceButtonEvent.Type.LONG_PRESS_START;
import static com.example.ahakey.platform.voice.VoiceButtonEvent.Type.SHORT_PRESS;
import static org.junit.jupiter.api.Assertions.assertEquals;

class LocalVoicePressHandlerTest {
    @Test
    void shortPressTogglesRecording() {
        LocalVoicePressHandler handler = new LocalVoicePressHandler();
        var start = handler.onEvent(SHORT_PRESS, false);
        assertEquals(START, start.command());
        assertEquals(SHORT_PRESS, start.trigger());
        assertEquals(STOP, handler.onEvent(SHORT_PRESS, true).command());
    }

    @Test
    void longPressRecordsWhileHeld() {
        LocalVoicePressHandler handler = new LocalVoicePressHandler();
        var start = handler.onEvent(LONG_PRESS_START, false);
        assertEquals(START, start.command());
        assertEquals(LONG_PRESS_START, start.trigger());
        assertEquals(STOP, handler.onEvent(LONG_PRESS_END, true).command());
    }

    @Test
    void longPressDuringAToggleRecordingStopsItAndItsReleaseDoesNothing() {
        LocalVoicePressHandler handler = new LocalVoicePressHandler();
        handler.onEvent(SHORT_PRESS, false);
        assertEquals(STOP, handler.onEvent(LONG_PRESS_START, true).command());
        assertEquals(NONE, handler.onEvent(LONG_PRESS_END, false).command());
        // The next press starts a new recording normally.
        assertEquals(START, handler.onEvent(SHORT_PRESS, false).command());
    }

    @Test
    void releaseAfterTheRecorderStoppedOnItsOwnIsIgnored() {
        LocalVoicePressHandler handler = new LocalVoicePressHandler();
        handler.onEvent(LONG_PRESS_START, false);
        assertEquals(NONE, handler.onEvent(LONG_PRESS_END, false).command());
    }

    @Test
    void shortPressAfterTheRecorderStoppedOnItsOwnStartsAgain() {
        LocalVoicePressHandler handler = new LocalVoicePressHandler();
        handler.onEvent(SHORT_PRESS, false);
        // e.g. microphone error ended the recording without a second press
        assertEquals(START, handler.onEvent(SHORT_PRESS, false).command());
    }
}
