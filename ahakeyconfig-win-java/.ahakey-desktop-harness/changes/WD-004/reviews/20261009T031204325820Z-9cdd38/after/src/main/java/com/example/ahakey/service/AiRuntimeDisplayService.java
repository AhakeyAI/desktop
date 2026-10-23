package com.example.ahakey.service;

import com.example.ahakey.model.AiRuntimeDisplayMode;
import com.example.ahakey.model.AiRuntimeSession;
import com.example.ahakey.model.AiRuntimeSlotBinding;
import com.example.ahakey.model.IDEState;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.util.AiRuntimeStore;
import com.fasterxml.jackson.databind.JsonNode;
import javafx.beans.property.ObjectProperty;
import javafx.beans.property.SimpleObjectProperty;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

public class AiRuntimeDisplayService {
    private static final Logger logger = LoggerFactory.getLogger(AiRuntimeDisplayService.class);

    private final BleManager bleManager;
    private final CodexSessionDiscoveryService codexDiscovery = new CodexSessionDiscoveryService();
    private final CursorSessionDiscoveryService cursorDiscovery = new CursorSessionDiscoveryService();
    private final ObjectProperty<AiRuntimeDisplayMode> displayMode =
        new SimpleObjectProperty<>(AiRuntimeDisplayMode.SINGLE);
    private final ObservableList<AiRuntimeSlotBinding> slots = FXCollections.observableArrayList();
    private AiRuntimeSlotBinding[] appliedSlots = new AiRuntimeSlotBinding[4];
    private String codexDataDir;
    private String cursorDataDir;
    private int primarySlotIndex = -1;

    public AiRuntimeDisplayService(BleManager bleManager) {
        this.bleManager = bleManager;
        AiRuntimeStore.Draft draft = AiRuntimeStore.loadOrDefault();
        displayMode.set(AiRuntimeDisplayMode.fromName(draft.displayMode));
        codexDataDir = draft.codexDataDir;
        cursorDataDir = draft.cursorDataDir;
        primarySlotIndex = draft.primarySlotIndex;
        for (int i = 0; i < 4; i++) {
            AiRuntimeSlotBinding binding = draft.slots != null && i < draft.slots.length && draft.slots[i] != null
                ? draft.slots[i]
                : new AiRuntimeSlotBinding(i);
            binding.setSlotIndex(i);
            slots.add(binding);
            appliedSlots[i] = copy(binding);
        }
        repairPrimarySlot(true, true);
    }

    public ObjectProperty<AiRuntimeDisplayMode> displayModeProperty() {
        return displayMode;
    }

    public AiRuntimeDisplayMode getDisplayMode() {
        return displayMode.get();
    }

    public String getCodexDataDir() {
        return codexDataDir;
    }

    public void setCodexDataDir(String codexDataDir) {
        this.codexDataDir = codexDataDir == null || codexDataDir.isBlank()
            ? Path.of(System.getProperty("user.home"), ".codex").toString()
            : codexDataDir;
        persist();
    }

    public String getCursorDataDir() {
        return cursorDataDir;
    }

    public void setCursorDataDir(String cursorDataDir) {
        this.cursorDataDir = cursorDataDir == null || cursorDataDir.isBlank()
            ? AiRuntimeStore.Draft.defaultCursorDataDir()
            : cursorDataDir;
        persist();
    }

    public int getPrimarySlotIndex() {
        return primarySlotIndex;
    }

    public void setPrimarySlotIndex(int slotIndex) {
        if (slotIndex < 0 || slotIndex >= slots.size() || !slots.get(slotIndex).isBound()) {
            return;
        }
        primarySlotIndex = slotIndex;
        persist();
    }

    public ObservableList<AiRuntimeSlotBinding> getSlots() {
        return slots;
    }

    public List<AiRuntimeSession> discoverCodexSessions() {
        return codexDiscovery.discover(Path.of(codexDataDir));
    }

    public List<AiRuntimeSession> discoverCursorSessions() {
        return cursorDiscovery.discover(Path.of(cursorDataDir));
    }

    public List<AiRuntimeSession> discoverSessions(String provider) {
        if ("Cursor".equals(provider)) {
            return discoverCursorSessions();
        }
        return discoverCodexSessions();
    }

    public boolean isDataDirValid(String provider) {
        String path = "Cursor".equals(provider) ? cursorDataDir : codexDataDir;
        return path != null && !path.isBlank() && Files.isDirectory(Path.of(path));
    }

