package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.protocol.BleTcpPacket;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;

public class BleManager {
    private static final Logger logger = LoggerFactory.getLogger(BleManager.class);
    private static final String DEFAULT_HOST = "127.0.0.1";
    private static final int DEFAULT_PORT = 9000;
    private static final long RESPONSE_TIMEOUT_MS = 15000;
    private static final long MODE_READBACK_TIMEOUT_MS = 5000;
    private static final long MODE_READBACK_REQUEST_INTERVAL_MS = 250;

    private final String host;
    private final int port;
    private final BleCallback callback;

    private Socket socket;
    private OutputStream outputStream;
    private InputStream inputStream;
    private Thread readerThread;
    private final UsbHidTransport usbTransport = new UsbHidTransport();

    private final ReentrantLock commandLock = new ReentrantLock();
    private final Condition responseReady = commandLock.newCondition();
    private final Object commandTransactionLock = new Object();
    private final Map<Byte, Deque<byte[]>> pendingNotifyFramesByCommand = new HashMap<>();
    private static final int NOTIFY_REASSEMBLY_MAX_BYTES = 512;
    private final byte[] notifyReassemblyBuffer = new byte[NOTIFY_REASSEMBLY_MAX_BYTES];
    private int notifyReassemblyLength = 0;
    private volatile long connectionGeneration;
    private volatile boolean displayWriteUncertain;
    private volatile boolean displayReadUncertain;
    private volatile long displayAdmissionGeneration = -1;
    private DisplayLease displayLease;
    private byte[] displayReply;
    private byte displayExpected;
    private int legacyWaiters;
    private volatile Byte deferredRuntimeState;
    private long deferredRuntimeAt;
    private volatile long lastOptionalQueryNanos;
    private Runnable displayIdleListener = () -> {};
    public void setDisplayIdleListener(Runnable listener) { displayIdleListener = listener; }

    public final class DisplayLease implements AutoCloseable {
        private final long generation;
        private final boolean usb;
        private final Thread owner = Thread.currentThread();
        private final boolean writing;
        private boolean closed;
        private DisplayLease(boolean writing) {
            this.generation = connectionGeneration;
            this.usb = usbTransport.isOpen();
            this.writing = writing;
        }
        public long generation() { return generation; }
        @Override public void close() {
            if (release()) notifyDisplayIdle();
        }
        private boolean release() {
            boolean notify;
            commandLock.lock();
            try {
                notify = displayLease == this && generation == connectionGeneration && !displayWriteUncertain;
                closed = true; if (displayLease == this) displayLease = null; responseReady.signalAll();
            }
            finally { commandLock.unlock(); }
            return notify;
        }
    }

    private void notifyDisplayIdle() {
        flushDeferredRuntimeState();
        try { displayIdleListener.run(); }
        catch (RuntimeException e) { logger.warn("Deferred runtime update failed: {}", e.getMessage()); }
    }

    public long connectionGeneration() { return connectionGeneration; }
    public boolean isDisplayWriteUncertain() { return displayWriteUncertain; }
    public void requireDisplayRecovery(long generation) {
        commandLock.lock();
        try { if (generation == connectionGeneration) displayWriteUncertain = true; }
        finally { commandLock.unlock(); }
    }
    public boolean isDisplayBusy() { commandLock.lock(); try { return displayLease != null; } finally { commandLock.unlock(); } }
    public boolean isDisplayAdmitted() {
        return isConnected && cachedStatus.isConnected() && displayAdmissionGeneration == connectionGeneration;
    }
    // Internal paired testing must explicitly confirm the exact installed HEX, never infer this from 0x88/catalog.
    public void confirmDisplayFirmware(long generation, String hexSha256) {
        if (!"D7D10510482228B74A2978BD8272F6A4E32668CF6B4F31F491A8503B0DC11E2E".equalsIgnoreCase(hexSha256)
                || generation != connectionGeneration || !isConnected || !cachedStatus.isConnected())
            throw new IllegalArgumentException("当前连接的 CP2 固件身份未确认。");
        displayAdmissionGeneration = generation;
    }

    private void resetDisplaySession() {
        commandLock.lock();
        try {
            connectionGeneration++;
            displayAdmissionGeneration = -1;
            displayWriteUncertain = false;
            displayReadUncertain = false;
            displayReply = null;
            displayLease = null;
            deferredRuntimeState = null;
            pendingNotifyFramesByCommand.clear();
            synchronized (notifyReassemblyBuffer) { notifyReassemblyLength = 0; }
            responseReady.signalAll();
        } finally { commandLock.unlock(); }
    }

    public DisplayLease openDisplayLease(boolean writing) throws IOException {
        return openDisplayLease(writing, connectionGeneration);
    }

    @FunctionalInterface
    public interface DisplayReadTask { void run(DisplayLease lease) throws Exception; }

    // Share the legacy transaction queue: background reads must not reject identity/input/mode flows.
    public void readDisplayConfig(long generation, DisplayReadTask task) throws Exception {
        boolean notify = false;
        try {
            synchronized (commandTransactionLock) {
                commandLock.lockInterruptibly();
                DisplayLease lease;
                try {
                    long remaining = TimeUnit.MILLISECONDS.toNanos(RESPONSE_TIMEOUT_MS);
                    while (legacyWaiters != 0) {
                        if (generation != connectionGeneration || !isConnected) throw new IOException("键盘连接已改变。");
                        if (remaining <= 0) throw new IOException("等待设备事务结束超时，请稍后刷新。");
                        remaining = responseReady.awaitNanos(remaining);
                    }
                    lease = openDisplayLease(false, generation);
                } finally { commandLock.unlock(); }
                try { task.run(lease); }
                finally { notify = lease.release(); }
            }
        } finally {
            // CP1 snapshot delivery also uses commandTransactionLock; never call it while holding that monitor.
            if (notify) notifyDisplayIdle();
        }
    }
    public void invalidateDisplayRead(DisplayLease lease) {
        commandLock.lock();
        try { if (lease.generation == connectionGeneration) displayReadUncertain = true; }
        finally { commandLock.unlock(); }
    }
    public DisplayLease openDisplayLease(boolean writing, long expectedGeneration) throws IOException {
        commandLock.lock();
        try {
            if (expectedGeneration != connectionGeneration) throw new IOException("键盘连接已改变。");
            if (!isConnected || !cachedStatus.isConnected()) throw new IOException("键盘连接已断开。");
            if (displayLease != null || legacyWaiters != 0) throw new IOException("设备正在处理其他事务。");
            if (writing && (!isDisplayAdmitted() || displayWriteUncertain))
                throw new IOException(displayWriteUncertain ? "设备保存结果未确认，请重新连接后同步。" : "请先确认当前键盘的 CP2 固件身份。");
            if (!writing && displayReadUncertain) throw new IOException("上次读取结果未确认，请重新连接后同步。");
            displayLease = new DisplayLease(writing);
            return displayLease;
        } finally { commandLock.unlock(); }
    }

