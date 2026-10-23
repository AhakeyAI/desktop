package com.example.ahakey.service;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.util.OLEDFrameEncoder;
import javafx.application.Platform;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

public final class DisplayConfigService implements AutoCloseable {
    private static final org.slf4j.Logger logger = org.slf4j.LoggerFactory.getLogger(DisplayConfigService.class);
    private final StudioState studio;
    private final DisplayConfigState state;
    private final BleManager ble;
    private final OledResourceStore store;
    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "display-config"); thread.setDaemon(true); return thread;
    });
    private volatile long loadGeneration;
    private long operationGeneration;
    private long observedConnection = -1;
    private boolean wasConnected;
    private boolean closed;
    private Consumer<String> errorHandler = message -> {};

    public DisplayConfigService(StudioState studio, BleManager ble) {
        this(studio, ble, new OledResourceStore());
    }
    public DisplayConfigService(StudioState studio, BleManager ble, OledResourceStore store) {
        this.studio = studio;
        this.state = studio.displayConfig();
        this.ble = ble;
        this.store = Objects.requireNonNull(store);
        state.select(studio.getSelectedMode().getIndex(), 0, 0);
        Map<Integer, String> legacy = new HashMap<>();
        for (ModeSlot mode : ModeSlot.values()) legacy.put(mode.getIndex() * 4, studio.getOledDraft(mode).getLocalAssetPath());
        worker.execute(() -> {
            try {
                Map<Integer, OledResourceState> loaded = store.load();
                List<String> warnings = new ArrayList<>();
                for (var item : legacy.entrySet()) {
                    if (item.getValue() == null || item.getValue().isBlank() || store.containsEntry(item.getKey())) continue;
                    try {
                        Path path = Path.of(item.getValue());
                        if (!Files.isRegularFile(path)) continue;
                        var asset = OledResourceState.Asset.fromBytes(OLEDFrameEncoder.paddedStream(OLEDFrameEncoder.importFile(path, 8)));
                        var migrated = loaded.get(item.getKey()).replace(asset);
                        store.save(migrated); loaded.put(item.getKey(), migrated);
                    } catch (Exception e) { warnings.add("旧 OLED 草稿迁移失败：" + reason(e)); }
                }
                fx(() -> {
                    loaded.values().forEach(state::put); state.ready.set(true);
                    if (!warnings.isEmpty()) errorHandler.accept(String.join("\n", warnings));
                    refresh();
                });
            } catch (Exception e) { fx(() -> error("本地资源库读取失败：" + reason(e))); }
        });
        studio.selectedModeProperty().addListener((o, a, b) -> {
            state.select(b.getIndex(), state.group.get(), state.substate.get()); refresh();
        });
        studio.selectedPartProperty().addListener((o, a, b) -> refresh());
        studio.modeSwitchingProperty().addListener((o, a, b) -> { updateWriteReady(); refresh(); });
    }
    public void setErrorHandler(Consumer<String> handler) { errorHandler = handler; }
    public DisplayConfigState state() { return state; }

    public void connectionChanged() {
        long generation = ble.connectionGeneration();
        boolean connected = ble.isConnected() && ble.getCachedStatus().isConnected();
        if (generation != observedConnection || connected != wasConnected) {
            if (observedConnection >= 0) state.message.set("键盘连接已改变，本地草稿已保留。");
            observedConnection = generation; wasConnected = connected; loadGeneration++;
            state.loading.set(false);
            state.resources.replaceAll((entry, resource) -> resource.unknown());
            state.endPreview(); state.changed();
            if (connected) refresh();
        }
        updateWriteReady();
    }
    public void confirmFirmware(long connection, String sha) {
        ble.confirmDisplayFirmware(connection, sha);
        updateWriteReady(); refresh();
    }
    private void updateWriteReady() {
        state.writeReady.set(ble.isDisplayAdmitted() && !ble.isDisplayWriteUncertain()
                && !state.busy.get() && !studio.modeSwitchingProperty().get());
    }

    public void select(int group, int substate) { state.select(studio.getSelectedMode().getIndex(), group, substate); }
    public void importFile(Path path, int entry) {
        if (!state.ready.get() || state.busy.get()) return;
        OledResourceState previous = state.resources.get(entry);
        state.message.set("处理中...");
        work(operation -> {
            var asset = OledResourceState.Asset.fromBytes(OLEDFrameEncoder.paddedStream(OLEDFrameEncoder.importFile(path, previous.capacity())));
            var next = previous.replace(asset);
            store.save(next);
            fx(() -> { state.put(next); state.message.set("草稿已保存。"); });
        });
    }
    public void clear(OledResourceState frozen) {
        if (!state.ready.get() || state.busy.get()) return;
        var current = state.resources.get(frozen.entry());
        if (current.asset() != frozen.asset()) { error("本地资源已变化，请重新确认清除目标。"); return; }
        OledResourceState next = current.clear();
        work(operation -> {
            try { store.save(next); }
            catch (OledResourceStore.CleanupFailure e) {
                fx(() -> { state.put(next); error(reason(e)); }); return;
            }
            fx(() -> { state.put(next); state.message.set("已清除本地资源。"); });
        });
    }

    public void upload(OledResourceState frozen) {
        if (state.busy.get() || !state.writeReady.get() || !frozen.canUpload() || state.current() != frozen) return;
        long connection = ble.connectionGeneration();
        studio.uploadingOledProperty().set(true);
        state.message.set("上传中...");
        work(true, operation -> {
            OledResourceState result;
            try {
                store.save(frozen.uploading());
                fx(() -> state.put(frozen.uploading()));
                OledUploadService.uploadResource(ble, connection, frozen.entry(), frozen.asset(),
                        percent -> {}, () -> store.save(frozen.committing()),
                        progress -> deviceFx(operation, () -> state.progress.set(progress.text())));
                result = frozen.applied();
            } catch (OledUploadService.UploadFailure e) {
                result = frozen.failed(reason(e), e.commitUncertain());
            } catch (Exception e) {
                result = frozen.failed(reason(e), false);
            }
            OledResourceState finalResult = result;
            try { store.save(result); }
            catch (IOException e) {
                fx(() -> error("设备操作结果已保留在当前界面，但本地记录保存失败：" + reason(e)));
            }
            fx(() -> {
                state.put(connection == ble.connectionGeneration() && wasConnected ? finalResult : finalResult.unknown());
                state.message.set(finalResult.localStatus() == OledResourceState.LocalStatus.APPLIED
                        ? "已应用到 " + finalResult.targetName() + "。" : finalResult.notice());
            });
        });
    }

    public void refresh() {
        long ticket = ++loadGeneration;
        state.loading.set(false);
        StudioPart part = studio.getSelectedPart();
        if (state.busy.get() || studio.modeSwitchingProperty().get() || !wasConnected || (part != StudioPart.OLED && part != StudioPart.LIGHT_BAR)) return;
        if (part == StudioPart.OLED && !state.ready.get()) return;
        int mode = studio.getSelectedMode().getIndex();
        long connection = ble.connectionGeneration();
        Map<Integer, OledResourceState> captured = new HashMap<>(state.resources);
        state.loading.set(true);
        worker.execute(() -> {
            try {
                ble.readDisplayConfig(connection, lease -> {
                if (ticket != loadGeneration) return;
                if (part == StudioPart.OLED) {
                    Map<Integer, OledResourceState> updates = new LinkedHashMap<>();
                    int[] targets = {mode * 4, mode * 4 + 1, mode * 4 + 2, mode * 4 + 3, 16, 17, 18};
                    for (int entry : targets) {
                        if (ticket != loadGeneration) return;
                        var basic = read(lease, 2, entry);
                        var integrity = read(lease, 3, entry);
                        var metadata = new OledResourceState.Metadata(basic.value() == 1, basic.writeState(), integrity.frames(), integrity.bytes(), integrity.crc());
                        updates.put(entry, captured.get(entry).merge(metadata));
                    }
                    if (ticket != loadGeneration || connection != ble.connectionGeneration()) return;
                    for (var resource : updates.values()) store.save(resource);
                    fx(() -> {
                        if (ticket != loadGeneration || connection != ble.connectionGeneration()) return;
                        updates.values().forEach(state::put);
                        state.message.set(updates.values().stream().map(OledResourceState::notice).filter(s -> !s.isBlank()).findFirst().orElse("已同步资源元数据。"));
                    });
                } else {
                    int brightness = read(lease, 0).value();
                    int[] effects = new int[9];
                    for (int ai = 0; ai < 9; ai++) {
                        if (ticket != loadGeneration) return;
                        effects[ai] = read(lease, 1, mode, ai).value();
                    }
                    fx(() -> {
                        if (ticket != loadGeneration || connection != ble.connectionGeneration()) return;
                        state.readBrightness(brightness);
                        for (int ai = 0; ai < 9; ai++) state.readEffect(mode, ai, effects[ai]);
                        state.message.set("已同步灯光配置。");
                    });
                }
                });
            } catch (Exception e) {
                fx(() -> { if (ticket == loadGeneration) { state.message.set("同步失败：" + reason(e)); state.resources.replaceAll((i, r) -> r.unknown()); state.changed(); } });
            } finally { fx(() -> { if (ticket == loadGeneration) state.loading.set(false); updateWriteReady(); }); }
        });
    }
    private AhaKeyResponseParser.DisplayRead read(BleManager.DisplayLease lease, int kind, int... selectors) throws Exception {
        byte[] reply = ble.exchangeDisplay(lease, AhaKeyProtocol.displayRead(kind, selectors));
        if (reply.length == 6 && reply[3] == 1) throw new OledUploadService.DeviceRejected();
        var parsed = AhaKeyResponseParser.parseDisplayRead(reply, kind, selectors);
        if (parsed == null) {
            ble.invalidateDisplayRead(lease);
            throw new IOException("显示配置响应目标或内容不匹配，请重新连接后同步。");
        }
        return parsed;
    }
    public void preview(Integer effect) {
        if (!state.writeReady.get() || state.busy.get() || (effect != null && (effect < 1 || effect > 16))) return;
        int brightness = state.brightness.get();
        long connection = ble.connectionGeneration();
        work(true, operation -> {
            try (BleManager.DisplayLease lease = ble.openDisplayLease(true, connection)) {
                OledUploadService.requireAck(ble.exchangeDisplay(lease, effect == null ? AhaKeyProtocol.previewBrightness(brightness)
                        : AhaKeyProtocol.previewLight(effect, brightness)), AhaKeyProtocol.CMD_DISPLAY_PREVIEW);
                long acceptedAt = System.nanoTime();
                deviceFx(operation, () -> {
                    if (System.nanoTime() - acceptedAt >= 10_000_000_000L) return;
                    state.previewAccepted(effect == null ? 1 : effect, brightness, acceptedAt);
                    state.message.set("设备预览中（10 秒）。");
                });
            }
        });
    }
    public void saveBrightness() {
        if (!state.writeReady.get() || state.busy.get()) return;
        int brightness = state.brightness.get();
        long edit = state.brightnessRevision();
        long connection = ble.connectionGeneration();
        work(true, operation -> {
            try (BleManager.DisplayLease lease = ble.openDisplayLease(true, connection)) {
                OledUploadService.requireAck(ble.exchangeDisplay(lease, AhaKeyProtocol.saveDisplayBrightness(brightness)), AhaKeyProtocol.CMD_DISPLAY_SAVE);
                logger.info("Brightness ACK: connection={}, operation={}, value={}", connection, operation.id(), brightness);
                deviceFx(operation, () -> { state.savedBrightness(brightness, edit); state.message.set("已保存全局亮度。"); });
            }
        });
    }
    public void saveModeLights() {
        if (!state.writeReady.get() || state.busy.get()) return;
        int mode = studio.getSelectedMode().getIndex();
        int[] effects = new int[9];
        long[] edits = new long[9];
        for (int ai = 0; ai < 9; ai++) {
            effects[ai] = state.effect(mode, ai);
            edits[ai] = state.effectRevision(mode, ai);
            if (effects[ai] < 0 || effects[ai] > 16) { error("存在未知灯效，请为该状态选择有效灯效后保存。"); return; }
        }
        long connection = ble.connectionGeneration();
        work(true, operation -> {
            int saved = 0;
            try (BleManager.DisplayLease lease = ble.openDisplayLease(true, connection)) {
                for (int ai = 0; ai < 9; ai++) {
                    OledUploadService.requireAck(ble.exchangeDisplay(lease, AhaKeyProtocol.saveDisplayLight(mode, ai, effects[ai])), AhaKeyProtocol.CMD_DISPLAY_SAVE);
                    int key = ai;
                    saved++;
                    logger.info("Light ACK: connection={}, operation={}, mode={}, ai={}, confirmed={}/9", connection, operation.id(), mode, key, saved);
                    deviceFx(operation, () -> state.savedEffect(mode, key, effects[key], edits[key]));
                }
                deviceFx(operation, () -> state.message.set("已保存 Mode " + (mode + 1) + " 的 9 项灯效。"));
            } catch (Exception e) { throw new IOException("已确认保存 " + saved + " / 9 项；第 " + (saved + 1) + " 项未确认，其余草稿保留。" + reason(e), e); }
        });
    }
    private record Operation(long id, long connection, boolean device) {}
    private interface Work { void run(Operation operation) throws Exception; }
    private void work(Work work) {
        work(false, work);
    }
    private boolean current(Operation operation) {
        return operation.id() == operationGeneration && operation.connection() == ble.connectionGeneration()
                && wasConnected && ble.isConnected() && ble.getCachedStatus().isConnected();
    }
    private void deviceFx(Operation operation, Runnable action) {
        fx(() -> { if (current(operation)) action.run(); });
    }
    private void work(boolean device, Work work) {
        Operation operation = new Operation(++operationGeneration, ble.connectionGeneration(), device);
        loadGeneration++; state.loading.set(false); state.busy.set(true); state.progress.set(""); updateWriteReady();
        worker.execute(() -> {
            try { work.run(operation); }
            catch (Exception e) {
                logger.warn("Display operation ended: connection={}, operation={}, reason={}", operation.connection(), operation.id(), reason(e));
                fx(() -> {
                    if (operation.device() && !current(operation)) return;
                    if (ble.isDisplayWriteUncertain()) state.endPreview(); error(reason(e));
                });
            }
            finally { fx(() -> {
                if (operation.id() != operationGeneration) return;
                boolean wasUpload = studio.uploadingOledProperty().get();
                state.busy.set(false); studio.uploadingOledProperty().set(false); updateWriteReady();
                if (wasUpload && state.current().localStatus() != OledResourceState.LocalStatus.APPLIED) refresh();
            }); }
        });
    }
    private void error(String message) { state.message.set(message); errorHandler.accept(message); }
    private static String reason(Exception e) { return e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage(); }
    private void fx(Runnable runnable) { Platform.runLater(() -> { if (!closed) runnable.run(); }); }
    @Override public void close() { closed = true; loadGeneration++; worker.shutdownNow(); }
}
