package com.example.ahakey.service;

import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;

import java.util.function.Consumer;

public final class OledUploadService {
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
        if (asset.frames() > AhaKeyProtocol.resourceCapacity(entry)) throw new IllegalArgumentException("frames");
        byte[] bytes = asset.bytes();
        boolean commitSent = false;
        try (BleManager.DisplayLease lease = ble.openDisplayLease(true, generation)) {
            try {
                requireAck(ble.exchangeDisplay(lease, AhaKeyProtocol.resourceBegin(entry, asset.frames(), asset.crc())), AhaKeyProtocol.CMD_RESOURCE_BEGIN);
                for (int offset = 0; offset < bytes.length; ) {
                    int length = Math.min(AhaKeyProtocol.RESOURCE_CHUNK_BYTES, bytes.length - offset);
                    requireAck(ble.exchangeDisplay(lease, AhaKeyProtocol.resourceChunk(entry, offset,
                            java.util.Arrays.copyOfRange(bytes, offset, offset + length))), AhaKeyProtocol.CMD_RESOURCE_CHUNK);
                    offset += length;
                    acknowledgedPercent.accept(offset * 100 / bytes.length);
                }
                beforeCommit.persist();
                commitSent = true;
                requireAck(ble.exchangeDisplay(lease, AhaKeyProtocol.resourceCommit(entry)), AhaKeyProtocol.CMD_RESOURCE_COMMIT);
            } catch (Exception e) {
                // Quarantine before close can flush deferred writers while an upload may still be active.
                if (!(e instanceof DeviceRejected)) ble.requireDisplayRecovery(generation);
                throw e;
            }
        } catch (Exception e) {
            throw new UploadFailure("上传并应用未完成：" + e.getMessage() + " 键盘资源有效性需重新同步确认。", e,
                    commitSent && !(e instanceof DeviceRejected));
        }
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
