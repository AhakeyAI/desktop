package com.example.ahakey.model;

import com.example.ahakey.service.AhaTypeConfig;
import com.example.ahakey.service.AhaTypeService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.net.URI;
import java.net.http.HttpClient;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import com.example.ahakey.platform.voice.VoiceAction;

class StudioStateDirtySnapshotTest {
    @TempDir
    Path tempDir;
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
    void ahaTypeStateRequiresAValidSessionAndCanToggleOff() throws Exception {
        AhaTypeConfig config = new AhaTypeConfig(tempDir.resolve("typeless_config.json"));
        Map<String, Object> values = AhaTypeConfig.defaults();
        values.put(AhaTypeConfig.ENABLED, true);
        values.put(AhaTypeConfig.ACCESS_TOKEN, "test-token");
        values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, "2030-01-01T00:00:00Z");
        config.save(values);
        AhaTypeService service = new AhaTypeService(config, HttpClient.newHttpClient(),
            URI.create("http://127.0.0.1/"),
            Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC));
        StudioState state = new StudioState(service);
        assertTrue(state.ahaTypeEnabledProperty().get());

        state.toggleAhaType(false);
        assertFalse(state.ahaTypeEnabledProperty().get());
        assertTrue(state.ahaTypeStatusProperty().get().contains("未启用"));

        state.toggleAhaType(true);
        assertTrue(state.ahaTypeEnabledProperty().get());
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
