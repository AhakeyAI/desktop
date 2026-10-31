package com.example.ahakey.service;

import com.sun.jna.LastErrorException;
import com.sun.jna.Native;
import com.sun.jna.Pointer;
import com.sun.jna.Structure;
import com.sun.jna.WString;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.win32.StdCallLibrary;
import com.sun.jna.win32.W32APIOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.Closeable;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.function.Consumer;

public class UsbHidTransport implements Closeable {
    private static final Logger logger = LoggerFactory.getLogger(UsbHidTransport.class);

    private static final int DIGCF_PRESENT = 0x00000002;
    private static final int DIGCF_DEVICEINTERFACE = 0x00000010;
    private static final int ERROR_NO_MORE_ITEMS = 259;
    private static final int GENERIC_READ = 0x80000000;
    private static final int GENERIC_WRITE = 0x40000000;
    private static final int FILE_SHARE_READ = 0x00000001;
    private static final int FILE_SHARE_WRITE = 0x00000002;
    private static final int OPEN_EXISTING = 3;
    private static final int REPORT_SIZE = 64;
    private static final byte USB_COMMAND_PACKET = (byte) 0xA1;
    private static final byte USB_DATA_PACKET = (byte) 0xA2;

    private volatile Pointer readHandle;
    private volatile Pointer writeHandle;
    private volatile String devicePath;
    private volatile Thread readerThread;
    private volatile boolean running;
    private Consumer<byte[]> frameConsumer;
    private volatile Runnable disconnectHandler=()->{};
    private enum Termination { OPEN, INTENTIONAL, UNEXPECTED }
    private final java.util.concurrent.atomic.AtomicReference<Termination> termination=new java.util.concurrent.atomic.AtomicReference<>(Termination.OPEN);
    public final void onUnexpectedDisconnect(Runnable handler){disconnectHandler=java.util.Objects.requireNonNull(handler);}
    public final boolean terminatedUnexpectedly(){return termination.get()==Termination.UNEXPECTED;}
    /** Reader terminal seam; notify before waiting for native writer cleanup. */
    protected final void readerTerminatedUnexpectedly(){
        if(!termination.compareAndSet(Termination.OPEN,Termination.UNEXPECTED))return;
        cancelled=true;running=false;
        try{disconnectHandler.run();}catch(RuntimeException failure){logger.warn("USB disconnect notification failed",failure);}
    }
    private volatile byte[] k1ReplyRequest;

    private final Object cancellationLock=new Object();
    private Pointer readThreadHandle,writeThreadHandle;
    private volatile boolean cancelled;
    private final java.util.concurrent.atomic.AtomicBoolean cancelling=new java.util.concurrent.atomic.AtomicBoolean();
    /** Revoke this handle set permanently; caller never waits for the synchronous native writer's monitor. */
    public void cancelPendingIo() {
        termination.compareAndSet(Termination.OPEN,Termination.INTENTIONAL);
        cancelled=true;running=false;
        if(!cancelling.compareAndSet(false,true))return;
        Thread cancel=new Thread(()->{
            long deadline=System.nanoTime()+java.util.concurrent.TimeUnit.SECONDS.toNanos(2);
            do {
                synchronized(cancellationLock) {
                    if(!isInvalidHandle(readThreadHandle))Kernel32.INSTANCE.CancelSynchronousIo(readThreadHandle);
                    if(!isInvalidHandle(writeThreadHandle))Kernel32.INSTANCE.CancelSynchronousIo(writeThreadHandle);
                    if(isInvalidHandle(readThreadHandle)&&isInvalidHandle(writeThreadHandle))return;
                }
                try{Thread.sleep(25);}catch(InterruptedException ignored){return;}
            }while(System.nanoTime()<deadline);
            logger.warn("USB cancellation requested; native completion not confirmed before cleanup deadline");
        },"usb-io-cancel");cancel.setDaemon(true);cancel.start();
    }
    public String devicePath() { return devicePath == null ? "" : devicePath; }
    public record MaintenanceDevice(String instanceId, String container, String port, boolean download, List<String> interfaces) {
        public boolean ownsHidPath(String path) {
            String id = path.replace("\\\\?\\", "").replace('#', '\\');
            int suffix = id.lastIndexOf("\\{"); if (suffix >= 0) id = id.substring(0, suffix);
            String expected = id;
            return interfaces.stream().anyMatch(i -> i.equalsIgnoreCase(expected));
        }
    }
    /** Read-only PnP observation. Enumerates physical USB parents, not BLE addresses. */
    public static List<MaintenanceDevice> maintenanceDevices() throws Exception {
        return com.example.ahakey.firmware.BootDeviceDetector.observeUsbIdentities().stream()
                .map(device -> new MaintenanceDevice(device.instanceId(),device.container(),device.port(),device.download(),device.interfaces()))
                .toList();
    }

