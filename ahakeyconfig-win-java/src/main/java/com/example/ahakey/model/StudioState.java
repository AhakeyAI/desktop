package com.example.ahakey.model;

import javafx.beans.property.BooleanProperty;
import javafx.beans.property.IntegerProperty;
import javafx.beans.property.ObjectProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.beans.property.SimpleIntegerProperty;
import javafx.beans.property.SimpleObjectProperty;
import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;
import com.example.ahakey.platform.voice.VoiceAction;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;

public class StudioState {
    private static final DateTimeFormatter SYNC_TIME_FORMAT = DateTimeFormatter.ofPattern("HH:mm");

    private final ObjectProperty<ModeSlot> selectedMode = new SimpleObjectProperty<>(ModeSlot.MODE0);
    private final ObjectProperty<StudioPart> selectedPart = new SimpleObjectProperty<>(StudioPart.KEY1);
    private final IntegerProperty dirtyCount = new SimpleIntegerProperty(0);
    private final IntegerProperty revision = new SimpleIntegerProperty(0);
    private final StringProperty syncStatus = new SimpleStringProperty("修改会先保存在本地，保存配置后写入键盘。");
    private final StringProperty lastSyncSummary = new SimpleStringProperty("尚未保存");
    private final BooleanProperty syncing = new SimpleBooleanProperty(false);
    private final BooleanProperty ahaTypeEnabled = new SimpleBooleanProperty(false);
    private final StringProperty ahaTypeStatus = new SimpleStringProperty("AhaType 尚未实现");
    private final ObjectProperty<LightBarPreviewState> lightBarPreview =
        new SimpleObjectProperty<>(LightBarPreviewState.AI_RUNNING);
    private final IntegerProperty lightBrightness = new SimpleIntegerProperty(35);
    private final KeyConfig voiceKeyShort = new KeyConfig(0x4000, "Typeless");
    private final KeyConfig voiceKeyLong = new KeyConfig(0x0A00, "WeChat Voice");
    /** Desktop voice semantics; legacy HID fields above remain migration-only. */
    private final IntegerProperty voiceThresholdMs = new SimpleIntegerProperty(350);
    private final ObjectProperty<VoiceAction> voiceShortAction =
        new SimpleObjectProperty<>(VoiceAction.SYSTEM_VOICE);
    private final ObjectProperty<VoiceAction> voiceLongAction =
        new SimpleObjectProperty<>(VoiceAction.AHAKEY_VOICE);

    private final Map<ModeSlot, EnumMap<StudioPart, KeyConfig>> keyConfigs = new EnumMap<>(ModeSlot.class);
    private final Map<ModeSlot, StringProperty> oledSummaries = new EnumMap<>(ModeSlot.class);
    private final Map<ModeSlot, StringProperty> oledCaptions = new EnumMap<>(ModeSlot.class);
    private final Map<ModeSlot, OledModeDraft> oledDrafts = new EnumMap<>(ModeSlot.class);
    private final Map<ModeSlot, PersistedDraft.ScreenAssetMetadata[]> screenAssets =
        new EnumMap<>(ModeSlot.class);
    private final BooleanProperty uploadingOled = new SimpleBooleanProperty(false);
    private final StringProperty oledUploadDetail = new SimpleStringProperty("");
    private final Map<ModeSlot, StringProperty> lightBarSummaries = new EnumMap<>(ModeSlot.class);
    private final Map<ModeSlot, EnumMap<IDEState, LightEffectStyle>> aiLightConfigs = new EnumMap<>(ModeSlot.class);
    private final EnumSet<StudioPart> dirtyParts = EnumSet.noneOf(StudioPart.class);
    private final EnumMap<StudioPart, Integer> dirtyRevisions =
        new EnumMap<>(StudioPart.class);

    public record DirtySnapshot(Map<StudioPart, Integer> revisions) {
        public DirtySnapshot {
            revisions = Map.copyOf(revisions);
        }
    }

    public StudioState() {
        seedDefaults();
    }

    private void seedDefaults() {
        for (ModeSlot mode : ModeSlot.values()) {
            keyConfigs.put(mode, new EnumMap<>(StudioPart.class));
            aiLightConfigs.put(mode, new EnumMap<>(IDEState.class));
            resetModeDefaults(mode);
        }
    }

