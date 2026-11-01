package com.example.ahakey.displayconfig;

import com.example.ahakey.service.BleManager;
import com.example.ahakey.service.UsbHidTransport;
import java.io.IOException;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;

/** Every fixture uses this constructor before any production send or lease operation. */
final class OfflineBleManager extends BleManager {
    final MemoryUsb usb = new MemoryUsb();
    final AtomicInteger discoveries = new AtomicInteger();
    final AtomicInteger blockedConnections = new AtomicInteger();
    volatile boolean usbPresent;

    OfflineBleManager(BleCallback callback) throws ReflectiveOperationException {
        super(callback);
        Field transport = BleManager.class.getDeclaredField("usbTransport");
        transport.setAccessible(true);
        transport.set(this, usb);
    }

    @Override protected boolean isUsbDevicePresent() {
        discoveries.incrementAndGet();
        return usbPresent;
    }

    @Override public void connect() {
        blockedConnections.incrementAndGet();
        throw new AssertionError("Real connection forbidden in offline fixture");
    }

    static final class MemoryUsb extends UsbHidTransport {
        private volatile boolean opened;
        volatile Consumer<byte[]> commands = frame -> { throw new AssertionError("Unexpected USB command"); };
        final AtomicInteger opens = new AtomicInteger();
        final AtomicInteger closes = new AtomicInteger();
        final List<byte[]> sent = Collections.synchronizedList(new ArrayList<>());
        final List<byte[]> data = Collections.synchronizedList(new ArrayList<>());

        @Override public void open(Consumer<byte[]> onFrame) {
            opens.incrementAndGet();
            opened = true;
        }
        @Override public boolean isOpen() { return opened; }
        @Override public void close() {
            closes.incrementAndGet();
            opened = false;
        }
        @Override public void sendCommand(byte[] frame) throws IOException {
            if (!opened) throw new IOException("Memory USB closed");
            sent.add(frame.clone());
            commands.accept(frame.clone());
        }
        @Override public void sendData(byte[] bytes) throws IOException {
            if (!opened) throw new IOException("Memory USB closed");
            data.add(bytes.clone());
        }
    }
}