    public static boolean isPresent() {
        return findDevicePath() != null;
    }

    public synchronized void open(Consumer<byte[]> onFrame) throws IOException {
        if (isOpen()) {
            return;
        }
        openExact(findDevicePath(), onFrame);
    }
    public synchronized void openExact(String path, Consumer<byte[]> onFrame) throws IOException {
        if(cancelled)throw new IOException("USB session was revoked");
        if (isOpen()) { if (devicePath.equalsIgnoreCase(path)) return; throw new IOException("USB handle belongs to another device"); }
        if (path == null || !configurationPaths().contains(path)) {
            throw new IOException("USB HID device not found");
        }
        Pointer r = Kernel32.INSTANCE.CreateFile(
            new WString(path),
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            Pointer.NULL,
            OPEN_EXISTING,
            0,
            Pointer.NULL
        );
        if (isInvalidHandle(r)) {
            throw new IOException("Open USB HID read failed: " + Native.getLastError());
        }
        Pointer w = Kernel32.INSTANCE.CreateFile(
            new WString(path),
            GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            Pointer.NULL,
            OPEN_EXISTING,
            0,
            Pointer.NULL
        );
        if (isInvalidHandle(w)) {
            Kernel32.INSTANCE.CloseHandle(r);
            throw new IOException("Open USB HID write failed: " + Native.getLastError());
        }

        if(cancelled){Kernel32.INSTANCE.CloseHandle(r);Kernel32.INSTANCE.CloseHandle(w);throw new IOException("USB session revoked while opening");}
        readHandle = r;
        writeHandle = w;
        devicePath = path;
        frameConsumer = onFrame;
        running = true;
        startReader();
        logger.info("USB HID connected: {}", path);
    }

    public boolean isOpen() {
        return !cancelled && devicePath != null && !devicePath.isBlank()
            && readHandle != null && !isInvalidHandle(readHandle)
            && writeHandle != null && !isInvalidHandle(writeHandle);
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
        int opcode = frame.length > 2 ? frame[2] & 255 : -1;
        k1ReplyRequest=opcode==0x9E?frame.clone():null;
        writeReport(payload, (opcode < 0x88 || opcode > 0x8E)&&opcode!=0x9E);
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
        writeReport(payload64, true);
    }

    private void writeReport(byte[] payload64, boolean allowLegacyFallback) throws IOException {
        byte[] reportWithId = new byte[REPORT_SIZE + 1];
        reportWithId[0] = 0;
        System.arraycopy(payload64, 0, reportWithId, 1, payload64.length);

        IntByReference written = new IntByReference();
        Pointer h = writeHandle;
        if (h == null || isInvalidHandle(h)) {
            throw new IOException("USB HID write handle not connected");
        }
        synchronized(cancellationLock){
            if(cancelled)throw new IOException("USB write cancelled");
            writeThreadHandle=Kernel32.INSTANCE.OpenThread(1,false,Kernel32.INSTANCE.GetCurrentThreadId());
            if(isInvalidHandle(writeThreadHandle))throw new IOException("Cannot obtain cancellable USB writer");
        }
        try {
            if(cancelled)throw new IOException("USB write cancelled");
            boolean ok = Kernel32.INSTANCE.WriteFile(h, reportWithId, reportWithId.length, written, Pointer.NULL);
            if (!ok && allowLegacyFallback && !cancelled) {
                written.setValue(0);
                ok = Kernel32.INSTANCE.WriteFile(h, payload64, payload64.length, written, Pointer.NULL);
            }
            if (cancelled || !ok || (!allowLegacyFallback && written.getValue() != reportWithId.length))
                throw new IOException("USB HID write unconfirmed: " + Native.getLastError());
        } finally {
            synchronized(cancellationLock){Kernel32.INSTANCE.CloseHandle(writeThreadHandle);writeThreadHandle=null;}
        }
    }