    private KeyConfig createKey(int hidCode, String description) {
        return new KeyConfig(hidCode, description);
    }

    private KeyConfig createVoiceKey(int hidCode, String description, VoicePreset preset) {
        KeyConfig key = new KeyConfig(hidCode, description);
        key.setVoicePreset(preset);
        return key;
    }

    private KeyConfig createMacroKey(String description, int[][] macroSteps) {
        KeyConfig key = new KeyConfig(0, description);
        key.setVoicePreset(VoicePreset.CUSTOM);
        for (int[] step : macroSteps) {
            String actionType = switch (step[0]) {
                case 1 -> "DOWN_KEY";
                case 2 -> "UP_KEY";
                default -> "DELAY";
            };
            key.addMacroStep(actionType, step[1]);
        }
        return key;
    }

    private void resetModeDefaults(ModeSlot mode) {
        EnumMap<StudioPart, KeyConfig> map = keyConfigs.get(mode);
        oledDrafts.putIfAbsent(mode, new OledModeDraft());
        screenAssets.putIfAbsent(mode, new PersistedDraft.ScreenAssetMetadata[4]);
        if (mode == ModeSlot.MODE0) {
            map.put(StudioPart.KEY1, createVoiceKey(HIDUsage.F18, "Record", VoicePreset.WINDOWS_NATIVE));
            map.put(StudioPart.KEY2, createKey(HIDUsage.ENTER, "Yes"));
            map.put(StudioPart.KEY3, createMacroKey("No", new int[][]{
                {1, HIDUsage.DOWN_ARROW}, {2, HIDUsage.DOWN_ARROW}, {3, 10},
                {1, HIDUsage.DOWN_ARROW}, {2, HIDUsage.DOWN_ARROW}, {3, 10},
                {1, HIDUsage.DOWN_ARROW}, {2, HIDUsage.DOWN_ARROW}, {3, 10},
                {1, HIDUsage.ENTER}, {2, HIDUsage.ENTER}
            }));
            map.put(StudioPart.KEY4, createKey(HIDUsage.BACKSPACE, "Backspace"));
            oledSummaries.put(mode, new SimpleStringProperty("Claude"));
            oledCaptions.put(mode, new SimpleStringProperty("Mode 1"));
            lightBarSummaries.put(mode, new SimpleStringProperty("AI 状态灯效"));
        } else if (mode == ModeSlot.MODE1) {
            map.put(StudioPart.KEY1, createVoiceKey(HIDUsage.F18, "Record", VoicePreset.WINDOWS_NATIVE));
            map.put(StudioPart.KEY2, createKey(HIDUsage.ENTER, "Accept"));
            map.put(StudioPart.KEY3, createKey(HIDUsage.BACKSPACE, "Reject"));
            map.put(StudioPart.KEY4, createKey(HIDUsage.BACKSPACE, "Backspace"));
            oledSummaries.put(mode, new SimpleStringProperty("Cursor"));
            oledCaptions.put(mode, new SimpleStringProperty("Mode 2"));
            lightBarSummaries.put(mode, new SimpleStringProperty("AI 状态灯效"));
        } else if (mode == ModeSlot.MODE2) {
            map.put(StudioPart.KEY1, createVoiceKey(HIDUsage.F18, "Record", VoicePreset.WINDOWS_NATIVE));
            map.put(StudioPart.KEY2, createKey(HIDUsage.ENTER, "Accept"));
            map.put(StudioPart.KEY3, createKey(HIDUsage.ESCAPE, "Reject"));
            map.put(StudioPart.KEY4, createKey(HIDUsage.BACKSPACE, "Backspace"));
            oledSummaries.put(mode, new SimpleStringProperty("Codex"));
            oledCaptions.put(mode, new SimpleStringProperty("Mode 3"));
            lightBarSummaries.put(mode, new SimpleStringProperty("AI 状态灯效"));
        } else {
            map.put(StudioPart.KEY1, createKey(0, "N/A"));
            map.put(StudioPart.KEY2, createKey(0, "N/A"));
            map.put(StudioPart.KEY3, createKey(0, "N/A"));
            map.put(StudioPart.KEY4, createKey(HIDUsage.BACKSPACE, "Backspace"));
            oledSummaries.put(mode, new SimpleStringProperty("N/A"));
            oledCaptions.put(mode, new SimpleStringProperty("Mode 4"));
            lightBarSummaries.put(mode, new SimpleStringProperty("AI 状态灯效"));
        }
        resetAiLightDefaults(mode);
    }

