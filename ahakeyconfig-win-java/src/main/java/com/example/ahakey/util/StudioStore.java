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
            StudioState.PersistedDraft savedDraft = MAPPER.readValue(file, StudioState.PersistedDraft.class);
            StudioState.PersistedDraft defaults = StudioState.PersistedDraft.defaults();

            if (savedDraft.modes != null) {
                for (int i = 0; i < Math.min(savedDraft.modes.length, defaults.modes.length); i++) {
                    StudioState.PersistedDraft.ModeDraft savedMode = savedDraft.modes[i];
                    StudioState.PersistedDraft.ModeDraft defaultMode = defaults.modes[i];
                    if (savedMode == null) continue;
                    defaultMode.key1Hid = savedMode.key1Hid;
                    defaultMode.key1Desc = savedMode.key1Desc;
                    defaultMode.key1Macro = savedMode.key1Macro;
                    defaultMode.key2Hid = savedMode.key2Hid;
                    defaultMode.key2Desc = savedMode.key2Desc;
                    defaultMode.key2Macro = savedMode.key2Macro;
                    defaultMode.key3Hid = savedMode.key3Hid;
                    defaultMode.key3Desc = savedMode.key3Desc;
                    defaultMode.key3Macro = savedMode.key3Macro;
                    defaultMode.key4Hid = savedMode.key4Hid;
                    defaultMode.key4Desc = savedMode.key4Desc;
                    defaultMode.key4Macro = savedMode.key4Macro;
                    if (savedMode.oledGifPath != null && !savedMode.oledGifPath.isEmpty()) {
                        defaultMode.oledGifPath = savedMode.oledGifPath;
                    }
                    if (savedMode.oledFps > 0) {
                        defaultMode.oledFps = savedMode.oledFps;
                    }
                    if (savedMode.oledFrameCount > 0) {
                        defaultMode.oledFrameCount = savedMode.oledFrameCount;
                    }
                    if (savedMode.oledSummary != null) {
                        defaultMode.oledSummary = savedMode.oledSummary;
                    }
                    if (savedMode.oledCaption != null) {
                        defaultMode.oledCaption = savedMode.oledCaption;
                    }
                    if (savedMode.voicePresetId != null) {
                        defaultMode.voicePresetId = savedMode.voicePresetId;
                    }
                    if (savedMode.aiLightEffectIds != null) {
                        defaultMode.aiLightEffectIds = savedMode.aiLightEffectIds;
                    }
                }
            }

            defaults.revision = savedDraft.revision;
            defaults.lightBarPreviewId = savedDraft.lightBarPreviewId;
            defaults.lightBrightness = savedDraft.lightBrightness;
            if (savedDraft.voiceKeyShortHid != null) {
                defaults.voiceKeyShortHid = savedDraft.voiceKeyShortHid;
            }
            if (savedDraft.voiceKeyLongHid != null) {
                defaults.voiceKeyLongHid = savedDraft.voiceKeyLongHid;
            }

            return defaults;
        } catch (IOException e) {
            logger.warn("StudioStore.load failed, returning defaults: {}", e.getMessage());
            return StudioState.PersistedDraft.defaults();
        }
    }
}
