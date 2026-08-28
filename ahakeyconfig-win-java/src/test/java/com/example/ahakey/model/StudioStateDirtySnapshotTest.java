package com.example.ahakey.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
}
