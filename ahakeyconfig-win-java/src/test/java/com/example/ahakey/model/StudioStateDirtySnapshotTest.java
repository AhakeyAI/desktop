package com.example.ahakey.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertEquals;
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
        StudioState loaded = new StudioState();
        loaded.loadFromPersisted(state.toPersisted());
        assertEquals(351, loaded.getVoiceThresholdMs());
        assertEquals(VoiceAction.CUSTOM_SHORTCUT, loaded.getVoiceShortAction());
        assertEquals(VoiceAction.NONE, loaded.getVoiceLongAction());
    }
}
