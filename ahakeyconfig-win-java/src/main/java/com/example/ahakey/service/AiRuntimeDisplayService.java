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
    private final Map<String, List<AiRuntimeSession>> sessionDiscoveryCache = new HashMap<>();
    private final Map<String, Long> sessionDiscoveryCacheMillis = new HashMap<>();
    private volatile AiRuntimeSlotBinding[] appliedSlots = new AiRuntimeSlotBinding[4];
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
        return bleManager.isDisplayAdmitted();
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
            if (safe == AiRuntimeDisplayMode.MULTI) {
                completion.accept("当前连接尚未识别到支持的固件版本，多任务模式未切换。");
            } else { displayMode.set(safe); persist(); completion.accept(null); }
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
        return handleHookEventResult(platform, state, payload) == Delivery.SENT;
    }

    public enum Delivery { SENT, PENDING, IGNORED, FAILED }
    private static final long FACT_TTL_NANOS = java.util.concurrent.TimeUnit.MINUTES.toNanos(5);
    private record RuntimeFact(IDEState state, long observedNanos, long connection) {
        boolean fresh(long currentConnection) {
            return connection == currentConnection && System.nanoTime() - observedNanos < FACT_TTL_NANOS;
        }
    }
    private final Map<String, RuntimeFact> liveFacts = new java.util.concurrent.ConcurrentHashMap<>();
    // Display occupancy is distinct from a stable session identity; anonymous tools remain owners.
    private record SingleOwner(String provider, String sessionId) {}
    private SingleOwner singleOwner;
    private long singleOwnerAt;
    private long singleOwnerConnection = -1;

    public Delivery handleHookEventResult(String platform, IDEState state, JsonNode payload) {
        String id = "Cursor".equals(platform)
                ? firstNonBlank(text(payload, "conversation_id"), text(payload, "conversationId"),
                    text(payload, "composerId"), text(payload, "composer_id"))
                : firstNonBlank(text(payload, "session_id"), text(payload, "sessionId"));
        String transcript = "Codex".equals(platform)
                ? firstNonBlank(text(payload, "transcript_path"), text(payload, "transcriptPath")) : "";
        var source = "Codex".equals(platform)
                ? codexDiscovery.eventSource(Path.of(codexDataDir), id)
                : CodexSessionDiscoveryService.EventSource.UNKNOWN;
        Delivery result;
        String matchedId = "";
        synchronized (snapshotSendLock) {
            liveFacts.entrySet().removeIf(entry -> !entry.getValue().fresh(bleManager.connectionGeneration()));
            if (source == CodexSessionDiscoveryService.EventSource.BACKGROUND) {
                result = Delivery.IGNORED;
            } else if (displayMode.get() == AiRuntimeDisplayMode.SINGLE) {
                String identity = id.isBlank() ? "" : platform + ":" + id;
                boolean terminal = state == IDEState.TASK_COMPLETED || state == IDEState.STOP || state == IDEState.SESSION_END;
                // A trusted terminal fact must survive even when another session owns SINGLE.
                if (!id.isBlank()) liveFacts.put(identity,
                        new RuntimeFact(state, System.nanoTime(), bleManager.connectionGeneration()));
                SingleOwner eventOwner = new SingleOwner(platform, id);
                if (singleOwnerConnection != bleManager.connectionGeneration()
                        || System.nanoTime() - singleOwnerAt >= FACT_TTL_NANOS) singleOwner = null;
                if (terminal && singleOwner != null && !singleOwner.equals(eventOwner)) {
                    result = Delivery.IGNORED;
                } else {
                    if (!terminal) {
                        singleOwner = eventOwner;
                        singleOwnerAt = System.nanoTime();
                        singleOwnerConnection = bleManager.connectionGeneration();
                    }
                    try {
                        result = bleManager.sendRuntimeState((byte) state.getCode()) ? Delivery.SENT
                                : bleManager.isConnected() ? Delivery.PENDING : Delivery.FAILED;
                    } catch (Exception e) { result = Delivery.FAILED; }
                }
            } else if (!isDeviceSupported() || (!"Codex".equals(platform) && !"Cursor".equals(platform))) {
                result = Delivery.IGNORED;
            } else {
                int matched = -1;
                for (int i = 0; i < appliedSlots.length; i++) {
                    if (matches(appliedSlots[i], platform, id, transcript)) {
                        if (matched >= 0) { matched = -2; break; }
                        matched = i;
                    }
                }
                if (matched < 0) result = Delivery.IGNORED;
                else {
                    AiRuntimeSlotBinding slot = appliedSlots[matched];
                    matchedId = slot.getStableId();
                    liveFacts.put(slot.getProvider() + ":" + slot.getStableId(),
                            new RuntimeFact(state, System.nanoTime(), bleManager.connectionGeneration()));
                    slot.setLastIdeState(state.name());
                    AiRuntimeSlotBinding draft = slots.get(matched);
                    if (Objects.equals(draft.getStableId(), slot.getStableId()) && Objects.equals(draft.getProvider(), slot.getProvider()))
                        draft.setLastIdeState(state.name());
                    snapshotRevision.incrementAndGet();
                    try { result = sendAppliedSnapshot(bleManager.connectionGeneration()) ? Delivery.SENT : Delivery.PENDING; }
                    catch (Exception e) { result = Delivery.FAILED; }
                }
            }
        }
        // Never log the original Hook input, transcript contents, cwd or chat text.
        logger.info("Runtime event platform={} session={} matchedSession={} state={} source={} result={} connection={}",
                platform, diagnosticId(id), diagnosticId(matchedId), state, source, result, bleManager.connectionGeneration());
        return result;
    }

    private String diagnosticId(String id) {
        return id.matches("[A-Za-z0-9_-]{1,128}") ? id : id.isBlank() ? "absent" : "redacted";
    }

    private void applyLiveFact(AiRuntimeSlotBinding slot) {
        RuntimeFact fact = liveFacts.get(slot.getProvider() + ":" + slot.getStableId());
        slot.setLastIdeState(fact != null && fact.fresh(bleManager.connectionGeneration()) ? fact.state().name() : "");
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
                applyLiveFact(copy);
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
        if (!stableId.isBlank()) return stableId.equals(slot.getStableId());
        if (!transcriptPath.isBlank() && transcriptPath.equalsIgnoreCase(slot.getTranscriptPath())) {
            return true;
        }
        return false;
    }

    private void sendAppliedSnapshot() throws Exception {
        sendAppliedSnapshot(bleManager.connectionGeneration());
    }

    private boolean sendAppliedSnapshot(long connection) throws Exception {
        synchronized (snapshotSendLock) {
        if (connection != bleManager.connectionGeneration()) return false;
        snapshotPending = true;
        snapshotConnection = connection;
        if (bleManager.isDisplayBusy() || bleManager.isDisplayWriteUncertain()) return false;
        long revision = snapshotRevision.get();
        boolean anyUsable = Arrays.stream(appliedSlots).anyMatch(slot -> slot != null && slot.isBound());
        if (!anyUsable) {
            logger.info("Skip 0x99 snapshot because no usable runtime slot is available");
            return false;
        }
        AiRuntimeSlotBinding[] snapshot = Arrays.stream(appliedSlots).map(this::copy).toArray(AiRuntimeSlotBinding[]::new);
        for (AiRuntimeSlotBinding slot : snapshot) applyLiveFact(slot);
        bleManager.sendMultiRuntimeSnapshot(snapshot, connection);
        snapshotPending = connection == bleManager.connectionGeneration() && snapshotRevision.get() != revision;
        return true;
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
        draft.slots = slots.stream().map(this::copy).peek(slot -> slot.setLastIdeState("")).toArray(AiRuntimeSlotBinding[]::new);
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
