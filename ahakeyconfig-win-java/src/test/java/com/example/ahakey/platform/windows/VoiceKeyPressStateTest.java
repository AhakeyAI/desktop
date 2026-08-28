package com.example.ahakey.platform.windows;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class VoiceKeyPressStateTest {
    @Test
    void repeatedKeyDownAndDuplicateKeyUpAreFilteredExplicitly() {
        VoiceKeyPressState state = new VoiceKeyPressState();
        assertTrue(state.firstKeyDown(0x81));
        assertFalse(state.firstKeyDown(0x81));
        assertTrue(state.firstKeyUp(0x81));
        assertFalse(state.firstKeyUp(0x81));
    }

    @Test
    void clearAllowsCleanRestartAfterShutdown() {
        VoiceKeyPressState state = new VoiceKeyPressState();
        assertTrue(state.firstKeyDown(0x81));
        state.clear();
        assertTrue(state.firstKeyDown(0x81));
    }
}
