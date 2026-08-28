package com.example.ahakey.util;

import com.example.ahakey.model.StudioState;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
}
