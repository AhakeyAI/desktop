package com.example.ahakey.service;

import com.sun.jna.Library;
import com.sun.jna.Native;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.Closeable;
import java.io.IOException;
import java.util.Arrays;
import java.util.function.Consumer;

/**
 * Ubuntu/Linux 平台 USB HID 传输层
 * 使用 Linux /dev/hidraw 接口访问设备
 */
public class UsbHidTransport implements Closeable {
    private static final Logger logger = LoggerFactory.getLogger(UsbHidTransport.class);

    private static final int REPORT_SIZE = 64;
    private static final byte USB_COMMAND_PACKET = (byte) 0xA1;
    private static final byte USB_DATA_PACKET = (byte) 0xA2;

    private volatile boolean running;
    private Consumer<byte[]> frameConsumer;
    private int nativeFd = -1;
    private String devicePath;
    private Thread readerThread;

    public interface LibC extends Library {
        LibC INSTANCE = Native.load("c", LibC.class);

        int O_RDWR = 2;

        int open(String path, int flags);
        int close(int fd);
        long read(int fd, byte[] buf, long count);
        long write(int fd, byte[] buf, long count);
    }

    public static boolean isPresent() {
        return findDevicePath() != null;
    }

    public synchronized void open(Consumer<byte[]> onFrame) throws IOException {
        if (isOpen()) {
            return;
        }
        devicePath = findDevicePath();
        if (devicePath == null) {
            throw new IOException("USB HID device not found");
        }

        int fd = LibC.INSTANCE.open(devicePath, LibC.O_RDWR);
        if (fd < 0) {
            int err = Native.getLastError();
            String hint = err == 13 ? " (permission denied — add udev rule or join 'input' group)" : "";
            throw new IOException("Failed to open " + devicePath + ": errno=" + err + hint);
        }

        nativeFd = fd;
        frameConsumer = onFrame;
        running = true;
        startReader();
        logger.info("USB HID connected: {}", devicePath);
    }

    public synchronized boolean isOpen() {
        return running && nativeFd >= 0;
    }

    public synchronized void sendCommand(byte[] frame) throws IOException {
        ensureOpen();
        if (frame.length > REPORT_SIZE - 2) {
            throw new IOException("USB command frame too large: " + frame.length);
        }
        byte[] payload = new byte[REPORT_SIZE];
        payload[0] = USB_COMMAND_PACKET;
        payload[1] = (byte) frame.length;
        System.arraycopy(frame, 0, payload, 2, frame.length);
        writeReport(payload);
    }

    public synchronized void sendData(byte[] data) throws IOException {
        ensureOpen();
        int offset = 0;
        while (offset < data.length) {
            int len = Math.min(REPORT_SIZE - 2, data.length - offset);
            byte[] payload = new byte[REPORT_SIZE];
            payload[0] = USB_DATA_PACKET;
            payload[1] = (byte) len;
            System.arraycopy(data, offset, payload, 2, len);
            writeReport(payload);
            offset += len;
            sleepQuietly(2);
        }
    }

    private void startReader() {
        readerThread = new Thread(() -> {
            byte[] buffer = new byte[REPORT_SIZE];
            while (running) {
                int fd;
                synchronized (this) {
                    fd = nativeFd;
                }
                if (fd < 0) break;
                try {
                    long bytesRead = LibC.INSTANCE.read(fd, buffer, REPORT_SIZE);
                    if (bytesRead > 0) {
                        byte[] frame = extractFrame(buffer, (int) bytesRead);
                        if (frame != null && frameConsumer != null) {
                            frameConsumer.accept(frame);
                        }
                    } else if (bytesRead < 0) {
                        if (running) {
                            logger.warn("USB read error: errno={}", Native.getLastError());
                        }
                        break;
                    }
                } catch (Exception e) {
                    if (running) {
                        logger.warn("USB read exception: {}", e.getMessage());
                    }
                    break;
                }
            }
            logger.debug("USB reader thread exiting");
        }, "usb-hid-reader");
        readerThread.setDaemon(true);
        readerThread.start();
    }

    private void writeReport(byte[] payload) throws IOException {
        int fd;
        synchronized (this) {
            fd = nativeFd;
        }
        if (fd < 0) throw new IOException("USB HID not connected");
        long bytesWritten = LibC.INSTANCE.write(fd, payload, payload.length);
        if (bytesWritten < 0) {
            throw new IOException("USB HID write failed: errno=" + Native.getLastError());
        }
        if (bytesWritten != payload.length) {
            logger.warn("Partial write: {} of {} bytes", bytesWritten, payload.length);
        }
    }

    private static void sleepQuietly(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private void ensureOpen() throws IOException {
        if (!isOpen()) {
            throw new IOException("USB HID not connected");
        }
    }

    @Override
    public synchronized void close() {
        logger.debug("USB close: starting shutdown");
        running = false;

        if (readerThread != null) {
            readerThread.interrupt();
            readerThread = null;
        }

        if (nativeFd >= 0) {
            LibC.INSTANCE.close(nativeFd);
            nativeFd = -1;
        }

        frameConsumer = null;
        devicePath = null;
        logger.debug("USB close: shutdown complete");
    }

    private static byte[] extractFrame(byte[] data, int len) {
        int start = -1;
        for (int i = 0; i + 1 < len; i++) {
            if (data[i] == (byte) 0xAA && data[i + 1] == (byte) 0xBB) {
                start = i;
                break;
            }
        }
        if (start < 0) return null;
        for (int i = start + 3; i + 1 < len; i++) {
            if (data[i] == (byte) 0xCC && data[i + 1] == (byte) 0xDD) {
                return Arrays.copyOfRange(data, start, i + 2);
            }
        }
        return null;
    }

    static String findDevicePath() {
        try {
            java.io.File devDir = new java.io.File("/dev");
            java.io.File[] hidrawFiles = devDir.listFiles((dir, name) -> name.startsWith("hidraw"));
            if (hidrawFiles != null) {
                for (java.io.File file : hidrawFiles) {
                    String ueventPath = "/sys/class/hidraw/" + file.getName() + "/device/uevent";
                    java.io.File uevent = new java.io.File(ueventPath);
                    if (uevent.exists()) {
                        String content = new String(java.nio.file.Files.readAllBytes(uevent.toPath()));
                        if (content.contains("HID_ID=0003:0000413C:00002107")) {
                            return "/dev/" + file.getName();
                        }
                    }
                }
            }
        } catch (Exception e) {
            logger.debug("USB device detection error: {}", e.getMessage());
        }
        return null;
    }
}