    public byte[] exchangeDisplay(DisplayLease lease, byte[] request) throws Exception {
        long queuedAt = System.nanoTime();
        commandLock.lockInterruptibly();
        long acquiredAt = System.nanoTime();
        long sentAt = 0;
        String outcome = "NOT_SENT";
        boolean sent = false;
        try {
            checkDisplayLease(lease);
            int opcode = request[2] & 255;
            if (opcode != 0x88 && opcode != 0x89 && opcode != 0x8A && opcode != 0x8B && opcode != 0x8C && opcode != 0x8E)
                throw new IllegalArgumentException("CP2 opcode");
            if (opcode != 0x88 && (!lease.writing || displayWriteUncertain || !isDisplayAdmitted())) throw new IOException("显示配置写入未准入。");
            if (opcode == 0x88 && displayReadUncertain) throw new IOException("读取结果未确认，请重新连接。");
            displayExpected = request[2];
            displayReply = null;
            sent = true;
            outcome = "WRITE_ATTEMPTED_UNKNOWN";
            if (lease.usb) usbTransport.sendCommand(request);
            else writePacket(BleTcpPacket.WRITE_COMMAND, request);
            sentAt = System.nanoTime();
            outcome = "ACK_UNKNOWN";
            long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(RESPONSE_TIMEOUT_MS);
            while (true) {
                checkDisplayLease(lease);
                if (displayReply != null) {
                    byte[] reply = displayReply;
                    displayReply = null;
                    if (AhaKeyResponseParser.displayReplyLength(reply, 0, reply.length) != reply.length)
                        throw new IOException("显示配置响应格式无效。");
                    outcome = reply[3] == 0 ? "ACK_OK" : "ACK_FAIL";
                    return reply;
                }
                long remaining = deadline - System.nanoTime();
                if (remaining <= 0) throw new IOException("设备保存或读取结果未确认，请重新连接后同步。");
                responseReady.awaitNanos(Math.min(remaining, TimeUnit.MILLISECONDS.toNanos(100)));
            }
        } catch (Exception e) {
            if (sent && lease.generation == connectionGeneration) {
                if (request[2] == AhaKeyProtocol.CMD_DISPLAY_READ) displayReadUncertain = true;
                else displayWriteUncertain = true;
            }
            throw e;
        } finally {
            long finishedAt = System.nanoTime();
            displayExpected = 0;
            commandLock.unlock();
            int opcode = request[2] & 255;
            if (opcode >= 0x8A && opcode <= 0x8C) {
                long offset = opcode == 0x8B ? Integer.toUnsignedLong(java.nio.ByteBuffer.wrap(request, 4, 4)
                        .order(java.nio.ByteOrder.LITTLE_ENDIAN).getInt()) : 0;
                logger.info("CP2 exchange connection={} transport={} opcode={} entry={} offset={} outcome={} queueUs={} writeUs={} ackUs={}",
                        lease.generation, lease.usb ? "USB" : "BLE", opcode, request[3] & 255, offset, outcome,
                        (acquiredAt - queuedAt) / 1000, sentAt == 0 ? -1 : (sentAt - acquiredAt) / 1000,
                        sentAt == 0 ? -1 : (finishedAt - sentAt) / 1000);
            }
        }
    }

    private void checkDisplayLease(DisplayLease lease) throws IOException {
        if (lease == null || lease != displayLease || lease.closed || lease.owner != Thread.currentThread()
                || lease.generation != connectionGeneration || !isConnected || !cachedStatus.isConnected()
                || lease.usb != usbTransport.isOpen()) throw new IOException("键盘连接已改变，本次事务已停止。");
    }

    private volatile boolean isConnected;
    private volatile boolean isScanning;
    private volatile DeviceStatus cachedStatus = new DeviceStatus();
    private volatile long lastStatusUpdateTime = 0;  // 最后一次状态更新时间

    public interface BleCallback {
        void onConnected();
        void onDisconnected();
        void onStatusReceived(DeviceStatus status);
        void onError(String message);
    }

    public BleManager(BleCallback callback) {
        this(DEFAULT_HOST, DEFAULT_PORT, callback);
    }

    public BleManager(String host, int port, BleCallback callback) {
        this.host = host;
        this.port = port;
        this.callback = callback;
    }

    public static BleManager fromEnvironment(BleCallback callback) {
        String h = System.getenv("AHAKEY_BLE_HOST");
        String p = System.getenv("AHAKEY_BLE_PORT");
        int port = DEFAULT_PORT;
        if (p != null && !p.isBlank()) {
            try {
                port = Integer.parseInt(p.trim());
            } catch (NumberFormatException ignored) {
            }
        }
        return new BleManager(h != null && !h.isBlank() ? h.trim() : DEFAULT_HOST, port, callback);
    }

    public void connect() {
        long startTime = System.currentTimeMillis();
        logger.info("[BLE] === 开始连接 (第{}次尝试) ===", ++connectAttemptCount);
        
        if (isScanning) {
            logger.warn("[BLE] 正在扫描中，忽略连接请求");
            return;
        }
        isScanning = true;
        
        new Thread(() -> {
            logger.info("[BLE] 连接线程启动，耗时={}ms", System.currentTimeMillis() - startTime);
            
            long phaseStart = System.currentTimeMillis();
            closeTcpOnly();
            logger.info("[BLE] closeTcpOnly 完成，耗时={}ms", System.currentTimeMillis() - phaseStart);
            
            phaseStart = System.currentTimeMillis();
            if (tryConnectUsb()) {
                logger.info("[BLE] USB连接成功，总耗时={}ms", System.currentTimeMillis() - startTime);
                return;
            }
            logger.info("[BLE] USB连接失败，尝试BLE桥，耗时={}ms", System.currentTimeMillis() - phaseStart);
            
            logger.info("[BLE] Start connecting BLE bridge - {}:{}", host, port);
            try {
                phaseStart = System.currentTimeMillis();
                socket = new Socket();
                socket.connect(new InetSocketAddress(host, port), 5000);
                socket.setTcpNoDelay(true);
                outputStream = socket.getOutputStream();
                inputStream = socket.getInputStream();
                resetDisplaySession();
                logger.info("[BLE] Socket连接成功，耗时={}ms", System.currentTimeMillis() - phaseStart);
                
                isConnected = true;
                isScanning = false;
                cachedStatus.clearFirmwareIdentity();
                cachedStatus.setConnected(false);
                cachedStatus.setDeviceName("Waiting for device");
                if (cachedStatus.getBatteryLevel() < 0) {
                    cachedStatus.setBatteryLevel(50);
                }
                if (cachedStatus.getSwitchState() < 0) {
                    cachedStatus.setSwitchState(1);
                }
                logger.info("[BLE] BLE bridge connected - {}:{}", host, port);
                
                phaseStart = System.currentTimeMillis();
                startReader();
                logger.info("[BLE] startReader 完成，耗时={}ms", System.currentTimeMillis() - phaseStart);
                
                phaseStart = System.currentTimeMillis();
                queryBridgeDeviceInfo();
                logger.info("[BLE] queryBridgeDeviceInfo 完成，耗时={}ms", System.currentTimeMillis() - phaseStart);
                
                logger.info("[BLE] === 连接完成，总耗时={}ms ===", System.currentTimeMillis() - startTime);
            } catch (IOException e) {
                isScanning = false;
                isConnected = false;
                cachedStatus.setConnected(false);
                logger.warn("[BLE] BLE bridge connect failed - {}:{}: {}, 总耗时={}ms", 
                    host, port, e.getMessage(), System.currentTimeMillis() - startTime);
                callback.onError("BLE bridge connect failed (" + host + ":" + port + "): " + e.getMessage());
            }
        }, "device-connect").start();
    }
    
