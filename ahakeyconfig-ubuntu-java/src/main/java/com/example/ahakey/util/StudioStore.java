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
            // 始终使用新的默认配置作为基础（确保按键配置与固件对齐）
            StudioState.PersistedDraft defaults = StudioState.PersistedDraft.defaults();
            
            // 合并用户自定义的非按键内容（如 OLED 图片等）
            if (savedDraft.modes != null) {
                for (int i = 0; i < Math.min(savedDraft.modes.length, defaults.modes.length); i++) {
                    if (savedDraft.modes[i] != null) {
                        StudioState.PersistedDraft.ModeDraft savedMode = savedDraft.modes[i];
                        StudioState.PersistedDraft.ModeDraft defaultMode = defaults.modes[i];
                        // 保留用户自定义的 OLED 设置
                        if (savedMode.oledGifPath != null && !savedMode.oledGifPath.isEmpty()) {
                            defaultMode.oledGifPath = savedMode.oledGifPath;
                        }
                        if (savedMode.oledFps > 0) {
                            defaultMode.oledFps = savedMode.oledFps;
                        }
                        if (savedMode.oledFrameCount > 0) {
                            defaultMode.oledFrameCount = savedMode.oledFrameCount;
                        }
                        if (savedMode.voicePresetId != null) {
                            defaultMode.voicePresetId = savedMode.voicePresetId;
                        }
                        if (savedMode.aiLightEffectIds != null) {
                            defaultMode.aiLightEffectIds = savedMode.aiLightEffectIds;
                        }
                    }
                }
            }
            
            // 保留全局设置
            defaults.revision = savedDraft.revision;
            defaults.lightBarPreviewId = savedDraft.lightBarPreviewId;
            defaults.lightBrightness = savedDraft.lightBrightness;
            
            return defaults;
        } catch (IOException e) {
            return StudioState.PersistedDraft.defaults();
        }
    }
}