    private void resetAiLightDefaults(ModeSlot mode) {
        EnumMap<IDEState, LightEffectStyle> map = aiLightConfigs.get(mode);
        map.clear();
        for (IDEState state : IDEState.values()) {
            map.put(state, LightEffectStyle.defaultFor(state));
        }
    }

    public ObjectProperty<ModeSlot> selectedModeProperty() {
        return selectedMode;
    }

    public ModeSlot getSelectedMode() {
        return selectedMode.get();
    }

    public void setSelectedMode(ModeSlot mode) {
        selectedMode.set(mode);
    }

    public ObjectProperty<StudioPart> selectedPartProperty() {
        return selectedPart;
    }

    public StudioPart getSelectedPart() {
        return selectedPart.get();
    }

    public void setSelectedPart(StudioPart part) {
        selectedPart.set(part);
    }

    public IntegerProperty dirtyCountProperty() {
        return dirtyCount;
    }

    public int getDirtyCount() {
        return dirtyCount.get();
    }

    public IntegerProperty revisionProperty() {
        return revision;
    }

    public StringProperty syncStatusProperty() {
        return syncStatus;
    }

    public StringProperty lastSyncSummaryProperty() {
        return lastSyncSummary;
    }

    public BooleanProperty syncingProperty() {
        return syncing;
    }

    public BooleanProperty ahaTypeEnabledProperty() {
        return ahaTypeEnabled;
    }

    public StringProperty ahaTypeStatusProperty() {
        return ahaTypeStatus;
    }

    public ObjectProperty<LightBarPreviewState> lightBarPreviewProperty() {
        return lightBarPreview;
    }

    public IntegerProperty lightBrightnessProperty() {
        return lightBrightness;
    }

    public int getLightBrightness() {
        return lightBrightness.get();
    }

    public void setLightBrightness(int value) {
        lightBrightness.set(Math.max(1, Math.min(100, value)));
        markDirty(StudioPart.LIGHT_BAR);
    }
    public LightBarPreviewState getLightBarPreview() {
        return lightBarPreview.get();
    }

    public void setLightBarPreview(LightBarPreviewState state) {
        lightBarPreview.set(state);
    }

    public LightEffectStyle getAiLightEffect(ModeSlot mode, IDEState state) {
        return aiLightConfigs.get(mode).getOrDefault(state, LightEffectStyle.defaultFor(state));
    }

    public void setAiLightEffect(ModeSlot mode, IDEState state, LightEffectStyle effect) {
        aiLightConfigs.get(mode).put(state, effect);
        lightBarSummaries.get(mode).set("已自定义 AI 状态灯效");
        markDirty(StudioPart.LIGHT_BAR);
    }

    public byte[] getAiLightEffectBytes(ModeSlot mode) {
        byte[] out = new byte[IDEState.values().length];
        for (IDEState state : IDEState.values()) {
            out[state.getCode()] = getAiLightEffect(mode, state).getCode();
        }
        return out;
    }
    public KeyConfig getKeyConfig(StudioPart part) {
        return getKeyConfig(getSelectedMode(), part);
    }

    public KeyConfig getKeyConfig(ModeSlot mode, StudioPart part) {
        return keyConfigs.get(mode).get(part);
    }

    public KeyConfig getVoiceKeyShort() {
        return voiceKeyShort;
    }

    public KeyConfig getVoiceKeyLong() {
        return voiceKeyLong;
    }

