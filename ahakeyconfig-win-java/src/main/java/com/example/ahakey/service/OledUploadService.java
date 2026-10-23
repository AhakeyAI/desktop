package com.example.ahakey.service;

import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;

import java.util.function.Consumer;

public final class OledUploadService {
    private static final org.slf4j.Logger logger = org.slf4j.LoggerFactory.getLogger(OledUploadService.class);
    private static final java.util.concurrent.atomic.AtomicLong IDS = new java.util.concurrent.atomic.AtomicLong();
    @FunctionalInterface public interface BeforeCommit { void persist() throws java.io.IOException; }
    public static final class UploadFailure extends Exception {
        private final boolean commitUncertain;
        public UploadFailure(String message, Throwable cause, boolean commitUncertain) {
            super(message, cause);
            this.commitUncertain = commitUncertain;
        }
        public boolean commitUncertain() { return commitUncertain; }
    }

    public static void uploadResource(BleManager ble, long generation, int entry,
            com.example.ahakey.model.OledResourceState.Asset asset,
            Consumer<Integer> acknowledgedPercent, BeforeCommit beforeCommit) throws Exception {
        uploadResource(ble, generation, entry, asset, acknowledgedPercent, beforeCommit, detail -> {});
    }

    public record Progress(int acknowledgedBytes, int totalBytes, long elapsedMillis) {
        public String text() {
            long rate = elapsedMillis > 0 ? acknowledgedBytes * 1000L / elapsedMillis : 0;
            return (acknowledgedBytes * 100 / totalBytes) + "% · " + (elapsedMillis / 1000) + " 秒 · " + rate + " B/s";
        }
    }

    public static void uploadResource(BleManager ble, long generation, int entry,
            com.example.ahakey.model.OledResourceState.Asset asset,
            Consumer<Integer> acknowledgedPercent, BeforeCommit beforeCommit, Consumer<Progress> progress) throws Exception {
        if (asset.frames() > AhaKeyProtocol.resourceCapacity(entry)) throw new IllegalArgumentException("frames");
        byte[] bytes = asset.bytes();
        boolean commitSent = false;
        long transaction = IDS.incrementAndGet();
        long start = System.nanoTime();
        String phase = "BEGIN";
        int acknowledged = 0;
        logger.info("OLED upload start txn={} connection={} entry={} bytes={} transport={}", transaction, generation, entry, bytes.length,
                ble.isUsbTransportOpen() ? "USB" : "BLE");
        try (BleManager.DisplayLease lease = ble.openDisplayLease(true, generation)) {
            try {
                requireAck(ble.exchangeDisplay(lease, AhaKeyProtocol.resourceBegin(entry, asset.frames(), asset.crc())), AhaKeyProtocol.CMD_RESOURCE_BEGIN);
                for (int offset = 0; offset < bytes.length; ) {
                    phase = "CHUNK";
                    int length = Math.min(AhaKeyProtocol.RESOURCE_CHUNK_BYTES, bytes.length - offset);
                    requireAck(ble.exchangeDisplay(lease, AhaKeyProtocol.resourceChunk(entry, offset,
                            java.util.Arrays.copyOfRange(bytes, offset, offset + length))), AhaKeyProtocol.CMD_RESOURCE_CHUNK);
                    offset += length;
                    acknowledged = offset;
                    acknowledgedPercent.accept(offset * 100 / bytes.length);
                    progress.accept(new Progress(offset, bytes.length, (System.nanoTime() - start) / 1_000_000));
                }
                phase = "LOCAL_COMMIT_RECORD";
                beforeCommit.persist();
                phase = "COMMIT";
                commitSent = true;
                requireAck(ble.exchangeDisplay(lease, AhaKeyProtocol.resourceCommit(entry)), AhaKeyProtocol.CMD_RESOURCE_COMMIT);
            } catch (Exception e) {
                // Quarantine before close can flush deferred writers while an upload may still be active.
                if (!(e instanceof DeviceRejected)) ble.requireDisplayRecovery(generation);
                throw e;
            }
        } catch (Exception e) {
            logger.warn("OLED upload incomplete txn={} connection={} entry={} phase={} acknowledged={} elapsedMs={} failure={} recoveryRequired={}",
                    transaction, generation, entry, phase, acknowledged, (System.nanoTime() - start) / 1_000_000,
                    e.getClass().getSimpleName(), ble.isDisplayWriteUncertain());
            throw new UploadFailure("上传并应用未完成（" + phase + "，已确认 " + acknowledged + "/" + bytes.length + " 字节）："
                    + e.getMessage() + " 键盘资源有效性需重新同步确认。"
                    + (ble.isDisplayWriteUncertain() ? " AI 状态发送已暂停；请断开并重新连接键盘后同步，本地资源已保留。" : ""), e,
                    commitSent && !(e instanceof DeviceRejected));
        }
        logger.info("OLED upload committed txn={} connection={} entry={} bytes={} elapsedMs={}",
                transaction, generation, entry, bytes.length, (System.nanoTime() - start) / 1_000_000);
    }

    public static final class DeviceRejected extends java.io.IOException {
        public DeviceRejected() { super("键盘返回 FAIL。"); }
    }

    public static void requireAck(byte[] reply, byte opcode) throws java.io.IOException {
        if (!AhaKeyResponseParser.isDisplayAck(reply, opcode)) throw new java.io.IOException("设备响应格式无效。");
        if (reply[3] != 0) throw new DeviceRejected();
    }
    private OledUploadService() { }
}
