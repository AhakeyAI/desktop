package com.example.ahakey.service;

import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.sun.jna.Pointer;
import com.sun.jna.ptr.IntByReference;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class UsbHidTransportSessionTest {
    @Test
    void configPayloadCcDdDoesNotTruncateAndSupportsSplitPaddedAndMultipleReports() {
        byte[] frame = hex("AA BB 9D 00 02 00 02 00 02 11 CC CC DD");
        UsbHidTransport.FrameExtractor extractor = new UsbHidTransport.FrameExtractor();
        assertTrue(extractor.accept(Arrays.copyOf(frame, 8), 8).isEmpty());
        byte[] padded = new byte[64];
        System.arraycopy(frame, 8, padded, 0, frame.length - 8);
        var frames = extractor.accept(padded, padded.length);
        assertEquals(1, frames.size());
        assertArrayEquals(frame, frames.get(0));
        var parsed = AhaKeyResponseParser.parseConfigChunk(
            AhaKeyResponseParser.parseCommandResponse(frames.get(0)));
        assertNotNull(parsed);
        assertArrayEquals(new byte[]{0x11, (byte) 0xCC}, parsed.data());

        UsbHidTransport.FrameExtractor multiple = new UsbHidTransport.FrameExtractor();
        byte[] second = hex("AA BB 9D 00 01 00 09 08 01 AA CC DD");
        byte[] carrier = new byte[frame.length + second.length];
        System.arraycopy(frame, 0, carrier, 0, frame.length);
        System.arraycopy(second, 0, carrier, frame.length, second.length);
        assertEquals(2, multiple.accept(carrier, carrier.length).size());
    }

    @Test
    void configExtractorRejectsMalformedTrailerAndTruncatedResponse() {
        UsbHidTransport.FrameExtractor extractor = new UsbHidTransport.FrameExtractor();
        byte[] malformed = hex("AA BB 9D 00 02 00 02 00 02 11 22 00 00");
        assertTrue(extractor.accept(malformed, malformed.length).isEmpty());
        byte[] truncated = hex("AA BB 9D 00 00 00 64 00 08 01 02");
        assertTrue(extractor.accept(truncated, truncated.length).isEmpty());
        assertNotNull(extractor);
    }

    @Test
    void blockedReadCloseReopenKeepsOldReaderIsolatedUntilItExits() throws Exception {
        ControlledHidIo io = new ControlledHidIo(true);
        UsbHidTransport transport = new UsbHidTransport(io, 25);
        AtomicInteger oldFrames = new AtomicInteger();
        AtomicInteger newFrames = new AtomicInteger();
        AtomicInteger oldDisconnects = new AtomicInteger();
        AtomicInteger newDisconnects = new AtomicInteger();

        transport.open((frame, time) -> oldFrames.incrementAndGet(),
            oldDisconnects::incrementAndGet);
        assertTrue(io.awaitRead(1));

        Thread close = new Thread(transport::close);
        close.start();
        assertTrue(io.awaitCancel(1));

        // open() can obtain the state lock while close() is waiting: close
        // does not join while holding the lock needed by reader/future open.
        transport.open((frame, time) -> newFrames.incrementAndGet(),
            newDisconnects::incrementAndGet);
        assertTrue(io.awaitRead(3));
        assertTrue(transport.isOpen());

        io.completeRead(1, statusFrame(0));
        close.join(1_000);
        assertFalse(close.isAlive());
        assertEquals(0, oldFrames.get(), "stale AUTO frame escaped old session");
        assertEquals(0, oldDisconnects.get(), "stale disconnect callback escaped old session");
        assertEquals(0, newDisconnects.get());
        assertTrue(transport.isOpen(), "old reader finally closed the new session");
        assertFalse(io.closedHandles.contains(3L));
        assertFalse(io.closedHandles.contains(4L));

        io.completeRead(3, statusFrame(1));
        assertTrue(waitForCount(newFrames, 1));
        transport.close();
    }

    @Test
    void closeIsIdempotentAndCancelsBlockingRead() throws Exception {
        ControlledHidIo io = new ControlledHidIo(false);
        UsbHidTransport transport = new UsbHidTransport(io, 100);
        transport.open((frame, time) -> {}, () -> {});
        assertTrue(io.awaitRead(1));

        transport.close();
        transport.close();

        assertFalse(transport.isOpen());
        assertEquals(1, io.cancelCount.get());
        assertEquals(Set.of(1L, 2L), io.closedHandles);
    }

    private static boolean waitForCount(AtomicInteger value, int expected)
        throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1);
        while (value.get() < expected && System.nanoTime() < deadline) {
            Thread.sleep(2);
        }
        return value.get() == expected;
    }

    private static byte[] statusFrame(int switchState) {
        return new byte[]{
            (byte) 0xAA, (byte) 0xBB, 0,
            94, 50, 1, 3, 2, 1, (byte) switchState, 35, 3,
            (byte) 0xCC, (byte) 0xDD
        };
    }

    private static byte[] hex(String value) {
        return java.util.HexFormat.of().parseHex(value.replace(" ", ""));
    }

    private static final class ControlledHidIo implements UsbHidTransport.HidIo {
        private final AtomicInteger nextHandle = new AtomicInteger(1);
        private final Map<Long, ReadControl> reads = new ConcurrentHashMap<>();
        private final boolean keepFirstReadBlockedAfterCancel;
        final Set<Long> closedHandles = ConcurrentHashMap.newKeySet();
        final AtomicInteger cancelCount = new AtomicInteger();

        ControlledHidIo(boolean keepFirstReadBlockedAfterCancel) {
            this.keepFirstReadBlockedAfterCancel = keepFirstReadBlockedAfterCancel;
        }

        @Override public String findDevicePath() { return "fake-hid"; }
        @Override public Pointer openRead(String path) {
            long id = nextHandle.getAndIncrement();
            reads.put(id, new ReadControl());
            return Pointer.createConstant(id);
        }
        @Override public Pointer openWrite(String path) {
            return Pointer.createConstant(nextHandle.getAndIncrement());
        }
        @Override public UsbHidTransport.ReadResult read(Pointer handle, byte[] buffer) {
            ReadControl control = reads.get(Pointer.nativeValue(handle));
            control.entered.countDown();
            try {
                if (control.calls.getAndIncrement() == 0) {
                    control.release.await(2, TimeUnit.SECONDS);
                } else {
                    control.cancelled.await(2, TimeUnit.SECONDS);
                    return new UsbHidTransport.ReadResult(false, 0, 995);
                }
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                return new UsbHidTransport.ReadResult(false, 0, 995);
            }
            if (control.frame == null) {
                return new UsbHidTransport.ReadResult(false, 0, 995);
            }
            Arrays.fill(buffer, (byte) 0);
            System.arraycopy(control.frame, 0, buffer, 0, control.frame.length);
            return new UsbHidTransport.ReadResult(true, control.frame.length, 0);
        }
        @Override public boolean write(
            Pointer handle, byte[] buffer, IntByReference written
        ) {
            if (closedHandles.contains(Pointer.nativeValue(handle))) return false;
            written.setValue(buffer.length);
            return true;
        }
        @Override public void cancel(Pointer handle) {
            cancelCount.incrementAndGet();
            long id = Pointer.nativeValue(handle);
            ReadControl control = reads.get(id);
            if (control != null && !(keepFirstReadBlockedAfterCancel && id == 1L)) {
                control.release.countDown();
                control.cancelled.countDown();
            }
        }
        @Override public void close(Pointer handle) {
            if (!isInvalid(handle)) closedHandles.add(Pointer.nativeValue(handle));
        }
        @Override public int lastError() { return 5; }
        @Override public boolean isInvalid(Pointer handle) {
            return handle == null || Pointer.nativeValue(handle) <= 0;
        }

        boolean awaitRead(long handle) throws InterruptedException {
            return reads.get(handle).entered.await(1, TimeUnit.SECONDS);
        }
        boolean awaitCancel(long handle) throws InterruptedException {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1);
            while (cancelCount.get() == 0 && System.nanoTime() < deadline) {
                Thread.sleep(2);
            }
            return cancelCount.get() > 0;
        }
        void completeRead(long handle, byte[] frame) {
            ReadControl control = reads.get(handle);
            control.frame = frame;
            control.release.countDown();
        }
    }

    private static final class ReadControl {
        final CountDownLatch entered = new CountDownLatch(1);
        final CountDownLatch release = new CountDownLatch(1);
        final CountDownLatch cancelled = new CountDownLatch(1);
        final AtomicInteger calls = new AtomicInteger();
        volatile byte[] frame;
    }
}
