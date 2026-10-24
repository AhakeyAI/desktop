package com.example.ahakey.util;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.example.ahakey.model.StudioState;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

/** 对齐 Swift `AhaKeyStudioStore`(UserDefaults → 此处用 `~/.ahakey/studio-draft.json`)。 */
public final class StudioStore {

    private static final Logger logger = LoggerFactory.getLogger(StudioStore.class);
    private static final ObjectMapper MAPPER = new ObjectMapper()
        .enable(SerializationFeature.INDENT_OUTPUT);
    private static final Path DRAFT_PATH = Path.of(
        System.getProperty("user.home"), ".ahakey", "studio-draft.json"
    );
    private static final Path DRAFT_TMP = Path.of(
        System.getProperty("user.home"), ".ahakey", "studio-draft.json.tmp"
    );
    private static final Path DRAFT_BAK = Path.of(
        System.getProperty("user.home"), ".ahakey", "studio-draft.json.bak"
    );

    private StudioStore() {
    }

    /** 原子保存：先写 .tmp，再 rename 正式文件为 .bak，最后原子 rename .tmp → 正式文件。 */
    public static void save(StudioState.PersistedDraft draft) {
        try {
            Files.createDirectories(DRAFT_PATH.getParent());
            MAPPER.writeValue(DRAFT_TMP.toFile(), draft);
            // 删除旧备份
            Files.deleteIfExists(DRAFT_BAK);
            // 当前正式文件 → 备份
            if (Files.exists(DRAFT_PATH)) {
                Files.move(DRAFT_PATH, DRAFT_BAK, StandardCopyOption.REPLACE_EXISTING);
            }
            // 原子替换 tmp → 正式文件
            Files.move(DRAFT_TMP, DRAFT_PATH, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            logger.error("StudioStore.save failed: {}", e.getMessage(), e);
        }
    }

    /**
     * 加载配置。以 savedDraft 为主体，仅对真正缺失的字段补默认值。
     * 这样以后给 ModeDraft 加新字段时，旧 JSON 缺少该字段会由 Jackson 反序列化为 null/0，
     * 本方法自动补默认值，不需要逐字段手动复制。
     */
    public static StudioState.PersistedDraft loadOrDefault() {
        File file = DRAFT_PATH.toFile();
        if (!file.exists()) {
            return StudioState.PersistedDraft.defaults();
        }
        try {
            StudioState.PersistedDraft savedDraft = MAPPER.readValue(file, StudioState.PersistedDraft.class);
            StudioState.PersistedDraft defaults = StudioState.PersistedDraft.defaults();

            // --- 补齐 modes 数组 ---
            if (savedDraft.modes == null) {
                savedDraft.modes = defaults.modes;
            } else if (savedDraft.modes.length < defaults.modes.length) {
                // 旧版本 mode 数量不够，补齐
                StudioState.PersistedDraft.ModeDraft[] patched =
                    new StudioState.PersistedDraft.ModeDraft[defaults.modes.length];
                System.arraycopy(savedDraft.modes, 0, patched, 0, savedDraft.modes.length);
                for (int i = savedDraft.modes.length; i < defaults.modes.length; i++) {
                    patched[i] = defaults.modes[i];
                }
                savedDraft.modes = patched;
            }

            // --- 对每个 mode，仅补 null 或无效字段 ---
            for (int i = 0; i < savedDraft.modes.length; i++) {
                if (savedDraft.modes[i] == null) {
                    savedDraft.modes[i] = defaults.modes[i];
                    continue;
                }
                StudioState.PersistedDraft.ModeDraft sm = savedDraft.modes[i];
                StudioState.PersistedDraft.ModeDraft dm = defaults.modes[i];
                if (sm.key1Desc == null) sm.key1Desc = dm.key1Desc;
                if (sm.key2Desc == null) sm.key2Desc = dm.key2Desc;
                if (sm.key3Desc == null) sm.key3Desc = dm.key3Desc;
                if (sm.key4Desc == null) sm.key4Desc = dm.key4Desc;
                if (sm.oledSummary == null) sm.oledSummary = dm.oledSummary;
                if (sm.oledCaption == null) sm.oledCaption = dm.oledCaption;
                if (sm.voicePresetId == null) sm.voicePresetId = dm.voicePresetId;
                if (sm.aiLightEffectIds == null) sm.aiLightEffectIds = dm.aiLightEffectIds;
                if (sm.oledFps <= 0) sm.oledFps = dm.oledFps;
            }

            // --- 全局字段补默认 ---
            if (savedDraft.lightBarPreviewId == null) savedDraft.lightBarPreviewId = defaults.lightBarPreviewId;
            if (savedDraft.lightBrightness <= 0) savedDraft.lightBrightness = defaults.lightBrightness;

            return savedDraft;
        } catch (IOException e) {
            logger.warn("StudioStore.load failed, trying backup: {}", e.getMessage());
            return tryRecoverFromBackup();
        }
    }

    /** 从 .bak 恢复，失败则返回默认值。 */
    private static StudioState.PersistedDraft tryRecoverFromBackup() {
        if (Files.exists(DRAFT_BAK)) {
            try {
                StudioState.PersistedDraft recovered = MAPPER.readValue(DRAFT_BAK.toFile(), StudioState.PersistedDraft.class);
                logger.info("StudioStore: recovered from backup");
                return recovered;
            } catch (IOException e2) {
                logger.warn("StudioStore: backup also corrupt, returning defaults");
            }
        }
        return StudioState.PersistedDraft.defaults();
    }
}