    private void startReader() {
        final Pointer sessionRead = readHandle;
        final Pointer sessionWrite = writeHandle;
        final Consumer<byte[]> sessionConsumer = frameConsumer;
        readerThread = new Thread(() -> {
            synchronized(cancellationLock){readThreadHandle=Kernel32.INSTANCE.OpenThread(1,false,Kernel32.INSTANCE.GetCurrentThreadId());}
            byte[] report = new byte[REPORT_SIZE + 1];
            while (running && readerThread == Thread.currentThread()) {
                Pointer h = sessionRead;
                if (h == null || isInvalidHandle(h)) {
                    readerTerminatedUnexpectedly();
                    break;
                }
                try {
                    Arrays.fill(report, (byte) 0);
                    IntByReference read = new IntByReference();
                    boolean ok = Kernel32.INSTANCE.ReadFile(h, report, report.length, read, Pointer.NULL);
                    if (!ok || read.getValue() <= 0) {
                        int err = Native.getLastError();
                        if (running) {
                            logger.warn("USB HID read stopped: {}", err);
                        }
                        readerTerminatedUnexpectedly();
                        break;
                    }
                    byte[] frame = extractFrame(report, read.getValue(),k1ReplyRequest);
                    // 在调用回调前再次检查 running 状态
                    if (running && readerThread == Thread.currentThread() && frame != null && sessionConsumer != null) {
                        sessionConsumer.accept(frame);
                    }
                } catch (Exception e) {
                    if (running) {
                        logger.warn("USB HID read error: {}", e.getMessage());
                    }
                    readerTerminatedUnexpectedly();
                    break;
                }
            }
            synchronized(cancellationLock){if(!isInvalidHandle(readThreadHandle))Kernel32.INSTANCE.CloseHandle(readThreadHandle);readThreadHandle=null;}
            // 线程退出时自行关闭 handles（避免主线程在 ReadFile 阻塞时关闭）
            logger.debug("USB reader: 线程退出，自行关闭 handles");
            synchronized (UsbHidTransport.this) {
                if (!isInvalidHandle(sessionRead)) {
                    try {
                        Kernel32.INSTANCE.CloseHandle(sessionRead);
                        logger.debug("USB reader: 自行关闭 readHandle");
                    } catch (Exception e) {
                        logger.warn("USB reader: 关闭 readHandle 失败 - {}", e.getMessage());
                    }
                }
                if (!isInvalidHandle(sessionWrite)) {
                    try {
                        Kernel32.INSTANCE.CloseHandle(sessionWrite);
                        logger.debug("USB reader: 自行关闭 writeHandle");
                    } catch (Exception e) {
                        logger.warn("USB reader: 关闭 writeHandle 失败 - {}", e.getMessage());
                    }
                }
                if (readerThread == Thread.currentThread()) {
                    readHandle = null;
                    writeHandle = null;
                    devicePath = null;
                    running = false;
                }
            }
        }, "usb-hid-reader");
        readerThread.setDaemon(true);
        readerThread.start();
    }