    public IntegerProperty voiceThresholdMsProperty() { return voiceThresholdMs; }
    public int getVoiceThresholdMs() { return voiceThresholdMs.get(); }
    public void setVoiceThresholdMs(int value) {
        voiceThresholdMs.set(Math.max(50, Math.min(5000, value)));
        markDirty(StudioPart.KEY1);
    }
    public ObjectProperty<VoiceAction> voiceShortActionProperty() { return voiceShortAction; }
    public VoiceAction getVoiceShortAction() { return voiceShortAction.get(); }
    public void setVoiceShortAction(VoiceAction value) {
        voiceShortAction.set(value == null ? VoiceAction.NONE : value);
        markDirty(StudioPart.KEY1);
    }
    public ObjectProperty<VoiceAction> voiceLongActionProperty() { return voiceLongAction; }
    public VoiceAction getVoiceLongAction() { return voiceLongAction.get(); }
    public void setVoiceLongAction(VoiceAction value) {
        voiceLongAction.set(value == null ? VoiceAction.NONE : value);
        markDirty(StudioPart.KEY1);
    }
    public void setVoiceActions(VoiceAction shortAction, VoiceAction longAction, int thresholdMs) {
        voiceShortAction.set(shortAction == null ? VoiceAction.NONE : shortAction);
        voiceLongAction.set(longAction == null ? VoiceAction.NONE : longAction);
        voiceThresholdMs.set(Math.max(50, Math.min(5000, thresholdMs)));
        markDirty(StudioPart.KEY1);
    }

    public void resetVoiceKeyDefaults() {
        voiceKeyShort.setHidCode(0x4000);
        voiceKeyShort.setDescription("Typeless");
        voiceKeyLong.setHidCode(0x0A00);
        voiceKeyLong.setDescription("WeChat Voice");
        voiceThresholdMs.set(350);
        voiceShortAction.set(VoiceAction.SYSTEM_VOICE);
        voiceLongAction.set(VoiceAction.AHAKEY_VOICE);
        markDirty(StudioPart.KEY1);
    }

    public static int keyIndexFor(StudioPart part) {
        return switch (part) {
            case KEY1 -> 0;
            case KEY2 -> 1;
            case KEY3 -> 2;
            case KEY4 -> 3;
            default -> 0;
        };
    }

    public String getLightBarSummary() {
        LightEffectStyle hw = LightEffectStyle.hardwareEffectFor(lightBarPreview.get());
        return lightBarPreview.get().getTitle() + " · " + hw.getTitle();
    }

    public OledModeDraft getOledDraft(ModeSlot mode) {
        return oledDrafts.computeIfAbsent(mode, m -> new OledModeDraft());
    }

    public OledModeDraft getOledDraft() {
        return getOledDraft(getSelectedMode());
    }

    public PersistedDraft.ScreenAssetMetadata getScreenAssetMetadata(ModeSlot mode, int asset) {
        if (mode == null || asset < 0 || asset >= 4) return null;
        PersistedDraft.ScreenAssetMetadata[] values = screenAssets.computeIfAbsent(
            mode, ignored -> new PersistedDraft.ScreenAssetMetadata[4]);
        return values[asset];
    }

    public void setScreenAssetMetadata(ModeSlot mode, int asset,
                                       PersistedDraft.ScreenAssetMetadata metadata) {
        if (mode == null || asset < 0 || asset >= 4) return;
        PersistedDraft.ScreenAssetMetadata[] values = screenAssets.computeIfAbsent(
            mode, ignored -> new PersistedDraft.ScreenAssetMetadata[4]);
        values[asset] = metadata;
    }

    public void clearScreenAssetMetadata(ModeSlot mode, int asset) {
        setScreenAssetMetadata(mode, asset, null);
    }

    public BooleanProperty uploadingOledProperty() {
        return uploadingOled;
    }

    public StringProperty oledUploadDetailProperty() {
        return oledUploadDetail;
    }

    public String getOledSummary() {
        OledModeDraft draft = getOledDraft();
        if (draft.getLocalAssetPath() != null && !draft.getLocalAssetPath().isBlank()) {
            return draft.getStatusLine();
        }
        return oledSummaries.get(getSelectedMode()).get();
    }

    public String getOledCaption() {
        OledModeDraft draft = getOledDraft();
        if (draft.getFrameCount() > 0) {
            return draft.getCaptionLine();
        }
        return oledCaptions.get(getSelectedMode()).get();
    }