    public boolean isDeviceSupported() {
        if (bleManager.getCachedStatus() == null) {
            return false;
        }
        return AhaKeyProtocol.isWs3Cp1RuntimeDisplaySupported(bleManager.getCachedStatus().getFirmwareCatalogKey());
    }

    public void setDisplayMode(AiRuntimeDisplayMode mode) {
        AiRuntimeDisplayMode safe = mode == null ? AiRuntimeDisplayMode.SINGLE : mode;
        if (safe == displayMode.get()) {
            return;
        }
        displayMode.set(safe);
        persist();
        if (isDeviceSupported()) {
            new Thread(() -> {
                try {
                    bleManager.setRuntimeDisplayMode(safe);
                } catch (Exception e) {
                    logger.warn("Set runtime display mode failed: {}", e.getMessage());
                }
            }, "ai-runtime-mode-send").start();
        }
    }

    public void onDeviceReady() {
        if (!isDeviceSupported()) {
            return;
        }
        new Thread(() -> {
            try {
                bleManager.setRuntimeDisplayMode(displayMode.get());
            } catch (Exception e) {
                logger.warn("Apply runtime display preference on connect failed: {}", e.getMessage());
            }
        }, "ai-runtime-connect-apply").start();
    }

    public void bindSlot(int slotIndex, AiRuntimeSession session) {
        if (slotIndex < 0 || slotIndex >= slots.size() || session == null) {
            return;
        }
        if (findBoundSlot(session.provider(), session.id()) >= 0) {
            return;
        }
        slots.set(slotIndex, session.toBinding(slotIndex));
        if (primarySlotIndex < 0) {
            primarySlotIndex = slotIndex;
        }
        persist();
    }

    public void clearSlot(int slotIndex) {
        if (slotIndex < 0 || slotIndex >= slots.size()) {
            return;
        }
        boolean wasPrimary = primarySlotIndex == slotIndex;
        slots.set(slotIndex, new AiRuntimeSlotBinding(slotIndex));
        if (wasPrimary) {
            primarySlotIndex = firstBoundSlot();
        }
        persist();
    }

    public void markDraftApplied() {
        markDraftApplied(true, true);
    }

    public void markDraftApplied(boolean codexHookLatest, boolean cursorHookLatest) {
        ApplyPlan plan = prepareApply(codexHookLatest, cursorHookLatest);
        appliedSlots = Arrays.stream(plan.slots()).map(this::copy).toArray(AiRuntimeSlotBinding[]::new);
    }

    public void applyToKeyboard() throws Exception {
        applyToKeyboard(true, true);
    }

    public void applyToKeyboard(boolean codexHookLatest, boolean cursorHookLatest) throws Exception {
        if (!isDeviceSupported()) {
            throw new IllegalStateException("当前固件不支持 WS3 CP1 运行态展示");
        }
        ApplyPlan plan = prepareApply(codexHookLatest, cursorHookLatest);
        if (displayMode.get() == AiRuntimeDisplayMode.MULTI && plan.usableCount() == 0) {
            throw new IllegalStateException("当前没有可应用到键盘的任务槽。请检查 Hook 状态或重新选择会话。");
        }
        bleManager.setRuntimeDisplayMode(displayMode.get());
        appliedSlots = Arrays.stream(plan.slots()).map(this::copy).toArray(AiRuntimeSlotBinding[]::new);
        if (displayMode.get() == AiRuntimeDisplayMode.MULTI) {
            sendAppliedSnapshot();
        }
        persist();
    }

