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
        assertEquals(java.util.List.of(
            VoiceAction.CUSTOM_SHORTCUT, VoiceAction.AHAKEY_VOICE, VoiceAction.NONE),
            VoiceActionRouter.shortActionChoices());
        assertEquals(java.util.List.of(
            VoiceAction.AHAKEY_VOICE, VoiceAction.CUSTOM_SHORTCUT, VoiceAction.NONE),
            VoiceActionRouter.longActionChoices());
        assertTrue(VoiceActionRouter.shortActionChoices().contains(VoiceAction.CUSTOM_SHORTCUT));
        assertTrue(VoiceActionRouter.longActionChoices().contains(VoiceAction.CUSTOM_SHORTCUT));
    }

    @Test
    void localVoiceChoicesAppearOnlyWhileTheOptionalFeatureIsAvailable() {
        for (boolean shortPress : new boolean[] {true, false}) {
            assertFalse(VoiceActionRouter.actionChoices(shortPress, false)
                .contains(VoiceAction.AHAKEY_VOICE));
            assertTrue(VoiceActionRouter.actionChoices(shortPress, true)
                .contains(VoiceAction.AHAKEY_VOICE));
            assertTrue(VoiceActionRouter.actionChoices(shortPress, false)
                .contains(VoiceAction.CUSTOM_SHORTCUT));
        }
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
        int shortLabel = source.indexOf("localize(\"短按动作（一次触发）\")");
        int longLabel = source.indexOf("localize(\"长按动作（按住）\")");
        assertTrue(shortLabel > 0 && longLabel > shortLabel);
        assertTrue(source.contains("voiceTriggerBlock(true, localVoice)"));
        assertTrue(source.indexOf("voiceTriggerBlock(true, localVoice)")
            < source.indexOf("voiceTriggerBlock(false, localVoice)"));
        assertTrue(source.contains("reservePhysicalF18"));
        assertFalse(source.contains("TextField shortcut ="),
            "K1 must not have a second text-field-only shortcut editor");
    }

    @Test
    void editAndSaveButtonSitsInEveryInspectorModuleTitleRow() throws IOException {
        String source = Files.readString(Path.of(
            "src/main/java/com/example/ahakey/view/InspectorPane.java"));
        assertTrue(source.contains("title, titleSpacer, configModeButton"));
        assertTrue(source.contains("controller.handleConfigurationModeButton()"));
    }

    @Test
    void mainAhaTypeAndVoiceControlsRemainDiscoverableWithoutModelFlag() throws IOException {
        String source = Files.readString(Path.of(
            "src/main/java/com/example/ahakey/view/TopBar.java"));
        // Lite single-row layout: the AhaType status and master switch sit after
        // the connect button; voice starts and stops with the switch. The BLE
        // driver opens from the connection block instead of its own button.
        String flat = source.replaceAll("\\s+", " ");
        assertTrue(flat.contains("titleBox, infoPills, spacer, actionButtons, "
            + "ahaTypeControls, rightSpacer, configStatus, menuBar"));
        assertFalse(source.contains("configModeButton"),
            "edit/save lives in the inspector, not in the top bar");
        assertTrue(source.contains("ahaTypeSwitch = createSwitch()"));
        assertTrue(source.contains("setupBleButtonLongPress(connectionPill)"));
        assertFalse(source.contains("\"button-ble\""));
    }
}
