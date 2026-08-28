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
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

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

    private static final long READER_JOIN_TIMEOUT_MS = 2_000;

    private final Object stateLock = new Object();
    private final HidIo io;
    private final long readerJoinTimeoutMillis;
    private final AtomicLong generationSequence = new AtomicLong();
    private volatile Session activeSession;

    @FunctionalInterface
    public interface FrameConsumer {
        void accept(byte[] frame, long receivedAtNanos);
    }

    interface HidIo {
        String findDevicePath();
        Pointer openRead(String path);
        Pointer openWrite(String path);
        ReadResult read(Pointer handle, byte[] buffer);
        boolean write(Pointer handle, byte[] buffer, IntByReference written);
        void cancel(Pointer handle);
        void close(Pointer handle);
        int lastError();
        boolean isInvalid(Pointer handle);
    }

    record ReadResult(boolean successful, int bytesRead, int errorCode) {}

    private static final class Session {
        final long generation;
        final String devicePath;
        final Pointer readHandle;
        final Pointer writeHandle;
        final FrameConsumer consumer;
        final Runnable disconnectedCallback;
        final AtomicBoolean stopRequested = new AtomicBoolean();
        final AtomicBoolean handlesClosed = new AtomicBoolean();
        final CountDownLatch terminated = new CountDownLatch(1);
        final Object writeMutex = new Object();
        volatile Thread readerThread;

        Session(
            long generation,
            String devicePath,
            Pointer readHandle,
            Pointer writeHandle,
            FrameConsumer consumer,
            Runnable disconnectedCallback
        ) {
            this.generation = generation;
            this.devicePath = devicePath;
            this.readHandle = readHandle;
            this.writeHandle = writeHandle;
            this.consumer = consumer;
            this.disconnectedCallback = disconnectedCallback;
        }
    }

    public UsbHidTransport() {
        this(new NativeHidIo(), READER_JOIN_TIMEOUT_MS);
    }

    UsbHidTransport(HidIo io) {
        this(io, READER_JOIN_TIMEOUT_MS);
    }

    UsbHidTransport(HidIo io, long readerJoinTimeoutMillis) {
        this.io = io;
        this.readerJoinTimeoutMillis = readerJoinTimeoutMillis;
    }

    public static boolean isPresent() {
        return findDevicePath() != null;
    }

    public void open(FrameConsumer onFrame) throws IOException {
        open(onFrame, null);
    }

    public void open(FrameConsumer onFrame, Runnable onDisconnected) throws IOException {
        if (onFrame == null) {
            throw new IllegalArgumentException("USB frame consumer is required");
        }
        synchronized (stateLock) {
            if (isOpenLocked()) {
                return;
            }
        }
        String path = io.findDevicePath();
        if (path == null) {
            throw new IOException("USB HID device not found");
        }
        Pointer r = io.openRead(path);
        if (io.isInvalid(r)) {
            throw new IOException("Open USB HID read failed: " + io.lastError());
        }
        Pointer w = io.openWrite(path);
        if (io.isInvalid(w)) {
            io.close(r);
            throw new IOException("Open USB HID write failed: " + io.lastError());
        }

        Session session = new Session(
            generationSequence.incrementAndGet(), path, r, w, onFrame, onDisconnected);
        synchronized (stateLock) {
            if (isOpenLocked()) {
                closeSessionHandles(session);
                return;
            }
            activeSession = session;
        }
        startReader(session);
        logger.info("USB HID connected: {}", path);
    }

    public boolean isOpen() {
        synchronized (stateLock) {
            return isOpenLocked();
        }
    }

    private boolean isOpenLocked() {
        Session session = activeSession;
        return session != null && !session.stopRequested.get()
            && !session.handlesClosed.get()
            && session.devicePath != null && !session.devicePath.isBlank()
            && !io.isInvalid(session.readHandle)
            && !io.isInvalid(session.writeHandle);
    }

    public void sendCommand(byte[] frame) throws IOException {
        Session session = requireActiveSession();
        if (frame.length > REPORT_SIZE - 2) {
            throw new IOException("USB command frame too large: " + frame.length);
        }
        byte[] payload = new byte[REPORT_SIZE];
        payload[0] = USB_COMMAND_PACKET;
        payload[1] = (byte) frame.length;
        System.arraycopy(frame, 0, payload, 2, frame.length);
        writeReport(session, payload);
    }

    public void sendData(byte[] data) throws IOException {
        Session session = requireActiveSession();
        int offset = 0;
        while (offset < data.length) {
            int len = Math.min(REPORT_SIZE - 2, data.length - offset);
            byte[] payload = new byte[REPORT_SIZE];
            payload[0] = USB_DATA_PACKET;
            payload[1] = (byte) len;
            System.arraycopy(data, offset, payload, 2, len);
            writeReport(session, payload);
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

    private void writeReport(Session session, byte[] payload64) throws IOException {
        byte[] reportWithId = new byte[REPORT_SIZE + 1];
        reportWithId[0] = 0;
        System.arraycopy(payload64, 0, reportWithId, 1, payload64.length);

        synchronized (session.writeMutex) {
            if (!isActive(session)) {
                throw new IOException("USB HID session is no longer active");
            }
            IntByReference written = new IntByReference();
            boolean ok = io.write(session.writeHandle, reportWithId, written);
            if (!ok) {
                written.setValue(0);
                ok = io.write(session.writeHandle, payload64, written);
            }
            if (!ok) {
                throw new IOException("USB HID write failed: " + io.lastError());
            }
        }
    }

    private void startReader(Session session) {
        Thread reader = new Thread(() -> {
            byte[] report = new byte[REPORT_SIZE + 1];
            boolean unexpectedDisconnect = false;
            try {
              while (!session.stopRequested.get()) {
                try {
                    Arrays.fill(report, (byte) 0);
                    ReadResult result = io.read(session.readHandle, report);
                    if (!result.successful() || result.bytesRead() <= 0) {
                        if (!session.stopRequested.get()) {
                            unexpectedDisconnect = true;
                            logger.warn("USB HID read stopped: {}", result.errorCode());
                        }
                        break;
                    }
                    // Capture arrival at the physical reader boundary before
                    // frame extraction, protocol validation, logging or any
                    // freshness coordination lock can delay processing.
                    long receivedAtNanos = System.nanoTime();
                    byte[] frame = extractFrame(report, result.bytesRead());
                    if (!session.stopRequested.get() && isActive(session) && frame != null) {
                        session.consumer.accept(frame, receivedAtNanos);
                    }
                } catch (Exception e) {
                    if (!session.stopRequested.get()) {
                        unexpectedDisconnect = true;
                        logger.warn("USB HID read error: {}", e.getMessage());
                    }
                    break;
                }
              }
            } finally {
                closeSessionHandles(session);
                boolean wasActive;
                synchronized (stateLock) {
                    wasActive = activeSession == session;
                    if (wasActive) {
                        activeSession = null;
                    }
                }
                session.terminated.countDown();
                if (unexpectedDisconnect && wasActive
                    && !session.stopRequested.get() && session.disconnectedCallback != null) {
                    try {
                        session.disconnectedCallback.run();
                    } catch (Exception e) {
                        logger.warn("USB disconnect callback failed: {}", e.getMessage());
                    }
                }
            }
        }, "usb-hid-reader-" + session.generation);
        session.readerThread = reader;
        reader.setDaemon(true);
        reader.start();
    }

    private static byte[] extractFrame(byte[] data, int len) {
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
        for (int i = start + 3; i + 1 < len; i++) {
            if (data[i] == (byte) 0xCC && data[i + 1] == (byte) 0xDD) {
                return Arrays.copyOfRange(data, start, i + 2);
            }
        }
        return null;
    }

    private Session requireActiveSession() throws IOException {
        synchronized (stateLock) {
            if (!isOpenLocked()) {
                throw new IOException("USB HID not connected");
            }
            return activeSession;
        }
    }

    private boolean isActive(Session session) {
        return activeSession == session && !session.stopRequested.get()
            && !session.handlesClosed.get();
    }

    @Override
    public void close() {
        Session session;
        synchronized (stateLock) {
            session = activeSession;
            if (session == null) {
                return;
            }
            activeSession = null;
            session.stopRequested.set(true);
        }

        // Cancel and close outside stateLock. The reader never needs that lock
        // to observe its stop flag or release its own captured handles.
        io.cancel(session.readHandle);
        closeSessionHandles(session);
        Thread reader = session.readerThread;
        if (reader != null && reader != Thread.currentThread()) {
            try {
                if (!session.terminated.await(readerJoinTimeoutMillis, TimeUnit.MILLISECONDS)) {
                    logger.warn(
                        "USB reader generation {} did not exit within {}ms; it remains isolated",
                        session.generation, readerJoinTimeoutMillis);
                }
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private void closeSessionHandles(Session session) {
        if (!session.handlesClosed.compareAndSet(false, true)) {
            return;
        }
        io.close(session.readHandle);
        io.close(session.writeHandle);
    }

    private static boolean isInvalidHandle(Pointer h) {
        return h == null || Pointer.nativeValue(h) == 0 || Pointer.nativeValue(h) == -1;
    }

    private static final class NativeHidIo implements HidIo {
        @Override
        public String findDevicePath() {
            return UsbHidTransport.findDevicePath();
        }

        @Override
        public Pointer openRead(String path) {
            return open(path, GENERIC_READ);
        }

        @Override
        public Pointer openWrite(String path) {
            return open(path, GENERIC_WRITE);
        }

        private Pointer open(String path, int access) {
            return Kernel32.INSTANCE.CreateFile(
                new WString(path), access, FILE_SHARE_READ | FILE_SHARE_WRITE,
                Pointer.NULL, OPEN_EXISTING, 0, Pointer.NULL);
        }

        @Override
        public ReadResult read(Pointer handle, byte[] buffer) {
            IntByReference read = new IntByReference();
            boolean ok = Kernel32.INSTANCE.ReadFile(
                handle, buffer, buffer.length, read, Pointer.NULL);
            return new ReadResult(ok, read.getValue(), ok ? 0 : Native.getLastError());
        }

        @Override
        public boolean write(Pointer handle, byte[] buffer, IntByReference written) {
            return Kernel32.INSTANCE.WriteFile(
                handle, buffer, buffer.length, written, Pointer.NULL);
        }

        @Override
        public void cancel(Pointer handle) {
            if (!isInvalid(handle)) {
                try {
                    Kernel32.INSTANCE.CancelIoEx(handle, Pointer.NULL);
                } catch (Throwable failure) {
                    logger.debug("CancelIoEx failed: {}", failure.getMessage());
                }
            }
        }

        @Override
        public void close(Pointer handle) {
            if (!isInvalid(handle)) {
                Kernel32.INSTANCE.CloseHandle(handle);
            }
        }

        @Override
        public int lastError() {
            return Native.getLastError();
        }

        @Override
        public boolean isInvalid(Pointer handle) {
            return isInvalidHandle(handle);
        }
    }

    private static String findDevicePath() {
        List<String> paths = listDevicePaths();
        for (String path : paths) {
            String p = path.toLowerCase(Locale.ROOT);
            if (p.contains("vid_413c") && p.contains("pid_2107") && (p.contains("mi_01") || p.contains("col02"))) {
                return path;
            }
        }
        for (String path : paths) {
            String p = path.toLowerCase(Locale.ROOT);
            if (p.contains("vid_413c") && p.contains("pid_2107")) {
                return path;
            }
        }
        return null;
    }

    private static List<String> listDevicePaths() {
        Guid.GUID hidGuid = new Guid.GUID();
        Hid.INSTANCE.HidD_GetHidGuid(hidGuid);
        Pointer infoSet = SetupApi.INSTANCE.SetupDiGetClassDevs(hidGuid, Pointer.NULL, Pointer.NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (isInvalidHandle(infoSet)) {
            return List.of();
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
                if (ok && detail.DevicePath != null) {
                    String path = Native.toString(detail.DevicePath);
                    if (path != null && !path.isBlank()) {
                        paths.add(path);
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("USB HID enumerate failed: {}", e.getMessage());
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
        boolean CancelIoEx(Pointer file, Pointer overlapped);
        boolean CloseHandle(Pointer object);
    }
}
