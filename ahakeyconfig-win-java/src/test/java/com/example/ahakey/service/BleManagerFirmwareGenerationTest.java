package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.net.ServerSocket;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Newer firmware answers 0x9F with a catalog key and uses 0x97-0x9D for other
 * features. This client must not send its own 0x93-0x9D commands to it, while
 * older firmware keeps working unchanged.
 */
class BleManagerFirmwareGenerationTest {

    static final String CATALOG_KEY = "x1-c582-hw1-p1-1.0.0-r001";

    @Test
    void parserTellsCatalogKeyRepliesFromCapabilityRecords() {
        assertTrue(AhaKeyResponseParser.isFirmwareCatalogKeyResponse(catalogFrame(true)));
        assertTrue(AhaKeyResponseParser.isFirmwareCatalogKeyResponse(catalogFrame(false)));
        assertFalse(AhaKeyResponseParser.isFirmwareCatalogKeyResponse(legacyCapabilityFrame()));
        assertFalse(AhaKeyResponseParser.isFirmwareCatalogKeyResponse(new byte[]{
            (byte) 0xAA, (byte) 0xBB, AhaKeyProtocol.CMD_QUERY_CAPABILITIES, 0,
            'a', 'b', 'c', (byte) 0xCC, (byte) 0xDD}), "too short to be a key");
        byte[] otherCommand = catalogFrame(true);
        otherCommand[2] = AhaKeyProtocol.CMD_TASK_LIGHT_MODE;
        assertFalse(AhaKeyResponseParser.isFirmwareCatalogKeyResponse(otherCommand));
    }

    @Test
    void newerFirmwareNeverReceivesLegacyTaskOrGifCommands() throws Exception {
        FakeUsb usb = new FakeUsb(catalogFrame(true));
        BleManager manager = connect(usb);
        try {
            assertThrows(IOException.class, () -> manager.setTaskDisplayMode(1));
            assertThrows(IOException.class, manager::queryTaskDisplayMode);
            assertThrows(IOException.class, manager::sendTaskHeartbeat);
            assertThrows(IOException.class, () -> manager.updateTaskSlot(0, 0, 0, false));
            assertThrows(IOException.class, manager::queryGifLayout);
            assertThrows(IOException.class, manager::readVoiceKeyConfig);
            assertThrows(IOException.class, () -> manager.readAiOledState(0, 1));

            assertTrue(manager.isCatalogKeyFirmware());
            assertNull(manager.queryDeviceCapabilities(),
                "a catalog key must not be parsed into a bogus firmware version");
            for (byte command : usb.sentCommands) {
                int code = command & 0xFF;
                assertFalse(code >= 0x93 && code <= 0x9D && code != 0x95,
                    "sent legacy command 0x" + Integer.toHexString(code));
            }
        } finally {
            manager.shutdown();
        }
    }

    @Test
    void olderFirmwareStillReceivesTaskCommands() throws Exception {
        FakeUsb usb = new FakeUsb(legacyCapabilityFrame());
        BleManager manager = connect(usb);
        try {
            manager.sendTaskHeartbeat();
            manager.updateTaskSlot(0, 0, 0, false);

            assertFalse(manager.isCatalogKeyFirmware());
            assertTrue(usb.sentCommands.contains(AhaKeyProtocol.CMD_TASK_HEARTBEAT));
            assertTrue(usb.sentCommands.contains(AhaKeyProtocol.CMD_TASK_SLOT_UPDATE));
            assertEquals(1, usb.sentCommands.stream()
                .filter(code -> code == AhaKeyProtocol.CMD_QUERY_CAPABILITIES).count(),
                "the 0x9F probe result is reused within the connection");
            assertNotNull(manager.queryDeviceCapabilities());
        } finally {
            manager.shutdown();
        }
    }

    @Test
    void firmwareThatNeverAnswers0x9FIsProbedOnlyOnce() throws Exception {
        FakeUsb usb = new FakeUsb(null);
        BleManager manager = connect(usb);
        try {
            BleManager.setResponseTimeoutForTesting(300);
            manager.sendTaskHeartbeat();
            manager.sendTaskHeartbeat();
            manager.updateTaskSlot(0, 0, 0, false);

            assertFalse(manager.isCatalogKeyFirmware());
            assertEquals(1, usb.sentCommands.stream()
                .filter(code -> code == AhaKeyProtocol.CMD_QUERY_CAPABILITIES).count(),
                "a 0x9F timeout is remembered for the connection");
            assertEquals(2, usb.sentCommands.stream()
                .filter(code -> code == AhaKeyProtocol.CMD_TASK_HEARTBEAT).count());
        } finally {
            BleManager.setResponseTimeoutForTesting(0);
            manager.shutdown();
        }
    }

