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
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.channels.FileChannel;

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

    public static boolean save(StudioState.PersistedDraft draft) {
        return save(DRAFT_PATH, draft);
    }

    static boolean save(Path destination, StudioState.PersistedDraft draft) {
        Path temporary = destination.resolveSibling(destination.getFileName() + ".tmp");
        try {
            Files.createDirectories(destination.getParent());
            byte[] bytes = MAPPER.writeValueAsBytes(draft);
            try (FileChannel channel = FileChannel.open(temporary,
                StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING,
                StandardOpenOption.WRITE)) {
                channel.write(java.nio.ByteBuffer.wrap(bytes));
                channel.force(true);
            }
            try {
                Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING);
            } catch (java.nio.file.AtomicMoveNotSupportedException unsupported) {
                Files.move(temporary, destination, StandardCopyOption.REPLACE_EXISTING);
            }
            return true;
        } catch (IOException e) {
            logger.error("StudioStore.save failed: {}", e.getMessage(), e);
            try { Files.deleteIfExists(temporary); } catch (IOException ignored) {}
            return false;
        }
    }

    public static StudioState.PersistedDraft loadOrDefault() {
        return load(DRAFT_PATH);
    }

    static StudioState.PersistedDraft load(Path source) {
        File file = source.toFile();
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
                    if (savedMode.screenAssets != null) {
                        defaultMode.screenAssets = savedMode.screenAssets;
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
            if (savedDraft.voiceThresholdMs != null) {
                defaults.voiceThresholdMs = savedDraft.voiceThresholdMs;
            }
            if (savedDraft.voiceShortAction != null) {
                defaults.voiceShortAction = savedDraft.voiceShortAction;
            }
            if (savedDraft.voiceLongAction != null) {
                defaults.voiceLongAction = savedDraft.voiceLongAction;
            }

            return defaults;
        } catch (IOException e) {
            logger.warn("StudioStore.load failed, returning defaults: {}", e.getMessage());
            return StudioState.PersistedDraft.defaults();
        }
    }
}
