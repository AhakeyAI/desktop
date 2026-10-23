package com.example.ahakey.model;

import com.example.ahakey.protocol.AhaKeyProtocol;
import java.util.zip.CRC32;

/** Local intent and device observations are deliberately independent. */
public record OledResourceState(int entry, Asset asset, LocalStatus localStatus,
                                Metadata device, boolean deviceKnown, boolean inFlight,
                                boolean commitUncertain, String notice) {
    public enum LocalStatus { EMPTY, DRAFT, FAILED, APPLIED }

    public record Asset(byte[] bytes, int frames, long crc) {
        public Asset {
            if (frames < 1 || frames > 12 || bytes.length != frames * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE)
                throw new IllegalArgumentException("Invalid OLED asset size");
            CRC32 checksum = new CRC32();
            checksum.update(bytes);
            if (checksum.getValue() != crc) throw new IllegalArgumentException("Invalid OLED asset CRC");
            for (int f = 0; f < frames; f++) {
                for (int i = AhaKeyProtocol.OLED_FRAME_BYTES; i < AhaKeyProtocol.OLED_FRAME_SLOT_SIZE; i++)
                    if (bytes[f * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE + i] != 0)
                        throw new IllegalArgumentException("Invalid OLED padding");
            }
            bytes = bytes.clone();
        }
        @Override public byte[] bytes() { return bytes.clone(); }
        public static Asset fromBytes(byte[] bytes) {
            CRC32 crc = new CRC32();
            crc.update(bytes);
            return new Asset(bytes, bytes.length / AhaKeyProtocol.OLED_FRAME_SLOT_SIZE, crc.getValue());
        }
    }

    public record Metadata(boolean valid, int writeState, int frames, long bytes, long crc) {
        public Metadata {
            if (writeState < 0 || writeState > 3 || valid != (writeState == 2) || crc < 0 || crc > 0xffffffffL
                    || (valid && (frames < 1 || frames > 12 || bytes != (long) frames * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE))
                    || (!valid && (frames != 0 || bytes != 0 || crc != 0)))
                throw new IllegalArgumentException("Inconsistent OLED metadata");
        }
        public boolean matches(Asset asset) {
            return valid && asset != null && frames == asset.frames() && bytes == asset.bytes.length && crc == asset.crc();
        }
    }

    public OledResourceState {
        int cap = AhaKeyProtocol.resourceCapacity(entry);
        if (asset != null && asset.frames() > cap) throw new IllegalArgumentException("OLED capacity");
        if (device != null && device.frames() > cap) throw new IllegalArgumentException("OLED device capacity");
        if (localStatus == null || (asset == null) != (localStatus == LocalStatus.EMPTY))
            throw new IllegalArgumentException("OLED local state");
        if (deviceKnown && device == null) throw new IllegalArgumentException("OLED device fact");
        notice = notice == null ? "" : notice;
    }

    public static OledResourceState empty(int entry) {
        return new OledResourceState(entry, null, LocalStatus.EMPTY, null, false, false, false, "");
    }
    public int capacity() { return AhaKeyProtocol.resourceCapacity(entry); }
    public boolean canUpload() { return asset != null && !inFlight && (localStatus == LocalStatus.DRAFT || localStatus == LocalStatus.FAILED); }
    public String targetName() {
        String[] single = {"默认屏幕", "SINGLE · 工作中", "SINGLE · 等待中", "SINGLE · 已完成"};
        String[] multi = {"运行中", "等待中", "已完成"};
        return entry < 16 ? "Mode " + (entry / 4 + 1) + " · " + single[entry % 4] : "全局 MULTI · " + multi[entry - 16];
    }
    public OledResourceState replace(Asset value) {
        return new OledResourceState(entry, value, LocalStatus.DRAFT, device, deviceKnown, false, false, "");
    }
    public OledResourceState clear() {
        return new OledResourceState(entry, null, LocalStatus.EMPTY, device, deviceKnown, false, false, "");
    }
    public OledResourceState uploading() {
        if (!canUpload()) throw new IllegalStateException("没有可上传的草稿。");
        return new OledResourceState(entry, asset, localStatus, device, false, true, false, "");
    }
    public OledResourceState failed(String reason, boolean uncertainCommit) {
        return new OledResourceState(entry, asset, asset == null ? LocalStatus.EMPTY : LocalStatus.FAILED,
                device, false, false, uncertainCommit, reason);
    }
    public OledResourceState committing() {
        return new OledResourceState(entry, asset, localStatus, device, false, true, true, "设备保存结果未确认。");
    }
    public OledResourceState applied() {
        if (asset == null) throw new IllegalStateException("Missing asset");
        return new OledResourceState(entry, asset, LocalStatus.APPLIED,
                new Metadata(true, 2, asset.frames(), asset.bytes.length, asset.crc()), true, false, false, "");
    }
    public OledResourceState unknown() {
        return new OledResourceState(entry, asset, localStatus, device, false, inFlight, commitUncertain, notice);
    }
    public OledResourceState merge(Metadata value) {
        LocalStatus status = localStatus;
        String message = notice;
        if (asset != null && localStatus == LocalStatus.APPLIED && !value.matches(asset)) {
            status = LocalStatus.DRAFT;
            message = "本机预览和当前键盘不一致，已作为草稿保留。";
        } else if (commitUncertain && value.matches(asset)) {
            status = LocalStatus.APPLIED;
            message = "已应用到 " + targetName() + "。";
        }
        return new OledResourceState(entry, asset, status, value, true, false, false, message);
    }
    public String statusText() {
        if (inFlight) return "上传中...";
        return switch (localStatus) {
            case DRAFT -> "草稿";
            case FAILED -> commitUncertain ? "保存结果未确认" : "上次失败";
            case APPLIED -> deviceKnown ? "已应用" : "已应用（待核对）";
            case EMPTY -> deviceKnown ? (device.valid() ? "设备已有" : "空") : "设备状态未知";
        };
    }
}