    private static BleManager connect(FakeUsb usb) throws Exception {
        int unusedPort;
        try (ServerSocket socket = new ServerSocket(0)) {
            unusedPort = socket.getLocalPort();
        }
        BleManager manager = new BleManager("127.0.0.1", unusedPort, new Callback(), usb,
            () -> true, 3000);
        manager.connect();
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        while (!manager.isUsbConnected() && System.nanoTime() < deadline) {
            Thread.sleep(10);
        }
        assertTrue(manager.isUsbConnected());
        return manager;
    }

    static byte[] catalogFrame(boolean withStatusByte) {
        byte[] key = CATALOG_KEY.getBytes(StandardCharsets.US_ASCII);
        int prefix = withStatusByte ? 4 : 3;
        byte[] frame = new byte[prefix + key.length + 4 + 2];
        frame[0] = (byte) 0xAA;
        frame[1] = (byte) 0xBB;
        frame[2] = AhaKeyProtocol.CMD_QUERY_CAPABILITIES;
        System.arraycopy(key, 0, frame, prefix, key.length);
        frame[frame.length - 2] = (byte) 0xCC;
        frame[frame.length - 1] = (byte) 0xDD;
        return frame;
    }

    static byte[] legacyCapabilityFrame() {
        // status 0; protocol 2.0, firmware 1.4, hw 1, capability bits, patch 8, model 1
        return new byte[]{(byte) 0xAA, (byte) 0xBB, AhaKeyProtocol.CMD_QUERY_CAPABILITIES, 0,
            2, 0, 1, 4, 1, (byte) 0xFF, (byte) 0xFF, 0, 0, 8, 1,
            (byte) 0xCC, (byte) 0xDD};
    }

    private static byte[] ack(byte command) {
        return new byte[]{(byte) 0xAA, (byte) 0xBB, command, 0, (byte) 0xCC, (byte) 0xDD};
    }

    private static byte[] statusFrame() {
        return new byte[]{(byte) 0xAA, (byte) 0xBB, 0,
            94, 50, 1, 3, 2, 1, 0, 35, 7, (byte) 0xCC, (byte) 0xDD};
    }

    private static final class Callback implements BleManager.BleCallback {
        @Override public void onConnected() {}
        @Override public void onDisconnected() {}
        @Override public void onStatusReceived(DeviceStatus status) {}
        @Override public void onError(String message) {}
    }

    /** USB keyboard that answers status, 0x9F and acknowledges everything else. */
    private static final class FakeUsb extends UsbHidTransport {
        final List<Byte> sentCommands = new CopyOnWriteArrayList<>();
        private final byte[] capabilityReply;
        private final AtomicBoolean open = new AtomicBoolean();
        private volatile FrameConsumer consumer;

        FakeUsb(byte[] capabilityReply) {
            this.capabilityReply = capabilityReply;
        }

        @Override public void open(FrameConsumer onFrame, Runnable onDisconnected) {
            consumer = onFrame;
            open.set(true);
        }

        @Override public boolean isOpen() { return open.get(); }

        @Override public void close() { open.set(false); }

        @Override public void sendCommand(byte[] frame) {
            byte command = frame[2];
            sentCommands.add(command);
            if (command == AhaKeyProtocol.CMD_QUERY_STATUS) {
                emitSoon(statusFrame());
            } else if (command == AhaKeyProtocol.CMD_QUERY_CAPABILITIES) {
                if (capabilityReply != null) emitSoon(capabilityReply);
            } else {
                emitSoon(ack(command));
            }
        }

        private void emitSoon(byte[] reply) {
            Thread delivery = new Thread(() -> {
                try {
                    Thread.sleep(3);
                    FrameConsumer target = consumer;
                    if (open.get() && target != null) target.accept(reply, System.nanoTime());
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }, "fake-usb-reply");
            delivery.setDaemon(true);
            delivery.start();
        }
    }
}