    public boolean handleHookEvent(String platform, IDEState state, JsonNode payload) {
        if (displayMode.get() == AiRuntimeDisplayMode.SINGLE) {
            try {
                bleManager.updateState((byte) state.getCode());
                return true;
            } catch (Exception e) {
                logger.warn("SINGLE runtime update failed: {}", e.getMessage());
                return false;
            }
        }
        if (displayMode.get() != AiRuntimeDisplayMode.MULTI
            || (!"Codex".equals(platform) && !"Cursor".equals(platform))
            || !isDeviceSupported()) {
            return false;
        }
        String stableId = "Cursor".equals(platform)
            ? firstNonBlank(
                text(payload, "conversation_id"),
                text(payload, "session_id"),
                text(payload, "composerId"),
                text(payload, "composer_id"),
                text(payload, "conversationId"),
                text(payload, "conversation_id")
            )
            : firstNonBlank(text(payload, "session_id"), text(payload, "sessionId"));
        String transcriptPath = "Codex".equals(platform)
            ? firstNonBlank(text(payload, "transcript_path"), text(payload, "transcriptPath"))
            : "";
        if (stableId.isBlank() && transcriptPath.isBlank()) {
            logger.info("MULTI runtime event ignored without session identity: platform={}", platform);
            return false;
        }
        for (int i = 0; i < appliedSlots.length; i++) {
            AiRuntimeSlotBinding slot = appliedSlots[i];
            if (!matches(slot, platform, stableId, transcriptPath)) {
                continue;
            }
            if (Objects.equals(slot.getLastIdeState(), state.name())) {
                return true;
            }
            slot.setLastIdeState(state.name());
            slots.get(i).setLastIdeState(state.name());
            persist();
            try {
                sendAppliedSnapshot();
                return true;
            } catch (Exception e) {
                logger.warn("MULTI runtime snapshot failed: {}", e.getMessage());
                return false;
            }
        }
        return false;
    }

    public ApplyPlan prepareApply(boolean codexHookLatest, boolean cursorHookLatest) {
        Map<String, Map<String, AiRuntimeSession>> indexes = new HashMap<>();
        indexes.put("Codex", indexById(codexHookLatest ? discoverCodexSessions() : List.of()));
        indexes.put("Cursor", indexById(cursorHookLatest ? discoverCursorSessions() : List.of()));
        AiRuntimeSlotBinding[] prepared = new AiRuntimeSlotBinding[4];
        List<UnavailableSlot> unavailable = new ArrayList<>();
        int usable = 0;
        int firstUsable = -1;
        boolean currentPrimaryUsable = false;
        String[] reasons = new String[4];
        for (int i = 0; i < 4; i++) {
            AiRuntimeSlotBinding source = slots.get(i);
            String reason = unavailableReason(source, codexHookLatest, cursorHookLatest, indexes);
            reasons[i] = reason;
            if (reason == null) {
                if (firstUsable < 0) {
                    firstUsable = i;
                }
                if (i == primarySlotIndex) {
                    currentPrimaryUsable = true;
                }
            }
        }
        int desiredPrimary = currentPrimaryUsable ? primarySlotIndex : firstUsable;
        if (primarySlotIndex != desiredPrimary) {
            primarySlotIndex = desiredPrimary;
            persist();
        }
        for (int i = 0; i < 4; i++) {
            AiRuntimeSlotBinding source = slots.get(i);
            String reason = reasons[i];
            if (reason == null) {
                AiRuntimeSlotBinding copy = copy(source);
                copy.setForeground(i == desiredPrimary);
                prepared[i] = copy;
                usable++;
            } else {
                prepared[i] = new AiRuntimeSlotBinding(i);
                if (source.isBound()) {
                    unavailable.add(new UnavailableSlot(i, reason));
                }
            }
        }
        return new ApplyPlan(prepared, unavailable, usable, desiredPrimary);
    }

    public String slotUnavailableReason(AiRuntimeSlotBinding slot, boolean codexHookLatest, boolean cursorHookLatest) {
        Map<String, Map<String, AiRuntimeSession>> indexes = new HashMap<>();
        indexes.put("Codex", indexById(codexHookLatest ? discoverCodexSessions() : List.of()));
        indexes.put("Cursor", indexById(cursorHookLatest ? discoverCursorSessions() : List.of()));
        return unavailableReason(slot, codexHookLatest, cursorHookLatest, indexes);
    }

    public int findBoundSlot(String provider, String stableId) {
        if (provider == null || stableId == null || stableId.isBlank()) {
            return -1;
        }
        for (int i = 0; i < slots.size(); i++) {
            AiRuntimeSlotBinding slot = slots.get(i);
            if (provider.equals(slot.getProvider()) && stableId.equals(slot.getStableId())) {
                return i;
            }
        }
        return -1;
    }

    private String unavailableReason(
        AiRuntimeSlotBinding slot,
        boolean codexHookLatest,
        boolean cursorHookLatest,
        Map<String, Map<String, AiRuntimeSession>> indexes
    ) {
        if (slot == null || !slot.isBound()) {
            return "未绑定会话";
        }
        boolean hookLatest = "Cursor".equals(slot.getProvider()) ? cursorHookLatest : codexHookLatest;
        if (!hookLatest) {
            return "需安装/更新 Hook";
        }
        Map<String, AiRuntimeSession> sourceIndex = indexes.getOrDefault(slot.getProvider(), Map.of());
        if (!sourceIndex.containsKey(slot.getStableId())) {
            return "会话记录已不可用";
        }
        return null;
    }