    private static byte[] extractFrame(byte[] data, int len) {
        return extractFrame(data,len,null);
    }
    private static byte[] extractFrame(byte[] data, int len,byte[] request) {
        int start = -1;
        for (int i = 0; i + 1 < len; i++) {
            if (data[i] == (byte) 0xAA && data[i + 1] == (byte) 0xBB) {
                start = i;
                break;
            }
        }
        if (start < 0) {
            return null;
        }
        int k1=com.example.ahakey.protocol.K1RouteProtocol.replyLength(data,start,len-start,request);
        if(k1>0)return Arrays.copyOfRange(data,start,start+k1);
        if(k1!=-1)return null;
        int fixed = com.example.ahakey.protocol.AhaKeyResponseParser.displayReplyLength(data, start, len - start);
        if (fixed > 0) return Arrays.copyOfRange(data, start, start + fixed);
        if (fixed != -1) return null;
        for (int i = start + 3; i + 1 < len; i++) {
            if (data[i] == (byte) 0xCC && data[i + 1] == (byte) 0xDD) {
                return Arrays.copyOfRange(data, start, i + 2);
            }
        }
        return null;
    }

    private void ensureOpen() throws IOException {
        if (!isOpen()) {
            throw new IOException("USB HID not connected");
        }
    }

    @Override
    public void close() {
        k1ReplyRequest=null;
        cancelPendingIo();
        Thread reader=readerThread;
        if(reader!=null && reader!=Thread.currentThread())try{reader.join(500);}catch(InterruptedException e){Thread.currentThread().interrupt();}
        // Handles are closed only by their owner after native I/O returns; a late completion cannot affect B.
    }

    private synchronized void closeQuietly() {
        running = false;
        if (readHandle != null && !isInvalidHandle(readHandle)) {
            Kernel32.INSTANCE.CloseHandle(readHandle);
        }
        if (writeHandle != null && !isInvalidHandle(writeHandle)) {
            Kernel32.INSTANCE.CloseHandle(writeHandle);
        }
        readHandle = null;
        writeHandle = null;
        devicePath = null;
    }

    private static boolean isInvalidHandle(Pointer h) {
        return h == null || Pointer.nativeValue(h) == 0 || Pointer.nativeValue(h) == -1;
    }

    private static String findDevicePath() {
        List<String> paths = listDevicePaths();
        for (String path : paths) {
            String p = path.toLowerCase(Locale.ROOT);
            if (p.contains("vid_413c") && p.contains("pid_2107") && p.contains("mi_01")) {
                return path;
            }
        }
        boolean hasAhaKey = paths.stream()
            .map(path -> path.toLowerCase(Locale.ROOT))
            .anyMatch(path -> path.contains("vid_413c") && path.contains("pid_2107"));
        if (hasAhaKey) {
            logger.warn("AhaKey USB HID device found, but vendor/config interface mi_01 was not available");
        }
        return null;
    }

