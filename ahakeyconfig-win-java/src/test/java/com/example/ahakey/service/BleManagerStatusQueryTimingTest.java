package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.protocol.AhaKeyProtocol;
import org.junit.jupiter.api.Test;

import java.net.ServerSocket;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Seen on a real keyboard: the status reply arrived about 12 ms before the
 * USB HID write call returned. The reply was rejected as older than the query,
 * the poll timed out, and the client rebuilt the connection every few seconds.
 */
class BleManagerStatusQueryTimingTest {

    @Test
    void replyThatArrivesBeforeTheWriteReturnsStillCounts() throws Exception {
        SlowWriteUsb usb = new SlowWriteUsb();
        int unusedPort;
        try (ServerSocket socket = new ServerSocket(0)) {
            unusedPort = socket.getLocalPort();
        }
        BleManager manager = new BleManager("127.0.0.1", unusedPort, new Callback(), usb,
            () -> true, 3000);
        try {
            manager.connect();
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
            while (!manager.isUsbConnected() && System.nanoTime() < deadline) {
                Thread.sleep(10);
            }
            assertTrue(manager.isUsbConnected());

            usb.slowWrites.set(true);
            for (int i = 0; i < 3; i++) {
                assertTrue(manager.queryStatusAndWait(750),
                    "status reply received during a slow write must be accepted");
            }
        } finally {
            manager.shutdown();
        }
    }

    private static final class Callback implements BleManager.BleCallback {
        @Override public void onConnected() {}
        @Override public void onDisconnected() {}
        @Override public void onStatusReceived(DeviceStatus status) {}
        @Override public void onError(String message) {}
    }

    /** Answers status queries on the reader side before the write call returns. */
    private static final class SlowWriteUsb extends UsbHidTransport {
        final AtomicBoolean slowWrites = new AtomicBoolean();
        private final AtomicBoolean open = new AtomicBoolean();
        private volatile FrameConsumer consumer;

        @Override public void open(FrameConsumer onFrame, Runnable onDisconnected) {
            consumer = onFrame;
            open.set(true);
        }

        @Override public boolean isOpen() { return open.get(); }

        @Override public void close() { open.set(false); }

        @Override public void sendCommand(byte[] frame) {
            if (frame[2] != AhaKeyProtocol.CMD_QUERY_STATUS) return;
            boolean slow = slowWrites.get();
            java.util.concurrent.CountDownLatch received = new java.util.concurrent.CountDownLatch(1);
            Thread reader = new Thread(() -> {
                FrameConsumer target = consumer;
                // Arrival time is taken when the frame is received, as the real reader does.
                long receivedAt = System.nanoTime();
                received.countDown();
                if (open.get() && target != null) target.accept(statusFrame(), receivedAt);
            }, "fake-usb-reader");
            reader.setDaemon(true);
            reader.start();
            if (slow) {
                try {
                    received.await(1, TimeUnit.SECONDS);
                    Thread.sleep(20);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
        }

        private static byte[] statusFrame() {
            return new byte[]{(byte) 0xAA, (byte) 0xBB, 0,
                94, 50, 1, 3, 2, 1, 0, 35, 7, (byte) 0xCC, (byte) 0xDD};
        }
    }
}