    private int repairPrimarySlot(boolean codexHookLatest, boolean cursorHookLatest) {
        int firstUsable = -1;
        for (int i = 0; i < slots.size(); i++) {
            AiRuntimeSlotBinding slot = slots.get(i);
            if (slot.isBound() && ("Cursor".equals(slot.getProvider()) ? cursorHookLatest : codexHookLatest)) {
                if (firstUsable < 0) {
                    firstUsable = i;
                }
                if (i == primarySlotIndex) {
                    return primarySlotIndex;
                }
            }
        }
        if (primarySlotIndex != firstUsable) {
            primarySlotIndex = firstUsable;
            persist();
        }
        return primarySlotIndex;
    }

    private int firstBoundSlot() {
        for (int i = 0; i < slots.size(); i++) {
            if (slots.get(i).isBound()) {
                return i;
            }
        }
        return -1;
    }

    private Map<String, AiRuntimeSession> indexById(List<AiRuntimeSession> sessions) {
        Map<String, AiRuntimeSession> index = new HashMap<>();
        for (AiRuntimeSession session : sessions) {
            if (session.id() != null && !session.id().isBlank()) {
                index.put(session.id(), session);
            }
        }
        return index;
    }

    private boolean matches(AiRuntimeSlotBinding slot, String platform, String stableId, String transcriptPath) {
        if (slot == null || !slot.isBound()) {
            return false;
        }
        if (!platform.equals(slot.getProvider())) {
            return false;
        }
        if (!stableId.isBlank() && stableId.equals(slot.getStableId())) {
            return true;
        }
        if (!transcriptPath.isBlank() && transcriptPath.equalsIgnoreCase(slot.getTranscriptPath())) {
            return true;
        }
        return false;
    }

    private void sendAppliedSnapshot() throws Exception {
        boolean anyUsable = Arrays.stream(appliedSlots).anyMatch(slot -> slot != null && slot.isBound());
        if (!anyUsable) {
            logger.info("Skip 0x99 snapshot because no usable runtime slot is available");
            return;
        }
        bleManager.sendMultiRuntimeSnapshot(Arrays.stream(appliedSlots).map(this::copy).toArray(AiRuntimeSlotBinding[]::new));
    }

    private String text(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        if (value == null || value.isNull()) {
            JsonNode hookInput = node == null ? null : node.get("hookInput");
            value = hookInput == null ? null : hookInput.get(field);
        }
        return value == null || value.isNull() ? "" : value.asText("");
    }

    private String firstNonBlank(String... values) {
        if (values != null) {
            for (String value : values) {
                if (value != null && !value.isBlank()) {
                    return value;
                }
            }
        }
        return "";
    }

    private AiRuntimeSlotBinding copy(AiRuntimeSlotBinding source) {
        AiRuntimeSlotBinding target = new AiRuntimeSlotBinding(source == null ? 0 : source.getSlotIndex());
        if (source == null) {
            return target;
        }
        target.setProvider(source.getProvider());
        target.setStableId(source.getStableId());
        target.setTranscriptPath(source.getTranscriptPath());
        target.setCwd(source.getCwd());
        target.setProjectName(source.getProjectName());
        target.setSessionTitle(source.getSessionTitle());
        target.setLastIdeState(source.getLastIdeState());
        target.setUpdatedAtMillis(source.getUpdatedAtMillis());
        target.setForeground(source.isForeground());
        return target;
    }

    private void persist() {
        AiRuntimeStore.Draft draft = new AiRuntimeStore.Draft();
        draft.displayMode = displayMode.get().name();
        draft.codexDataDir = codexDataDir;
        draft.cursorDataDir = cursorDataDir;
        draft.primarySlotIndex = primarySlotIndex;
        draft.slots = slots.toArray(new AiRuntimeSlotBinding[0]);
        AiRuntimeStore.save(draft);
    }

    public record ApplyPlan(
        AiRuntimeSlotBinding[] slots,
        List<UnavailableSlot> unavailableSlots,
        int usableCount,
        int primarySlotIndex
    ) {}

    public record UnavailableSlot(int slotIndex, String reason) {}
}
