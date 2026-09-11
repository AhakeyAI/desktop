package com.example.ahakey.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import com.example.ahakey.platform.voice.VoiceAction;

class StudioStateDirtySnapshotTest {
    @Test
    void editingSameItemDuringSaveRemainsDirty() {
        StudioState state = new StudioState();
        state.markDirty(StudioPart.KEY1);
        StudioState.DirtySnapshot saved = state.captureDirtySnapshot();
        state.markDirty(StudioPart.KEY1);
        state.clearDirtyAfterSync(saved);
        assertTrue(state.isDirty(StudioPart.KEY1));
    }

    @Test
    void editingAnotherItemDuringSaveRemainsDirty() {
        StudioState state = new StudioState();
        state.markDirty(StudioPart.KEY1);
        StudioState.DirtySnapshot saved = state.captureDirtySnapshot();
        state.markDirty(StudioPart.KEY2);
        state.clearDirtyAfterSync(saved);
        assertFalse(state.isDirty(StudioPart.KEY1));
        assertTrue(state.isDirty(StudioPart.KEY2));
    }

    @Test
    void editingAnotherModeDuringSaveKeepsThatConfigurationDirty() {
        StudioState state = new StudioState();
        state.markDirty(StudioPart.KEY1);
        StudioState.DirtySnapshot saved = state.captureDirtySnapshot();
        state.setSelectedMode(ModeSlot.MODE2);
        state.markDirty(StudioPart.LIGHT_BAR);
        state.clearDirtyAfterSync(saved);
        assertTrue(state.isDirty(StudioPart.LIGHT_BAR));
    }

    @Test
    void selectingGifDuringSaveKeepsOledDirty() {
        StudioState state = new StudioState();
        state.markDirty(StudioPart.KEY1);
        StudioState.DirtySnapshot saved = state.captureDirtySnapshot();
        state.applyOledGifSelection("new.gif", 8);
        state.clearDirtyAfterSync(saved);
        assertTrue(state.isDirty(StudioPart.OLED));
    }

    @Test
    void desktopVoiceActionsRoundTripThroughExistingDraftStoreModel() {
        StudioState state = new StudioState();
        state.setVoiceActions(VoiceAction.CUSTOM_SHORTCUT, VoiceAction.NONE, 351);
        state.setVoiceShortCustomShortcutHid(0x800 | 0x0B);
        state.setVoiceLongCustomShortcutHid(0x200 | 0x400 | 0x04);
        StudioState loaded = new StudioState();
        loaded.loadFromPersisted(state.toPersisted());
        assertEquals(351, loaded.getVoiceThresholdMs());
        assertEquals(VoiceAction.CUSTOM_SHORTCUT, loaded.getVoiceShortAction());
        assertEquals(VoiceAction.NONE, loaded.getVoiceLongAction());
        assertEquals(0x800 | 0x0B, loaded.getVoiceShortCustomShortcutHid());
        assertEquals(0x200 | 0x400 | 0x04, loaded.getVoiceLongCustomShortcutHid());
    }

    @Test
    void newDefaultsUseOneShotSystemShortAndPushToTalkLong() {
        StudioState state = new StudioState();
        assertEquals(VoiceAction.CUSTOM_SHORTCUT, state.getVoiceShortAction());
        assertEquals(VoiceAction.AHAKEY_VOICE, state.getVoiceLongAction());
        assertEquals(350, state.getVoiceThresholdMs());
        assertEquals(0x800 | 0x0B, state.getVoiceShortCustomShortcutHid());
    }

    @Test
    void oldSystemVoiceActionsMigrateToLocalCustomShortcut() {
        StudioState.PersistedDraft draft = StudioState.PersistedDraft.defaults();
        draft.voiceShortAction = VoiceAction.SYSTEM_VOICE.name();
        draft.voiceLongAction = VoiceAction.SYSTEM_VOICE.name();
        draft.voiceThresholdMs = 500;
        draft.voiceShortCustomShortcutHid = 0x6C; // legacy/invalid for this migration
        draft.voiceLongCustomShortcutHid = 0x04;
        StudioState loaded = new StudioState();
        loaded.loadFromPersisted(draft);
        assertEquals(VoiceAction.CUSTOM_SHORTCUT, loaded.getVoiceShortAction());
        assertEquals(VoiceAction.CUSTOM_SHORTCUT, loaded.getVoiceLongAction());
        assertEquals(500, loaded.getVoiceThresholdMs(),
            "legacy threshold remains readable for compatibility but runtime is fixed");
        assertEquals(0x800 | 0x0B, loaded.getVoiceShortCustomShortcutHid());
        assertEquals(0x800 | 0x0B, loaded.getVoiceLongCustomShortcutHid());
    }

    @Test
    void physicalF18CannotBePersistedAsARecursiveCustomShortcut() {
        StudioState state = new StudioState();
        assertThrows(IllegalArgumentException.class,
            () -> state.setVoiceShortCustomShortcutHid(HIDUsage.F18));
        assertThrows(IllegalArgumentException.class,
            () -> state.setVoiceLongCustomShortcutHid(HIDUsage.F18));
    }

    @Test
    void unsupportedLegacyShortAhaKeyActionMigratesToWinHCustomShortcut() {
        StudioState.PersistedDraft draft = StudioState.PersistedDraft.defaults();
        draft.voiceShortAction = VoiceAction.AHAKEY_VOICE.name();
        draft.voiceShortCustomShortcutHid = HIDUsage.F17;

        StudioState loaded = new StudioState();
        loaded.loadFromPersisted(draft);

        assertEquals(VoiceAction.CUSTOM_SHORTCUT, loaded.getVoiceShortAction());
        assertEquals(0x800 | 0x0B, loaded.getVoiceShortCustomShortcutHid());
    }
}
