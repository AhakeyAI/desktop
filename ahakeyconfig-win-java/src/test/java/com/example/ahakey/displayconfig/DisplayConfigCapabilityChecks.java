package com.example.ahakey.displayconfig;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.service.*;
import com.example.ahakey.view.InspectorPane;
import javafx.application.Platform;
import javafx.beans.property.*;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.VBox;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** No App/controller construction; real protocol and services on memory USB/TCP only. */
public final class DisplayConfigCapabilityChecks {
    private static final String KEY = "x1-c582-hw1-p1-1.0.0-r001";
    private static int checks;
    private static void check(String name, boolean ok) {
        if (!ok) throw new AssertionError(name);
        checks++; System.out.println("PASS " + name);
    }
    private interface Action { void run() throws Exception; }
    private static void denied(String name, Action action) throws Exception {
        try { action.run(); throw new AssertionError(name + " unexpectedly accepted"); }
        catch (IOException expected) { check(name, true); }
    }
    private static void fx(Action action) throws Exception {
        FutureTask<Void> task = new FutureTask<>(() -> { action.run(); return null; });
        Platform.runLater(task); task.get(20, TimeUnit.SECONDS);
    }
    private static byte[] identity(String key) { return AhaKeyProtocol.buildFrame((byte)0x9F, ("\0" + key).getBytes(StandardCharsets.US_ASCII)); }
    private static void reset(BleManager ble) throws Exception {
        var method = BleManager.class.getDeclaredMethod("resetDisplaySession"); method.setAccessible(true); method.invoke(ble);
    }
    private static void sessionReply(BleManager ble, long generation, byte[] reply, boolean usb) throws Exception {
        if (usb) {
            var method = BleManager.class.getDeclaredMethod("onSessionNotify", long.class, byte[].class);
            method.setAccessible(true); method.invoke(ble, generation, reply);
        } else {
            var method = BleManager.class.getDeclaredMethod("handleSessionPacket", long.class, byte.class, byte[].class);
            method.setAccessible(true); method.invoke(ble, generation, BleTcpPacket.BLE_NOTIFY, reply);
        }
    }
    public static void main(String[] args) throws Exception {
        lifecycleFailures();
        Path dir = Files.createTempDirectory("wd005-r9-");
        withIsolatedHome(dir, () -> Platform.startup(() -> {}), () -> {
            for (boolean usb : new boolean[]{false, true}) { admission(usb); generations(usb); }
            timeoutAndRecovery();
            transportSwitch();
            leaseAndDedup();
            fx(DisplayConfigCapabilityChecks::sections);
            fx(DisplayConfigCapabilityChecks::slotSupport);
            serviceDrafts(dir);
            System.out.println("PASS " + checks + " capability checks; isolated UI/services, no full application or hardware");
        }, Platform::exit);
    }
    private static void withIsolatedHome(Path dir, Action startup, Action body, Action shutdown) throws Exception {
        String home = System.getProperty("user.home");
        Throwable failure = null;
        try {
            System.setProperty("user.home", dir.toString());
            startup.run();
            body.run();
        } catch (Exception | Error ex) {
            failure = ex;
            throw ex;
        } finally {
            try {
                shutdown.run();
            } catch (Exception | Error ex) {
                if (failure == null) throw ex;
                failure.addSuppressed(ex);
            } finally {
                if (home == null) System.clearProperty("user.home");
                else System.setProperty("user.home", home);
                cleanupHome(dir);
            }
        }
    }
    private static void cleanupHome(Path dir) {
        // Only this process's temporary home is eligible; loaded JavaFX DLLs stay until exit.
        Path cache = dir.resolve(".openjfx");
        try (var files = Files.walk(dir)) {
            for (Path file : files.sorted(Comparator.reverseOrder()).toList()) {
                if (file.startsWith(cache) || (file.equals(dir) && Files.exists(cache))) continue;
                try { Files.deleteIfExists(file); }
                catch (IOException | RuntimeException ex) { System.err.println("Temporary cleanup failed: " + file + ": " + ex); }
            }
        } catch (IOException | RuntimeException ex) { System.err.println("Temporary cleanup failed: " + dir + ": " + ex); }
        if (Files.exists(cache)) System.out.println("Retained process-loaded JavaFX cache: " + cache);
    }
    private static void lifecycleFailures() throws Exception {
        String home = System.getProperty("user.home");
        for (int stage = 0; stage < 3; stage++) {
            Path dir = Files.createTempDirectory("wd005-r9-failure-");
            Files.writeString(dir.resolve("fixture.txt"), "isolated");
            final int at = stage;
            boolean[] bodyRan = {false}, shutdownRan = {false};
            Throwable expected = at == 0 ? new IOException("simulated startup failure") : new UnsatisfiedLinkError("simulated initialization/body failure");
            try {
                withIsolatedHome(dir, () -> {
                    check("R9-startup-uses-temporary-home-" + at, dir.toString().equals(System.getProperty("user.home")));
                    if (at == 0) throw (IOException)expected;
                    if (at == 1) throw (Error)expected;
                }, () -> { bodyRan[0] = true; throw (Error)expected; }, () -> {
                    shutdownRan[0] = true;
                    if (at == 2) throw new IOException("simulated shutdown failure");
                });
                throw new AssertionError("Failure was lost");
            } catch (Exception | Error actual) {
                check("R9-original-failure-preserved-" + at, actual == expected);
                check("R9-shutdown-failure-suppressed-" + at, actual.getSuppressed().length == (at == 2 ? 1 : 0));
            }
            check("R9-home-restored-" + at, Objects.equals(home, System.getProperty("user.home")));
            check("R9-temporary-files-cleaned-" + at, !Files.exists(dir));
            check("R9-lifecycle-order-" + at, shutdownRan[0] && bodyRan[0] == (at == 2));
        }
        Path dir = Files.createTempDirectory("wd005-r9-cache-");
        Path cache = Files.createDirectories(dir.resolve(".openjfx"));
        Path sentinel = Files.writeString(cache.resolve("not-a-real-dll"), "temporary cache sentinel");
        try {
            withIsolatedHome(dir, () -> {}, () -> Files.writeString(dir.resolve("draft"), "temporary"), () -> {});
            check("R9-cache-retained-other-files-cleaned", Files.exists(sentinel) && !Files.exists(dir.resolve("draft")));
            check("R9-success-restores-home", Objects.equals(home, System.getProperty("user.home")));
        } finally {
            Files.deleteIfExists(sentinel); Files.deleteIfExists(cache); Files.deleteIfExists(dir);
        }
    }
    private static void slotSupport() throws Exception {
        var factory = InspectorPane.class.getDeclaredMethod("runtimeSlotSupport");
        factory.setAccessible(true);
        var language = com.example.ahakey.util.LanguageManager.getInstance();
        String original = language.getCurrentLanguage();
        try {
            for (String locale : new String[]{"zh", "en"}) {
                language.switchLanguage(locale);
                Label support = (Label)factory.invoke(null);
                String expected = locale.equals("zh") ? "槽位绑定保存在本机，不受键盘连接或固件识别状态影响。"
                        : "Slot bindings are saved locally, regardless of keyboard connection or firmware identification status.";
                check("R9-actual-slot-note-neutral-" + locale, support.getText().equals(expected));
                check("R9-actual-slot-note-wrap-style-" + locale, support.isWrapText() && support.getStyleClass().contains("group-note"));
                var display = new DisplayConfigState();
                var mode = new SimpleObjectProperty<>(AiRuntimeDisplayMode.MULTI);
                var pending = new SimpleBooleanProperty();
                VBox group = new VBox(new Label("Slots"), new VBox(support));
                var decorate = InspectorPane.class.getDeclaredMethod("decorateDisplaySection", VBox.class, DisplayConfigState.class, ObjectProperty.class, BooleanProperty.class, AiRuntimeDisplayMode.class);
                decorate.setAccessible(true);
                decorate.invoke(null, group, display, mode, pending, AiRuntimeDisplayMode.MULTI);
                Label reason = (Label)group.getChildren().get(1);
                for (String state : new String[]{"reading", "failed", "unknown", "unsupported", "disconnected", ""}) {
                    String key = state.isEmpty() ? "" : "display.identity-" + state;
                    display.disabledReasonKey.set(key);
                    check("R9-slot-note-survives-" + locale + "-" + state, support.getText().equals(expected));
                    check("R9-identity-reason-remains-authoritative-" + locale + "-" + state,
                            reason.getText().equals(key.isEmpty() ? "" : language.getString(key)));
                }
            }
        } finally { language.switchLanguage(original); }
    }
    private static void admission(boolean usb) throws Exception {
        var w = new DisplayConfigChecks.FakeSession(false);
        if (usb) w.useUsb();
        List<byte[]> sent = new ArrayList<>();
        w.respond = request -> { sent.add(request); w.reply(AhaKeyProtocol.buildFrame(request[2], new byte[]{0})); };
        w.ble.getCachedStatus().setFirmwareCatalogKey(KEY);
        check("C01-arbitrary-cache-not-authority-" + usb, !w.ble.isDisplayAdmitted());
        denied("C01-98-denied-" + usb, () -> w.ble.setRuntimeDisplayMode(AiRuntimeDisplayMode.MULTI));
        denied("C01-99-denied-" + usb, () -> w.ble.sendCommand(AhaKeyProtocol.buildFrame((byte)0x99,new byte[0])));
        for (int opcode : new int[]{0x88,0x89,0x8A,0x8B,0x8C,0x8E})
            denied("C01-direct-" + opcode + "-" + usb, () -> w.ble.sendCommand(AhaKeyProtocol.buildFrame((byte)opcode,new byte[0])));
        denied("C01-upload-lease-denied-" + usb, () -> w.ble.openDisplayLease(true));
        check("C01-no-new-wire-write-" + usb, sent.isEmpty());
        check("C04-single-legacy-delivered-" + usb, w.ble.sendRuntimeState((byte)1));
        check("C04-single-wire90-" + usb, (sent.get(0)[2] & 255) == 0x90);
        w.ble.getCachedStatus().setFirmwareMain(1); w.ble.getCachedStatus().setFirmwareSub(2);
        for (String value : new String[]{"V1.0", "", "x1-c582-hw1-p1-1.0.0-r002", "junk", " " + KEY, "\u0001" + KEY, KEY + "\0junk"}) {
            w.respond = request -> w.reply(identity(value));
            try { w.ble.readFirmwareCatalogKey(); } catch (IOException expected) { /* Empty response is failure. */ }
            check("C01-no-admission-" + usb + "-" + value.replace('\0','?'), !w.ble.isDisplayAdmitted());
        }
        w.respond = request -> w.reply(identity(""));
        denied("C01-empty-response-fails-" + usb, () -> w.ble.readFirmwareCatalogKey());
        check("C04-basic-version-fallback-" + usb, w.ble.getCachedStatus().getDisplayFirmwareVersion().equals("V1.2"));
        w.identify();
        check("C01-valid-response-auto-admits-" + usb, w.ble.isDisplayAdmitted()
                && w.ble.firmwareIdentity().state() == DeviceStatus.IdentityState.SUPPORTED);
        sent.clear();
        w.respond = request -> { sent.add(request); w.reply(AhaKeyProtocol.buildFrame(request[2],new byte[]{0})); };
        w.ble.setRuntimeDisplayMode(AiRuntimeDisplayMode.MULTI);
        try (var lease = w.ble.openDisplayLease(true)) { w.ble.exchangeDisplay(lease,AhaKeyProtocol.previewBrightness(50)); }
        check("C01-current-wire-98-89-" + usb, sent.size()==2 && sent.get(0)[2]==(byte)0x98 && sent.get(1)[2]==(byte)0x89);
        w.ble.requireDisplayRecovery(w.ble.connectionGeneration());
        w.identify();
        check("C03-identity-keeps-unknown-ACK-" + usb, w.ble.isDisplayAdmitted() && w.ble.isDisplayWriteUncertain());
        denied("C03-recovery-write-still-denied-" + usb, () -> w.ble.openDisplayLease(true));
        check("C07-memory-routing-" + usb, usb ? !w.ble.usb.sent.isEmpty() : w.ble.usb.sent.isEmpty());
        check("C07-no-connect-" + usb, w.ble.blockedConnections.get()==0);
    }
    private static void generations(boolean usb) throws Exception {
        var w = new DisplayConfigChecks.FakeSession(false); if (usb) w.useUsb();
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            long old = w.ble.connectionGeneration();
            CountDownLatch sent = new CountDownLatch(1);
            w.respond = request -> sent.countDown();
            Future<?> read = pool.submit(() -> {
                try { w.ble.readFirmwareCatalogKey(old); throw new AssertionError("old read succeeded"); }
                catch (Exception expected) { return null; }
            });
            check("C02-old-read-started-"+usb, sent.await(5,TimeUnit.SECONDS));
            var oldReading = w.ble.firmwareIdentity();
            reset(w.ble);
            sessionReply(w.ble,old,identity(KEY),usb);
            read.get(5,TimeUnit.SECONDS);
            check("C02-old-frame-and-failure-no-admission-"+usb,!w.ble.isDisplayAdmitted() && w.ble.getCachedStatus().getFirmwareCatalogKey().isEmpty());
            w.identify(); var current = w.ble.firmwareIdentity();
            sessionReply(w.ble,old,identity("future"),usb);
            check("C02-current-survives-old-packet-"+usb,w.ble.isDisplayAdmitted() && w.ble.isCurrentIdentity(current));
            fx(() -> check("C02-delayed-old-FX-ticket-rejected-"+usb,!w.ble.isCurrentIdentity(oldReading) && w.ble.isCurrentIdentity(current)));
            denied("C02-old-request-generation-denied-"+usb,() -> w.ble.readFirmwareCatalogKey(old));
            check("C02-old-request-does-not-clear-current-"+usb,w.ble.isDisplayAdmitted());
            w.ble.clearCachedFirmwareIdentity();
            check("C02-refresh-revokes-"+usb,!w.ble.isDisplayAdmitted());
            w.identify();
            w.field("isConnected",false); w.ble.getCachedStatus().setConnected(false);
            check("C02-disconnected-write-denied-"+usb,!w.ble.isDisplayAdmitted());
        } finally { pool.shutdownNow(); }
    }
    private static void timeoutAndRecovery() throws Exception {
        var w = new DisplayConfigChecks.FakeSession(false);
        w.respond = request -> {};
        denied("C01-real-timeout", () -> w.ble.readFirmwareCatalogKey());
        check("C01-timeout-is-FAILED-not-legacy",w.ble.firmwareIdentity().state()==DeviceStatus.IdentityState.FAILED && !w.ble.isDisplayAdmitted());
        w.identify(); check("C01-explicit-retry-recovers",w.ble.isDisplayAdmitted());
    }
    private static void transportSwitch() throws Exception {
        var w = new DisplayConfigChecks.FakeSession();
        var before = w.ble.firmwareIdentity();
        w.ble.usbPresent = true;
        denied("C02-auto-USB-switch-blocks-old-admission", () -> w.ble.setRuntimeDisplayMode(AiRuntimeDisplayMode.MULTI));
        check("C02-switch-no-write-on-new-USB", w.ble.usb.sent.isEmpty() && !w.ble.isDisplayAdmitted()
                && !w.ble.isCurrentIdentity(before) && w.ble.getCachedStatus().getFirmwareCatalogKey().isEmpty());
        w.identify(); check("C02-new-USB-response-required",w.ble.isDisplayAdmitted() && w.ble.usb.sent.size()==1);
    }
    private static void awaitBlocked(Thread thread) throws Exception {
        long end = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (thread.getState()!=Thread.State.BLOCKED && thread.getState()!=Thread.State.TIMED_WAITING) {
            if (!thread.isAlive() || System.nanoTime()>end) throw new AssertionError("Reader did not wait");
            Thread.sleep(2);
        }
    }
    private static void leaseAndDedup() throws Exception {
        var w = new DisplayConfigChecks.FakeSession();
        List<byte[]> sent = new CopyOnWriteArrayList<>();
        w.respond = request -> { sent.add(request); w.reply(request[2]==(byte)0x9F ? identity(KEY) : AhaKeyProtocol.buildFrame(request[2],new byte[]{0})); };
        FutureTask<String> task = new FutureTask<>(() -> w.ble.readFirmwareCatalogKey());
        Thread thread = new Thread(task,"isolated-identity-wait");
        try (var lease = w.ble.openDisplayLease(true)) {
            w.ble.clearCachedFirmwareIdentity();
            check("C03-refresh-clear-does-not-revoke-active-lease",w.ble.isDisplayAdmitted());
            thread.start(); awaitBlocked(thread);
            check("C03-queued-identity-does-not-revoke-upload",w.ble.isDisplayAdmitted() && sent.isEmpty());
            w.ble.exchangeDisplay(lease,AhaKeyProtocol.previewBrightness(50));
            check("C03-active-transaction-still-sends",sent.size()==1 && sent.get(0)[2]==(byte)0x89);
        }
        check("C03-identity-resumes-after-lease",task.get(5,TimeUnit.SECONDS).equals(KEY) && sent.size()==2);
        CountDownLatch sentIdentity = new CountDownLatch(1); sent.clear();
        w.respond = request -> { sent.add(request); sentIdentity.countDown(); };
        FutureTask<String> first = new FutureTask<>(() -> w.ble.readFirmwareCatalogKey());
        FutureTask<String> second = new FutureTask<>(() -> w.ble.readFirmwareCatalogKey());
        Thread a = new Thread(first,"isolated-identity-first"), b = new Thread(second,"isolated-identity-second");
        a.start(); check("C03-read-start",sentIdentity.await(5,TimeUnit.SECONDS));
        b.start(); awaitBlocked(b);
        w.reply(identity(KEY));
        check("C03-concurrent-read-deduplicated",first.get(5,TimeUnit.SECONDS).equals(KEY) && second.get(5,TimeUnit.SECONDS).equals(KEY) && sent.size()==1);
    }
    private static void sections() throws Exception {
        var display = new DisplayConfigState();
        ObjectProperty<AiRuntimeDisplayMode> mode = new SimpleObjectProperty<>(AiRuntimeDisplayMode.SINGLE);
        BooleanProperty pending = new SimpleBooleanProperty();
        var decorate = InspectorPane.class.getDeclaredMethod("decorateDisplaySection",VBox.class,DisplayConfigState.class,ObjectProperty.class,BooleanProperty.class,AiRuntimeDisplayMode.class);
        decorate.setAccessible(true);
        VBox root = new VBox(12); root.setStyle("-fx-background-color:white;");
        List<VBox> groups = new ArrayList<>();
        for (AiRuntimeDisplayMode target : new AiRuntimeDisplayMode[]{null,null,AiRuntimeDisplayMode.SINGLE,AiRuntimeDisplayMode.MULTI}) {
            VBox group = new VBox(4,new Label("分区标题"),new VBox(new TextField("本地草稿")));
            decorate.invoke(null,group,display,mode,pending,target); groups.add(group); root.getChildren().add(group);
        }
        new Scene(root,600,600).getStylesheets().add(InspectorPane.class.getResource("/style.css").toExternalForm());
        root.applyCss(); root.layout();
        for (VBox group : groups) check("C05-title-reason-not-disabled", !group.isDisabled() && !group.getChildren().get(0).isDisabled() && !group.getChildren().get(1).isDisabled());
        check("C05-single-active-multi-disabled",!groups.get(2).getChildren().get(2).isDisabled() && groups.get(3).getChildren().get(2).isDisabled());
        Label reason = (Label)groups.get(3).getChildren().get(1);
        check("C05-identity-before-mode",reason.getText().contains("未连接"));
        display.disabledReasonKey.set("");
        check("C05-mode-explanation",reason.getText().contains("单任务模式"));
        display.busy.set(true); check("C05-busy-before-mode",reason.getText().contains("处理配置"));
        display.busy.set(false); pending.set(true); check("C05-pending-before-mode",reason.getText().contains("切换"));
        pending.set(false); mode.set(AiRuntimeDisplayMode.MULTI);
        check("C05-global-brightness-not-mode-locked",!groups.get(1).getChildren().get(2).isDisabled());
        check("C05-multi-active-single-disabled",!groups.get(3).getChildren().get(2).isDisabled() && groups.get(2).getChildren().get(2).isDisabled());
        check("C06-draft-retained",((TextField)((VBox)groups.get(2).getChildren().get(2)).getChildren().get(0)).getText().equals("本地草稿"));
        check("C06-readable-reason-color",reason.getTextFill().equals(javafx.scene.paint.Color.web("#35424f")) && reason.getOpacity()==1);
    }
    private static void serviceDrafts(Path directory) throws Exception {
        var w = new DisplayConfigChecks.FakeSession(false);
        List<byte[]> sent = new CopyOnWriteArrayList<>(); w.respond = sent::add;
        StudioState studio = new StudioState(); studio.setSelectedPart(StudioPart.KEY1);
        DisplayConfigService[] service = new DisplayConfigService[1];
        fx(() -> {
            service[0] = new DisplayConfigService(studio,w.ble,new OledResourceStore(directory.resolve("oled")));
            service[0].connectionChanged(); studio.displayConfig().editBrightness(71);
            service[0].saveBrightness(); service[0].preview(null);
            studio.setSelectedPart(StudioPart.OLED); service[0].refresh();
            check("C01-service-unknown-disabled",!studio.displayConfig().writeReady.get());
            check("C06-local-edit-and-unknown-no-wire",studio.displayConfig().brightness.get()==71 && sent.isEmpty());
        });
        w.identify();
        fx(() -> {
            studio.setSelectedPart(StudioPart.KEY1); service[0].capabilityChanged();
            check("C01-service-auto-ready",studio.displayConfig().writeReady.get());
            check("C03-no-auto-save",sent.isEmpty() && studio.displayConfig().brightnessDirty());
            service[0].close();
        });
    }
}