    public void applyOledGifSelection(String path, int frameCount) {
        OledModeDraft draft = getOledDraft();
        draft.setLocalAssetPath(path);
        draft.setFrameCount(frameCount);
        draft.setStatusLine("已选择 GIF / 图片");
        draft.setCaptionLine(frameCount + " 帧 · " + java.nio.file.Path.of(path).getFileName());
        oledSummaries.get(getSelectedMode()).set(draft.getStatusLine());
        oledCaptions.get(getSelectedMode()).set(draft.getCaptionLine());
        markDirty(StudioPart.OLED);
    }

    public void updateKeyCode(StudioPart part, String displayName) {
        if (!part.isKey()) {
            return;
        }
        getKeyConfig(part).setHidCode(HIDUsage.getCode(displayName));
        markDirty(part);
    }

    public void updateKeyDescription(StudioPart part, String description) {
        if (!part.isKey()) {
            return;
        }
        getKeyConfig(part).setDescription(description);
        markDirty(part);
    }

    public void setLightBarSummary(String summary) {
        lightBarSummaries.get(getSelectedMode()).set(summary);
        markDirty(StudioPart.LIGHT_BAR);
    }

    public void setOledSummary(String summary) {
        oledSummaries.get(getSelectedMode()).set(summary);
        markDirty(StudioPart.OLED);
    }

    public void setOledCaption(String caption) {
        oledCaptions.get(getSelectedMode()).set(caption);
        markDirty(StudioPart.OLED);
    }

    public void toggleAhaType(boolean enabled) {
        // WIN-019: do not expose a no-op feature as enabled.
        ahaTypeEnabled.set(false);
        ahaTypeStatus.set("AhaType 尚未实现；语音结果直接输入");
    }

    public boolean isDirty(StudioPart part) {
        return dirtyParts.contains(part);
    }

    public void markDirty(StudioPart part) {
        int nextRevision = revision.get() + 1;
        dirtyParts.add(part);
        dirtyRevisions.put(part, nextRevision);
        dirtyCount.set(dirtyParts.size());
        revision.set(nextRevision);
        syncStatus.set("有 " + dirtyParts.size() + " 处改动待保存。");
    }

    public void restoreCurrentModeDefaults() {
        resetModeDefaults(getSelectedMode());
        resetVoiceKeyDefaults();
        int nextRevision = revision.get() + 1;
        for (StudioPart part : StudioPart.values()) {
            dirtyParts.add(part);
            dirtyRevisions.put(part, nextRevision);
        }
        dirtyCount.set(dirtyParts.size());
        revision.set(nextRevision);
        syncStatus.set("已恢复 " + getSelectedMode().getTitle() + " 默认值，等待保存。");
    }

    public void clearOledPreview() {
        OledModeDraft draft = getOledDraft();
        draft.setLocalAssetPath(null);
        draft.setFrameCount(0);
        draft.setStatusLine("未选择");
        draft.setCaptionLine("等待选择 GIF / 图片");
        oledSummaries.get(getSelectedMode()).set("未选择");
        oledCaptions.get(getSelectedMode()).set("等待选择 GIF / 图片");
        markDirty(StudioPart.OLED);
    }

    public void clearDirtyAfterSync() {
        clearDirtyAfterSync(captureDirtySnapshot());
    }

    public DirtySnapshot captureDirtySnapshot() {
        return new DirtySnapshot(dirtyRevisions);
    }

    public void clearDirtyAfterSync(DirtySnapshot snapshot) {
        if (snapshot == null) return;
        for (Map.Entry<StudioPart, Integer> saved : snapshot.revisions().entrySet()) {
            Integer current = dirtyRevisions.get(saved.getKey());
            if (saved.getValue().equals(current)) {
                dirtyRevisions.remove(saved.getKey());
                dirtyParts.remove(saved.getKey());
            }
        }
        dirtyCount.set(dirtyParts.size());
        lastSyncSummary.set("最近保存 " + LocalDateTime.now().format(SYNC_TIME_FORMAT));
    }

    public int getRevision() {
        return revision.get();
    }

