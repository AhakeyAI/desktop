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
import javafx.beans.property.BooleanProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.application.Platform;
import java.util.function.Consumer;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Files;
import java.nio.file.Path;
import java.net.URI;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

public class AiRuntimeDisplayService {
    private static final Logger logger = LoggerFactory.getLogger(AiRuntimeDisplayService.class);
    private static final long SESSION_DISCOVERY_CACHE_MILLIS = 5000L;

    private final BleManager bleManager;
    private final CodexSessionDiscoveryService codexDiscovery = new CodexSessionDiscoveryService();
    private final CursorSessionDiscoveryService cursorDiscovery = new CursorSessionDiscoveryService();
    private final ObjectProperty<AiRuntimeDisplayMode> displayMode =
        new SimpleObjectProperty<>(AiRuntimeDisplayMode.SINGLE);
    private final ObservableList<AiRuntimeSlotBinding> slots = FXCollections.observableArrayList();
    private final Map<String, Integer> lastActiveSlotByPlatform = new HashMap<>();
    private final Map<String, List<AiRuntimeSession>> sessionDiscoveryCache = new HashMap<>();
    private final Map<String, Long> sessionDiscoveryCacheMillis = new HashMap<>();
    private AiRuntimeSlotBinding[] appliedSlots = new AiRuntimeSlotBinding[4];
    private String codexDataDir;
    private String cursorDataDir;
    private int primarySlotIndex = -1;
    private volatile boolean snapshotPending;
    private volatile long snapshotConnection = -1;
    private final BooleanProperty modeChangePending = new SimpleBooleanProperty();
    private final Object snapshotSendLock = new Object();
    private final java.util.concurrent.atomic.AtomicLong snapshotRevision = new java.util.concurrent.atomic.AtomicLong();

    public AiRuntimeDisplayService(BleManager bleManager) {
        this.bleManager = bleManager;
        bleManager.setDisplayIdleListener(() -> {
            long connection = snapshotConnection;
            if (snapshotPending && connection == bleManager.connectionGeneration()
                    && displayMode.get() == AiRuntimeDisplayMode.MULTI) {
                try { sendAppliedSnapshot(connection); }
                catch (Exception e) { logger.debug("Latest runtime snapshot remains pending: {}", e.getMessage()); }
            }
        });
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
            appliedSlots[i] = new AiRuntimeSlotBinding(i);
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
        invalidateSessionCache("Codex");
        persist();
    }

    public String getCursorDataDir() {
        return cursorDataDir;
    }