    private int connectAttemptCount = 0;
    public void disconnect() {
        resetDisplaySession();
        long startTime = System.currentTimeMillis();
        logger.info("[BLE] === 开始断开连接 ===");
        
        // 第一步：立即标记断开状态，阻止新操作
        long phaseStart = System.currentTimeMillis();
        isConnected = false;
        cachedStatus.setConnected(false);
        cachedStatus.clearFirmwareIdentity();
        logger.info("[BLE] 步骤1: 设置断开状态，耗时={}ms", System.currentTimeMillis() - phaseStart);
        
        // 第二步：唤醒等待响应的线程
        phaseStart = System.currentTimeMillis();
        commandLock.lock();
        try {
            responseReady.signalAll();
        } finally {
            commandLock.unlock();
        }
        logger.info("[BLE] 步骤2: 唤醒等待响应的线程，耗时={}ms", System.currentTimeMillis() - phaseStart);
        
        // 第三步：关闭 USB（会停止其内部 readerThread）
        phaseStart = System.currentTimeMillis();
        try {
            usbTransport.close();
            logger.info("[BLE] 步骤3: USB 传输已关闭，耗时={}ms", System.currentTimeMillis() - phaseStart);
        } catch (Exception e) {
            logger.error("[BLE] 步骤3失败: USB 关闭异常 - {}，耗时={}ms", e.getMessage(), System.currentTimeMillis() - phaseStart, e);
        }
        
        // 第四步：关闭 TCP 连接
        phaseStart = System.currentTimeMillis();
        try {
            closeTcpOnly();
            logger.info("[BLE] 步骤4: TCP 连接已关闭，耗时={}ms", System.currentTimeMillis() - phaseStart);
        } catch (Exception e) {
            logger.error("[BLE] 步骤4失败: TCP 关闭异常 - {}，耗时={}ms", e.getMessage(), System.currentTimeMillis() - phaseStart, e);
        }
        
        // 第五步：通知回调（最后执行，避免回调中访问正在清理的资源）
        phaseStart = System.currentTimeMillis();
        try {
            callback.onDisconnected();
            logger.info("[BLE] 步骤5: 回调通知成功，耗时={}ms", System.currentTimeMillis() - phaseStart);
        } catch (Exception e) {
            logger.error("[BLE] 步骤5失败: 回调异常 - {}，耗时={}ms", e.getMessage(), System.currentTimeMillis() - phaseStart, e);
        }
        
        logger.info("[BLE] === 断开连接完成，总耗时={}ms ===", System.currentTimeMillis() - startTime);
    }

