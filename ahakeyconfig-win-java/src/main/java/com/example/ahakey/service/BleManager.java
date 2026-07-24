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
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;

public class BleManager {
    private static final Logger logger = LoggerFactory.getLogger(BleManager.class);
    private static final String DEFAULT_HOST = "127.0.0.1";
    private static final int DEFAULT_PORT = 9000;
    private static final long RESPONSE_TIMEOUT_MS = 15000;

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
    private volatile byte[] pendingNotifyFrame;

    private volatile boolean isConnected;
    private volatile boolean isScanning;
    private DeviceStatus cachedStatus = new DeviceStatus();
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
                logger.info("[BLE] Socket连接成功，耗时={}ms", System.currentTimeMillis() - phaseStart);
                
                isConnected = true;
                isScanning = false;
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
        long startTime = System.currentTimeMillis();
        logger.info("[BLE] === 开始断开连接 ===");
        
        // 第一步：立即标记断开状态，阻止新操作
        long phaseStart = System.currentTimeMillis();
        isConnected = false;
        cachedStatus.setConnected(false);
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
        logger.debug("发送命令: {}", bytesToHex(command, Math.min(20, command.length)));
        if (ensureUsbConnected()) {
            usbTransport.sendCommand(command);
        } else {
            writePacket(BleTcpPacket.WRITE_COMMAND, command);
        }
    }

    public void sendCommandExpecting(byte[] command, byte expectedCmd) throws Exception {
        commandLock.lock();
        try {
            pendingNotifyFrame = null;
            sendCommand(command);
            waitForResponse(expectedCmd);
        } finally {
            commandLock.unlock();
        }
    }

    public void writeData(byte[] chunk) throws IOException {
        logger.debug("发送数据块: {} 字节", chunk.length);
        if (ensureUsbConnected()) {
            usbTransport.sendData(chunk);
        } else {
            writePacket(BleTcpPacket.WRITE_DATA, chunk);
        }
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

                pendingNotifyFrame = null;
                sendCommand(AhaKeyProtocol.prepareWrite(chunkLen, chunkAddr));
                waitForResponse(AhaKeyProtocol.CMD_PREPARE_WRITE);

                pendingNotifyFrame = null;
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
            pendingNotifyFrame = null;
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
        queryStatus();
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
            sendCommand(AhaKeyProtocol.updateState(state));
        } catch (IOException e) {
            callback.onError("发送状态更新失败: " + e.getMessage());
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

    public boolean isConnected() {
        return isConnected;
    }

    public boolean isScanning() {
        return isScanning;
    }

    public DeviceStatus getCachedStatus() {
        return cachedStatus;
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
            usbTransport.open(this::onBleNotify);
            isConnected = true;
            isScanning = false;
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
        if (usbTransport.isOpen()) {
            return true;
        }
        if (!UsbHidTransport.isPresent()) {
            return false;
        }
        try {
            closeTcpOnly();
            usbTransport.open(this::onBleNotify);
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
        logger.debug("开始等待响应 0x{}", Integer.toHexString(expectedCmd & 0xFF));
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(RESPONSE_TIMEOUT_MS);
        
        while (true) {
            // 检查连接状态，如果断开则等待重连
            if (!isConnected) {
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
                deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(RESPONSE_TIMEOUT_MS);
            }
            
            long remaining = deadline - System.nanoTime();
            if (remaining <= 0) {
                throw new IOException("等待设备响应 0x" + Integer.toHexString(expectedCmd & 0xFF) + " 超时");
            }
            if (pendingNotifyFrame != null) {
                byte[] frame = pendingNotifyFrame;
                pendingNotifyFrame = null;
                AhaKeyResponseParser.CommandResponse parsed = AhaKeyResponseParser.parseCommandResponse(frame);
                if (parsed == null) {
                    throw new IOException("无法解析设备响应帧");
                }
                if (parsed.cmd() == expectedCmd) {
                    logger.debug("收到期望的响应 0x{}", Integer.toHexString(expectedCmd & 0xFF));
                    if (parsed.status() != 0) {
                        throw new IOException("设备返回错误码 " + parsed.status());
                    }
                    return frame;
                }
                logger.debug("收到不匹配的响应 0x{}，期望 0x{}，继续等待", 
                    Integer.toHexString(parsed.cmd() & 0xFF),
                    Integer.toHexString(expectedCmd & 0xFF));
            }
            responseReady.awaitNanos(remaining);
        }
    }

    private void startReader() {
        logger.info("[BLE] startReader 开始创建读取线程");
        readerThread = new Thread(() -> {
            logger.info("[BLE] readerThread 已启动");
            byte[] header = new byte[3];
            try {
                while (isConnected && !Thread.currentThread().isInterrupted()) {
                    if (!readFully(inputStream, header, 3)) {
                        logger.warn("[BLE] readerThread: 读取头部失败，连接可能已断开");
                        break;
                    }
                    int len = (header[1] & 0xFF) | ((header[2] & 0xFF) << 8);
                    byte[] body = len > 0 ? new byte[len] : new byte[0];
                    if (len > 0 && !readFully(inputStream, body, len)) {
                        logger.warn("[BLE] readerThread: 读取数据失败，连接可能已断开");
                        break;
                    }
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
            status.setConnected(true);
            cachedStatus = status;
            callback.onStatusReceived(status);
            return;
        }
        logger.debug("parseDeviceStatus 返回 null");

        commandLock.lock();
        try {
            pendingNotifyFrame = data;
            responseReady.signalAll();
            byte receivedCmd = data[2];
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

