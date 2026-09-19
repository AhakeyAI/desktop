package com.example.ahakey.view;

import com.example.ahakey.platform.voice.VoiceAction;
import com.example.ahakey.platform.voice.VoiceActionRouter;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class InspectorPaneVoiceActionChoicesTest {
    @Test
    void configuredShortcutChoicesExposeOnlyImplementedActions() {
        assertEquals(java.util.List.of(VoiceAction.CUSTOM_SHORTCUT, VoiceAction.NONE),
            VoiceActionRouter.shortActionChoices());
        assertEquals(java.util.List.of(
            VoiceAction.AHAKEY_VOICE, VoiceAction.CUSTOM_SHORTCUT, VoiceAction.NONE),
            VoiceActionRouter.longActionChoices());
        assertTrue(VoiceActionRouter.shortActionChoices().contains(VoiceAction.CUSTOM_SHORTCUT));
        assertTrue(VoiceActionRouter.longActionChoices().contains(VoiceAction.CUSTOM_SHORTCUT));
    }

    @Test
    void localAhaKeyVoiceIsNotAFalseShortActionOption() {
        assertFalse(VoiceActionRouter.shortActionChoices().contains(VoiceAction.AHAKEY_VOICE));
        assertTrue(VoiceActionRouter.longActionChoices().contains(VoiceAction.AHAKEY_VOICE));
    }

    @Test
    void inspectorDoesNotExposeAUserEditableLongPressThreshold() throws IOException {
        String source = Files.readString(Path.of(
            "src/main/java/com/example/ahakey/view/InspectorPane.java"));
        assertFalse(source.contains("长按阈值"));
        assertFalse(source.contains("voiceThresholdMsProperty"));
    }

    @Test
    void k1CustomEditorsUseTheSharedShortcutEditorAndStayInShortThenLongOrder()
        throws IOException {
        String source = Files.readString(Path.of(
            "src/main/java/com/example/ahakey/view/InspectorPane.java"));
        assertTrue(source.replace("\r\n", "\n").contains("createShortcutEditor(\n            shortcutModel"));
        assertTrue(source.contains("new Label(localize(\"短按动作（一次触发）\"))"));
        assertTrue(source.contains("new Label(localize(\"长按动作（按住说话）\"))"));
        assertTrue(source.contains("reservePhysicalF18"));
        assertFalse(source.contains("TextField shortcut ="),
            "K1 must not have a second text-field-only shortcut editor");
    }

    @Test
    void mainAhaTypeAndVoiceControlsRemainDiscoverableWithoutModelFlag() throws IOException {
        String source = Files.readString(Path.of(
            "src/main/java/com/example/ahakey/view/TopBar.java"));
        assertTrue(source.contains("mainRow.getChildren().addAll(ahaTypeToggle, ahaTypeStatus, voiceControlBox)"));
        assertTrue(source.contains("button.start-voice"));
    }
}