    public void loadFromPersisted(PersistedDraft draft) {
        voiceKeyShort.setHidCode(draft.voiceKeyShortHid == null ? 0x4000 : draft.voiceKeyShortHid);
        voiceKeyLong.setHidCode(draft.voiceKeyLongHid == null ? 0x0A00 : draft.voiceKeyLongHid);
        voiceThresholdMs.set(draft.voiceThresholdMs == null
            ? 350 : Math.max(50, Math.min(5000, draft.voiceThresholdMs)));
        voiceShortAction.set(parseVoiceAction(draft.voiceShortAction, VoiceAction.SYSTEM_VOICE));
        voiceLongAction.set(parseVoiceAction(draft.voiceLongAction, VoiceAction.AHAKEY_VOICE));
        for (int i = 0; i < ModeSlot.values().length; i++) {
            ModeSlot mode = ModeSlot.values()[i];
            PersistedDraft.ModeDraft md = draft.modes[i];
            EnumMap<StudioPart, KeyConfig> map = keyConfigs.get(mode);
            KeyConfig k1 = new KeyConfig(md.key1Hid, md.key1Desc);
            KeyConfig k2 = new KeyConfig(md.key2Hid, md.key2Desc);
            KeyConfig k3 = new KeyConfig(md.key3Hid, md.key3Desc);
            KeyConfig k4 = new KeyConfig(md.key4Hid, md.key4Desc);
            if (md.key1Macro != null) k1.setMacro(md.key1Macro);
            if (md.key2Macro != null) k2.setMacro(md.key2Macro);
            if (md.key3Macro != null) k3.setMacro(md.key3Macro);
            if (md.key4Macro != null) k4.setMacro(md.key4Macro);
            map.put(StudioPart.KEY1, k1);
            map.put(StudioPart.KEY2, k2);
            map.put(StudioPart.KEY3, k3);
            map.put(StudioPart.KEY4, k4);
            oledSummaries.get(mode).set(md.oledSummary);
            oledCaptions.get(mode).set(md.oledCaption);
            OledModeDraft od = getOledDraft(mode);
            od.setLocalAssetPath(md.oledGifPath);
            od.setFrameCount(md.oledFrameCount);
            od.setStatusLine(md.oledSummary);
            od.setCaptionLine(md.oledCaption);
            PersistedDraft.ScreenAssetMetadata[] persistedAssets = md.screenAssets;
            PersistedDraft.ScreenAssetMetadata[] stateAssets = screenAssets.computeIfAbsent(
                mode, ignored -> new PersistedDraft.ScreenAssetMetadata[4]);
            if (persistedAssets != null) {
                for (int asset = 0; asset < Math.min(4, persistedAssets.length); asset++) {
                    stateAssets[asset] = persistedAssets[asset];
                }
            }
            if (md.voicePresetId != null) {
                try {
                    k1.setVoicePreset(VoicePreset.valueOf(md.voicePresetId));
                } catch (IllegalArgumentException ignored) {
                    k1.setVoicePreset(VoicePreset.WINDOWS_NATIVE);
                }
            }
        }
        lightBarPreview.set(LightBarPreviewState.fromId(draft.lightBarPreviewId));
        if (draft.lightBrightness > 0) {
            lightBrightness.set(Math.max(1, Math.min(100, draft.lightBrightness)));
        }
        for (ModeSlot mode : ModeSlot.values()) {
            PersistedDraft.ModeDraft md = draft.modes[mode.getIndex()];
            if (md.aiLightEffectIds != null) {
                for (IDEState state : IDEState.values()) {
                    if (state.getCode() < md.aiLightEffectIds.length) {
                        aiLightConfigs.get(mode).put(state, LightEffectStyle.fromId(md.aiLightEffectIds[state.getCode()]));
                    }
                }
            }
        }
        revision.set(draft.revision);
        dirtyParts.clear();
        dirtyCount.set(0);
    }

