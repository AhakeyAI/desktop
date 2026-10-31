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
    private final com.example.ahakey.firmware.FirmwareCatalog firmwareCatalog = new com.example.ahakey.firmware.FirmwareCatalog();
    private volatile FirmwareIdentity exactCatalogIdentity;
    public com.example.ahakey.firmware.FirmwareCatalog firmwareCatalog() { return firmwareCatalog; }
    public boolean isFirmwareCapabilityAdmitted(String capability) {
        FirmwareIdentity identity = firmwareIdentity;
        return isConnected && cachedStatus.isConnected() && isCurrentIdentity(identity)
                && (isDisplayAdmitted() || identity == exactCatalogIdentity)
                && firmwareCatalog.capabilities(identity.catalogKey()).contains(capability);
    }
    private final com.example.ahakey.firmware.DeviceMaintenanceCoordinator maintenance = new com.example.ahakey.firmware.DeviceMaintenanceCoordinator();
    public com.example.ahakey.firmware.DeviceMaintenanceCoordinator maintenance() { return maintenance; }
    public com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Operation beginMaintenance(
            com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Identity identity, String hash, String profile, boolean install) throws IOException {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                if (isScanning || wireExpected>=0 || displayLease != null || legacyWaiters != 0 || displayWriteUncertain || displayReadUncertain)
                    throw new IOException("设备事务未结束或结果未确认，请先重新连接并同步。");
                if (!install && (identity == null || identity.generation() != connectionGeneration || !isConnected || !usbTransport.isOpen()
                        || !java.util.Objects.equals(identity.devicePath(), usbTransport.devicePath()))) throw new IOException("请先连接并确认唯一 USB 键盘。");
                var op = maintenance.begin(identity, hash, profile, install);
                deferredRuntimeState = null; pendingNotifyFramesByCommand.clear();
                return op;
            } finally { commandLock.unlock(); }
        }
    }
    public String usbDevicePath() { return usbTransport.devicePath(); }
    public com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Operation beginBootMaintenance(
            com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Identity observed,String hash,String profile)throws IOException {
        synchronized(commandTransactionLock) {
            commandLock.lock();
            try {
                if(isScanning||wireExpected>=0||displayLease!=null||legacyWaiters!=0||k1RouteOwner!=null||displayWriteUncertain||displayReadUncertain)
                    throw new IOException("设备事务未结束，请稍后重新检测下载设备。");
                if(observed.port().isBlank()||!observed.devicePath().toUpperCase(java.util.Locale.ROOT).startsWith("USB\\VID_4348&PID_55E0\\"))throw new IOException("下载目标身份无效。");
                var source=new com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Identity(connectionGeneration,"USB",observed.devicePath(),"",observed.port(),"");
                var operation=maintenance.begin(source,hash,profile,false);
                deferredRuntimeState=null;pendingNotifyFramesByCommand.clear();return operation;
            } finally {commandLock.unlock();}
        }
    }
    protected List<UsbHidTransport.MaintenanceDevice> observeMaintenanceDevices() throws Exception { return UsbHidTransport.maintenanceDevices(); }
    private void sendUsbCommand(byte[] frame) throws IOException {
        commandLock.lock();
        try { maintenance.admitFrame(frame, connectionGeneration);
            if (maintenance.normalAllowed()) firmwareExchange(frame,false,frame[2]&255);
            else usbTransport.sendCommand(frame); }
        finally { commandLock.unlock(); }
    }
    public void maintenanceDisconnect(com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Operation op) throws Exception {
        maintenance.within(op, () -> { disconnectInternal(); return null; });
    }
    public void maintenanceReconnect(com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Operation op,
            com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Identity observed) throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                if (maintenance.current() != op || op.stage() != com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Stage.RECONNECT
                        || !op.source().samePhysicalDevice(observed)) throw new IOException("重连设备身份不匹配。");
                resetDisplaySession();
                long generation = connectionGeneration;
                var candidates = observeMaintenanceDevices();
                if (candidates.size() != 1 || candidates.get(0).download()
                        || !candidates.get(0).container().equalsIgnoreCase(observed.container())
                        || !candidates.get(0).port().equalsIgnoreCase(observed.port())) throw new IOException("USB 目标已改变。");
                usbTransport.openExact(observed.devicePath(), data -> onSessionNotify(generation, data));
                var after = observeMaintenanceDevices();
                if (after.size() != 1 || !after.get(0).ownsHidPath(usbTransport.devicePath())
                        || !after.get(0).container().equalsIgnoreCase(observed.container()) || !after.get(0).port().equalsIgnoreCase(observed.port())) {
                    usbTransport.close(); throw new IOException("打开期间 USB 身份改变。");
                }
                isConnected = true; cachedStatus.setConnected(true);
                maintenance.bindReconnection(op, new com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Identity(generation,
                        "USB", usbTransport.devicePath(), observed.container(), observed.port(), ""));
            } finally { commandLock.unlock(); }
        }
    }
    public boolean requestApplicationExit(com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Operation installation) {
        return maintenance.requestExit(installation);
    }
    public void shutdownTransport() { connectionIntent.incrementAndGet();disconnectInternal();closeManagedBridge(); }

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
    private volatile UsbHidTransport usbTransport = new UsbHidTransport();

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
    public record FirmwareIdentity(long generation, long ticket, DeviceStatus.IdentityState state, String catalogKey) {}
    private volatile FirmwareIdentity firmwareIdentity = new FirmwareIdentity(0, 0, DeviceStatus.IdentityState.DISCONNECTED, "");
    public FirmwareIdentity firmwareIdentity() { return firmwareIdentity; }
    public boolean isCurrentIdentity(FirmwareIdentity identity) {
        return identity == firmwareIdentity && identity.generation() == connectionGeneration;
    }
    private DisplayLease displayLease;
    private byte[] displayReply;
    private byte displayExpected;
    private int legacyWaiters;
    private Thread k1RouteOwner;
    private volatile byte[] k1ReplyRequest;

    public <T> T k1RouteTransaction(long generation, com.example.ahakey.firmware.DeviceMaintenanceCoordinator.Task<T> task) throws Exception {
        boolean released=false;
        try (var normal = maintenance.normalTransaction()) {
            synchronized (commandTransactionLock) {
                commandLock.lockInterruptibly();
                try {
                    if (generation != connectionGeneration || !isConnected || !cachedStatus.isConnected()
                            || displayLease != null || displayWriteUncertain || legacyWaiters != 0 || k1RouteOwner != null)
                        throw new IOException("K1事务不可用或连接已改变。");
                    k1RouteOwner = Thread.currentThread();
                    T result = task.run();
                    if (generation != connectionGeneration) throw new IOException("K1连接已改变。");
                    return result;
                } finally { if(k1RouteOwner==Thread.currentThread()){k1RouteOwner=null;released=true;}commandLock.unlock(); }
            }
        } finally { if(released)notifyDisplayIdle(); }
    }
    public byte[] exchangeK1Route(byte[] frame, long generation) throws Exception {
        if (k1RouteOwner != Thread.currentThread() || generation != connectionGeneration
                || frame == null || frame.length > 62 || frame.length < 7 || frame[2] != (byte)0x9E)
            throw new IOException("K1事务权限无效。");
        pendingNotifyFramesByCommand.clear();
        synchronized(notifyReassemblyBuffer){notifyReassemblyLength=0;}
        k1ReplyRequest=frame.clone();
        try {
            sendCommand(frame);
            byte[] reply = waitForResponseFrame((byte)0x9E, false, false);
            if (generation != connectionGeneration) throw new IOException("K1连接已改变。");
            return reply;
        } finally { k1ReplyRequest=null; }
    }
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
        try { if (generation == connectionGeneration) requireDeviceRecovery(); }
        finally { commandLock.unlock(); }
    }
    public boolean isDisplayBusy() { commandLock.lock(); try { return displayLease != null; } finally { commandLock.unlock(); } }
    public boolean isDisplayAdmitted() {
        FirmwareIdentity identity = firmwareIdentity;
        return isConnected && cachedStatus.isConnected() && isCurrentIdentity(identity)
                && identity.state() == DeviceStatus.IdentityState.SUPPORTED;
    }
    private void publishIdentity(DeviceStatus.IdentityState state, String key) {
        exactCatalogIdentity = null;
        firmwareIdentity = new FirmwareIdentity(connectionGeneration, firmwareIdentity.ticket() + 1, state, key);
        cachedStatus.setFirmwareCatalogKey(key);
        cachedStatus.setIdentityState(state);
    }
    private void requireCapability() throws IOException {
        if (!isDisplayAdmitted()) throw new IOException("当前连接尚未识别到支持的固件版本。");
    }

    private void resetDisplaySession() {
        commandLock.lock();
        try {
            connectionGeneration++;
            wireExpected=-1;wireReply=null;wireSerial++;responseReady.signalAll();
            cachedStatus.clearSavedBindings();
            publishIdentity(DeviceStatus.IdentityState.DISCONNECTED, "");
            displayWriteUncertain = false;
            displayReadUncertain = false;
            displayReply = null;
            k1ReplyRequest = null;
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
            maintenance.admit(writing ? 0x8E : 0x88, connectionGeneration);
            if (expectedGeneration != connectionGeneration) throw new IOException("键盘连接已改变。");
            if (!isConnected || !cachedStatus.isConnected()) throw new IOException("键盘连接已断开。");
            if (displayLease != null || legacyWaiters != 0 || k1RouteOwner != null) throw new IOException("设备正在处理其他事务。");
            if (writing && ((!isDisplayAdmitted() && !isFirmwareCapabilityAdmitted("lights")) || displayWriteUncertain))
                throw new IOException(displayWriteUncertain ? "设备保存结果未确认，请重新连接后同步。" : "当前连接尚未识别到支持的固件版本。");
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
            maintenance.admitFrame(request, connectionGeneration);
            int opcode = request[2] & 255;
            boolean lighting = (opcode == 0x88 || opcode == 0x8E) && request.length >= 6 && (request[3] & 255) <= 1;
            boolean admitted = isDisplayAdmitted() || (lighting && isFirmwareCapabilityAdmitted("lights"));
            if (!admitted) throw new IOException("当前 catalog 未声明此项能力。");
            if (opcode != 0x88 && opcode != 0x89 && opcode != 0x8A && opcode != 0x8B && opcode != 0x8C && opcode != 0x8E)
                throw new IllegalArgumentException("CP2 opcode");
            if (opcode != 0x88 && (!lease.writing || displayWriteUncertain || !admitted)) throw new IOException("显示配置写入未准入。");
            if (opcode == 0x88 && displayReadUncertain) throw new IOException("读取结果未确认，请重新连接。");
            displayExpected = request[2];
            displayReply = null;
            sent = true;
            outcome = "WRITE_ATTEMPTED_UNKNOWN";
            if (lease.usb) sendUsbCommand(request);
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

    private final com.example.ahakey.service.connection.ManagedBridgeClient managedBridge = new com.example.ahakey.service.connection.ManagedBridgeClient();
    private volatile com.example.ahakey.model.connection.DeviceTarget activeTarget;
    private volatile String bridgeSession = "";
    private volatile String bridgeSnapshot = "";
    private final java.util.concurrent.atomic.AtomicLong connectionIntent = new java.util.concurrent.atomic.AtomicLong();
    private final com.example.ahakey.service.connection.DeviceRecoveryRegistry recoveryTargets = new com.example.ahakey.service.connection.DeviceRecoveryRegistry(java.nio.file.Path.of(System.getProperty("user.home"),".ahakey","device-recovery.json"));
    private final ThreadLocal<Boolean> recoveryProbe=ThreadLocal.withInitial(()->false);
    private volatile long lastBleObservation;
    private void quarantine(String identity){try{recoveryTargets.require(identity);}catch(IOException failure){logger.error("设备恢复记录写入失败，当前会话继续禁止写入",failure);}}

    private final java.util.concurrent.ExecutorService transportIo = java.util.concurrent.Executors.newCachedThreadPool(r -> { var t=new Thread(r,"device-io");t.setDaemon(true);return t; });
    private final java.util.concurrent.ExecutorService transitions = java.util.concurrent.Executors.newSingleThreadExecutor(r -> {var t=new Thread(r,"device-transitions");t.setDaemon(true);return t;});
    private java.util.concurrent.CompletableFuture<Void> bridgeRelease = java.util.concurrent.CompletableFuture.completedFuture(null);
    private Object bridgeReleaseOwner;
    private java.util.concurrent.ScheduledExecutorService discovery;
    private java.util.Set<String> previousUsb = java.util.Set.of();
    private final java.util.concurrent.ConcurrentMap<String,String> usbAttachments=new java.util.concurrent.ConcurrentHashMap<>();
    private volatile java.util.function.Function<List<com.example.ahakey.model.connection.DeviceTarget>,java.util.concurrent.CompletableFuture<com.example.ahakey.model.connection.DeviceTarget>> selector = candidates ->
        candidates.size()==1 ? java.util.concurrent.CompletableFuture.completedFuture(candidates.get(0)) : java.util.concurrent.CompletableFuture.failedFuture(new IOException("请在主界面选择目标设备"));
    public String targetIdentity() { var target=activeTarget; return target==null?"":target.key(); }
    public String draftIdentity() {
        var target=activeTarget;if(target==null)return "";
        return target.transport().equals("USB") ? target.key()+"#"+usbAttachments.computeIfAbsent(target.id(),id->java.util.UUID.randomUUID().toString()) : target.key();
    }
    protected void observeUsbCandidates(java.util.Set<String> now)throws IOException {
        var added=new java.util.HashSet<>(now);added.removeAll(previousUsb);previousUsb=java.util.Set.copyOf(now);
        usbAttachments.keySet().removeIf(id->!now.contains(id));
        recoveryTargets.observe("USB",now);
        var target=activeTarget;
        if(!maintenance.normalAllowed() || !isConnected || target==null)return;
        if(target.transport().equals("USB") && !now.contains(target.id())) { disconnect(); return; }
        if(added.size()==1 && !(target.transport().equals("USB")&&added.contains(target.id())))connectSelected(new com.example.ahakey.model.connection.DeviceTarget("USB",added.iterator().next(),"AhaKey USB"));
    }
    public void setTargetSelector(java.util.function.Function<List<com.example.ahakey.model.connection.DeviceTarget>,java.util.concurrent.CompletableFuture<com.example.ahakey.model.connection.DeviceTarget>> value) { selector=value; }
    protected UsbHidTransport createUsbTransport(){return new UsbHidTransport();}
    private void usbSessionTerminated(UsbHidTransport source,long generation){
        commandLock.lock();
        try{
            if(source!=usbTransport || generation!=connectionGeneration || activeTarget==null || !activeTarget.transport().equals("USB"))return;
            // A dead reader invalidates attachment identity, but is not evidence of physical absence.
            usbAttachments.remove(activeTarget.id());
            connectionIntent.incrementAndGet();isScanning=false;
            disconnectInternal();
            if(callback!=null)callback.onError("USB连接已中断，请重新点击连接；旧键盘草稿已保留，重新连接后读取设备配置。");
        }finally{commandLock.unlock();}
    }
    protected List<String> usbCandidates() { return UsbHidTransport.configurationPaths(); }
    protected void pollUsbCandidates()throws IOException { observeUsbCandidates(new java.util.HashSet<>(usbCandidates())); }
    public void startBackgroundDiscovery() {
        if(discovery!=null)return;
        managedBridge.onEvent(this::managedEvent);
        discovery=java.util.concurrent.Executors.newSingleThreadScheduledExecutor(r->{var t=new Thread(r,"device-observer");t.setDaemon(true);return t;});
        transportIo.execute(()->{try{managedBridge.start();}catch(Exception e){logger.info("后台桥尚未就绪：{}",e.getMessage());}});
        try{previousUsb=new java.util.HashSet<>(usbCandidates());}catch(RuntimeException failure){logger.debug("初始USB枚举未完成",failure);}
        discovery.scheduleWithFixedDelay(()->{
            try {
                pollUsbCandidates();
                if(managedBridge.running() && !isScanning && System.nanoTime()-lastBleObservation>TimeUnit.SECONDS.toNanos(2)) {
                    lastBleObservation=System.nanoTime();
                    transportIo.execute(()->{try{
                        var response=managedBridge.request("enumerateConnected",com.example.ahakey.service.connection.ManagedBridgeClient.fields().put("observationOnly",true),5000);
                        var present=new java.util.HashSet<String>();for(var item:response.path("candidates"))present.add(item.path("targetId").asText());
                        recoveryTargets.observe("BLE",present);
                    }catch(Exception failure){logger.debug("BLE离线观察未确认",failure);}});
                }
            }catch(Exception e){logger.debug("设备发现失败",e);}
        },500,500,TimeUnit.MILLISECONDS);
    }
    private void managedEvent(com.fasterxml.jackson.databind.JsonNode event) {
        if("bridgeDisconnected".equals(event.path("event").asText())) {
            if(activeTarget!=null && activeTarget.transport().equals("BLE"))disconnect();return;
        }
        long eventGeneration=event.path("clientGeneration").asLong(-1);
        if(!bridgeSession.equals(event.path("sessionId").asText()) || !Long.toString(connectionGeneration).equals(event.path("clientGeneration").asText()))return;
        if("sessionDisconnected".equals(event.path("event").asText())) {
            disconnect();return;
        }
        if("notify".equals(event.path("event").asText())) {
            try { onSessionNotify(eventGeneration,java.util.Base64.getDecoder().decode(event.path("bytes").asText())); }
            catch(IllegalArgumentException e){logger.warn("桥通知编码无效");}
        }
    }
    public void connect() {
        if(!maintenance.normalAllowed() || isScanning)return;
        long intent=connectionIntent.incrementAndGet();isScanning=true;
        transportIo.execute(()->{
            try {
                var candidates=new ArrayList<com.example.ahakey.model.connection.DeviceTarget>();
                for(String path:usbCandidates())candidates.add(new com.example.ahakey.model.connection.DeviceTarget("USB",path,"AhaKey USB"));
                if(candidates.isEmpty()) {
                    managedBridge.onEvent(this::managedEvent);managedBridge.start();
                    var reply=managedBridge.request("enumerateConnected",5000);bridgeSnapshot=reply.path("snapshotId").asText();
                    for(var item:reply.path("candidates"))candidates.add(new com.example.ahakey.model.connection.DeviceTarget("BLE",item.path("targetId").asText(),item.path("name").asText()));
                }
                if(candidates.isEmpty())throw new IOException("没有可用设备，请插入USB或先在Windows中连接AhaKey蓝牙。");
                var chosen=selector.apply(List.copyOf(candidates)).get();
                if(intent!=connectionIntent.get())return;
                if(chosen!=null) transitions.submit(()->{openSelected(chosen,intent);return null;}).get();
            }catch(Exception e){if(intent==connectionIntent.get())callback.onError("连接未完成："+e.getMessage());}
            finally{if(intent==connectionIntent.get())isScanning=false;}
        });
    }
    public void connectSelected(com.example.ahakey.model.connection.DeviceTarget target) {
        if(!maintenance.normalAllowed())return;
        long intent=connectionIntent.incrementAndGet();isScanning=true;
        transitions.execute(()->{try{openSelected(target,intent);}catch(Exception e){if(intent==connectionIntent.get())callback.onError(e.getMessage());}finally{if(intent==connectionIntent.get())isScanning=false;}});
    }
    private void openSelected(com.example.ahakey.model.connection.DeviceTarget target,long intent) throws Exception {
        long generation;
        java.util.concurrent.CompletableFuture<Void> release;
        Object releaseOwner;
        UsbHidTransport openedUsb = createUsbTransport();
        String openedSession = "";
        commandLock.lock();
        try {
            // The intent check and revocation are one transition: an obsolete queued attempt has no rights.
            if(intent!=connectionIntent.get() || !maintenance.normalAllowed())return;
            disconnectInternal();
            activeTarget=target; displayWriteUncertain=recoveryTargets.contains(target.key());
            generation=connectionGeneration; release=bridgeRelease;releaseOwner=bridgeReleaseOwner;
            if(target.transport().equals("USB")){
                // A path without a unique serial cannot prove the same keyboard survived a closed session.
                usbAttachments.put(target.id(),java.util.UUID.randomUUID().toString());
                usbTransport=openedUsb;
                openedUsb.onUnexpectedDisconnect(()->usbSessionTerminated(openedUsb,generation));
            }
        } finally { commandLock.unlock(); }
        boolean published=false;
        try {
            try{release.get(2500,TimeUnit.MILLISECONDS);}
            catch(java.util.concurrent.ExecutionException failure){
                // Recheck the captured owner on each explicit retry; a historical failed Future is not current liveness.
                if(!managedBridge.ownerRetired(releaseOwner))throw failure;
                commandLock.lock();try{if(bridgeRelease==release){bridgeRelease=java.util.concurrent.CompletableFuture.completedFuture(null);bridgeReleaseOwner=null;}}finally{commandLock.unlock();}
            }
            if(intent!=connectionIntent.get())return;
            if(target.transport().equals("USB")) {
                if(!usbCandidates().contains(target.id()))throw new IOException("USB目标已移除。");
                var opening=transportIo.submit(()->{openedUsb.openExact(target.id(),bytes->onSessionNotify(generation,bytes));return null;});
                try { opening.get(2500,TimeUnit.MILLISECONDS); }
                catch(Exception failure) { opening.cancel(true); throw failure; }
            } else {
                var fields=com.example.ahakey.service.connection.ManagedBridgeClient.fields().put("targetId",target.id()).put("snapshotId",bridgeSnapshot).put("clientGeneration",Long.toString(generation));
                var reply=managedBridge.request("connect",fields,15000);
                openedSession=reply.path("sessionId").asText();
                if(openedSession.isBlank())throw new IOException("蓝牙配置会话未就绪。");
            }
            commandLock.lock();
            try {
                if(intent!=connectionIntent.get() || generation!=connectionGeneration || !maintenance.normalAllowed())return;
                if(target.transport().equals("USB")&&!openedUsb.isOpen())throw new IOException("USB读取会话已结束。");
                usbTransport=openedUsb;bridgeSession=openedSession;
                isConnected=true;isScanning=false;cachedStatus.setConnected(true);cachedStatus.setDeviceName(target.name());cachedStatus.clearFirmwareIdentity();
                published=true;
            }finally{commandLock.unlock();}
            try(var binding=bindGeneration(generation)){
                try{if(displayWriteUncertain && recoveryTargets.absenceObserved(target.key()))recoverAfterPhysicalReconnect(target.key(),generation);}
                finally{commandLock.lock();try{if(generation==connectionGeneration&&intent==connectionIntent.get())callback.onConnected();}finally{commandLock.unlock();}}
                queryStatus();
            }
        } finally {
            if(!published) {
                transportIo.execute(openedUsb::close);
                if(!openedSession.isEmpty()) releaseBridge(openedSession,target.id(),generation);
                commandLock.lock();
                try { if(intent==connectionIntent.get() && generation==connectionGeneration)disconnectInternal(); }
                finally {commandLock.unlock();}
            }
        }
    }
    private void recoverAfterPhysicalReconnect(String target,long generation) throws Exception {
        recoveryProbe.set(true);
        try {
            // Pinned Firmware rejects 0x9F/0x88 while its resource transaction is active.
            readFirmwareCatalogKey(generation);
            if(!isDisplayAdmitted())throw new IOException("恢复需当前固件的资源元数据支持。");
            try(var lease=openDisplayLease(false,generation)) {
                for(int entry=0;entry<19;entry++) {
                    var reply=exchangeDisplay(lease,AhaKeyProtocol.displayRead(2,entry));
                    var metadata=AhaKeyResponseParser.parseDisplayRead(reply,2,entry);
                    if(metadata==null || metadata.writeState()==1)throw new IOException("资源事务仍未结束，请断电后重新连接。");
                }
            }
            commandLock.lock();try{requireGeneration(generation);recoveryTargets.confirmed(target);displayWriteUncertain=false;displayReadUncertain=false;}finally{commandLock.unlock();}
        }finally{recoveryProbe.remove();}
    }
    private void releaseBridge(String session,String target,long generation) throws Exception {
        managedBridge.request("disconnect",com.example.ahakey.service.connection.ManagedBridgeClient.fields().put("sessionId",session).put("targetId",target).put("clientGeneration",Long.toString(generation)),2000);
    }
    public void confirmSavedBindings(com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchConfig config,long generation) throws IOException {
        commandLock.lock();try{requireGeneration(generation);cachedStatus.setSavedBindings(config);cachedStatus.setSwitchState(config.physicalPosition());
        if(callback!=null)callback.onStatusReceived(cachedStatus);}finally{commandLock.unlock();}
    }
    public void closeManagedBridge() {if(discovery!=null)discovery.shutdownNow();transitions.shutdownNow();managedBridge.close();transportIo.shutdownNow();}
    public void startManagedBridge() throws Exception { managedBridge.start(); }
    public void restartManagedBridge(boolean stopOnly) throws Exception {
        if(!maintenance.normalAllowed())throw new IOException("设备维护中");
        if(activeTarget!=null && activeTarget.transport().equals("BLE"))disconnect();
        if(stopOnly)managedBridge.stop();else managedBridge.restart();
    }

    private int connectAttemptCount = 0;
    public void disconnect() {
        connectionIntent.incrementAndGet(); isScanning=false;
        try (var transaction = maintenance.normalTransaction()) { disconnectInternal(); }
        catch (Exception busy) { logger.debug("Disconnect deferred: {}", busy.getMessage()); }
    }
    private void disconnectInternal() {
        commandLock.lock();
        try {
        String oldSession=bridgeSession;String oldTarget=activeTarget==null?"":activeTarget.id();long oldGeneration=connectionGeneration;
        Object oldBridge=managedBridge.ownerIdentity();
        UsbHidTransport oldUsb=usbTransport;
        // Compete atomically with reader failure before replacing ownership. A queued callback cannot lose its cause.
        oldUsb.cancelPendingIo();
        if(activeTarget!=null && activeTarget.transport().equals("USB") && oldUsb.terminatedUnexpectedly())usbAttachments.remove(oldTarget);
        // Invalidate operations before asynchronous native cleanup; old handles are never reused by B.
        isConnected=false;cachedStatus.setConnected(false);cachedStatus.setSwitchState(-1);cachedStatus.clearSavedBindings();
        if(displayLease!=null || wireExpected>=0) quarantine(targetIdentity());
        resetDisplaySession(); bridgeSession=""; activeTarget=null;
        usbTransport=new UsbHidTransport();
        transportIo.execute(()->{try{oldUsb.close();}catch(Exception ignored){}});
        if(!oldSession.isEmpty()){bridgeReleaseOwner=oldBridge;bridgeRelease=java.util.concurrent.CompletableFuture.runAsync(()->{
            try{managedBridge.releaseSession(oldBridge,com.example.ahakey.service.connection.ManagedBridgeClient.fields().put("sessionId",oldSession).put("targetId",oldTarget).put("clientGeneration",Long.toString(oldGeneration)));}catch(Exception failure){throw new java.util.concurrent.CompletionException(failure);}
        },transportIo);}
        closeTcpOnly();
        if(callback!=null)callback.onDisconnected();
        }finally{commandLock.unlock();}
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

    private int wireExpected=-1;
    private long wireSerial;
    private volatile long cancellationEpoch;
    private byte[] wireReply;
    private final ThreadLocal<Long> boundGeneration=new ThreadLocal<>();
    public AutoCloseable bindGeneration(long generation) throws IOException {
        Long previous=boundGeneration.get();boundGeneration.set(generation);
        return ()->{if(previous==null)boundGeneration.remove();else boundGeneration.set(previous);};
    }
    public long operationGeneration() { Long bound=boundGeneration.get();return bound==null?connectionGeneration:bound; }
    public void requireGeneration(long generation) throws IOException {if(generation!=connectionGeneration || !isConnected)throw new IOException("设备会话已改变。");}
    public void requireDeviceRecovery() {cancellationEpoch++;if(activeTarget!=null)quarantine(targetIdentity());displayWriteUncertain=true;cachedStatus.clearSavedBindings();}
    public void cancelDeviceOperation() {cancelDeviceOperation(connectionGeneration);}
    public void cancelDeviceOperation(long generation) {
        commandLock.lock();try{
            if(generation!=connectionGeneration)return;
            requireDeviceRecovery();wireExpected=-1;wireReply=null;wireSerial++;responseReady.signalAll();
            usbTransport.cancelPendingIo();
        }finally{commandLock.unlock();}
    }
    private void firmwareExchange(byte[] frame,boolean data,int expected) throws IOException {
        long generation=connectionGeneration;String target=targetIdentity();
        if(data)maintenance.admit(-1,generation);else maintenance.admitFrame(frame,generation);
        long admittedEpoch=cancellationEpoch;
        String capturedTargetId=activeTarget==null?"":activeTarget.id();long requestTicket=-1;
        if(boundGeneration.get()!=null)requireGeneration(boundGeneration.get());
        requireGeneration(generation);
        if(displayWriteUncertain && !(recoveryProbe.get() && (expected==0x9F || expected==0x88)))throw new IOException("原设备结果未确认；请保持软件与蓝牙桥运行，让键盘断电至少3秒后重连。仅重启软件无法清除隔离。");
        try {
            long deadline=System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(RESPONSE_TIMEOUT_MS);
            while(wireExpected>=0) {
                requireGeneration(generation);
                long left=deadline-System.nanoTime();if(left<=0)throw new IOException("设备请求队列超时");responseReady.awaitNanos(left);
            }
            requireGeneration(generation);
            if(admittedEpoch!=cancellationEpoch || (displayWriteUncertain && !(recoveryProbe.get() && (expected==0x9F || expected==0x88))))throw new IOException("排队请求已取消或设备已隔离");
            wireExpected=expected;wireReply=null;requestTicket=++wireSerial;
            pendingNotifyFramesByCommand.remove((byte)expected);
            UsbHidTransport usb=usbTransport;String session=bridgeSession;
            var io=transportIo.submit(()->{
                requireGeneration(generation);
                if(admittedEpoch!=cancellationEpoch)throw new IOException("发送前请求已取消");
                transmitFirmware(usb,session,capturedTargetId,generation,frame,data);
                return null;
            });
            // Never block native cleanup or UI indefinitely on a driver call.
            int holds=commandLock.getHoldCount();
            for(int i=0;i<holds;i++)commandLock.unlock();
            try {io.get(2500,TimeUnit.MILLISECONDS);}catch(Exception e){usb.cancelPendingIo();io.cancel(true);throw e;}
            finally{for(int i=0;i<holds;i++)commandLock.lock();}
            requireGeneration(generation);
            if(requestTicket!=wireSerial)throw new IOException("设备请求已取消");
            logger.debug("设备请求 target={} generation={} opcode={} written",target,generation,expected);
            while(wireReply==null) {
                requireGeneration(generation);
                if(wireExpected<0 || requestTicket!=wireSerial)throw new IOException("设备请求已取消");
                long left=deadline-System.nanoTime();if(left<=0)throw new IOException("设备回应超时：0x"+Integer.toHexString(expected));
                responseReady.awaitNanos(left);
            }
        }catch(Exception e){if(generation==connectionGeneration)requireDeviceRecovery();throw e instanceof IOException?(IOException)e:new IOException("设备发送或等待失败",e);}
        finally{if(generation==connectionGeneration && requestTicket==wireSerial){wireExpected=-1;wireReply=null;wireSerial++;responseReady.signalAll();}}
    }

    protected void transmitFirmware(UsbHidTransport usb,String session,String target,long generation,byte[] frame,boolean data) throws Exception {
        if(usb.isOpen()){if(data)usb.sendData(frame);else usb.sendCommand(frame);}
        else {
            var fields=com.example.ahakey.service.connection.ManagedBridgeClient.fields().put("sessionId",session).put("targetId",target).put("clientGeneration",Long.toString(generation)).put("channel",data?"data":"command").put("bytes",java.util.Base64.getEncoder().encodeToString(frame));
            managedBridge.request("write",fields,5000);
        }
    }
    /** A fresh serialized physical status plus confirmed bindings; busy/unknown/timeout always defers. */
    public boolean refreshAutoApproval() {
        long generation=connectionGeneration;
        if(!isConnected || displayWriteUncertain || !maintenance.normalAllowed())return false;
        var refresh=transportIo.submit(()->{
            if(!commandLock.tryLock())return false;
            try(var binding=bindGeneration(generation)) {
                if(displayLease!=null || wireExpected>=0 || legacyWaiters!=0 || k1RouteOwner!=null)return false;
                requireGeneration(generation);long before=statusSequence;
                sendCommand(AhaKeyProtocol.queryDeviceStatus());
                return generation==connectionGeneration && statusSequence>before && cachedStatus.isAutoApproval();
            }finally{commandLock.unlock();}
        });
        try{return refresh.get(2000,TimeUnit.MILLISECONDS);}
        catch(Exception failure){refresh.cancel(true);return false;}
    }
    private long statusSequence;

    public void sendCommand(byte[] command) throws IOException {
        if (!commandLock.tryLock()) throw new IOException("设备正在处理其他命令。");
        try {
        maintenance.admitFrame(command, connectionGeneration);
        int opcode = command[2] & 255;
        if ((k1RouteOwner != null && k1RouteOwner != Thread.currentThread())
                || (opcode == 0x9E && k1RouteOwner != Thread.currentThread()))
            throw new IOException("K1命令必须通过独占路由事务发送。");
        if (opcode == 0x88 || opcode == 0x89 || opcode == 0x8A || opcode == 0x8B || opcode == 0x8C || opcode == 0x8E)
            throw new IOException("显示配置命令必须通过已准入事务发送。");
        if (opcode == 0x98 || opcode == 0x99) requireCapability();
        if (command[2] != AhaKeyProtocol.CMD_QUERY_STATUS && (displayLease != null
                || (displayWriteUncertain && !recoveryProbe.get() && command[2] != AhaKeyProtocol.CMD_FIRMWARE_CATALOG_KEY)))
            throw new IOException("显示配置事务占用或保存结果未确认。");
        if (displayLease != null) {
            checkDisplayTransport();
            if (displayLease.usb) sendUsbCommand(command);
            else writePacket(BleTcpPacket.WRITE_COMMAND, command);
            return;
        }
        logger.debug("发送命令: {}", bytesToHex(command, Math.min(20, command.length)));
        if (ensureUsbConnected()) {
            if (opcode == 0x98 || opcode == 0x99) requireCapability();
            sendUsbCommand(command);
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
        return readFirmwareCatalogKey(connectionGeneration);
    }

    public String readFirmwareCatalogKey(long generation) throws Exception {
        maintenance.admit(0x9F, generation);
        if(displayWriteUncertain&&!recoveryProbe.get())throw new IOException("设备恢复尚未确认，暂不读取普通配置");
        FirmwareIdentity queued = firmwareIdentity;
        synchronized (commandTransactionLock) {
            commandLock.lock();
            FirmwareIdentity reading = null;
            try {
                if (generation != connectionGeneration || !isConnected || !cachedStatus.isConnected())
                    throw new IOException("键盘连接已改变。");
                // Do not revoke an upload's admission while waiting for its complete lease.
                legacyWaiters++;
                try {
                    long remaining = TimeUnit.MILLISECONDS.toNanos(RESPONSE_TIMEOUT_MS);
                    while (displayLease != null) {
                        if (displayLease.owner == Thread.currentThread() || remaining <= 0)
                            throw new IOException("设备正在处理显示配置，请稍后刷新。");
                        remaining = responseReady.awaitNanos(remaining);
                        if (generation != connectionGeneration || !isConnected || !cachedStatus.isConnected())
                            throw new IOException("键盘连接已改变。");
                    }
                } finally { legacyWaiters--; responseReady.signalAll(); }
                // Coalesce readers queued behind the same completed identity request.
                if (queued != firmwareIdentity && firmwareIdentity.state() != DeviceStatus.IdentityState.READING) {
                    if (firmwareIdentity.state() == DeviceStatus.IdentityState.FAILED) throw new IOException("固件版本读取失败。");
                    return firmwareIdentity.catalogKey();
                }
                publishIdentity(DeviceStatus.IdentityState.READING, "");
                reading = firmwareIdentity;
                if(!recoveryProbe.get())callback.onStatusReceived(cachedStatus);
                pendingNotifyFramesByCommand.clear();
                logger.info("Reading firmware catalog key with command 0x9F");
                sendCommand(AhaKeyProtocol.queryFirmwareCatalogKey());
                if (!isCurrentIdentity(reading)) throw new IOException("键盘连接已改变。");
                byte[] frame = waitForIdentityResponse(reading);
                String catalogKey = AhaKeyResponseParser.parseFirmwareCatalogKey(frame);
                if (catalogKey == null || catalogKey.isBlank()) {
                    throw new IOException("无法解析键盘固件版本");
                }
                logger.info("Firmware catalog key: {}", catalogKey);
                if (!isCurrentIdentity(reading)) throw new IOException("键盘连接已改变。");
                publishIdentity(AhaKeyProtocol.isDisplayCapabilityResponse(frame)
                        ? DeviceStatus.IdentityState.SUPPORTED : DeviceStatus.IdentityState.UNKNOWN, catalogKey);
                if (exactCatalogResponse(frame, catalogKey)) exactCatalogIdentity = firmwareIdentity;
                if(!recoveryProbe.get())callback.onStatusReceived(cachedStatus);
                return catalogKey;
            } catch (Exception e) {
                if (reading != null && isCurrentIdentity(reading)) {
                    publishIdentity(DeviceStatus.IdentityState.FAILED, "");
                    if(!recoveryProbe.get())callback.onStatusReceived(cachedStatus);
                }
                throw e;
            } finally {
                commandLock.unlock();
            }
        }
    }

    private boolean exactCatalogResponse(byte[] frame, String catalogKey) {
        int offset = frame[3] == 0 ? 4 : 3;
        byte[] key = catalogKey.getBytes(java.nio.charset.StandardCharsets.US_ASCII);
        if (frame.length - 2 - offset < key.length) return false;
        for (byte value : key) if (frame[offset++] != value) return false;
        while (offset < frame.length - 2) if (frame[offset++] != 0) return false;
        return true;
    }

    private byte[] waitForIdentityResponse(FirmwareIdentity reading) throws Exception {
        legacyWaiters++;
        try {
            long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(RESPONSE_TIMEOUT_MS);
            while (isCurrentIdentity(reading) && isConnected && cachedStatus.isConnected()) {
                Deque<byte[]> frames = pendingNotifyFramesByCommand.get(AhaKeyProtocol.CMD_FIRMWARE_CATALOG_KEY);
                if (frames != null && !frames.isEmpty()) return frames.removeFirst();
                long remaining = deadline - System.nanoTime();
                if (remaining <= 0) throw new IOException("固件版本读取超时。");
                responseReady.awaitNanos(remaining);
            }
            throw new IOException("键盘连接已改变。");
        } finally { legacyWaiters--; responseReady.signalAll(); }
    }

    public AhaKeyResponseParser.SideSwitchConfig readSideSwitchConfig() throws Exception {
        synchronized (commandTransactionLock) {
            commandLock.lock();
            try {
                requireGeneration(operationGeneration());
                cachedStatus.clearSavedBindings();
                pendingNotifyFramesByCommand.clear();
                logger.info("Reading CP4C side switch config with command 0x97");
                sendCommand(AhaKeyProtocol.readSideSwitchConfig());
                byte[] frame = waitForResponse(AhaKeyProtocol.CMD_SIDE_SWITCH_CONFIG);
                AhaKeyResponseParser.SideSwitchConfig parsed = AhaKeyResponseParser.parseSideSwitchConfig(frame);
                if (parsed == null) {
                    throw new IOException("无法解析侧拨配置回读");
                }
                confirmSavedBindings(parsed,operationGeneration());
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
                requireGeneration(operationGeneration());
                cachedStatus.clearSavedBindings();
                if(callback!=null)callback.onStatusReceived(cachedStatus);
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
                if (parsed == null || parsed.mode() != mode || parsed.keyIndex() != keyIndex) {
                    throw new IOException("无法解析普通键配置回读或目标不匹配");
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
        maintenance.admit(-1, connectionGeneration);
        commandLock.lock();
        try {
        if (displayLease != null || displayWriteUncertain) throw new IOException("显示配置事务占用或保存结果未确认。");
        logger.debug("发送数据块: {} 字节", chunk.length);
        if (ensureUsbConnected()) {
            maintenance.admit(-1, connectionGeneration);
            firmwareExchange(chunk,true,AhaKeyProtocol.CMD_WRITE_RESULT&255);
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
        if (!maintenance.normalAllowed() || displayWriteUncertain) return;
        try {
            // Coalesce poller/status callers only; explicit approval refresh uses the forced path.
            if (commandLock.isLocked()) return;
            if (isDisplayBusy() && System.nanoTime() - lastOptionalQueryNanos < TimeUnit.SECONDS.toNanos(1)) return;
            lastOptionalQueryNanos = System.nanoTime();
            long generation=operationGeneration();
            transportIo.execute(()->{try(var binding=bindGeneration(generation)){requireGeneration(generation);queryStatusNow();}catch(Exception ignored){}});
        } catch (RuntimeException e) { logger.debug("Optional status query skipped: {}", e.getMessage()); }
    }

    private void queryStatusNow() {
        if (!maintenance.normalAllowed()) return;
        try {
            if (commandLock.isLocked()) {
                return;
            }
            if (ensureUsbConnected()) {
                sendCommand(AhaKeyProtocol.queryDeviceStatus());
                return;
            }
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
            if (!maintenance.normalAllowed()) { deferredRuntimeState = null; return false; }
            if (!isConnected || !cachedStatus.isConnected()) return false;
            deferredRuntimeState = state;
            deferredRuntimeAt = System.nanoTime();
            if (displayLease != null || displayWriteUncertain || k1RouteOwner != null) return false;
            sendCommand(AhaKeyProtocol.updateState(state));
            deferredRuntimeState = null;
            return true;
        } finally { commandLock.unlock(); }
    }
    private void flushDeferredRuntimeState() {
        if (!maintenance.normalAllowed()) { deferredRuntimeState = null; return; }
        commandLock.lock();
        try {
            if (deferredRuntimeState != null && System.nanoTime() - deferredRuntimeAt >= TimeUnit.MINUTES.toNanos(5))
                deferredRuntimeState = null;
            if (displayLease != null || displayWriteUncertain || k1RouteOwner != null) return;
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
            sendUsbCommand(AhaKeyProtocol.queryDeviceStatus());
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
        commandLock.lock();
        try {
            if (displayLease != null) return;
            cachedStatus.clearFirmwareIdentity();
            publishIdentity(isConnected && cachedStatus.isConnected()
                    ? DeviceStatus.IdentityState.UNKNOWN : DeviceStatus.IdentityState.DISCONNECTED, "");
            responseReady.signalAll();
            callback.onStatusReceived(cachedStatus);
        } finally { commandLock.unlock(); }
    }

    public boolean isUsbConnected() {
        return usbTransport.isOpen();
    }

    public String selectPreferredTransport() throws IOException {
        if (ensureUsbConnected()) {
            return "USB";
        }
        if (isConnected && !bridgeSession.isEmpty()) {
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

    protected boolean isUsbDevicePresent() {
        return UsbHidTransport.isPresent();
    }

    private boolean tryConnectUsb() {
        if (!maintenance.normalAllowed()) return false;
        try {
            if (!isUsbDevicePresent()) {
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

    private boolean ensureUsbConnected() { return isConnected && usbTransport.isOpen(); }
    private void writePacket(byte type, byte[] data) throws IOException {
        commandLock.lock();
        try {
            if(type==BleTcpPacket.WRITE_COMMAND)firmwareExchange(data,false,data[2]&255);
            else if(type==BleTcpPacket.WRITE_DATA)firmwareExchange(data,true,AhaKeyProtocol.CMD_WRITE_RESULT&255);
            else throw new IOException("旧桥端口请求已停用");
            // Managed bridge status is delivered by its session events, never legacy port 9000.
        }finally{commandLock.unlock();}
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
        long waitingGeneration = connectionGeneration;
        logger.debug("开始等待响应 0x{}", Integer.toHexString(expectedCmd & 0xFF));
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs);
        
        while (true) {
            if (!isConnected || waitingGeneration != connectionGeneration) throw new IOException("设备会话已结束，旧请求不会重连或续传。");
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
                    sendUsbCommand(AhaKeyProtocol.queryDeviceStatus());
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
                status.setSavedBindings(cachedStatus.getSavedBindings());
            status.setFirmwareCatalogKey(cachedStatus.getFirmwareCatalogKey());
                status.setIdentityState(firmwareIdentity.state());
                cachedStatus = status;statusSequence++;lastStatusUpdateTime=System.currentTimeMillis();
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
                    handleSessionPacket(generation, header[0], body);
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

    private void handleSessionPacket(long generation, byte type, byte[] data) {
        commandLock.lock();
        try { if (generation == connectionGeneration) handlePacket(type, data); }
        finally { commandLock.unlock(); }
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
                // An invalid binary K1 frame has no safe interior delimiter to resynchronize on.
                if(end==-2){notifyReassemblyLength=0;return frames;}
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
        int k1 = com.example.ahakey.protocol.K1RouteProtocol.replyLength(buffer,0,len,k1ReplyRequest);
        if(k1>0)return k1-2;
        if(k1!=-1)return k1==0?-1:-2;
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
        commandLock.lock();
        try {if(AhaKeyProtocol.isValidFrame(data) && data.length>2 && (data[2]&255)==wireExpected) {
            wireReply=data.clone();responseReady.signalAll();
        }}finally{commandLock.unlock();}
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
            status.setSavedBindings(cachedStatus.getSavedBindings());
            status.setFirmwareCatalogKey(cachedStatus.getFirmwareCatalogKey());
            status.setIdentityState(firmwareIdentity.state());
            status.setConnected(true);
            cachedStatus = status;statusSequence++;lastStatusUpdateTime=System.currentTimeMillis();
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

