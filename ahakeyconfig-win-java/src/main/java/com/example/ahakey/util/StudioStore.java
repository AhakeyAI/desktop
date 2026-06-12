package com.example.ahakey.util;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/** 对齐 Swift `AhaKeyStudioStore`（UserDefaults → 此处用 `~/.ahakey/studio-draft.json`）。 */
public final class StudioStore {
    
    private static final Logger logger = LoggerFactory.getLogger(StudioStore.class);
    private static final ObjectMapper MAPPER = new ObjectMapper()
        .enable(SerializationFeature.INDENT_OUTPUT);
    private static final Path DRAFT_PATH = Path.of(
        System.getProperty("user.home"), ".ahakey", "studio-draft.json"
    );

    private StudioStore() {
    }

    public static void save(StudioState.PersistedDraft draft) {
        try {
            Files.createDirectories(DRAFT_PATH.getParent());
            MAPPER.writeValue(DRAFT_PATH.toFile(), draft);
        } catch (IOException e) {
            logger.error("StudioStore.save failed: {}", e.getMessage(), e);
        }
    }

    public static StudioState.PersistedDraft loadOrDefault() {
        File file = DRAFT_PATH.toFile();
        if (!file.exists()) {
            return StudioState.PersistedDraft.defaults();
        }
        try {
            StudioState.PersistedDraft draft = MAPPER.readValue(file, StudioState.PersistedDraft.class);
            if (draft.modes == null) {
                draft.modes = new StudioState.PersistedDraft.ModeDraft[0];
            }
            if (draft.modes.length != ModeSlot.values().length) {
                StudioState.PersistedDraft defaults = StudioState.PersistedDraft.defaults();
                int copyLength = Math.min(draft.modes.length, defaults.modes.length);
                for (int i = 0; i < copyLength; i++) {
                    if (draft.modes[i] != null) {
                        defaults.modes[i] = draft.modes[i];
                    }
                }
                defaults.revision = draft.revision;
                defaults.lightBarPreviewId = draft.lightBarPreviewId;
                defaults.lightBrightness = draft.lightBrightness;
                return defaults;
            }
            StudioState.PersistedDraft defaults = StudioState.PersistedDraft.defaults();
            for (int i = 0; i < draft.modes.length; i++) {
                if (draft.modes[i] == null) {
                    draft.modes[i] = defaults.modes[i];
                }
            }
            return draft;
        } catch (IOException e) {
            return StudioState.PersistedDraft.defaults();
        }
    }
}