    private void closeTcpOnly() {
        long startTime = System.currentTimeMillis();
        logger.info("[BLE] closeTcpOnly 开始");
        
        try {
            if (readerThread != null) {
                long phaseStart = System.currentTimeMillis();
                readerThread.interrupt();
                // 等待线程退出
                try {
                    readerThread.join(2000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                logger.info("[BLE] readerThread 已中断并等待退出，耗时={}ms", System.currentTimeMillis() - phaseStart);
            }
            
            if (inputStream != null) {
                long phaseStart = System.currentTimeMillis();
                inputStream.close();
                logger.info("[BLE] inputStream 已关闭，耗时={}ms", System.currentTimeMillis() - phaseStart);
            }
            
            if (outputStream != null) {
                long phaseStart = System.currentTimeMillis();
                outputStream.close();
                logger.info("[BLE] outputStream 已关闭，耗时={}ms", System.currentTimeMillis() - phaseStart);
            }
            
            if (socket != null) {
                long phaseStart = System.currentTimeMillis();
                socket.close();
                logger.info("[BLE] socket 已关闭，耗时={}ms", System.currentTimeMillis() - phaseStart);
            }
        } catch (IOException e) {
            logger.warn("[BLE] Close TCP connection failed: {}", e.getMessage());
        } finally {
            inputStream = null;
            outputStream = null;
            socket = null;
            readerThread = null;
        }
        
        logger.info("[BLE] closeTcpOnly 完成，总耗时={}ms", System.currentTimeMillis() - startTime);
    }

    public void sendCommand(byte[] command) throws IOException {
        if (!commandLock.tryLock()) throw new IOException("设备正在处理其他命令。");
        try {
        if (command[2] != AhaKeyProtocol.CMD_QUERY_STATUS && (displayLease != null || displayWriteUncertain))
            throw new IOException("显示配置事务占用或保存结果未确认。");
        if (displayLease != null) {
            checkDisplayTransport();
            if (displayLease.usb) usbTransport.sendCommand(command);
            else writePacket(BleTcpPacket.WRITE_COMMAND, command);
            return;
        }
        logger.debug("发送命令: {}", bytesToHex(command, Math.min(20, command.length)));
        if (ensureUsbConnected()) {
            usbTransport.sendCommand(command);
        } else {
            writePacket(BleTcpPacket.WRITE_COMMAND, command);
        }
        } finally { commandLock.unlock(); }
    }

    private void checkDisplayTransport() throws IOException {
        if (!isConnected || displayLease.generation != connectionGeneration || displayLease.usb != usbTransport.isOpen())
            throw new IOException("键盘连接已改变。");
    }

    public boolean isUsbTransportOpen() {
        return usbTransport.isOpen();
    }

    public void sendCommandExpecting(byte[] command, byte expectedCmd) throws Exception {
        commandLock.lock();
        try {
            pendingNotifyFramesByCommand.clear();
            sendCommand(command);
            waitForResponse(expectedCmd);
        } finally {
            commandLock.unlock();
        }
    }

    public int readSleepWaitTimeMinutes() throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                pendingNotifyFramesByCommand.clear();
                sendCommand(AhaKeyProtocol.querySleepWaitTime());
                byte[] frame = waitForResponse(AhaKeyProtocol.CMD_SLEEP_WAIT_TIME);
                AhaKeyResponseParser.SleepWaitTimeResponse parsed = AhaKeyResponseParser.parseSleepWaitTime(frame);
                if (parsed == null || parsed.minutes() == null) {
                    throw new IOException("无法解析睡眠等待时间响应");
                }
                logger.info("Sleep wait time read: {} minutes", parsed.minutes());
                return parsed.minutes();
            } finally {
                commandLock.unlock();
            }
        }
    }

    public String readFirmwareCatalogKey() throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                pendingNotifyFramesByCommand.clear();
                logger.info("Reading firmware catalog key with command 0x9F");
                sendCommand(AhaKeyProtocol.queryFirmwareCatalogKey());
                byte[] frame = waitForResponseFrame(AhaKeyProtocol.CMD_FIRMWARE_CATALOG_KEY, false);
                String catalogKey = AhaKeyResponseParser.parseFirmwareCatalogKey(frame);
                if (catalogKey == null || catalogKey.isBlank()) {
                    throw new IOException("无法解析键盘固件版本");
                }
                logger.info("Firmware catalog key: {}", catalogKey);
                cachedStatus.setFirmwareCatalogKey(catalogKey);
                callback.onStatusReceived(cachedStatus);
                return catalogKey;
            } finally {
                commandLock.unlock();
            }
        }
    }

    public AhaKeyResponseParser.SideSwitchConfig readSideSwitchConfig() throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                pendingNotifyFramesByCommand.clear();
                logger.info("Reading CP4C side switch config with command 0x97");
                sendCommand(AhaKeyProtocol.readSideSwitchConfig());
                byte[] frame = waitForResponse(AhaKeyProtocol.CMD_SIDE_SWITCH_CONFIG);
                AhaKeyResponseParser.SideSwitchConfig parsed = AhaKeyResponseParser.parseSideSwitchConfig(frame);
                if (parsed == null) {
                    throw new IOException("无法解析侧拨配置回读");
                }
                return parsed;
            } finally {
                commandLock.unlock();
            }
        }
    }

    public void writeSideSwitchConfig(AhaKeyResponseParser.SideSwitchConfig config) throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                pendingNotifyFramesByCommand.clear();
                logger.info("Writing CP4C side switch config with command 0x97");
                sendCommand(AhaKeyProtocol.setSideSwitchConfig(
                    config.up().binding(),
                    config.up().actionPayload(),
                    config.down().binding(),
                    config.down().actionPayload()
                ));
                byte[] frame = waitForResponseFrame(AhaKeyProtocol.CMD_SIDE_SWITCH_CONFIG, false);
                AhaKeyResponseParser.CommandResponse response = AhaKeyResponseParser.parseCommandResponse(frame);
                if (response == null) {
                    throw new IOException("无法解析侧拨配置保存响应");
                }
                if (response.status() != 0) {
                    throw new IOException("侧拨配置保存失败，设备返回错误码 " + (response.status() & 0xFF));
                }
            } finally {
                commandLock.unlock();
            }
        }
    }

    public AhaKeyResponseParser.OrdinaryKeyReadback readOrdinaryKeyConfig(int mode, int keyIndex) throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                pendingNotifyFramesByCommand.clear();
                logger.info("Reading CP4C ordinary key with command 0x87: mode={}, keyIndex={}", mode, keyIndex);
                sendCommand(AhaKeyProtocol.readOrdinaryKeyConfig(mode, keyIndex));
                byte[] frame = waitForResponseFrame(AhaKeyProtocol.CMD_ORDINARY_KEY_READBACK, false);
                AhaKeyResponseParser.CommandResponse response = AhaKeyResponseParser.parseCommandResponse(frame);
                if (response == null) {
                    throw new IOException("无法解析普通键配置回读响应");
                }
                int status = response.status() & 0xFF;
                if (status != AhaKeyProtocol.STATUS_OK) {
                    throw new IOException(ordinaryKeyReadbackStatusMessage(status));
                }
                AhaKeyResponseParser.OrdinaryKeyReadback parsed = AhaKeyResponseParser.parseOrdinaryKeyReadback(frame);
                if (parsed == null) {
                    throw new IOException("无法解析普通键配置回读");
                }
                return parsed;
            } finally {
                commandLock.unlock();
            }
        }
    }

    private String ordinaryKeyReadbackStatusMessage(int status) {
        return switch (status) {
            case AhaKeyProtocol.STATUS_INVALID_PAYLOAD -> "普通键配置读取请求无效";
            case AhaKeyProtocol.STATUS_OUT_OF_RANGE -> "普通键配置读取范围错误或固件中存在不支持的动作类型";
            case AhaKeyProtocol.STATUS_TOO_LARGE -> "该按键配置过长，当前固件不能单包读回；请保留设备端配置或减少宏步骤后再编辑";
            default -> "普通键配置读取失败，设备返回错误码 " + status;
        };
    }

    public int setSleepWaitTimeMinutesAndVerify(int minutes) throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                pendingNotifyFramesByCommand.clear();
                sendCommand(AhaKeyProtocol.setSleepWaitTime(minutes));
                byte[] setFrame = waitForResponseFrame(AhaKeyProtocol.CMD_SLEEP_WAIT_TIME, false);
                AhaKeyResponseParser.CommandResponse setResponse = AhaKeyResponseParser.parseCommandResponse(setFrame);
                if (setResponse == null) {
                    throw new IOException("无法解析睡眠等待时间保存响应");
                }
                if (setResponse.status() != 0) {
                    throw new IOException("睡眠等待时间保存失败: " + sleepWaitTimeStatusMessage(setResponse.status()));
                }

                pendingNotifyFramesByCommand.clear();
                sendCommand(AhaKeyProtocol.querySleepWaitTime());
                byte[] queryFrame = waitForResponse(AhaKeyProtocol.CMD_SLEEP_WAIT_TIME);
                AhaKeyResponseParser.SleepWaitTimeResponse parsed = AhaKeyResponseParser.parseSleepWaitTime(queryFrame);
                if (parsed == null || parsed.minutes() == null) {
                    throw new IOException("无法解析睡眠等待时间回读响应");
                }
                if (parsed.minutes() != minutes) {
                    throw new IOException("睡眠等待时间回读不匹配: 期望 " + minutes + "，实际 " + parsed.minutes());
                }
                return parsed.minutes();
            } finally {
                commandLock.unlock();
            }
        }
    }

    public void writeData(byte[] chunk) throws IOException {
        commandLock.lock();
        try {
        if (displayLease != null || displayWriteUncertain) throw new IOException("显示配置事务占用或保存结果未确认。");
        logger.debug("发送数据块: {} 字节", chunk.length);
        if (ensureUsbConnected()) {
            usbTransport.sendData(chunk);
        } else {
            writePacket(BleTcpPacket.WRITE_DATA, chunk);
        }
        } finally { commandLock.unlock(); }
    }

    public void writeLargeData(long address, byte[] data) throws Exception {
        if (address % AhaKeyProtocol.OLED_CHUNK_SIZE != 0) {
            throw new IllegalArgumentException("地址必须 4K 对齐: " + address);
        }
        commandLock.lock();
        try {
            int offset = 0;
            int totalChunks = (int) Math.ceil((double) data.length / AhaKeyProtocol.OLED_CHUNK_SIZE);
            logger.info("开始写入大数据: 地址={}, 总长度={}, 分块数={}", address, data.length, totalChunks);
            while (offset < data.length) {
                int chunkLen = Math.min(AhaKeyProtocol.OLED_CHUNK_SIZE, data.length - offset);
                long chunkAddr = address + offset;
                byte[] chunk = new byte[chunkLen];
                System.arraycopy(data, offset, chunk, 0, chunkLen);

                logger.debug("写入分块 {}/{}: 地址={}, 长度={}", (offset / AhaKeyProtocol.OLED_CHUNK_SIZE) + 1, totalChunks, chunkAddr, chunkLen);

                pendingNotifyFramesByCommand.clear();
                sendCommand(AhaKeyProtocol.prepareWrite(chunkLen, chunkAddr));
                waitForResponse(AhaKeyProtocol.CMD_PREPARE_WRITE);

                pendingNotifyFramesByCommand.clear();
                writeData(chunk);
                waitForResponse(AhaKeyProtocol.CMD_WRITE_RESULT);

                offset += chunkLen;
            }
            logger.info("大数据写入完成: 地址={}, 总长度={}", address, data.length);
        } finally {
            commandLock.unlock();
        }
    }

    public AhaKeyResponseParser.PictureState readPictureState(int mode) throws Exception {
        commandLock.lock();
        try {
            pendingNotifyFramesByCommand.clear();
            sendCommand(AhaKeyProtocol.readPicState(mode));
            byte[] frame = waitForResponse(AhaKeyProtocol.CMD_READ_PIC_STATE);
            AhaKeyResponseParser.CommandResponse parsed = AhaKeyResponseParser.parseCommandResponse(frame);
            if (parsed == null || parsed.status() != 0) {
                return null;
            }
            return AhaKeyResponseParser.parsePictureState(parsed.payload());
        } finally {
            commandLock.unlock();
        }
    }

    public void queryStatus() {
        try {
            // Coalesce poller/status callers only; explicit approval refresh uses the forced path.
            if (commandLock.isLocked()) return;
            if (isDisplayBusy() && System.nanoTime() - lastOptionalQueryNanos < TimeUnit.SECONDS.toNanos(1)) return;
            lastOptionalQueryNanos = System.nanoTime();
            queryStatusNow();
        } catch (RuntimeException e) { logger.debug("Optional status query skipped: {}", e.getMessage()); }
    }

    private void queryStatusNow() {
        try {
            if (commandLock.isLocked()) {
                return;
            }
            if (ensureUsbConnected()) {
                sendCommand(AhaKeyProtocol.queryDeviceStatus());
                return;
            }
            // 查询BLE连接状态（参考Python版本）
            writePacket(BleTcpPacket.QUERY_BLE_STATUS, null);
            // 查询设备信息
            writePacket(BleTcpPacket.QUERY_DEVICE_INFO, null);
            // 查询设备状态
            writePacket(BleTcpPacket.WRITE_COMMAND, AhaKeyProtocol.queryDeviceStatus());
        } catch (IOException e) {
            callback.onError("查询设备状态失败: " + e.getMessage());
        }
    }

    /**
     * 查询设备实时状态并等待响应刷新缓存，最多等待 {@code timeoutMs} 毫秒。
     * 用于在读取 switchState 之前确保缓存是最新的。
     */
    public void queryStatusAndWait(long timeoutMs) {
        long beforeTs = lastStatusUpdateTime;
        queryStatusNow();
        long deadline = System.currentTimeMillis() + timeoutMs;
        while (lastStatusUpdateTime == beforeTs && System.currentTimeMillis() < deadline) {
            try {
                Thread.sleep(10);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
        if (lastStatusUpdateTime == beforeTs) {
            logger.warn("queryStatusAndWait: {}ms 内未收到设备状态更新，使用缓存值 switchState={}", timeoutMs, cachedStatus.getSwitchState());
        } else {
            logger.debug("queryStatusAndWait: 状态已刷新 switchState={}", cachedStatus.getSwitchState());
        }
    }

    public void updateState(byte state) {
        try {
            sendRuntimeState(state);
        } catch (IOException e) {
            callback.onError("发送状态更新失败: " + e.getMessage());
        }
    }

    public boolean sendRuntimeState(byte state) throws IOException {
        commandLock.lock();
        try {
            if (!isConnected || !cachedStatus.isConnected()) return false;
            deferredRuntimeState = state;
            deferredRuntimeAt = System.nanoTime();
            if (displayLease != null || displayWriteUncertain) return false;
            sendCommand(AhaKeyProtocol.updateState(state));
            deferredRuntimeState = null;
            return true;
        } finally { commandLock.unlock(); }
    }
    private void flushDeferredRuntimeState() {
        commandLock.lock();
        try {
            if (deferredRuntimeState != null && System.nanoTime() - deferredRuntimeAt >= TimeUnit.MINUTES.toNanos(5))
                deferredRuntimeState = null;
            if (displayLease != null || displayWriteUncertain) return;
            if (deferredRuntimeState != null && isConnected && cachedStatus.isConnected()) {
                // Retry the original fact; only a newly received event may advance its TTL.
                sendCommand(AhaKeyProtocol.updateState(deferredRuntimeState));
                deferredRuntimeState = null;
            }
        } catch (IOException e) { logger.debug("Runtime state remains pending: {}", e.getMessage()); }
        finally { commandLock.unlock(); }
    }

    public void setRuntimeDisplayMode(com.example.ahakey.model.AiRuntimeDisplayMode mode) throws Exception {
        setRuntimeDisplayMode(mode, connectionGeneration);
    }

    public void setRuntimeDisplayMode(com.example.ahakey.model.AiRuntimeDisplayMode mode, long generation) throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                if (generation != connectionGeneration) throw new IOException("键盘连接已改变。");
                pendingNotifyFramesByCommand.clear();
                sendCommand(AhaKeyProtocol.setRuntimeDisplayMode(mode));
                waitForResponseFrame(AhaKeyProtocol.CMD_RUNTIME_DISPLAY_MODE, true, false);
                if (generation != connectionGeneration) throw new IOException("键盘连接已改变，展示模式未确认。");
            } finally {
                commandLock.unlock();
            }
        }
    }

    public void sendMultiRuntimeSnapshot(com.example.ahakey.model.AiRuntimeSlotBinding[] slots) throws Exception {
        sendMultiRuntimeSnapshot(slots, connectionGeneration);
    }

    public void sendMultiRuntimeSnapshot(com.example.ahakey.model.AiRuntimeSlotBinding[] slots, long generation) throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                if (generation != connectionGeneration) throw new IOException("键盘连接已改变。");
                pendingNotifyFramesByCommand.clear();
                sendCommand(AhaKeyProtocol.multiRuntimeSnapshot(slots));
                waitForResponseFrame(AhaKeyProtocol.CMD_MULTI_RUNTIME_SNAPSHOT, true, false);
                if (generation != connectionGeneration) throw new IOException("键盘连接已改变。");
            } finally {
                commandLock.unlock();
            }
        }
    }

    public void setLightEffect(byte effectCode) {
        try {
            sendCommand(AhaKeyProtocol.setLightEffect(effectCode));
        } catch (IOException e) {
            callback.onError("发送灯效指令失败: " + e.getMessage());
        }
    }

    public void setLightBrightness(int brightness) {
        try {
            sendCommand(AhaKeyProtocol.setLightBrightness(brightness));
        } catch (IOException e) {
            callback.onError("发送灯光亮度失败: " + e.getMessage());
        }
    }

    public void setAiLightConfig(int mode, byte[] effectCodes) {
        try {
            sendCommand(AhaKeyProtocol.setAiLightConfig(mode, effectCodes));
        } catch (IOException e) {
            callback.onError("发送 AI 状态灯效配置失败: " + e.getMessage());
        }
    }

    public void setWorkMode(int mode) {
        try {
            sendCommand(AhaKeyProtocol.setWorkMode(mode));
        } catch (IOException e) {
            callback.onError("切换键盘模式失败: " + e.getMessage());
        }
    }

    public int setWorkModeAndVerify(int mode) throws Exception {
        int targetMode = Math.max(0, Math.min(3, mode));
        synchronized (commandTransactionLock) {
            long statusVersionBeforeSet = lastStatusUpdateTime;
            commandLock.lock();
            try {
                pendingNotifyFramesByCommand.clear();
                sendCommand(AhaKeyProtocol.setWorkMode(targetMode));
                byte[] setFrame = waitForResponseFrame(AhaKeyProtocol.CMD_SET_WORK_MODE, false, false);
                AhaKeyResponseParser.CommandResponse response = AhaKeyResponseParser.parseCommandResponse(setFrame);
                if (response == null) {
                    throw new IOException("无法解析模式切换响应");
                }
                if (response.status() != 0) {
                    throw new IOException("模式切换失败，设备返回错误码 " + (response.status() & 0xFF));
                }
            } finally {
                commandLock.unlock();
            }

            DeviceStatus readback = waitForWorkModeReadback(targetMode, statusVersionBeforeSet, MODE_READBACK_TIMEOUT_MS);
            int confirmedMode = readback.getWorkMode();
            if (confirmedMode != targetMode) {
                throw new IOException("模式回读不匹配: 期望 Mode " + (targetMode + 1) + "，实际 Mode " + (confirmedMode + 1));
            }
            return confirmedMode;
        }
    }

    private DeviceStatus waitForWorkModeReadback(int targetMode, long statusVersionBeforeSet, long timeoutMs) throws Exception {
        long deadline = System.currentTimeMillis() + timeoutMs;
        long nextRequestAt = 0;
        IOException lastRequestFailure = null;

        while (System.currentTimeMillis() < deadline) {
            DeviceStatus status = cachedStatus;
            if (lastStatusUpdateTime > statusVersionBeforeSet && status != null && status.isConnected()
                    && status.getWorkMode() == targetMode) {
                logger.info("Mode switch readback confirmed from refreshed status: Mode {}", targetMode + 1);
                return status;
            }

            long now = System.currentTimeMillis();
            if (now >= nextRequestAt) {
                try {
                    requestModeReadbackStatus();
                    lastRequestFailure = null;
                } catch (IOException e) {
                    lastRequestFailure = e;
                    logger.debug("Mode switch readback status request failed: {}", e.getMessage());
                }
                nextRequestAt = now + MODE_READBACK_REQUEST_INTERVAL_MS;
            }

            try {
                Thread.sleep(25);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IOException("等待模式回读被中断", e);
            }
        }

        DeviceStatus status = cachedStatus;
        if (lastRequestFailure != null && (!isConnected || status == null || !status.isConnected())) {
            throw lastRequestFailure;
        }
        if (status != null && status.isConnected()) {
            throw new IOException("Mode readback mismatch: expected Mode " + (targetMode + 1)
                    + ", actual Mode " + (status.getWorkMode() + 1));
        }
        throw new IOException("Mode readback timed out for Mode " + (targetMode + 1));
    }

    private void requestModeReadbackStatus() throws IOException {
        if (ensureUsbConnected()) {
            usbTransport.sendCommand(AhaKeyProtocol.queryDeviceStatus());
            return;
        }
        writePacket(BleTcpPacket.QUERY_BLE_STATUS, null);
        writePacket(BleTcpPacket.QUERY_DEVICE_INFO, null);
        writePacket(BleTcpPacket.WRITE_COMMAND, AhaKeyProtocol.queryDeviceStatus());
    }

    public boolean isConnected() {
        return isConnected;
    }

    public boolean isScanning() {
        return isScanning;
    }

    public DeviceStatus getCachedStatus() {
        return cachedStatus;
    }

    public void clearCachedFirmwareIdentity() {
        cachedStatus.clearFirmwareIdentity();
    }

    public boolean isUsbConnected() {
        return usbTransport.isOpen();
    }

    public String selectPreferredTransport() throws IOException {
        if (ensureUsbConnected()) {
            return "USB";
        }
        if (isConnected && outputStream != null) {
            return "BLE";
        }
        throw new IOException("Device is not connected");
    }

    public long getLastStatusUpdateTime() {
        return lastStatusUpdateTime;
    }

    private void queryBridgeDeviceInfo() {
        try {
            if (usbTransport.isOpen()) {
                sendCommand(AhaKeyProtocol.queryDeviceStatus());
                return;
            }
            writePacket(BleTcpPacket.QUERY_BLE_STATUS, null);
        } catch (IOException ignored) {
        }
    }

    private boolean tryConnectUsb() {
        try {
            if (!UsbHidTransport.isPresent()) {
                return false;
            }
            closeTcpOnly();
            resetDisplaySession();
            long generation = connectionGeneration;
            usbTransport.open(data -> onSessionNotify(generation, data));
            isConnected = true;
            isScanning = false;
            cachedStatus.clearFirmwareIdentity();
            cachedStatus.setConnected(true);
            cachedStatus.setDeviceName("AhaKey USB");
            cachedStatus.setBatteryLevel(100);
            callback.onConnected();
            queryBridgeDeviceInfo();
            return true;
        } catch (Exception e) {
            logger.warn("USB HID connect failed: {}", e.getMessage());
            usbTransport.close();
            return false;
        }
    }

    private boolean ensureUsbConnected() {
        if (displayLease != null || displayWriteUncertain || displayReadUncertain) return usbTransport.isOpen();
        if (usbTransport.isOpen()) {
            return true;
        }
        if (!UsbHidTransport.isPresent()) {
            return false;
        }
        try {
            closeTcpOnly();
            resetDisplaySession();
            long generation = connectionGeneration;
            usbTransport.open(data -> onSessionNotify(generation, data));
            isConnected = true;
            isScanning = false;
            cachedStatus.setConnected(true);
            cachedStatus.setDeviceName("AhaKey USB");
            cachedStatus.setBatteryLevel(100);
            callback.onConnected();
            return true;
        } catch (Exception e) {
            logger.warn("USB HID reconnect failed: {}", e.getMessage());
            usbTransport.close();
            return false;
        }
    }
    private void writePacket(byte type, byte[] data) throws IOException {
        if (!isConnected || outputStream == null) {
            throw new IOException("BLE 桥未连接");
        }
        int dataLen = data == null ? 0 : data.length;
        logger.debug("发送 TCP 包: type=0x{}, len={}", Integer.toHexString(type & 0xFF), dataLen);
        synchronized (outputStream) {
            outputStream.write(BleTcpPacket.encode(type, data));
            outputStream.flush();
        }
    }

    private static final long RECONNECT_WAIT_MS = 30000;  // 重连等待时间30秒

    private byte[] waitForResponse(byte expectedCmd) throws Exception {
        return waitForResponseFrame(expectedCmd, true);
    }

    private byte[] waitForResponseFrame(byte expectedCmd, boolean throwOnDeviceError) throws Exception {
        return waitForResponseFrame(expectedCmd, throwOnDeviceError, true);
    }

    private byte[] waitForResponseFrame(byte expectedCmd, boolean throwOnDeviceError, boolean waitForReconnect) throws Exception {
        return waitForResponseFrame(expectedCmd, throwOnDeviceError, waitForReconnect, RESPONSE_TIMEOUT_MS);
    }

    private byte[] waitForResponseFrame(byte expectedCmd, boolean throwOnDeviceError, boolean waitForReconnect, long timeoutMs) throws Exception {
        legacyWaiters++;
        try {
        logger.debug("开始等待响应 0x{}", Integer.toHexString(expectedCmd & 0xFF));
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs);
        
        while (true) {
            // 检查连接状态，如果断开则等待重连
            if (!isConnected) {
                if (!waitForReconnect) {
                    throw new IOException("设备连接中断");
                }
                logger.info("BLE连接断开，等待重连...");
                long reconnectDeadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(RECONNECT_WAIT_MS);
                
                while (!isConnected) {
                    long remaining = reconnectDeadline - System.nanoTime();
                    if (remaining <= 0) {
                        throw new IOException("BLE连接断开，等待重连超时");
                    }
                    responseReady.awaitNanos(Math.min(remaining, TimeUnit.MILLISECONDS.toNanos(100)));
                }
                
                logger.info("BLE重连成功，继续等待响应");
                // 重连后重置响应超时时间
                deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs);
            }
            
            long remaining = deadline - System.nanoTime();
            if (remaining <= 0) {
                throw new IOException("等待设备响应 0x" + Integer.toHexString(expectedCmd & 0xFF) + " 超时");
            }
            Deque<byte[]> frames = pendingNotifyFramesByCommand.get(expectedCmd);
            if (frames != null && !frames.isEmpty()) {
                byte[] frame = frames.removeFirst();
                if (expectedCmd == AhaKeyProtocol.CMD_QUERY_STATUS) {
                    if (AhaKeyProtocol.parseDeviceStatus(frame) == null) {
                        throw new IOException("无法解析设备状态响应帧");
                    }
                    logger.debug("收到期望的状态响应 0x{}", Integer.toHexString(expectedCmd & 0xFF));
                    return frame;
                }
                AhaKeyResponseParser.CommandResponse parsed = AhaKeyResponseParser.parseCommandResponse(frame);
                if (parsed == null) {
                    throw new IOException("无法解析设备响应帧");
                }
                logger.debug("收到期望的响应 0x{}", Integer.toHexString(expectedCmd & 0xFF));
                if (throwOnDeviceError && parsed.status() != 0) {
                    throw new IOException("设备返回错误码 " + parsed.status());
                }
                return frame;
            }
            responseReady.awaitNanos(remaining);
        }
        } finally { legacyWaiters--; responseReady.signalAll(); }
    }

    public DeviceStatus queryDeviceStatusSnapshot(long timeoutMs, boolean failOnDisconnect) throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                pendingNotifyFramesByCommand.clear();
                if (ensureUsbConnected()) {
                    usbTransport.sendCommand(AhaKeyProtocol.queryDeviceStatus());
                } else {
                    writePacket(BleTcpPacket.WRITE_COMMAND, AhaKeyProtocol.queryDeviceStatus());
                }
                byte[] frame = waitForResponseFrame(AhaKeyProtocol.CMD_QUERY_STATUS, true, !failOnDisconnect, timeoutMs);
                DeviceStatus status = AhaKeyProtocol.parseDeviceStatus(frame);
                if (status == null) {
                    throw new IOException("无法解析设备状态回读");
                }
                status.setConnected(true);
                if (cachedStatus.getDeviceName() != null && !cachedStatus.getDeviceName().isBlank()) {
                    status.setDeviceName(cachedStatus.getDeviceName());
                }
                status.setFirmwareCatalogKey(cachedStatus.getFirmwareCatalogKey());
                cachedStatus = status;
                lastStatusUpdateTime = System.currentTimeMillis();
                callback.onStatusReceived(status);
                return status;
            } finally {
                commandLock.unlock();
            }
        }
    }

    private String sleepWaitTimeStatusMessage(byte status) {
        return switch (status) {
            case 1 -> "非法值";
            case 2 -> "固化失败";
            case 3 -> "数据长度错误";
            default -> "设备返回错误码 " + status;
        };
    }

    private void startReader() {
        logger.info("[BLE] startReader 开始创建读取线程");
        final long generation = connectionGeneration;
        final InputStream sessionInput = inputStream;
        readerThread = new Thread(() -> {
            logger.info("[BLE] readerThread 已启动");
            byte[] header = new byte[3];
            try {
                while (isConnected && !Thread.currentThread().isInterrupted()) {
                    if (!readFully(sessionInput, header, 3)) {
                        logger.warn("[BLE] readerThread: 读取头部失败，连接可能已断开");
                        break;
                    }
                    int len = (header[1] & 0xFF) | ((header[2] & 0xFF) << 8);
                    byte[] body = len > 0 ? new byte[len] : new byte[0];
                    if (len > 0 && !readFully(sessionInput, body, len)) {
                        logger.warn("[BLE] readerThread: 读取数据失败，连接可能已断开");
                        break;
                    }
                    if (generation != connectionGeneration) break;
                    handlePacket(header[0], body);
                }
            } catch (IOException e) {
                logger.warn("[BLE] readerThread: 读取异常 - {}", e.getMessage());
                if (isConnected) {
                    callback.onError("BLE 桥连接断开: " + e.getMessage());
                }
            } finally {
                logger.info("[BLE] readerThread: 线程退出，isConnected={}, isInterrupted={}", 
                    isConnected, Thread.currentThread().isInterrupted());
                if (isConnected && Thread.currentThread() == readerThread) {
                    logger.info("[BLE] readerThread: 触发自动断开连接");
                    disconnect();
                }
            }
        }, "ble-tcp-reader");
        readerThread.setDaemon(true);
        readerThread.start();
        logger.info("[BLE] startReader: 读取线程已启动");
    }

    private void handlePacket(byte type, byte[] data) {
        logger.debug("收到 TCP 包: type=0x{}, len={}", Integer.toHexString(type & 0xFF), data == null ? 0 : data.length);
        switch (type) {
            case BleTcpPacket.BLE_NOTIFY -> onBleNotify(data);
            case BleTcpPacket.DEVICE_INFO_RESP -> {
                if (data != null && data.length >= 8) {
                    int battery = data[0] & 0xFF;
                    int firmwareMain = data[2] & 0xFF;
                    int firmwareSub = data[3] & 0xFF;
                    int workMode = data[4] & 0xFF;
                    int switchState = data[6] & 0xFF;
                    
                    // 验证数据有效性
                    boolean isValidBattery = battery >= 0 && battery <= 100;
                    boolean isValidWorkMode = workMode >= 0 && workMode <= 3;
                    
                    logger.info("收到设备信息 - 电量: {}, 工作模式: {}, 拨杆: {}, 有效: {}", 
                        battery, workMode, switchState, isValidBattery && isValidWorkMode);
                    
                    // 更新最后状态更新时间
                    lastStatusUpdateTime = System.currentTimeMillis();
                    
                    // 更新缓存状态
                    cachedStatus.setBatteryLevel(battery);
                    cachedStatus.setFirmwareMain(firmwareMain);
                    cachedStatus.setFirmwareSub(firmwareSub);
                    cachedStatus.setWorkMode(workMode);
                    cachedStatus.setSwitchState(switchState);
                    
                    // 如果数据有效，确保标记为已连接
                    if (isValidBattery && isValidWorkMode) {
                        cachedStatus.setConnected(true);
                        cachedStatus.setDeviceName("AhaKey Keyboard");
                    }
                    
                    callback.onStatusReceived(cachedStatus);
                }
            }
            case BleTcpPacket.BLE_STATUS_RESP -> {
                if (data != null && data.length > 0) {
                    // 解析BLE状态响应（参考Python的parse_status_response）
                    // 格式: [connected:1][name_len:1][name:N][mac_len:1][mac:N][is_target:1]
                    boolean bleConnected = (data[0] & 0xFF) == 1;
                    String deviceName = "";
                    
                    if (data.length >= 3) {
                        int nameLen = data[1] & 0xFF;
                        if (nameLen > 0 && data.length >= 2 + nameLen) {
                            deviceName = new String(data, 2, nameLen);
                        }
                    }
                    
                    logger.info("BLE状态响应 - 连接: {}, 设备名: {}", bleConnected, deviceName.isEmpty() ? "(empty)" : deviceName);
                    
                    lastStatusUpdateTime = System.currentTimeMillis();
                    
                    boolean wasConnected = cachedStatus.isConnected();
                    cachedStatus.setConnected(bleConnected);
                    cachedStatus.setDeviceName(bleConnected ? deviceName : "");
                    
                    // 如果是从断开变为连接，通知回调
                    if (bleConnected && !wasConnected) {
                        callback.onConnected();
                    }
                    
                    // 如果是从连接变为断开，更新状态并唤醒等待线程
                    if (!bleConnected && wasConnected) {
                        isConnected = false;
                        resetDisplaySession();
                        commandLock.lock();
                        try {
                            responseReady.signalAll();
                        } finally {
                            commandLock.unlock();
                        }
                    }
                    
                    callback.onStatusReceived(cachedStatus);
                }
            }
            default -> {
            }
        }
    }

    private void onBleNotify(byte[] data) {
        logger.debug("收到 BLE NOTIFY 通知，数据长度: {}", data.length);
        lastStatusUpdateTime = System.currentTimeMillis();
        
        // 打印前16字节的十六进制数据
        StringBuilder hex = new StringBuilder();
        for (int i = 0; i < Math.min(data.length, 16); i++) {
            hex.append(String.format("%02X ", data[i]));
        }
        logger.debug("数据内容(前16字节): {}", hex);

        List<byte[]> frames = reassembleNotifyFrames(data);
        if (frames.isEmpty()) {
            logger.debug("BLE notify 分片已缓存，等待完整帧");
            return;
        }
        for (byte[] frame : frames) {
            processNotifyFrame(frame);
        }
    }

    private void onSessionNotify(long generation, byte[] data) {
        commandLock.lock();
        try { if (generation == connectionGeneration) onBleNotify(data); }
        finally { commandLock.unlock(); }
    }

    private List<byte[]> reassembleNotifyFrames(byte[] data) {
        List<byte[]> frames = new ArrayList<>();
        if (data == null || data.length == 0) {
            return frames;
        }

        synchronized (notifyReassemblyBuffer) {
            if (data.length > notifyReassemblyBuffer.length - notifyReassemblyLength) {
                logger.warn("BLE notify 重组缓冲区溢出，丢弃未完成分片");
                notifyReassemblyLength = 0;
            }
            if (data.length > notifyReassemblyBuffer.length) {
                logger.warn("BLE notify 单片过长，无法重组: {} bytes", data.length);
                return frames;
            }

            System.arraycopy(data, 0, notifyReassemblyBuffer, notifyReassemblyLength, data.length);
            notifyReassemblyLength += data.length;

            while (true) {
                int start = findFrameStart(notifyReassemblyBuffer, notifyReassemblyLength);
                if (start < 0) {
                    boolean trailingHeader = notifyReassemblyLength > 0 && notifyReassemblyBuffer[notifyReassemblyLength - 1] == (byte) 0xAA;
                    notifyReassemblyLength = trailingHeader ? 1 : 0;
                    if (trailingHeader) notifyReassemblyBuffer[0] = (byte) 0xAA;
                    return frames;
                }
                if (start > 0) {
                    shiftNotifyBuffer(start);
                }

                int end = findFrameEnd(notifyReassemblyBuffer, notifyReassemblyLength);
                if (end < 0) {
                    return frames;
                }

                byte[] frame = Arrays.copyOfRange(notifyReassemblyBuffer, 0, end + 2);
                frames.add(frame);
                shiftNotifyBuffer(end + 2);
            }
        }
    }

    private boolean startsWithFrameHeader(byte[] data) {
        return data.length >= 2 && data[0] == (byte) 0xAA && data[1] == (byte) 0xBB;
    }

    private int findFrameStart(byte[] buffer, int len) {
        for (int i = 0; i + 1 < len; i++) {
            if (buffer[i] == (byte) 0xAA && buffer[i + 1] == (byte) 0xBB) {
                return i;
            }
        }
        return -1;
    }

    private int findFrameEnd(byte[] buffer, int len) {
        int fixed = AhaKeyResponseParser.displayReplyLength(buffer, 0, len);
        if (fixed > 0) return fixed - 2;
        if (fixed != -1) return -1;
        for (int i = 3; i + 1 < len; i++) {
            if (buffer[i] == (byte) 0xCC && buffer[i + 1] == (byte) 0xDD) {
                return i;
            }
        }
        return -1;
    }

    private void shiftNotifyBuffer(int consumed) {
        if (consumed >= notifyReassemblyLength) {
            notifyReassemblyLength = 0;
            return;
        }
        int remaining = notifyReassemblyLength - consumed;
        System.arraycopy(notifyReassemblyBuffer, consumed, notifyReassemblyBuffer, 0, remaining);
        notifyReassemblyLength = remaining;
    }

    private void processNotifyFrame(byte[] data) {
        int opcode = data.length > 2 ? data[2] & 255 : -1;
        if (opcode == 0x88 || opcode == 0x89 || opcode == 0x8A || opcode == 0x8B || opcode == 0x8C || opcode == 0x8E) {
            commandLock.lock();
            try {
                if (displayLease != null && displayLease.generation == connectionGeneration && displayExpected == data[2]) {
                    displayReply = data.clone();
                    responseReady.signalAll();
                }
            } finally { commandLock.unlock(); }
            return;
        }
        if (!AhaKeyProtocol.isValidFrame(data)) {
            logger.warn("无效的帧格式 - isValidFrame 返回 false");
            // 检查帧头帧尾
            if (data.length >= 4) {
                logger.debug("帧头: {}, 帧尾: {}", 
                    String.format("%02X%02X", data[0], data[1]),
                    String.format("%02X%02X", data[data.length-2], data[data.length-1]));
            }
            return;
        }
        DeviceStatus status = AhaKeyProtocol.parseDeviceStatus(data);
        if (status != null) {
            logger.info("解析到设备状态 - 电量: {}, 工作模式: {}, 拨杆状态: {}", 
                status.getBatteryLevel(), 
                status.getWorkMode(), 
                status.getSwitchState());
            if (usbTransport.isOpen()) {
                status.setDeviceName("AhaKey USB");
            } else if (cachedStatus.getDeviceName() != null && !cachedStatus.getDeviceName().isBlank()) {
                status.setDeviceName(cachedStatus.getDeviceName());
            }
            status.setFirmwareCatalogKey(cachedStatus.getFirmwareCatalogKey());
            status.setConnected(true);
            cachedStatus = status;
            enqueueNotifyFrame(data);
            callback.onStatusReceived(status);
            return;
        }
        logger.debug("parseDeviceStatus 返回 null");

        enqueueNotifyFrame(data);
    }

    private void enqueueNotifyFrame(byte[] data) {
        commandLock.lock();
        try {
            byte receivedCmd = data[2];
            Deque<byte[]> frames = pendingNotifyFramesByCommand.computeIfAbsent(receivedCmd, ignored -> new ArrayDeque<>());
            frames.addLast(data);
            while (frames.size() > 16) {
                frames.removeFirst();
            }
            responseReady.signalAll();
            logger.debug("收到响应 0x{}，唤醒等待线程", Integer.toHexString(receivedCmd & 0xFF));
        } finally {
            commandLock.unlock();
        }
    }

    private static String bytesToHex(byte[] bytes, int len) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < len; i++) {
            sb.append(String.format("%02X", bytes[i]));
        }
        return sb.toString();
    }

    private static boolean readFully(InputStream in, byte[] buf, int len) throws IOException {
        int read = 0;
        while (read < len) {
            int n = in.read(buf, read, len - read);
            if (n < 0) {
                return false;
            }
            read += n;
        }
        return true;
    }
}

