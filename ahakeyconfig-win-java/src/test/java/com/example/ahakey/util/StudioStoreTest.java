package com.example.ahakey.util;

import com.example.ahakey.model.StudioState;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertEquals;

class StudioStoreTest {
    @TempDir Path temp;

    @Test
    void saveUsesReplacementAndLeavesNoTemporaryFile() throws Exception {
        Path destination = temp.resolve("state").resolve("studio-draft.json");
        assertTrue(StudioStore.save(destination, StudioState.PersistedDraft.defaults()));
        assertTrue(Files.isRegularFile(destination));
        assertFalse(Files.exists(destination.resolveSibling("studio-draft.json.tmp")));
        assertTrue(Files.readString(destination).contains("modes"));
    }

    @Test
    void failureIsReportedInsteadOfSilentSuccess() throws Exception {
        Path parentFile = temp.resolve("not-a-directory");
        Files.writeString(parentFile, "occupied");
        assertFalse(StudioStore.save(
            parentFile.resolve("studio-draft.json"), StudioState.PersistedDraft.defaults()));
    }

    @Test
    void shortAndLongCustomShortcutsPersistInSeparateDesktopFields() throws Exception {
        Path destination = temp.resolve("state").resolve("studio-draft.json");
        StudioState.PersistedDraft draft = StudioState.PersistedDraft.defaults();
        draft.voiceShortAction = "CUSTOM_SHORTCUT";
        draft.voiceLongAction = "CUSTOM_SHORTCUT";
        draft.voiceShortCustomShortcutHid = 0x800 | 0x0B; // Win+H
        draft.voiceLongCustomShortcutHid = 0x200 | 0x400 | 0x04; // Ctrl+Alt+A

        assertTrue(StudioStore.save(destination, draft));
        StudioState.PersistedDraft loaded = StudioStore.load(destination);
        assertEquals(draft.voiceShortCustomShortcutHid, loaded.voiceShortCustomShortcutHid);
        assertEquals(draft.voiceLongCustomShortcutHid, loaded.voiceLongCustomShortcutHid);
        assertTrue(Files.readString(destination).contains("voiceShortCustomShortcutHid"));
        assertTrue(Files.readString(destination).contains("voiceLongCustomShortcutHid"));
    }
}
