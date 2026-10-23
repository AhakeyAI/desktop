package com.example.ahakey.displayconfig;

import com.example.ahakey.model.AiRuntimeDisplayMode;
import com.example.ahakey.model.IDEState;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.AiRuntimeDisplayService;
import com.example.ahakey.service.BleManager;
import java.io.IOException;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Probe the production routing with memory endpoints, including simulated USB presence. */
public final class DisplayConfigIsolationChecks {
    private static int checks;

    public static void main(String[] args) throws Exception {
        Path temp = Files.createTempDirectory("wd005-isolation-");
        String home = System.getProperty("user.home");
        System.setProperty("user.home", temp.toString());
        try {
            bleAndReset();
            usbDiscovery(false);
            usbDiscovery(true);
            anonymousPending();
            System.out.println("PASS " + checks + " isolation checks; memory USB/TCP only");
        } finally {
            System.setProperty("user.home", home);
            try (var paths = Files.walk(temp)) {
                for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(path);
            }
        }
    }

    private static DisplayConfigChecks.FakeSession wire(List<byte[]> sent) throws Exception {
        var w = new DisplayConfigChecks.FakeSession();
        w.respond = frame -> {
            sent.add(frame.clone());
            w.reply(AhaKeyProtocol.buildFrame(frame[2], new byte[]{0}));
        };
        return w;
    }

    private static void noConnectionObjects(OfflineBleManager ble) throws Exception {
        for (String name : List.of("socket", "inputStream", "readerThread"))
            check("no-real-" + name, field(ble, name) == null);
    }

    private static void blockedConnect(OfflineBleManager ble) throws Exception {
        int before = ble.blockedConnections.get();
        boolean blocked = false;
        try { ble.connect(); } catch (AssertionError expected) {
            blocked = expected.getMessage().equals("Real connection forbidden in offline fixture");
        }
        check("connect-blocked-before-thread", blocked && ble.blockedConnections.get() == before + 1);
        noConnectionObjects(ble);
    }

    private static void bleAndReset() throws Exception {
        List<byte[]> sent = new ArrayList<>();
        var w = wire(sent);
        check("constructor-no-discovery", w.ble.discoveries.get() == 0);
        check("closed-memory-usb-default", !w.ble.usb.isOpen());
        blockedConnect(w.ble);
        check("try-connect-absent", !(boolean)invoke(w.ble, "tryConnectUsb"));
        check("no-fake-quarantine", !(boolean)field(w.ble, "displayReadUncertain") && !w.ble.isDisplayWriteUncertain());
        check("BLE-real-send-entry", w.ble.sendRuntimeState((byte)1));
        check("BLE-memory-output-not-USB", sent.size() == 1 && sent.get(0)[3] == 1 && w.ble.usb.sent.isEmpty());
        sent.clear();
        try (var lease = w.ble.openDisplayLease(true)) {
            check("lease-holds-runtime", !w.ble.sendRuntimeState((byte)2) && sent.isEmpty());
            check("lease-replaces-runtime", !w.ble.sendRuntimeState((byte)3));
        }
        check("lease-close-real-flush", sent.size() == 1 && sent.get(0)[3] == 3);
        int discoveries = w.ble.discoveries.get();
        long generation = w.ble.connectionGeneration();
        invoke(w.ble, "resetDisplaySession");
        check("reset-real-generation", w.ble.connectionGeneration() == generation + 1);
        check("reset-keeps-fake-USB", field(w.ble, "usbTransport") == w.ble.usb);
        check("reset-keeps-BLE-discovery-policy", w.ble.sendRuntimeState((byte)4)
                && w.ble.discoveries.get() > discoveries && sent.get(sent.size()-1)[3] == 4);
        check("reset-does-not-forge-quarantine", !(boolean)field(w.ble, "displayReadUncertain") && !w.ble.isDisplayWriteUncertain());
        w.ble.requireDisplayRecovery(w.ble.connectionGeneration());
        int count = sent.size();
        check("real-recovery-defers", !w.ble.sendRuntimeState((byte)5));
        w.reply(AhaKeyProtocol.buildFrame((byte)0x8B, new byte[]{0}));
        invoke(w.ble, "flushDeferredRuntimeState");
        check("late-ACK-still-quarantined", sent.size() == count && w.ble.isDisplayWriteUncertain());
        invoke(w.ble, "resetDisplaySession");
        invoke(w.ble, "flushDeferredRuntimeState");
        check("reset-clears-old-pending", sent.size() == count && field(w.ble, "deferredRuntimeState") == null);
        blockedConnect(w.ble);
    }