    public static List<String> listDevicePaths() {
        try { return enumerateDevicePaths(); }
        catch(RuntimeException failure){logger.warn("USB HID enumerate failed: {}",failure.getMessage());return List.of();}
    }
    public static List<String> configurationPaths() { return configurationPaths(enumerateDevicePaths()); }
    static List<String> configurationPaths(List<String> paths) {
        return paths.stream().filter(path->{String p=path.toLowerCase(Locale.ROOT);return p.contains("vid_413c")&&p.contains("pid_2107")&&p.contains("mi_01");}).toList();
    }
    /** A failed/partial enumeration must never become evidence that a quarantined device is absent. */
    private static List<String> enumerateDevicePaths() {
        Guid.GUID hidGuid = new Guid.GUID();
        Hid.INSTANCE.HidD_GetHidGuid(hidGuid);
        Pointer infoSet = SetupApi.INSTANCE.SetupDiGetClassDevs(hidGuid, Pointer.NULL, Pointer.NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (isInvalidHandle(infoSet)) {
            throw new LastErrorException(Native.getLastError());
        }

        List<String> paths = new ArrayList<>();
        try {
            for (int index = 0; ; index++) {
                SP_DEVICE_INTERFACE_DATA data = new SP_DEVICE_INTERFACE_DATA();
                data.cbSize = data.size();
                boolean ok = SetupApi.INSTANCE.SetupDiEnumDeviceInterfaces(infoSet, Pointer.NULL, hidGuid, index, data);
                if (!ok) {
                    int err = Native.getLastError();
                    if (err == ERROR_NO_MORE_ITEMS) {
                        break;
                    }
                    throw new LastErrorException(err);
                }

                SP_DEVICE_INTERFACE_DETAIL_DATA detail = new SP_DEVICE_INTERFACE_DETAIL_DATA();
                detail.cbSize = Native.POINTER_SIZE == 8 ? 8 : 6;
                IntByReference required = new IntByReference();
                ok = SetupApi.INSTANCE.SetupDiGetDeviceInterfaceDetail(
                    infoSet,
                    data,
                    detail,
                    detail.size(),
                    required,
                    Pointer.NULL
                );
                if (!ok || detail.DevicePath == null) throw new LastErrorException(Native.getLastError());
                if (ok && detail.DevicePath != null) {
                    String path = Native.toString(detail.DevicePath);
                    if (path != null && !path.isBlank()) {
                        paths.add(path);
                    }
                }
            }
        } finally {
            SetupApi.INSTANCE.SetupDiDestroyDeviceInfoList(infoSet);
        }
        return paths;
    }

    public static class Guid {
        @Structure.FieldOrder({"Data1", "Data2", "Data3", "Data4"})
        public static class GUID extends Structure {
            public int Data1;
            public short Data2;
            public short Data3;
            public byte[] Data4 = new byte[8];
        }
    }

    @Structure.FieldOrder({"cbSize", "InterfaceClassGuid", "Flags", "Reserved"})
    public static class SP_DEVICE_INTERFACE_DATA extends Structure {
        public int cbSize;
        public Guid.GUID InterfaceClassGuid;
        public int Flags;
        public Pointer Reserved;
    }

    @Structure.FieldOrder({"cbSize", "DevicePath"})
    public static class SP_DEVICE_INTERFACE_DETAIL_DATA extends Structure {
        public int cbSize;
        public char[] DevicePath = new char[512];
    }

    private interface Hid extends StdCallLibrary {
        Hid INSTANCE = Native.load("hid", Hid.class, W32APIOptions.UNICODE_OPTIONS);
        void HidD_GetHidGuid(Guid.GUID hidGuid);
    }

    private interface SetupApi extends StdCallLibrary {
        SetupApi INSTANCE = Native.load("setupapi", SetupApi.class, W32APIOptions.UNICODE_OPTIONS);

        Pointer SetupDiGetClassDevs(Guid.GUID classGuid, Pointer enumerator, Pointer hwndParent, int flags);
        boolean SetupDiEnumDeviceInterfaces(Pointer deviceInfoSet, Pointer deviceInfoData, Guid.GUID interfaceClassGuid, int memberIndex, SP_DEVICE_INTERFACE_DATA deviceInterfaceData);
        boolean SetupDiGetDeviceInterfaceDetail(Pointer deviceInfoSet, SP_DEVICE_INTERFACE_DATA deviceInterfaceData, SP_DEVICE_INTERFACE_DETAIL_DATA deviceInterfaceDetailData, int deviceInterfaceDetailDataSize, IntByReference requiredSize, Pointer deviceInfoData);
        boolean SetupDiDestroyDeviceInfoList(Pointer deviceInfoSet);
    }

    private interface Kernel32 extends StdCallLibrary {
        Kernel32 INSTANCE = Native.load("kernel32", Kernel32.class, W32APIOptions.UNICODE_OPTIONS);

        Pointer CreateFile(WString fileName, int desiredAccess, int shareMode, Pointer securityAttributes, int creationDisposition, int flagsAndAttributes, Pointer templateFile);
        boolean WriteFile(Pointer file, byte[] buffer, int bytesToWrite, IntByReference bytesWritten, Pointer overlapped);
        boolean ReadFile(Pointer file, byte[] buffer, int bytesToRead, IntByReference bytesRead, Pointer overlapped);
        boolean CloseHandle(Pointer object);
        Pointer OpenThread(int access,boolean inherit,int threadId);
        int GetCurrentThreadId();
        boolean CancelSynchronousIo(Pointer thread);
    }
}
