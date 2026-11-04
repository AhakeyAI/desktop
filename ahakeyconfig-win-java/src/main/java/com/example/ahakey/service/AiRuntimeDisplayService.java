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
    private final CursorSessionDiscoveryService cursorDiscovery;
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
    // Only protects in-memory intent. Device locks and ACK waits must never hold this lock.
    private boolean snapshotSending;
    private volatile long snapshotConnection = -1;
    private final BooleanProperty modeChangePending = new SimpleBooleanProperty();
    private final Object snapshotSendLock = new Object();
    private final Object singleSendLock = new Object();
    private final java.util.concurrent.atomic.AtomicLong singleRevision = new java.util.concurrent.atomic.AtomicLong();
    private final java.util.concurrent.atomic.AtomicLong snapshotRevision = new java.util.concurrent.atomic.AtomicLong();

    // Native Cursor observations are a MULTI-only overlay, never synthetic Hook events.
    private final Map<String, CursorTracking> cursorTracking = new HashMap<>();
    private final Object cursorLifecycleLock = new Object();
    private java.util.concurrent.ScheduledExecutorService cursorMonitor;
    private java.util.concurrent.ScheduledExecutorService snapshotRetry;
    private boolean snapshotRetryQueued;
    private volatile boolean cursorClosed;
    private volatile long cursorEpoch;
    private long cursorSample, cursorConnection = -1;
    private long cursorClearPendingConnection = -1, cursorMaintenance = -1;
    private String cursorProcess = "";
    private String cursorObservedProcess = "";
    private record CursorOverlay(long connection, Map<String, String> states) {}
    private volatile CursorOverlay cursorOverlay = new CursorOverlay(-1, Map.of());
    private static final class CursorTracking {
        Boolean lastValue;
        boolean waiting, unknown, anchored, confirmed;
        long hookRevision, acceptedSample;
        String generation = "";
        String fallbackGeneration = "";
        boolean fallbackTerminal;
        boolean terminal, pendingStartedFromFalse, generationStartedFromFalse, nativeIdentityContext;
        final java.util.Set<String> retiredGenerations = new java.util.HashSet<>();
        final java.util.LinkedHashMap<String, IDEState> pendingHooks = new java.util.LinkedHashMap<>();
    }
    private record CursorRead(long epoch, long connection, long maintenance, long sequence, String process,
                              String directory, Map<String, Long> hooks) {}

    public AiRuntimeDisplayService(BleManager bleManager) {
        this(bleManager, new CursorSessionDiscoveryService());
    }

    AiRuntimeDisplayService(BleManager bleManager, CursorSessionDiscoveryService cursorDiscovery) {
        this.bleManager = bleManager;
        this.cursorDiscovery = cursorDiscovery;
        displayMode.addListener((observable, before, after) -> {
            synchronized (snapshotSendLock) {
                invalidateCursorContext(); snapshotPending = false; snapshotRevision.incrementAndGet();
                singleRevision.incrementAndGet();
            }
        });
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

    public void startCursorMonitoring() {
        synchronized (cursorLifecycleLock) {
            if (cursorClosed || cursorMonitor != null) return;
            cursorMonitor = java.util.concurrent.Executors.newSingleThreadScheduledExecutor(r -> {
                Thread thread = new Thread(r, "cursor-waiting-observer"); thread.setDaemon(true); return thread;
            });
            cursorMonitor.scheduleWithFixedDelay(() -> {
                try { pollCursorWaiting(); }
                catch (Exception e) { logger.debug("Cursor waiting observation unavailable"); }
            }, 0, 500, java.util.concurrent.TimeUnit.MILLISECONDS);
        }
    }

    public void close() {
        synchronized (cursorLifecycleLock) {
            cursorClosed = true;
            cursorOverlay = new CursorOverlay(-1, Map.of());
            if (cursorMonitor != null) { cursorMonitor.shutdownNow(); cursorMonitor = null; }
            if (snapshotRetry != null) { snapshotRetry.shutdownNow(); snapshotRetry = null; }
        }
    }

    private void invalidateCursorContext() {
        cursorEpoch++; cursorTracking.clear(); cursorProcess = ""; cursorObservedProcess = ""; cursorConnection = -1; cursorMaintenance = -1;
        cursorOverlay = new CursorOverlay(-1, Map.of());
    }

    private Map<String, Long> cursorTargets() {
        Map<String, Long> result = new HashMap<>();
        java.util.Set<String> duplicates = new java.util.HashSet<>();
        for (AiRuntimeSlotBinding slot : appliedSlots) {
            if (slot != null && slot.isBound() && "Cursor".equals(slot.getProvider())) {
                String id = slot.getStableId();
                if (result.put(id, cursorTracking.computeIfAbsent(id, key -> new CursorTracking()).hookRevision) != null)
                    duplicates.add(id);
            }
        }
        duplicates.forEach(result::remove);
        cursorTracking.keySet().retainAll(result.keySet());
        return result;
    }

    // Package-visible deterministic seam: the same method is used by the production scheduler.
    void pollCursorWaiting() {
        try { observeCursorWaiting(); }
        finally {
            if (snapshotPending) {
                try { sendAppliedSnapshot(snapshotConnection); }
                catch (Exception e) { logger.debug("Cursor waiting snapshot remains pending"); }
            }
        }
    }

    private void observeCursorWaiting() {
        synchronized (snapshotSendLock) { if (cursorClosed || displayMode.get() != AiRuntimeDisplayMode.MULTI) return; }
        var process = cursorDiscovery.runningCursor();
        String processIdentity = process.generation() + ":" + process.version();
        CursorRead read;
        synchronized (snapshotSendLock) {
            if (cursorClosed || displayMode.get() != AiRuntimeDisplayMode.MULTI) return;
            if (!bleManager.maintenance().normalAllowed() || !isDeviceSupported()) { invalidateCursorContext(); return; }
            long connection = bleManager.connectionGeneration();
            long maintenance = bleManager.maintenance().epoch();
            if (cursorConnection != connection || cursorMaintenance != maintenance) {
                invalidateCursorContext(); cursorConnection = connection; cursorMaintenance = maintenance;
            }
            if (cursorClearPendingConnection == connection) { cursorClearPendingConnection = -1; sendCursorSnapshot(); }
            else cursorClearPendingConnection = -1;
            if (!processIdentity.equals(cursorObservedProcess)) {
                boolean changed = false;
                for (var entry : cursorTracking.entrySet()) {
                    CursorTracking tracking = entry.getValue();
                    if (tracking.confirmed) { tracking.unknown = true; changed = true; }
                    if (!tracking.generation.isEmpty()) tracking.retiredGenerations.add(tracking.generation);
                    if (!tracking.fallbackGeneration.isEmpty()) tracking.retiredGenerations.add(tracking.fallbackGeneration);
                    changed |= liveFacts.remove("Cursor:" + entry.getKey()) != null;
                    tracking.generation = ""; tracking.pendingHooks.clear(); tracking.terminal = false;
                    tracking.fallbackGeneration = ""; tracking.fallbackTerminal = false; tracking.nativeIdentityContext = false;
                    tracking.waiting = false; tracking.confirmed = false; tracking.anchored = false; tracking.lastValue = null; tracking.hookRevision++;
                }
                cursorObservedProcess = processIdentity;
                cursorEpoch++; cursorProcess = process.supported() ? processIdentity : "";
                if (changed) sendCursorSnapshot();
            }
            if (!process.supported()) return;
            Map<String, Long> hooks = cursorTargets();
            if (hooks.isEmpty()) return;
            read = new CursorRead(cursorEpoch, connection, maintenance, ++cursorSample, cursorProcess, cursorDataDir, Map.copyOf(hooks));
        }
        // No FX thread, snapshot lock or device transaction is held during the bounded SQLite read.
        var observations = cursorDiscovery.readRuntimeStates(Path.of(read.directory()), read.hooks().keySet(), process.version());
        var after = cursorDiscovery.runningCursor();
        synchronized (snapshotSendLock) {
            if (cursorClosed || read.epoch() != cursorEpoch || read.connection() != bleManager.connectionGeneration()
                    || read.maintenance() != bleManager.maintenance().epoch()
                    || displayMode.get() != AiRuntimeDisplayMode.MULTI || !bleManager.maintenance().normalAllowed()
                    || !Objects.equals(read.directory(), cursorDataDir) || !after.supported()
                    || !read.process().equals(after.generation() + ":" + after.version())) return;
            boolean changed = false;
            for (var entry : read.hooks().entrySet()) {
                CursorTracking tracking = cursorTracking.get(entry.getKey());
                if (tracking == null || tracking.hookRevision != entry.getValue() || read.sequence() <= tracking.acceptedSample) continue;
                tracking.acceptedSample = read.sequence();
                boolean wasWaiting = tracking.waiting, wasUnknown = tracking.unknown;
                var state = observations.get(entry.getKey());
                if (state == null || state.state() == CursorSessionDiscoveryService.Waiting.UNKNOWN
                        || state.generation().isEmpty() || tracking.retiredGenerations.contains(state.generation())) {
                    // Unknown cannot manufacture a green/done recovery from a previous yellow.
                    tracking.unknown |= tracking.confirmed;
                    tracking.waiting = false;
                    if (!tracking.confirmed) tracking.lastValue = null;
                } else {
                    tracking.nativeIdentityContext = true;
                    if (!state.generation().equals(tracking.generation)) {
                        boolean previousFalse = Boolean.FALSE.equals(tracking.lastValue) && !tracking.unknown;
                        boolean candidateFalse = tracking.pendingStartedFromFalse;
                        boolean hadGeneration = !tracking.generation.isEmpty();
                        if (hadGeneration) tracking.retiredGenerations.add(tracking.generation);
                        tracking.generation = state.generation(); tracking.terminal = false;
                        tracking.waiting = false; tracking.confirmed = false; tracking.unknown = false;
                        tracking.anchored = false; tracking.lastValue = null;
                        boolean removedFact = liveFacts.remove("Cursor:" + entry.getKey()) != null;
                        IDEState pending = tracking.pendingHooks.get(tracking.generation);
                        tracking.pendingHooks.clear(); tracking.pendingStartedFromFalse = false;
                        tracking.generationStartedFromFalse = pending != null ? candidateFalse : previousFalse;
                        if (pending != null) {
                            if (tracking.generationStartedFromFalse) tracking.lastValue = false;
                            acceptCursorHook(tracking, pending);
                            liveFacts.put("Cursor:" + entry.getKey(), new RuntimeFact(pending, System.nanoTime(), read.connection()));
                        }
                        changed |= hadGeneration || removedFact || pending != null;
                    }
                    if (!tracking.pendingHooks.isEmpty()) {
                        // A different turn has arrived before its composerData save. The header
                        // may already describe that turn: do not attach it to the older identity.
                        tracking.unknown = true; tracking.waiting = false; tracking.confirmed = false;
                        tracking.anchored = false; tracking.lastValue = null;
                        changed |= !wasUnknown || wasWaiting;
                        continue;
                    }
                    boolean waiting = state.state() == CursorSessionDiscoveryService.Waiting.WAITING;
                    if (!waiting) { tracking.waiting = false; tracking.confirmed = false; tracking.unknown = false; }
                    else if (tracking.confirmed || (Boolean.FALSE.equals(tracking.lastValue) && tracking.anchored)) {
                        tracking.waiting = true; tracking.confirmed = true; tracking.unknown = false;
                    }
                    // Historical first true never proves activity. An established native wait has no guessed time limit.
                    tracking.lastValue = waiting;
                }
                changed |= wasWaiting != tracking.waiting || wasUnknown != tracking.unknown;
            }
            if (changed) sendCursorSnapshot();
        }
    }

    private void sendCursorSnapshot() {
        publishCursorOverlay();
        snapshotRevision.incrementAndGet();
        snapshotPending = true;
        snapshotConnection = bleManager.connectionGeneration();
    }

    private void publishCursorOverlay() {
        Map<String, String> states = new HashMap<>();
        cursorTracking.forEach((id, tracking) -> {
            if (tracking.unknown) states.put(id, "");
            else if (tracking.waiting) states.put(id, IDEState.NOTIFICATION.name());
        });
        cursorOverlay = new CursorOverlay(cursorConnection, Map.copyOf(states));
    }

    private Delivery cursorHook(String id, IDEState state, JsonNode payload) {
        CursorTracking tracking = cursorTracking.computeIfAbsent(id, key -> new CursorTracking());
        JsonNode identity = payload == null ? null : payload.get("generation_id");
        if (identity == null && payload != null) identity = payload.path("hookInput").get("generation_id");
        String generation = identity != null && identity.isTextual() ? identity.textValue() : "";
        if (!tracking.nativeIdentityContext) {
            if (identity != null && !identity.isNull() && (!identity.isTextual() || generation.isBlank())) return Delivery.IGNORED;
            return cursorHookWithoutNativeIdentity(id, tracking, state, generation);
        }
        if (generation.isBlank() || generation.length() > 128 || cursorProcess.isBlank()
                || tracking.retiredGenerations.contains(generation)) return Delivery.IGNORED;
        if (!generation.equals(tracking.generation)) {
            // UUIDs have no ordering. An unfamiliar Hook cannot replace the native current run.
            // Retain only bounded candidates until the exact native identity independently matches.
            if (isTerminal(state) && !tracking.pendingHooks.containsKey(generation)) return Delivery.IGNORED;
            tracking.hookRevision++;
            if (tracking.pendingHooks.isEmpty())
                tracking.pendingStartedFromFalse = Boolean.FALSE.equals(tracking.lastValue) && !tracking.unknown;
            tracking.pendingHooks.put(generation, state);
            while (tracking.pendingHooks.size() > 8) tracking.pendingHooks.remove(tracking.pendingHooks.keySet().iterator().next());
            return Delivery.PENDING;
        }
        if (tracking.terminal) return Delivery.IGNORED;
        if (!tracking.pendingHooks.isEmpty()) return Delivery.PENDING;
        tracking.hookRevision++;
        acceptCursorHook(tracking, state);
        publishCursorOverlay();
        return Delivery.SENT;
    }

    private Delivery cursorHookWithoutNativeIdentity(String id, CursorTracking tracking, IDEState state, String generation) {
        // Unsupported/missing native metadata disables the waiting overlay, not the existing Hook path.
        // Hook facts may report RUN/DONE, but can never establish a native waiting anchor here.
        if (generation.length() > 128 || tracking.retiredGenerations.contains(generation)) return Delivery.IGNORED;
        RuntimeFact existing = liveFacts.get("Cursor:" + id);
        if (isTerminal(state)) {
            if (!generation.equals(tracking.fallbackGeneration) || tracking.fallbackTerminal
                    || existing == null || !existing.fresh(bleManager.connectionGeneration())
                    || isTerminal(existing.state())) return Delivery.IGNORED;
            tracking.fallbackTerminal = true;
        } else {
            if (generation.isEmpty() && !tracking.fallbackGeneration.isEmpty()) return Delivery.IGNORED;
            if (generation.equals(tracking.fallbackGeneration) && tracking.fallbackTerminal && !generation.isEmpty()) return Delivery.IGNORED;
            if (!generation.equals(tracking.fallbackGeneration) && !tracking.fallbackGeneration.isEmpty())
                tracking.retiredGenerations.add(tracking.fallbackGeneration);
            tracking.fallbackGeneration = generation;
            tracking.fallbackTerminal = false;
        }
        tracking.hookRevision++;
        tracking.unknown = false; tracking.waiting = false; tracking.confirmed = false; tracking.anchored = false;
        if (!generation.isEmpty() && !cursorProcess.isEmpty()) {
            tracking.pendingHooks.put(generation, state);
            while (tracking.pendingHooks.size() > 8) tracking.pendingHooks.remove(tracking.pendingHooks.keySet().iterator().next());
        }
        publishCursorOverlay();
        return Delivery.SENT;
    }

    private boolean isTerminal(IDEState state) {
        return state == IDEState.STOP || state == IDEState.SESSION_END || state == IDEState.TASK_COMPLETED;
    }

    private void acceptCursorHook(CursorTracking tracking, IDEState state) {
        if (isTerminal(state)) {
            tracking.terminal = true;
            tracking.anchored = false; tracking.confirmed = false; tracking.waiting = false;
            tracking.unknown = false; tracking.lastValue = null;
        } else {
            tracking.anchored = !cursorProcess.isBlank() && cursorConnection == bleManager.connectionGeneration();
            if (tracking.anchored && tracking.generationStartedFromFalse && Boolean.TRUE.equals(tracking.lastValue)) {
                tracking.waiting = true; tracking.confirmed = true; tracking.unknown = false;
            }
            tracking.generationStartedFromFalse = false;
            if (tracking.unknown && !tracking.confirmed) { tracking.unknown = false; tracking.lastValue = null; }
        }
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
        synchronized (snapshotSendLock) {
        this.cursorDataDir = cursorDataDir == null || cursorDataDir.isBlank()
            ? AiRuntimeStore.Draft.defaultCursorDataDir()
            : cursorDataDir;
        invalidateCursorContext();
        liveFacts.keySet().removeIf(key -> key.startsWith("Cursor:"));
        // The observer sends EMPTY for the invalidated source on this connection; never leave the old physical yellow.
        if (displayMode.get() == AiRuntimeDisplayMode.MULTI) {
            cursorClearPendingConnection = bleManager.connectionGeneration();
            snapshotRevision.incrementAndGet(); snapshotPending = true;
            snapshotConnection = cursorClearPendingConnection;
        }
        }
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

    public void maintenanceChanged() {
        synchronized (snapshotSendLock) {
            invalidateCursorContext();
            snapshotPending = false; snapshotRevision.incrementAndGet(); liveFacts.clear();
            singleOwner = null; singleOwnerConnection = -1; singleRevision.incrementAndGet();
        }
    }
    public void onDeviceReady() {
        if (!bleManager.maintenance().normalAllowed()) return;
        if (!isDeviceSupported()) {
            return;
        }
        long connection = bleManager.connectionGeneration();
        AiRuntimeDisplayMode preference = displayMode.get();
        long maintenanceEpoch = bleManager.maintenance().epoch();
        new Thread(() -> {
            try {
                if (maintenanceEpoch != bleManager.maintenance().epoch() || !bleManager.maintenance().normalAllowed()) return;
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
        synchronized (snapshotSendLock) {
        invalidateCursorContext();
        appliedSlots = Arrays.stream(plan.slots()).map(this::copy).toArray(AiRuntimeSlotBinding[]::new);
        }
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
        synchronized (snapshotSendLock) {
        invalidateCursorContext();
        appliedSlots = Arrays.stream(plan.slots()).map(this::copy).toArray(AiRuntimeSlotBinding[]::new);
        snapshotRevision.incrementAndGet();
        }
        if (displayMode.get() == AiRuntimeDisplayMode.MULTI) sendAppliedSnapshot();
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
        long eventConnection = bleManager.connectionGeneration(), eventCursorEpoch = cursorEpoch;
        if (!bleManager.maintenance().normalAllowed()) return Delivery.IGNORED;
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
        boolean sendMulti = false, sendSingle = false;
        long eventSingleRevision = -1;
        String matchedId = "";
        synchronized (snapshotSendLock) {
            if (eventConnection != bleManager.connectionGeneration()
                    || ("Cursor".equals(platform) && eventCursorEpoch != cursorEpoch)) return Delivery.IGNORED;
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
                    sendSingle = true;
                    eventSingleRevision = singleRevision.incrementAndGet();
                    result = Delivery.PENDING;
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
                    Delivery accepted = "Cursor".equals(platform) ? cursorHook(matchedId, state, payload) : Delivery.SENT;
                    if (accepted != Delivery.SENT) result = accepted;
                    else {
                    liveFacts.put(slot.getProvider() + ":" + slot.getStableId(),
                            new RuntimeFact(state, System.nanoTime(), bleManager.connectionGeneration()));
                    slot.setLastIdeState(state.name());
                    AiRuntimeSlotBinding draft = slots.get(matched);
                    if (Objects.equals(draft.getStableId(), slot.getStableId()) && Objects.equals(draft.getProvider(), slot.getProvider()))
                        draft.setLastIdeState(state.name());
                    snapshotRevision.incrementAndGet();
                    snapshotPending = true;
                    snapshotConnection = eventConnection;
                    sendMulti = true;
                    result = Delivery.PENDING;
                    }
                }
            }
        }
        // Sending (including isDisplayBusy's device lock) runs after releasing the state lock.
        try {
            if (sendMulti) result = sendAppliedSnapshot(eventConnection) ? Delivery.SENT : Delivery.PENDING;
            else if (sendSingle) synchronized (singleSendLock) {
                if (eventSingleRevision != singleRevision.get() || eventConnection != bleManager.connectionGeneration()
                        || displayMode.get() != AiRuntimeDisplayMode.SINGLE) result = Delivery.IGNORED;
                else result = bleManager.sendRuntimeState((byte) state.getCode()) ? Delivery.SENT
                        : bleManager.isConnected() ? Delivery.PENDING : Delivery.FAILED;
            }
        } catch (Exception e) { result = Delivery.FAILED; }
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
        CursorOverlay overlay = cursorOverlay;
        if (!cursorClosed && displayMode.get() == AiRuntimeDisplayMode.MULTI && "Cursor".equals(slot.getProvider())
                && overlay.connection() == bleManager.connectionGeneration()) {
            String override = overlay.states().get(slot.getStableId());
            if (override != null) slot.setLastIdeState(override);
        }
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
            if (cursorClosed || connection != bleManager.connectionGeneration()
                    || displayMode.get() != AiRuntimeDisplayMode.MULTI
                    || !bleManager.maintenance().normalAllowed()) return false;
            snapshotPending = true;
            snapshotConnection = connection;
            if (snapshotSending) return false;
            snapshotSending = true;
        }
        boolean sent = false;
        boolean ownsSender = true;
        try {
            while (true) {
                // Both this check and the send below can wait for the device command lock.
                // Concurrent Hooks only update intent and return PENDING while this sender owns I/O.
                if (bleManager.isDisplayBusy() || bleManager.isDisplayWriteUncertain()) return sent;
                AiRuntimeSlotBinding[] snapshot;
                long revision, epoch, maintenance;
                synchronized (snapshotSendLock) {
                    if (cursorClosed || !snapshotPending || snapshotConnection != connection
                            || connection != bleManager.connectionGeneration()
                            || displayMode.get() != AiRuntimeDisplayMode.MULTI
                            || !bleManager.maintenance().normalAllowed()) return sent;
                    if (Arrays.stream(appliedSlots).noneMatch(slot -> slot != null && slot.isBound())) {
                        snapshotPending = false;
                        return sent;
                    }
                    revision = snapshotRevision.get(); epoch = cursorEpoch;
                    maintenance = bleManager.maintenance().epoch();
                    snapshot = Arrays.stream(appliedSlots).map(this::copy).toArray(AiRuntimeSlotBinding[]::new);
                    for (AiRuntimeSlotBinding slot : snapshot) applyLiveFact(slot);
                }
                boolean delivered = bleManager.sendMultiRuntimeSnapshot(snapshot, connection,
                        () -> !cursorClosed && connection == bleManager.connectionGeneration()
                                && epoch == cursorEpoch && revision == snapshotRevision.get()
                                && maintenance == bleManager.maintenance().epoch()
                                && bleManager.maintenance().normalAllowed());
                sent |= delivered;
                synchronized (snapshotSendLock) {
                    if (cursorClosed || connection != bleManager.connectionGeneration()
                            || displayMode.get() != AiRuntimeDisplayMode.MULTI
                            || !bleManager.maintenance().normalAllowed()
                            || maintenance != bleManager.maintenance().epoch()) return sent;
                    if (delivered && epoch == cursorEpoch && revision == snapshotRevision.get()) {
                        snapshotPending = false;
                        // Release ownership atomically with observing no new intent: no lost wake-up.
                        snapshotSending = false; ownsSender = false;
                        return true;
                    }
                    // An in-flight frame cannot be recalled. Rebuild from current bindings and facts
                    // after ACK, never replay the captured snapshot across an invalidation boundary.
                    if (!snapshotPending || snapshotConnection != connection) return sent;
                }
            }
        } finally {
            if (ownsSender) synchronized (snapshotSendLock) { snapshotSending = false; }
            scheduleSnapshotRetry();
        }
    }

    private void scheduleSnapshotRetry() {
        // A device-idle callback may race the sender's release. A bounded retry avoids losing
        // the final intent, including on connection changes while the previous ACK is pending.
        synchronized (cursorLifecycleLock) {
            if (cursorClosed || !snapshotPending || snapshotRetryQueued
                    || displayMode.get() != AiRuntimeDisplayMode.MULTI
                    || snapshotConnection != bleManager.connectionGeneration()
                    || !bleManager.maintenance().normalAllowed()) return;
            if (snapshotRetry == null) snapshotRetry = java.util.concurrent.Executors.newSingleThreadScheduledExecutor(r -> {
                Thread thread = new Thread(r, "runtime-snapshot-retry"); thread.setDaemon(true); return thread;
            });
            snapshotRetryQueued = true;
            snapshotRetry.schedule(() -> {
                synchronized (cursorLifecycleLock) { snapshotRetryQueued = false; }
                if (!cursorClosed && snapshotPending) {
                    try { sendAppliedSnapshot(snapshotConnection); }
                    catch (Exception e) { logger.debug("Runtime snapshot remains pending"); }
                }
            }, 250, java.util.concurrent.TimeUnit.MILLISECONDS);
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