    public void setCursorDataDir(String cursorDataDir) {
        this.cursorDataDir = cursorDataDir == null || cursorDataDir.isBlank()
            ? AiRuntimeStore.Draft.defaultCursorDataDir()
            : cursorDataDir;
        invalidateSessionCache("Cursor");
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

    public synchronized List<AiRuntimeSession> discoverSessions(String provider) {
        List<AiRuntimeSession> cached = sessionDiscoveryCache.get(provider);
        Long cachedAt = sessionDiscoveryCacheMillis.get(provider);
        if (cached != null && cachedAt != null && System.currentTimeMillis() - cachedAt < SESSION_DISCOVERY_CACHE_MILLIS) {
            return cached;
        }
        List<AiRuntimeSession> sessions = "Cursor".equals(provider)
            ? discoverCursorSessions()
            : discoverCodexSessions();
        sessionDiscoveryCache.put(provider, sessions);
        sessionDiscoveryCacheMillis.put(provider, System.currentTimeMillis());
        return sessions;
    }

    public boolean isDataDirValid(String provider) {
        String path = "Cursor".equals(provider) ? cursorDataDir : codexDataDir;
        return path != null && !path.isBlank() && Files.isDirectory(Path.of(path));
    }

    public boolean isDeviceSupported() {
        if (!bleManager.isConnected() || bleManager.getCachedStatus() == null || !bleManager.getCachedStatus().isConnected()) {
            return false;
        }
        return AhaKeyProtocol.isWs3Cp1RuntimeDisplaySupported(bleManager.getCachedStatus().getFirmwareCatalogKey());
    }

    public void setDisplayMode(AiRuntimeDisplayMode mode) {
        setDisplayMode(mode, error -> { if (error != null) logger.warn("{}", error); });
    }

    public BooleanProperty modeChangePendingProperty() { return modeChangePending; }

    public void setDisplayMode(AiRuntimeDisplayMode mode, Consumer<String> completion) {
        AiRuntimeDisplayMode safe = mode == null ? AiRuntimeDisplayMode.SINGLE : mode;
        if (modeChangePending.get() || bleManager.isDisplayBusy() || bleManager.isDisplayWriteUncertain()) {
            completion.accept("设备正在处理显示配置或保存结果未确认，展示模式未切换。");
            return;
        }
        if (safe == displayMode.get()) {
            completion.accept(null);
            return;
        }
        if (isDeviceSupported()) {
            long connection = bleManager.connectionGeneration();
            modeChangePending.set(true);
            new Thread(() -> {
                String failure = null;
                try {
                    bleManager.setRuntimeDisplayMode(safe, connection);
                } catch (Exception e) {
                    failure = "展示模式未确认：" + e.getMessage();
                }
                String result = failure;
                Platform.runLater(() -> {
                    modeChangePending.set(false);
                    if (connection != bleManager.connectionGeneration() || !isDeviceSupported()) {
                        completion.accept("键盘连接已改变，展示模式未确认。"); return;
                    }
                    if (result == null) { displayMode.set(safe); persist(); }
                    completion.accept(result);
                });
            }, "ai-runtime-mode-send").start();
        } else {
            displayMode.set(safe); persist(); completion.accept(null);
        }
    }

    public void onDeviceReady() {
        if (!isDeviceSupported()) {
            return;
        }
        long connection = bleManager.connectionGeneration();
        AiRuntimeDisplayMode preference = displayMode.get();
        new Thread(() -> {
            try {
                bleManager.setRuntimeDisplayMode(preference, connection);
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
        removeLastActiveSlot(slotIndex);
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
        lastActiveSlotByPlatform.clear();
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
        lastActiveSlotByPlatform.clear();
        if (displayMode.get() == AiRuntimeDisplayMode.MULTI) {
            sendAppliedSnapshot();
        }
        persist();
    }

    public boolean handleHookEvent(String platform, IDEState state, JsonNode payload) {
        if (displayMode.get() == AiRuntimeDisplayMode.SINGLE) {
            try {
                bleManager.sendRuntimeState((byte) state.getCode());
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
        String workingDir = firstNonBlank(
            text(payload, "cwd"),
            text(payload, "current_working_directory"),
            text(payload, "currentWorkingDirectory")
        );
        if (stableId.isBlank() && transcriptPath.isBlank() && workingDir.isBlank()) {
            int fallbackSlot = fallbackTerminalSlotForPlatform(platform);
            if (fallbackSlot < 0 || !isTerminalState(state)) {
                logger.info("MULTI runtime event ignored without session identity: platform={}, state={}", platform, state);
                return false;
            }
            return updateRuntimeSlotState(fallbackSlot, platform, state);
        }
        for (int i = 0; i < appliedSlots.length; i++) {
            AiRuntimeSlotBinding slot = appliedSlots[i];
            if (!matches(slot, platform, stableId, transcriptPath)) {
                continue;
            }
            return updateRuntimeSlotState(i, platform, state);
        }
        if (!workingDir.isBlank()) {
            int locationSlot = uniqueLocationSlotForPlatform(platform, workingDir);
            if (locationSlot >= 0) {
                return updateRuntimeSlotState(locationSlot, platform, state);
            }
        }
        return false;
    }

    private boolean updateRuntimeSlotState(int slotIndex, String platform, IDEState state) {
        AiRuntimeSlotBinding slot = appliedSlots[slotIndex];
        lastActiveSlotByPlatform.put(platform, slotIndex);
        if (Objects.equals(slot.getLastIdeState(), state.name()) && !snapshotPending) {
            return true;
        }
        slot.setLastIdeState(state.name());
        snapshotRevision.incrementAndGet();
        slots.get(slotIndex).setLastIdeState(state.name());
        persist();
        try {
            sendAppliedSnapshot();
            return true;
        } catch (Exception e) {
            logger.warn("MULTI runtime snapshot failed: {}", e.getMessage());
            return false;
        }
    }

    private int fallbackTerminalSlotForPlatform(String platform) {
        int runningSlot = uniqueRunningSlotForPlatform(platform);
        if (runningSlot >= 0) {
            return runningSlot;
        }
        int only = -1;
        int count = 0;
        for (int i = 0; i < appliedSlots.length; i++) {
            AiRuntimeSlotBinding slot = appliedSlots[i];
            if (slot != null && slot.isBound() && platform.equals(slot.getProvider())) {
                only = i;
                count++;
            }
        }
        if (count == 1) {
            return only;
        }

        if (primarySlotIndex >= 0 && primarySlotIndex < appliedSlots.length) {
            AiRuntimeSlotBinding primary = appliedSlots[primarySlotIndex];
            if (primary != null && primary.isBound() && platform.equals(primary.getProvider())) {
                return primarySlotIndex;
            }
        }
        return -1;
    }

    private int uniqueRunningSlotForPlatform(String platform) {
        int runningSlot = -1;
        int runningCount = 0;
        for (int i = 0; i < appliedSlots.length; i++) {
            AiRuntimeSlotBinding slot = appliedSlots[i];
            if (slot != null && slot.isBound() && platform.equals(slot.getProvider()) && isRunningSlot(slot)) {
                runningSlot = i;
                runningCount++;
            }
        }
        return runningCount == 1 ? runningSlot : -1;
    }

    private boolean isRunningSlot(AiRuntimeSlotBinding slot) {
        if (slot == null || slot.getLastIdeState() == null || slot.getLastIdeState().isBlank()) {
            return false;
        }
        try {
            return com.example.ahakey.model.AiRuntimeSlotState.fromIdeState(IDEState.valueOf(slot.getLastIdeState()))
                == com.example.ahakey.model.AiRuntimeSlotState.RUNNING;
        } catch (IllegalArgumentException e) {
            return false;
        }
    }

    private void removeLastActiveSlot(int slotIndex) {
        lastActiveSlotByPlatform.entrySet().removeIf(entry -> entry.getValue() == slotIndex);
    }

    private boolean isTerminalState(IDEState state) {
        return state == IDEState.TASK_COMPLETED || state == IDEState.STOP || state == IDEState.SESSION_END;
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
        indexes.put("Codex", indexById(codexHookLatest ? discoverSessions("Codex") : List.of()));
        indexes.put("Cursor", indexById(cursorHookLatest ? discoverSessions("Cursor") : List.of()));
        return unavailableReason(slot, codexHookLatest, cursorHookLatest, indexes);
    }

    private synchronized void invalidateSessionCache(String provider) {
        sessionDiscoveryCache.remove(provider);
        sessionDiscoveryCacheMillis.remove(provider);
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

    private int uniqueLocationSlotForPlatform(String platform, String workingDir) {
        int matchedSlot = -1;
        int matchedCount = 0;
        for (int i = 0; i < appliedSlots.length; i++) {
            AiRuntimeSlotBinding slot = appliedSlots[i];
            if (slot != null && slot.isBound() && platform.equals(slot.getProvider())
                && (sameLocation(workingDir, slot.getCwd()) || sameLocation(workingDir, slot.getProjectName()))) {
                matchedSlot = i;
                matchedCount++;
            }
        }
        return matchedCount == 1 ? matchedSlot : -1;
    }

    private boolean sameLocation(String left, String right) {
        String normalizedLeft = normalizeLocation(left);
        String normalizedRight = normalizeLocation(right);
        return !normalizedLeft.isBlank() && normalizedLeft.equalsIgnoreCase(normalizedRight);
    }

    private String normalizeLocation(String value) {
        if (value == null || value.isBlank()) {
            return "";
        }
        String normalized = value.trim();
        if (normalized.startsWith("\\\\?\\")) {
            normalized = normalized.substring(4);
        }
        if (normalized.startsWith("file:/")) {
            try {
                normalized = Path.of(URI.create(normalized)).toString();
            } catch (Exception ignored) {
                normalized = normalized.replace("file:///", "");
            }
        }
        return normalized.replace('/', '\\');
    }

    private void sendAppliedSnapshot() throws Exception {
        sendAppliedSnapshot(bleManager.connectionGeneration());
    }

    private void sendAppliedSnapshot(long connection) throws Exception {
        synchronized (snapshotSendLock) {
        if (connection != bleManager.connectionGeneration()) return;
        snapshotPending = true;
        snapshotConnection = connection;
        if (bleManager.isDisplayBusy() || bleManager.isDisplayWriteUncertain()) return;
        long revision = snapshotRevision.get();
        boolean anyUsable = Arrays.stream(appliedSlots).anyMatch(slot -> slot != null && slot.isBound());
        if (!anyUsable) {
            logger.info("Skip 0x99 snapshot because no usable runtime slot is available");
            return;
        }
        bleManager.sendMultiRuntimeSnapshot(Arrays.stream(appliedSlots).map(this::copy).toArray(AiRuntimeSlotBinding[]::new), connection);
        snapshotPending = connection == bleManager.connectionGeneration() && snapshotRevision.get() != revision;
        }
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
