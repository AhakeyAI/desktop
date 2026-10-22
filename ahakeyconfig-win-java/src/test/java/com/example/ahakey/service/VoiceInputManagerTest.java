package com.example.ahakey.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Verifies the real VoiceInputManager push-to-talk lifecycle without a microphone. */
class VoiceInputManagerTest {
    @Test
    void activatedLongPressStartsAndStopsRecordingExactlyOnce() {
        FakeSpeechService speech = new FakeSpeechService();
        VoiceInputManager manager = new VoiceInputManager(speech, null);

        manager.startVoiceInput();
        assertTrue(manager.isActivated());

        manager.startRecording();
        manager.startRecording(); // repeat DOWN must not start a second stream
        assertEquals(1, speech.startCount);
        assertTrue(manager.isRecording());

        manager.stopRecording();
        manager.stopRecording(); // isolated UP is a no-op
        assertEquals(1, speech.stopCount);
        assertTrue(!manager.isRecording());
    }

    @Test
    void inactiveManagerDoesNotStartLocalRecording() {
        FakeSpeechService speech = new FakeSpeechService();
        VoiceInputManager manager = new VoiceInputManager(speech, null);

        manager.startRecording();
        assertEquals(0, speech.startCount);
    }

    private static final class FakeSpeechService extends SpeechService {
        private int startCount;
        private int stopCount;

        @Override
        public void startListening(Consumer<String> partial, Consumer<String> finalResult) {
            startCount++;
        }

        @Override
        public void stopListening() {
            stopCount++;
        }

        @Override
        public void release() {
            // no native resources in this fake
        }
    }
}
