package com.example.ahakey.view;

import com.example.ahakey.platform.voice.VoiceAction;
import com.example.ahakey.platform.voice.VoiceActionRouter;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class InspectorPaneVoiceActionChoicesTest {
    @Test
    void customShortcutIsNotExposedAsAnImplementedUiChoice() {
        assertEquals(java.util.List.of(VoiceAction.SYSTEM_VOICE, VoiceAction.NONE),
            VoiceActionRouter.shortActionChoices());
        assertEquals(java.util.List.of(
            VoiceAction.AHAKEY_VOICE, VoiceAction.SYSTEM_VOICE, VoiceAction.NONE),
            VoiceActionRouter.longActionChoices());
        assertFalse(VoiceActionRouter.shortActionChoices().contains(VoiceAction.CUSTOM_SHORTCUT));
        assertFalse(VoiceActionRouter.longActionChoices().contains(VoiceAction.CUSTOM_SHORTCUT));
    }

    @Test
    void localAhaKeyVoiceIsNotAFalseShortActionOption() {
        assertFalse(VoiceActionRouter.shortActionChoices().contains(VoiceAction.AHAKEY_VOICE));
        assertTrue(VoiceActionRouter.longActionChoices().contains(VoiceAction.AHAKEY_VOICE));
    }
}