    public PersistedDraft toPersisted() {
        PersistedDraft d = new PersistedDraft();
        d.voiceKeyShortHid = voiceKeyShort.getHidCode();
        d.voiceKeyLongHid = voiceKeyLong.getHidCode();
        d.voiceThresholdMs = voiceThresholdMs.get();
        d.voiceShortAction = voiceShortAction.get().name();
        d.voiceLongAction = voiceLongAction.get().name();
        d.revision = revision.get();
        d.lightBarPreviewId = lightBarPreview.get().getId();
        d.lightBrightness = lightBrightness.get();
        d.modes = new PersistedDraft.ModeDraft[ModeSlot.values().length];
        for (ModeSlot mode : ModeSlot.values()) {
            PersistedDraft.ModeDraft md = new PersistedDraft.ModeDraft();
            KeyConfig k1 = getKeyConfig(mode, StudioPart.KEY1);
            KeyConfig k2 = getKeyConfig(mode, StudioPart.KEY2);
            KeyConfig k3 = getKeyConfig(mode, StudioPart.KEY3);
            KeyConfig k4 = getKeyConfig(mode, StudioPart.KEY4);
            md.key1Hid = k1.getHidCode();
            md.key1Desc = k1.getDescription();
            md.key1Macro = k1.getMacro();
            md.key2Hid = k2.getHidCode();
            md.key2Desc = k2.getDescription();
            md.key2Macro = k2.getMacro();
            md.key3Hid = k3.getHidCode();
            md.key3Desc = k3.getDescription();
            md.key3Macro = k3.getMacro();
            md.key4Hid = k4.getHidCode();
            md.key4Desc = k4.getDescription();
            md.key4Macro = k4.getMacro();
            md.oledSummary = oledSummaries.get(mode).get();
            md.oledCaption = oledCaptions.get(mode).get();
            OledModeDraft od = getOledDraft(mode);
            md.oledGifPath = od.getLocalAssetPath();
            md.oledFrameCount = od.getFrameCount();
            PersistedDraft.ScreenAssetMetadata[] assets = screenAssets.computeIfAbsent(
                mode, ignored -> new PersistedDraft.ScreenAssetMetadata[4]);
            md.screenAssets = java.util.Arrays.copyOf(assets, assets.length);
            md.voicePresetId = getKeyConfig(mode, StudioPart.KEY1).getVoicePreset().name();
            md.aiLightEffectIds = new String[IDEState.values().length];
            for (IDEState state : IDEState.values()) {
                md.aiLightEffectIds[state.getCode()] = getAiLightEffect(mode, state).getId();
            }
            d.modes[mode.getIndex()] = md;
        }
        return d;
    }

    /** JSON 持久化 DTO，字段名稳定供 Jackson 使用。 */
    public static class PersistedDraft {
        public int revision;
        public String lightBarPreviewId = LightBarPreviewState.AI_RUNNING.getId();
        public int lightBrightness = 35;
        public Integer voiceKeyShortHid = 0x4000;
        public Integer voiceKeyLongHid = 0x0A00;
        public Integer voiceThresholdMs = 350;
        public String voiceShortAction = VoiceAction.SYSTEM_VOICE.name();
        public String voiceLongAction = VoiceAction.AHAKEY_VOICE.name();
        public ModeDraft[] modes = new ModeDraft[ModeSlot.values().length];

        public static PersistedDraft defaults() {
            StudioState s = new StudioState();
            return s.toPersisted();
        }

        public static class ModeDraft {
            public int key1Hid;
            public String key1Desc;
            public List<MacroStep> key1Macro;
            public int key2Hid;
            public String key2Desc;
            public List<MacroStep> key2Macro;
            public int key3Hid;
            public String key3Desc;
            public List<MacroStep> key3Macro;
            public int key4Hid;
            public String key4Desc;
            public List<MacroStep> key4Macro;
            public String oledSummary;
            public String oledCaption;
            public String oledGifPath;
            /** Legacy input compatibility; never written or used by the client. */
            @com.fasterxml.jackson.annotation.JsonIgnore
            public int oledFps = 10;
            public int oledFrameCount;
            public String voicePresetId = VoicePreset.CUSTOM.name();
            public String[] aiLightEffectIds;
            /** Metadata for managed local copies; payloads are never stored in settings. */
            public ScreenAssetMetadata[] screenAssets = new ScreenAssetMetadata[4];
        }

        public static class ScreenAssetMetadata {
            public String originalFileName;
            public String originalSourcePath;
            public String managedCachePath;
            public String mediaType;
            public int frameCount;
            public int width;
            public int height;
            public long fileSize;
            public String sha256;
            public String updatedAt;
        }
    }

    private static VoiceAction parseVoiceAction(String value, VoiceAction fallback) {
        if (value == null) return fallback;
        try { return VoiceAction.valueOf(value); }
        catch (IllegalArgumentException ignored) { return fallback; }
    }
}