    private static void usbDiscovery(boolean initialConnectPath) throws Exception {
        List<byte[]> sent = new ArrayList<>();
        var w = wire(sent);
        w.ble.usbPresent = true;
        if (initialConnectPath) check("try-connect-present", (boolean)invoke(w.ble, "tryConnectUsb"));
        else check("ensure-connect-present", w.ble.sendRuntimeState((byte)1));
        check("fake-discovery-and-open-" + initialConnectPath, w.ble.discoveries.get() == 1
                && w.ble.usb.opens.get() == 1 && w.ble.usb.isOpen());
        check("USB-real-send-branch-" + initialConnectPath, w.ble.usb.sent.size() == 1 && sent.size() == 1);
        noConnectionObjects(w.ble);
        w.ble.usb.sendData(new byte[]{7,8});
        check("raw-data-memory-only", w.ble.usb.data.size() == 1 && w.ble.usb.data.get(0)[1] == 8);
        invoke(w.ble, "resetDisplaySession");
        check("open-USB-survives-generation", w.ble.sendRuntimeState((byte)2) && w.ble.usb.sent.size() == 2);
        w.ble.usb.close();
        boolean closedRejected = false;
        try { w.ble.usb.sendCommand(new byte[]{1}); } catch (IOException expected) { closedRejected = true; }
        check("closed-USB-send-rejected", closedRejected);
        check("closed-USB-rediscovered-in-memory", w.ble.sendRuntimeState((byte)3)
                && w.ble.usb.opens.get() == 2 && w.ble.discoveries.get() == 2);
        blockedConnect(w.ble);
        w.ble.disconnect();
        check("real-disconnect-fake-close", !w.ble.usb.isOpen() && !w.ble.isConnected());
        noConnectionObjects(w.ble);
    }

    private static void anonymousPending() throws Exception {
        List<byte[]> sent = new ArrayList<>();
        var w = wire(sent);
        var service = new AiRuntimeDisplayService(w.ble);
        service.displayModeProperty().set(AiRuntimeDisplayMode.SINGLE);
        try (var lease = w.ble.openDisplayLease(true)) {
            check("anonymous-start-pending", service.handleHookEventResult("Kimi", IDEState.USER_PROMPT_SUBMIT, null)
                    == AiRuntimeDisplayService.Delivery.PENDING);
            check("anonymous-own-terminal-pending", service.handleHookEventResult("Kimi", IDEState.SESSION_END, null)
                    == AiRuntimeDisplayService.Delivery.PENDING);
            check("anonymous-lease-no-write", sent.isEmpty());
        }
        check("anonymous-own-terminal-flushed", sent.size() == 1 && sent.get(0)[3] == IDEState.SESSION_END.getCode());
    }

    private static Object field(BleManager ble, String name) throws Exception {
        var f = BleManager.class.getDeclaredField(name); f.setAccessible(true); return f.get(ble);
    }
    private static Object invoke(BleManager ble, String name) throws Exception {
        Method m = BleManager.class.getDeclaredMethod(name); m.setAccessible(true); return m.invoke(ble);
    }
    private static void check(String name, boolean ok) {
        if (!ok) throw new AssertionError(name);
        checks++; System.out.println("PASS " + name);
    }
}
