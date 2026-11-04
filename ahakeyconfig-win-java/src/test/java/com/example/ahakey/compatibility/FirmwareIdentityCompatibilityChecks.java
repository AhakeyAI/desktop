package com.example.ahakey.compatibility;

import com.example.ahakey.firmware.FirmwareCatalog;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.AiRuntimeDisplayMode;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.BleTcpPacket;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.service.UsbHidTransport;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.*;

/** Actual WD006 admission/response paths, with all USB/TCP endpoints replaced by memory. */
public final class FirmwareIdentityCompatibilityChecks {
    private static final String[] SUPPORTED = {"x1-c582-hw1-p1-1.0.0-r001",
            "x1-c582-hw1-p1-1.0.1-r001", "x1-c582-hw2-p1-1.0.1-r001"};
    private static int checks;
    private static void check(String name, boolean value) {
        if (!value) throw new AssertionError(name);
        checks++; System.out.println("PASS " + name);
    }
    private static byte[] identity(String key) {
        return AhaKeyProtocol.buildFrame((byte)0x9F, ("\0" + key).getBytes(StandardCharsets.US_ASCII));
    }
    private static void field(BleManager ble, String name, Object value) throws Exception {
        Field f = BleManager.class.getDeclaredField(name); f.setAccessible(true); f.set(ble, value);
    }
    private static final class Fixture extends BleManager {
        String key = SUPPORTED[0]; boolean timeout; int writes;
        final MemoryUsb usb = new MemoryUsb();
        Fixture(boolean useUsb) throws Exception {
            super(new BleCallback() {
                public void onConnected() {} public void onDisconnected() {}
                public void onStatusReceived(DeviceStatus status) {} public void onError(String message) {}
            });
            field(this, "usbTransport", usb); usb.opened = useUsb;
            field(this, "isConnected", true); getCachedStatus().setConnected(true);
            field(this, "outputStream", new ByteArrayOutputStream() {
                @Override public synchronized void write(byte[] b, int offset, int length) {
                    respond(Arrays.copyOfRange(b, offset + 3, offset + length));
                }
            });
        }
        @Override protected boolean isUsbDevicePresent() { return false; }
        @Override public void connect() { throw new AssertionError("Real connection forbidden"); }
        void reset() throws Exception {
            Method m = BleManager.class.getDeclaredMethod("resetDisplaySession"); m.setAccessible(true); m.invoke(this);
        }
        void reply(byte[] response, long generation) {
            try {
                if (usb.opened) {
                    Method m = BleManager.class.getDeclaredMethod("onSessionNotify", long.class, byte[].class);
                    m.setAccessible(true); m.invoke(this, generation, response);
                } else {
                    Method m = BleManager.class.getDeclaredMethod("handleSessionPacket", long.class, byte.class, byte[].class);
                    m.setAccessible(true); m.invoke(this, generation, BleTcpPacket.BLE_NOTIFY, response);
                }
            } catch (ReflectiveOperationException ex) { throw new AssertionError(ex); }
        }
        void respond(byte[] request) {
            writes++;
            byte command = request[2];
            byte[] response = switch (command & 255) {
                case 0x9F -> timeout ? null : identity(key);
                case 0x87 -> AhaKeyProtocol.buildFrame(command, new byte[]{0, request[3], request[4], 0, 0, 0});
                case 0x97 -> AhaKeyProtocol.buildFrame(command, request.length == 5 ? new byte[]{0, 0, 2, 0, 0, 0, 0} : new byte[]{0});
                default -> AhaKeyProtocol.buildFrame(command, new byte[]{0});
            };
            if (response != null) reply(response, connectionGeneration());
        }
        final class MemoryUsb extends UsbHidTransport {
            boolean opened;
            @Override public boolean isOpen() { return opened; }
            @Override public void open(java.util.function.Consumer<byte[]> callback) { throw new AssertionError("No HID"); }
            @Override public void openExact(String path, java.util.function.Consumer<byte[]> callback) { throw new AssertionError("No HID"); }
            @Override public void sendCommand(byte[] command) { respond(command); }
            @Override public void sendData(byte[] data) { throw new AssertionError("No image upload in identity test"); }
            @Override public void close() { opened = false; }
        }
    }
    public static void main(String[] args) throws Exception {
        for (String key : SUPPORTED) {
            check("ordinary gate " + key, AhaKeyProtocol.isCp4cCatalogKey(key));
            check("runtime gate " + key, AhaKeyProtocol.isWs3Cp1RuntimeDisplaySupported(key));
            check("display frame gate " + key, AhaKeyProtocol.isDisplayCapabilityResponse(identity(key)));
            check("offline connection capabilities " + key, new FirmwareCatalog().connectionCapabilities(key).equals(FirmwareCatalog.ALL));
            check("padded identity " + key, AhaKeyProtocol.isDisplayCapabilityResponse(identity(key + "\0\0")));
            for (String invalid : new String[]{" " + key, key + " ", key + "\0junk", key.substring(0, key.length()-1), key.replace("-p1-", "-p2-")}) {
                check("reject nonexact identity " + invalid.replace('\0', '?'), !AhaKeyProtocol.isDisplayCapabilityResponse(identity(invalid)));
            }
        }
        check("null not supported", !AhaKeyProtocol.isCp4cCatalogKey(null));
        for (boolean usb : new boolean[]{false, true}) {
            Fixture wire = new Fixture(usb);
            for (String key : SUPPORTED) {
                wire.key = key; wire.reset();
                check("before identity cannot admit " + usb, !wire.isFirmwareCapabilityAdmitted("keys"));
                check("real identity read " + usb + " " + key, wire.readFirmwareCatalogKey().equals(key));
                check("real gates " + usb + " " + key, wire.isDisplayAdmitted()
                        && wire.isFirmwareCapabilityAdmitted("keys") && wire.isFirmwareCapabilityAdmitted("side")
                        && wire.isFirmwareCapabilityAdmitted("lights"));
                check("ordinary read after admission " + usb, wire.readOrdinaryKeyConfig(2, 1).mode() == 2);
                var side = wire.readSideSwitchConfig();
                wire.writeSideSwitchConfig(side);
                check("side read/save ACK " + usb, side.physicalPosition() == 0);
                wire.setRuntimeDisplayMode(AiRuntimeDisplayMode.MULTI);
                try (var lease = wire.openDisplayLease(true)) {
                    byte[] ack = wire.exchangeDisplay(lease, AhaKeyProtocol.saveDisplayBrightness(35));
                    check("display save admitted ACK " + usb, ack[3] == 0);
                }
                long oldGeneration = wire.connectionGeneration();
                var oldIdentity = wire.firmwareIdentity();
                wire.reset(); wire.reply(identity(key), oldGeneration);
                check("old callback cannot re-admit " + usb, !wire.isCurrentIdentity(oldIdentity) && !wire.isDisplayAdmitted()
                        && !wire.isFirmwareCapabilityAdmitted("keys"));
            }
            for (String unknown : new String[]{"x1-c582-hw2-p1-1.0.2-r001", "v1.0.0"}) {
                wire.key = unknown; wire.readFirmwareCatalogKey();
                check("unknown identity not admitted " + usb, !wire.isDisplayAdmitted() && !wire.isFirmwareCapabilityAdmitted("keys"));
            }
            wire.key = "";
            try { wire.readFirmwareCatalogKey(); throw new AssertionError("Empty legacy ACK accepted"); }
            catch (IOException expected) { check("legacy ACK keeps unavailable new capabilities " + usb, !wire.isDisplayAdmitted()); }
            int before = wire.writes;
            wire.sendCommand(AhaKeyProtocol.setKeyMapping(0, 1, new byte[]{4}));
            wire.sendCommand(AhaKeyProtocol.saveConfig());
            check("legacy basic K2 write/save path retained " + usb, wire.writes == before + 2);
            wire.key = SUPPORTED[1]; wire.readFirmwareCatalogKey(); wire.timeout = true;
            try { wire.readFirmwareCatalogKey(); throw new AssertionError("Missing reply accepted"); }
            catch (IOException expected) {
                check("timeout FAILED not legacy/supported " + usb, wire.firmwareIdentity().state() == DeviceStatus.IdentityState.FAILED
                        && !wire.isDisplayAdmitted() && !wire.isFirmwareCapabilityAdmitted("keys"));
            }
        }
        FirmwareCatalog catalog = new FirmwareCatalog();
        check("maintenance target catalog unchanged", catalog.knownCapabilities().keySet().equals(Set.of(SUPPORTED[0]))
                && catalog.capabilities(SUPPORTED[1]).isEmpty() && catalog.capabilities(SUPPORTED[2]).isEmpty());
        var builtin = new FirmwareCatalog.Target(FirmwareCatalog.Source.BUILTIN, "fixture", FirmwareCatalog.CATALOG,
                "x1-c582-hw1", "p1", FirmwareCatalog.HEX_HASH, FirmwareCatalog.ALL, 0, Path.of("not-opened.hex"));
        try { catalog.compatible(builtin, SUPPORTED[2]); throw new AssertionError("HW1 flash accepted for HW2"); }
        catch (IOException expected) { check("HW2 config capability does not admit HW1 builtin flash", true); }
        System.out.println("PASS " + checks + " checks; memory USB/TCP only; no device/UAT claims");
    }
}
