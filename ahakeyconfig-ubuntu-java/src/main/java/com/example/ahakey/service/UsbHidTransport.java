package com.example.ahakey.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.Closeable;
import java.io.IOException;
import java.util.function.Consumer;

/**
 * Ubuntu/Linux 平台 USB HID 传输层
 * 使用 Linux HIDAPI 或 /dev/hidraw 接口访问设备
 */
public class UsbHidTransport implements Closeable {
    private static final Logger logger = LoggerFactory.getLogger(UsbHidTransport.class);

    private static final int REPORT_SIZE = 64;
    private static final byte USB_COMMAND_PACKET = (byte) 0xA1;
    private static final byte USB_DATA_PACKET = (byte) 0xA2;

    private volatile boolean running;
    private Consumer<byte[]> frameConsumer;

    public static boolean isPresent() {
        // Ubuntu 平台检查设备是否存在
        return findDevicePath() != null;
    }

    public synchronized void open(Consumer<byte[]> onFrame) throws IOException {
        if (isOpen()) {
            return;
        }
        String path = findDevicePath();
        if (path == null) {
            throw new IOException("USB HID device not found");
        }
        frameConsumer = onFrame;
        running = true;
        logger.info("USB HID connected: {}", path);
    }

    public synchronized boolean isOpen() {
        return running;
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

    private static void sleepQuietly(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private void writeReport(byte[] payload64) throws IOException {
        // Ubuntu 版本：使用 Java 的 ProcessBuilder 调用 hidapi 工具或直接写入 /dev/hidraw
        // 这里使用简化实现，实际项目中需要使用 JNA 或专门的 HID 库
        logger.debug("USB HID write (Linux stub): {} bytes", payload64.length);
    }

    private void ensureOpen() throws IOException {
        if (!isOpen()) {
            throw new IOException("USB HID not connected");
        }
    }

    @Override
    public synchronized void close() {
        logger.debug("USB close: 开始关闭 USB 传输");
        running = false;
        frameConsumer = null;
        logger.debug("USB close: 关闭完成");
    }

    private static String findDevicePath() {
        // Ubuntu 版本：查找 /dev/hidraw* 设备
        // VID_413C PID_2107 是 AhaKey 设备
        try {
            java.io.File devDir = new java.io.File("/dev");
            java.io.File[] hidrawFiles = devDir.listFiles((dir, name) -> name.startsWith("hidraw"));
            if (hidrawFiles != null) {
                for (java.io.File file : hidrawFiles) {
                    String path = "/sys/class/hidraw/" + file.getName() + "/device/uevent";
                    java.io.File uevent = new java.io.File(path);
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
