package com.example.ahakey.displayconfig;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.*;
import com.example.ahakey.util.AiRuntimeStore;
import com.fasterxml.jackson.databind.ObjectMapper;
import javafx.application.Platform;

import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.BooleanSupplier;

/** Controlled ACK/FX ordering, memory-only USB substitute. Never constructs App/StudioController. */
public final class DisplayConfigRaceChecks {
    private static final String HEX = "D7D10510482228B74A2978BD8272F6A4E32668CF6B4F31F491A8503B0DC11E2E";
    private static final String CATALOG = "x1-c582-hw1-p1-1.0.0-r001";
    private static int checks;
    private static Path root;

    public static void main(String[] args) throws Exception {
        root = Files.createTempDirectory("wd005-races-");
        // AiRuntimeStore captures user.home at class initialization; no real user preference is read/written.
        String home = System.getProperty("user.home");
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME))
                .setLevel(ch.qos.logback.classic.Level.WARN);
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(BleManager.class)).setLevel(ch.qos.logback.classic.Level.WARN);
        Platform.startup(() -> {});
        System.setProperty("user.home", root.toString());
        Throwable originalFailure = null;
        try {
            identityOrdering(true);
            identityOrdering(false);
            modeOrdering();
            cp1Admission();
            pendingGeneration();
            staleFx("brightness", false);
            staleFx("lights", false);
            staleFx("preview", false);
            staleFx("brightness", true);
            staleFx("lights", true);
            staleFx("preview", true);
            sameValueEdit();
            System.out.println("PASS " + checks + " controlled race checks; no full application or hardware claim");
        } catch (Exception | Error e) {
            originalFailure = e;
            throw e;
        } finally {
            Platform.exit();
            System.setProperty("user.home", home);
            try (var paths = Files.walk(root)) {
                for (Path p : paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(p);
            } catch (Exception cleanup) {
                if (originalFailure != null) originalFailure.addSuppressed(cleanup);
                else throw cleanup;
            }
        }
    }

    private static void identityOrdering(boolean readFirst) throws Exception {
        try (Fixture f = new Fixture()) {
            CountDownLatch held = new CountDownLatch(1);
            AtomicReference<byte[]> delayed = new AtomicReference<>();
            int delayedOpcode = readFirst ? 0x88 : 0x9F;
            f.wire.respond = request -> {
                f.requests.add(request.clone());
                if ((request[2] & 255) == delayedOpcode && delayed.compareAndSet(null, request.clone())) held.countDown();
                else f.answer(request);
            };
            FutureTask<String> identity = new FutureTask<>(() -> {
                String catalog = f.wire.ble.readFirmwareCatalogKey();
                f.wire.ble.readSideSwitchConfig();
                for (int mode = 0; mode < 4; mode++) for (int key = 0; key < 4; key++) f.wire.ble.readOrdinaryKeyConfig(mode, key);
                return catalog;
            });
            if (readFirst) {
                fx(() -> f.studio.setSelectedPart(StudioPart.OLED));
                latch(held); start(identity);
            } else {
                start(identity); latch(held);
                fx(() -> f.studio.setSelectedPart(StudioPart.OLED));
            }
            f.answer(delayed.get());
            check("F1-identity-" + readFirst, CATALOG.equals(identity.get(10, TimeUnit.SECONDS)));
            awaitFx(() -> !f.studio.displayConfig().loading.get());
            check("F1-input-flow-" + readFirst, f.count(0x97) == 1 && f.count(0x87) == 16);
            check("F1-metadata-not-dropped-" + readFirst, f.count(0x88) == 14);
        }
    }

    private static void modeOrdering() throws Exception {
        try (Fixture f = new Fixture()) {
            CountDownLatch held = new CountDownLatch(1);
            AtomicReference<byte[]> delayed = new AtomicReference<>();
            f.wire.respond = request -> {
                f.requests.add(request.clone());
                if (request[2] == (byte)0x88 && delayed.compareAndSet(null, request.clone())) held.countDown();
                else f.answer(request);
            };
            fx(() -> f.studio.setSelectedPart(StudioPart.OLED)); latch(held);
            fx(() -> { f.studio.modeSwitchingProperty().set(true); f.studio.setSelectedMode(ModeSlot.MODE1); });
            FutureTask<Integer> change = new FutureTask<>(() -> f.wire.ble.setWorkModeAndVerify(1));
            start(change); f.answer(delayed.get());
            check("F1-mode-confirmed-after-read", change.get(10, TimeUnit.SECONDS) == 1);
            fx(() -> f.studio.modeSwitchingProperty().set(false));
            awaitFx(() -> !f.studio.displayConfig().loading.get());
            check("F1-mode-no-local-rollback", f.studio.getSelectedMode() == ModeSlot.MODE1);
            check("F1-mode-92-and-status", f.count(0x92) == 1 && f.count(0x00) >= 1);
            check("F1-cancel-old-read-and-refresh-current", f.count(0x88) == 16);
        }
    }

    private static void cp1Admission() throws Exception {
        try (Fixture f = new Fixture()) {
            AiRuntimeDisplayService[] runtime = new AiRuntimeDisplayService[1];
            fx(() -> { runtime[0] = new AiRuntimeDisplayService(f.wire.ble); runtime[0].displayModeProperty().set(AiRuntimeDisplayMode.SINGLE); });
            for (boolean writing : new boolean[]{false, true}) {
                for (AiRuntimeDisplayMode current : AiRuntimeDisplayMode.values()) {
                    fx(() -> runtime[0].displayModeProperty().set(current));
                    AiRuntimeDisplayMode next = current == AiRuntimeDisplayMode.SINGLE ? AiRuntimeDisplayMode.MULTI : AiRuntimeDisplayMode.SINGLE;
                    String before = AiRuntimeStore.loadOrDefault().displayMode;
                    AtomicReference<String> error = new AtomicReference<>();
                    try (var lease = f.wire.ble.openDisplayLease(writing)) {
                        fx(() -> runtime[0].setDisplayMode(next, error::set));
                        check("F2-reject-" + writing + "-" + current, error.get() != null && runtime[0].getDisplayMode() == current);
                        check("F2-no-persist-" + writing + "-" + current, before.equals(AiRuntimeStore.loadOrDefault().displayMode));
                    }
                }
            }
            check("F2-conflicts-send-no-98", f.count(0x98) == 0);
            fx(() -> runtime[0].displayModeProperty().set(AiRuntimeDisplayMode.SINGLE));
            CountDownLatch held = new CountDownLatch(1);
            f.wire.respond = request -> { f.requests.add(request.clone()); held.countDown(); };
            AtomicReference<String> outcome = new AtomicReference<>("pending");
            fx(() -> runtime[0].setDisplayMode(AiRuntimeDisplayMode.MULTI, outcome::set)); latch(held);
            fx(() -> check("F2-no-local-success-before-ACK", runtime[0].getDisplayMode() == AiRuntimeDisplayMode.SINGLE && runtime[0].modeChangePendingProperty().get()));
            f.wire.reply(AhaKeyProtocol.buildFrame((byte)0x98, new byte[]{0}));
            awaitFx(() -> !runtime[0].modeChangePendingProperty().get());
            check("F2-confirmed-mode-persisted", outcome.get() == null && runtime[0].getDisplayMode() == AiRuntimeDisplayMode.MULTI && AiRuntimeStore.loadOrDefault().displayMode.equals("MULTI"));
            f.wire.respond = request -> { f.requests.add(request.clone()); f.wire.reply(AhaKeyProtocol.buildFrame(request[2], new byte[]{1})); };
            fx(() -> runtime[0].setDisplayMode(AiRuntimeDisplayMode.SINGLE, outcome::set));
            awaitFx(() -> !runtime[0].modeChangePendingProperty().get());
            check("F2-device-FAIL-keeps-mode", outcome.get() != null && runtime[0].getDisplayMode() == AiRuntimeDisplayMode.MULTI);
            f.normalReplies();
            fx(() -> runtime[0].setDisplayMode(AiRuntimeDisplayMode.SINGLE, outcome::set));
            awaitFx(() -> !runtime[0].modeChangePendingProperty().get());
            check("F2-reverse-success", outcome.get() == null && runtime[0].getDisplayMode() == AiRuntimeDisplayMode.SINGLE);
        }
    }

    private static void pendingGeneration() throws Exception {
        try (Fixture f = new Fixture()) {
            try (var lease = f.wire.ble.openDisplayLease(false)) {
                f.wire.ble.sendRuntimeState((byte)1); f.wire.ble.sendRuntimeState((byte)6);
            }
            check("R1-SINGLE-latest-once", f.count(0x90) == 1 && f.requests.stream().filter(r -> r[2] == (byte)0x90).findFirst().orElseThrow()[3] == 6);
            f.requests.clear();
            try (var old = f.wire.ble.openDisplayLease(false)) {
                f.wire.ble.sendRuntimeState((byte)3); f.reset();
            }
            try (var current = f.wire.ble.openDisplayLease(false)) { }
            check("R1-SINGLE-old-connection-not-replayed", f.count(0x90) == 0);

            AiRuntimeDisplayService[] runtime = new AiRuntimeDisplayService[1];
            fx(() -> { runtime[0] = new AiRuntimeDisplayService(f.wire.ble); runtime[0].displayModeProperty().set(AiRuntimeDisplayMode.MULTI); });
            AiRuntimeSlotBinding slot = new AiRuntimeSlotBinding(0);
            slot.setProvider("Codex"); slot.setStableId("race-session");
            AiRuntimeSlotBinding[] applied = {slot, new AiRuntimeSlotBinding(1), new AiRuntimeSlotBinding(2), new AiRuntimeSlotBinding(3)};
            field(runtime[0], "appliedSlots", applied);
            var payload = new ObjectMapper().createObjectNode().put("session_id", "race-session");
            try (var lease = f.wire.ble.openDisplayLease(false)) {
                runtime[0].handleHookEvent("Codex", IDEState.PRE_TOOL_USE, payload);
                runtime[0].handleHookEvent("Codex", IDEState.TASK_COMPLETED, payload);
            }
            check("R1-MULTI-latest-once", f.count(0x99) == 1);
            byte[] expected = AhaKeyProtocol.multiRuntimeSnapshot(applied);
            check("R1-MULTI-latest-content", Arrays.equals(expected, f.requests.stream().filter(r -> r[2] == (byte)0x99).findFirst().orElseThrow()));
            f.requests.clear();
            try (var old = f.wire.ble.openDisplayLease(false)) {
                runtime[0].handleHookEvent("Codex", IDEState.PERMISSION_REQUEST, payload); f.reset();
            }
            try (var current = f.wire.ble.openDisplayLease(false)) { }
            check("R1-MULTI-old-connection-not-replayed", f.count(0x99) == 0);
            runtime[0].onDeviceReady();
            await(() -> f.count(0x98) == 1);
            synchronized (field(f.wire.ble, "commandTransactionLock")) { /* Wait for the connect ACK to complete. */ }
            check("R1-reconnect-mode-sync-retained", f.count(0x98) == 1 && f.count(0x99) == 0);
            try (var current = f.wire.ble.openDisplayLease(false)) {
                runtime[0].handleHookEvent("Codex", IDEState.TASK_COMPLETED, payload);
            }
            check("R1-new-connection-new-fact-delivered", f.count(0x99) == 1);
        }
    }

    private static void staleFx(String kind, boolean reconnect) throws Exception {
        try (Fixture f = new Fixture()) {
            CountDownLatch blocked = new CountDownLatch(1), release = new CountDownLatch(1);
            AtomicReference<Throwable> failure = new AtomicReference<>();
            Platform.runLater(() -> {
                try {
                    f.studio.displayConfig().editBrightness(67);
                    for (int i = 0; i < 9; i++) f.studio.displayConfig().editEffect(0, i, 2);
                    switch (kind) {
                        case "brightness" -> f.service.saveBrightness();
                        case "lights" -> f.service.saveModeLights();
                        case "preview" -> f.service.preview(null);
                        default -> throw new AssertionError(kind);
                    }
                    blocked.countDown(); latch(release);
                    f.reset();
                    if (!reconnect) { f.wire.field("isConnected", false); f.wire.ble.getCachedStatus().setConnected(false); }
                    f.service.connectionChanged();
                    f.studio.displayConfig().message.set("new-context");
                } catch (Throwable e) { failure.set(e); }
            });
            latch(blocked);
            // This barrier runs after ACK handling and after every success/finally callback is queued.
            ExecutorService worker = (ExecutorService)field(f.service, "worker");
            try { worker.submit(() -> {}).get(10, TimeUnit.SECONDS); }
            finally { release.countDown(); }
            fx(() -> {});
            if (failure.get() != null) throw new AssertionError(failure.get());
            fx(() -> {
                check("F3-" + kind + "-" + reconnect + "-brightness-draft", f.studio.displayConfig().brightnessDirty());
                check("F3-" + kind + "-" + reconnect + "-light-drafts", java.util.stream.IntStream.range(0,9).allMatch(i -> f.studio.displayConfig().effectDirty(0,i)));
                check("F3-" + kind + "-" + reconnect + "-no-preview", !f.studio.displayConfig().devicePreview.get());
                check("F3-" + kind + "-" + reconnect + "-no-success-message", f.studio.displayConfig().message.get().equals("new-context"));
                check("F3-" + kind + "-" + reconnect + "-operation-complete", !f.studio.displayConfig().busy.get());
            });
            check("F3-" + kind + "-" + reconnect + "-actual-ACKs-not-erased", f.count(kind.equals("preview") ? 0x89 : 0x8E) == (kind.equals("lights") ? 9 : 1));
            if (reconnect) {
                fx(() -> f.studio.setSelectedPart(StudioPart.LIGHT_BAR));
                awaitFx(() -> !f.studio.displayConfig().loading.get());
                fx(() -> check("F3-" + kind + "-new-device-read-preserves-intent",
                        f.studio.displayConfig().brightness.get() == 67 && f.studio.displayConfig().effect(0,0) == 2));
            }
        }
    }

    private static void sameValueEdit() throws Exception {
        fx(() -> {
            var state = new DisplayConfigState();
            state.editBrightness(60); long revision = state.brightnessRevision();
            state.editBrightness(60); state.savedBrightness(60, revision);
            check("F3-same-value-new-brightness-intent", state.brightnessDirty());
            state.editEffect(0, 0, 2); long edit = state.effectRevision(0, 0);
            state.editEffect(0, 0, 2); state.savedEffect(0, 0, 2, edit);
            check("F3-same-value-new-effect-intent", state.effectDirty(0, 0));
            long acknowledged = System.nanoTime() - TimeUnit.SECONDS.toNanos(4);
            state.previewAccepted(1, 60, acknowledged);
            check("F3-preview-deadline-starts-at-ACK", state.previewUntilNanos.get() == acknowledged + TimeUnit.SECONDS.toNanos(10));
        });
    }

    private static final class Fixture implements AutoCloseable {
        final DisplayConfigChecks.FakeSession wire = new DisplayConfigChecks.FakeSession();
        final List<byte[]> requests = new CopyOnWriteArrayList<>();
        StudioState studio;
        DisplayConfigService service;
        int deviceMode;
        Fixture() throws Exception {
            wire.useUsb();
            wire.ble.getCachedStatus().setFirmwareCatalogKey(CATALOG);
            normalReplies();
            Path library = Files.createTempDirectory(root, "library-");
            fx(() -> {
                studio = new StudioState(); studio.setSelectedPart(StudioPart.KEY1);
                service = new DisplayConfigService(studio, wire.ble, new OledResourceStore(library)); service.connectionChanged();
            });
            awaitFx(() -> studio.displayConfig().ready.get());
        }
        void normalReplies() { wire.respond = request -> { requests.add(request.clone()); answer(request); }; }
        int count(int opcode) { return (int)requests.stream().filter(r -> (r[2] & 255) == opcode).count(); }
        void answer(byte[] r) {
            byte[] payload;
            switch (r[2] & 255) {
                case 0x88 -> payload = switch(r[3]) {
                    case 0 -> new byte[]{0,0,35};
                    case 1 -> new byte[]{0,1,r[4],r[5],6};
                    case 2 -> new byte[]{0,2,r[4],0,0};
                    case 3 -> new byte[]{0,3,r[4],0,0,0,0,0,0,0,0,0,0};
                    default -> throw new AssertionError("selector");
                };
                case 0x9F -> payload = ("\0" + CATALOG).getBytes(StandardCharsets.US_ASCII);
                case 0x97 -> payload = new byte[]{0,0,2,0,0,1,0};
                case 0x87 -> payload = new byte[]{0,r[3],r[4],(byte)AhaKeyProtocol.ORDINARY_KEY_ACTION_EMPTY,0,0};
                case 0x92 -> { deviceMode = r[3]; payload = new byte[]{0}; }
                case 0x00 -> payload = new byte[]{80,0,1,0,(byte)deviceMode,0,1,35};
                default -> payload = new byte[]{0};
            }
            try {
                var receive = BleManager.class.getDeclaredMethod("onBleNotify", byte[].class);
                receive.setAccessible(true);
                receive.invoke(wire.ble, (Object)AhaKeyProtocol.buildFrame(r[2], payload));
            } catch (ReflectiveOperationException e) { throw new IllegalStateException(e); }
        }
        void reset() throws Exception {
            var reset = BleManager.class.getDeclaredMethod("resetDisplaySession"); reset.setAccessible(true); reset.invoke(wire.ble);
            wire.ble.confirmDisplayFirmware(wire.ble.connectionGeneration(), HEX);
        }
        @Override public void close() throws Exception { fx(() -> service.close()); }
    }

    private interface Action { void run() throws Exception; }
    private static void fx(Action action) throws Exception {
        FutureTask<Void> task = new FutureTask<>(() -> { action.run(); return null; }); Platform.runLater(task); task.get(10, TimeUnit.SECONDS);
    }
    private static void latch(CountDownLatch gate) throws InterruptedException { if (!gate.await(10, TimeUnit.SECONDS)) throw new AssertionError("latch timeout"); }
    private static void start(FutureTask<?> task) { Thread thread = new Thread(task, "race-test"); thread.setDaemon(true); thread.start(); }
    private static void await(BooleanSupplier condition) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        while (!condition.getAsBoolean()) { if (System.nanoTime() >= deadline) throw new AssertionError("condition timeout"); Thread.sleep(5); }
    }
    private static void awaitFx(BooleanSupplier condition) throws Exception {
        AtomicBoolean done = new AtomicBoolean();
        await(() -> { try { fx(() -> done.set(condition.getAsBoolean())); return done.get(); } catch (Exception e) { throw new IllegalStateException(e); } });
    }
    private static Object field(Object target, String name) throws Exception { Field f = (target instanceof BleManager ? BleManager.class : target.getClass()).getDeclaredField(name); f.setAccessible(true); return f.get(target); }
    private static void field(Object target, String name, Object value) throws Exception { Field f = target.getClass().getDeclaredField(name); f.setAccessible(true); f.set(target, value); }
    private static void check(String id, boolean condition) { if (!condition) throw new AssertionError(id); checks++; System.out.println("PASS " + id); }
}
