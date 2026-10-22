package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.BleTcpPacket;
import org.junit.jupiter.api.Test;

import java.io.EOFException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BleManagerTransportMigrationTest {
    @Test
    void initialConnectionPrefersUsbWhenBothTransportsExist() throws Exception {
        try (FakeBleBridge bridge = new FakeBleBridge()) {
            FakeUsbTransport usb = new FakeUsbTransport();
            usb.present.set(true);
            Callback callback = new Callback();
            BleManager manager = manager(bridge, usb, callback);
            try {
                manager.connect();
                assertTrue(waitUntil(manager::isUsbConnected));
                assertEquals("USB", manager.getCachedStatus().getTransport());
                assertEquals(1, usb.openCount.get());
                assertEquals(0, bridge.acceptCount.get());
            } finally {
                manager.shutdown();
            }
        }
    }

    @Test
    void activeBleMigratesOnlyAfterFreshUsbStatus() throws Exception {
        try (FakeBleBridge bridge = new FakeBleBridge()) {
            FakeUsbTransport usb = new FakeUsbTransport();
            Callback callback = new Callback();
            BleManager manager = manager(bridge, usb, callback);
            try {
                connectBle(manager);
                int disconnects = callback.disconnected.get();
                usb.present.set(true);

                manager.queryStatus();
                assertTrue(waitUntil(manager::isUsbConnected));
                assertTrue(manager.queryStatus());
                assertEquals("USB", manager.getCachedStatus().getTransport());
                assertEquals(disconnects, callback.disconnected.get());
                assertTrue(bridge.isClientOpen(), "BLE fallback must remain open");
            } finally {
                manager.shutdown();
            }
        }
    }

    @Test
    void failedUsbCandidatePreservesBleStateAndDoesNotReportDisconnect() throws Exception {
        try (FakeBleBridge bridge = new FakeBleBridge()) {
            FakeUsbTransport usb = new FakeUsbTransport();
            Callback callback = new Callback();
            BleManager manager = manager(bridge, usb, callback);
            try {
                connectBle(manager);
                int disconnects = callback.disconnected.get();
                usb.present.set(true);
                usb.answerStatus.set(false);

                assertTrue(manager.queryStatus(), "the preserved BLE query should still succeed");
                assertFalse(manager.isUsbConnected());
                assertEquals("BLE", manager.getCachedStatus().getTransport());
                assertTrue(manager.getCachedStatus().isConnected());
                assertEquals(disconnects, callback.disconnected.get());
                assertTrue(bridge.isClientOpen());
            } finally {
                manager.shutdown();
            }
        }
    }

    @Test
    void usbRemovalRestoresPreservedBleAndStaleBleCannotCompleteUsbRequest() throws Exception {
        try (FakeBleBridge bridge = new FakeBleBridge()) {
            FakeUsbTransport usb = new FakeUsbTransport();
            Callback callback = new Callback();
            BleManager manager = manager(bridge, usb, callback);
            try {
                connectBle(manager);
                usb.present.set(true);
                manager.queryStatus();
                assertTrue(waitUntil(manager::isUsbConnected));
                assertTrue(manager.queryStatus());

                usb.answerMode.set(false);
                FutureTask<Integer> query = new FutureTask<>(manager::queryWorkMode);
                Thread queryThread = new Thread(query, "usb-mode-query-test");
                queryThread.start();
                assertTrue(usb.modeQuery.await(1, TimeUnit.SECONDS));
                bridge.sendNotify(modeFrame(1));
                Thread.sleep(80);
                assertFalse(query.isDone(), "old BLE receiver must not satisfy the USB request");
                usb.emit(modeFrame(2));
                assertEquals(2, query.get(2, TimeUnit.SECONDS));

                usb.simulateRemoval();
                assertTrue(waitUntil(() -> "BLE".equals(manager.getCachedStatus().getTransport())));
                assertTrue(manager.getCachedStatus().isConnected());
                assertFalse(manager.isUsbConnected());
            } finally {
                manager.shutdown();
            }
        }
    }

    @Test
    void explicitDisconnectAndShutdownDoNotStartUsbMigration() throws Exception {
        try (FakeBleBridge bridge = new FakeBleBridge()) {
            FakeUsbTransport usb = new FakeUsbTransport();
            Callback callback = new Callback();
            BleManager manager = manager(bridge, usb, callback);
            connectBle(manager);
            usb.present.set(true);
            manager.disconnect();
            assertFalse(manager.queryStatus());
            assertEquals(0, usb.openCount.get());
            manager.shutdown();
            assertFalse(manager.queryStatus());
            assertEquals(0, usb.openCount.get());
        }
    }

    private static BleManager manager(FakeBleBridge bridge, FakeUsbTransport usb,
                                      Callback callback) {
        return new BleManager("127.0.0.1", bridge.port(), callback, usb,
            usb.present::get, 120);
    }

    private static void connectBle(BleManager manager) throws Exception {
        manager.connect();
        assertTrue(waitUntil(() -> "BLE".equals(manager.getCachedStatus().getTransport())));
        assertTrue(manager.getCachedStatus().isConnected());
    }

    private static boolean waitUntil(java.util.function.BooleanSupplier condition)
            throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
        while (!condition.getAsBoolean() && System.nanoTime() < deadline) {
            Thread.sleep(10);
        }
        return condition.getAsBoolean();
    }

    private static byte[] statusFrame() {
        return new byte[]{
            (byte) 0xAA, (byte) 0xBB, 0,
            94, 50, 1, 3, 2, 1, 0, 35, 7,
            (byte) 0xCC, (byte) 0xDD
        };
    }

    private static byte[] modeFrame(int mode) {
        return new byte[]{(byte) 0xAA, (byte) 0xBB, AhaKeyProtocol.CMD_MODE_SYNC,
            0, (byte) mode, 0, (byte) 0xCC, (byte) 0xDD};
    }

    private static final class Callback implements BleManager.BleCallback {
        final AtomicInteger disconnected = new AtomicInteger();
        @Override public void onConnected() {}
        @Override public void onDisconnected() { disconnected.incrementAndGet(); }
        @Override public void onStatusReceived(DeviceStatus status) {}
        @Override public void onError(String message) {}
    }

    private static final class FakeUsbTransport extends UsbHidTransport {
        final AtomicBoolean present = new AtomicBoolean();
        final AtomicBoolean answerStatus = new AtomicBoolean(true);
        final AtomicBoolean answerMode = new AtomicBoolean(true);
        final AtomicInteger openCount = new AtomicInteger();
        final CountDownLatch modeQuery = new CountDownLatch(1);
        private volatile boolean open;
        private volatile FrameConsumer consumer;
        private volatile Runnable disconnected;

        @Override public void open(FrameConsumer onFrame, Runnable onDisconnected) {
            if (!present.get()) throw new IllegalStateException("not present");
            openCount.incrementAndGet();
            open = true;
            consumer = onFrame;
            disconnected = onDisconnected;
        }

        @Override public boolean isOpen() { return open; }

        @Override public void sendCommand(byte[] frame) {
            if (!open) throw new IllegalStateException("closed");
            if (frame[2] == AhaKeyProtocol.CMD_QUERY_STATUS && answerStatus.get()) {
                emitSoon(statusFrame());
            } else if (frame[2] == AhaKeyProtocol.CMD_MODE_SYNC) {
                modeQuery.countDown();
                if (answerMode.get()) emitSoon(modeFrame(2));
            }
        }

        @Override public void close() { open = false; }

        void emit(byte[] frame) {
            FrameConsumer target = consumer;
            if (open && target != null) target.accept(frame, System.nanoTime());
        }

        void emitSoon(byte[] frame) {
            Thread delivery = new Thread(() -> {
                try {
                    Thread.sleep(3);
                    emit(frame);
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                }
            }, "fake-usb-delivery");
            delivery.setDaemon(true);
            delivery.start();
        }

        void simulateRemoval() {
            present.set(false);
            open = false;
            Runnable target = disconnected;
            if (target != null) target.run();
        }
    }

    private static final class FakeBleBridge implements AutoCloseable {
        private final ServerSocket server;
        private final Thread worker;
        private final AtomicInteger acceptCount = new AtomicInteger();
        private volatile Socket client;
        private volatile OutputStream output;

        FakeBleBridge() throws Exception {
            server = new ServerSocket(0);
            worker = new Thread(this::serve, "fake-ble-bridge");
            worker.setDaemon(true);
            worker.start();
        }

        int port() { return server.getLocalPort(); }
        boolean isClientOpen() { return client != null && !client.isClosed(); }

        synchronized void sendNotify(byte[] frame) throws Exception {
            if (output == null) throw new IllegalStateException("bridge not connected");
            output.write(BleTcpPacket.encode(BleTcpPacket.BLE_NOTIFY, frame));
            output.flush();
        }

        private void serve() {
            try (Socket accepted = server.accept()) {
                client = accepted;
                acceptCount.incrementAndGet();
                output = accepted.getOutputStream();
                InputStream input = accepted.getInputStream();
                byte[] header = new byte[3];
                while (!accepted.isClosed()) {
                    readFully(input, header);
                    int length = (header[1] & 0xff) | ((header[2] & 0xff) << 8);
                    byte[] body = new byte[length];
                    readFully(input, body);
                    if (header[0] == BleTcpPacket.QUERY_BLE_STATUS) {
                        sendStatusAndFreshState();
                    } else if (header[0] == BleTcpPacket.WRITE_COMMAND
                        && body.length > 2 && body[2] == AhaKeyProtocol.CMD_QUERY_STATUS) {
                        sendNotifySoon(statusFrame());
                    }
                }
            } catch (Exception ignored) {
            }
        }

        private synchronized void sendStatusAndFreshState() throws Exception {
            byte[] name = "AhaKey BLE".getBytes(java.nio.charset.StandardCharsets.UTF_8);
            byte[] status = new byte[3 + name.length];
            status[0] = 1;
            status[1] = (byte) name.length;
            System.arraycopy(name, 0, status, 2, name.length);
            status[status.length - 1] = 1;
            output.write(BleTcpPacket.encode(BleTcpPacket.BLE_STATUS_RESP, status));
            output.write(BleTcpPacket.encode(BleTcpPacket.BLE_NOTIFY, statusFrame()));
            output.flush();
        }

        private void sendNotifySoon(byte[] frame) {
            Thread delivery = new Thread(() -> {
                try {
                    Thread.sleep(3);
                    sendNotify(frame);
                } catch (Exception ignored) {
                }
            }, "fake-ble-delivery");
            delivery.setDaemon(true);
            delivery.start();
        }

        private static void readFully(InputStream input, byte[] bytes) throws Exception {
            int offset = 0;
            while (offset < bytes.length) {
                int read = input.read(bytes, offset, bytes.length - offset);
                if (read < 0) throw new EOFException();
                offset += read;
            }
        }

        @Override public void close() throws Exception {
            Socket current = client;
            if (current != null) current.close();
            server.close();
            worker.join(500);
        }
    }
}
