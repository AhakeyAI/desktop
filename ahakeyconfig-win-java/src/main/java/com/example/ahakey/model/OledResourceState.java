package com.example.ahakey.model;

import com.example.ahakey.protocol.AhaKeyProtocol;
import java.util.zip.CRC32;

/** Local intent and device observations are deliberately independent. */
public record OledResourceState(int entry, Asset asset, LocalStatus localStatus,
                                Metadata device, boolean deviceKnown, boolean inFlight,
                                boolean commitUncertain, String notice, UploadIdentity uploadIdentity) {
    public OledResourceState(int entry,Asset asset,LocalStatus localStatus,Metadata device,boolean deviceKnown,boolean inFlight,boolean commitUncertain,String notice){
        this(entry,asset,localStatus,device,deviceKnown,inFlight,commitUncertain,notice,null);
    }
    public record UploadIdentity(int protocol,int frames,long bytes,long crc){
        public UploadIdentity {if((protocol!=2&&protocol!=3&&protocol!=4)||frames<1||frames>12||bytes!=frames*28672L||crc<0||crc>0xffffffffL)throw new IllegalArgumentException("Invalid upload identity");}
        public boolean matches(Metadata m){return m!=null&&m.valid()&&m.frames()==frames&&m.bytes()==bytes&&m.crc()==crc;}
    }
    public OledResourceState forUpload(boolean legacy){
        UploadIdentity identity;
        if(asset.compact())identity=new UploadIdentity(3,asset.frames(),asset.bytes.length,asset.crc());
        else if(legacy)identity=new UploadIdentity(2,asset.frames(),asset.bytes.length,asset.crc());
        else {var e=com.example.ahakey.util.LosslessResourceEncoder.encode(asset.bytes(),entry);identity=new UploadIdentity(4,asset.frames(),asset.bytes.length,e.expandedCrc());}
        return new OledResourceState(entry,asset,localStatus,device,deviceKnown,inFlight,commitUncertain,notice,identity);
    }
    private boolean matchesExpected(Metadata value){return uploadIdentity==null?value.matches(asset):uploadIdentity.matches(value);}
    public enum LocalStatus { EMPTY, DRAFT, FAILED, APPLIED }

    public record Asset(byte[] bytes, int frames, long crc, byte[] compactBytes) {
        public Asset(byte[] bytes, int frames, long crc) { this(bytes, frames, crc, null); }
        public Asset {
            if (frames < 1 || frames > 12 || bytes.length != frames * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE)
                throw new IllegalArgumentException("Invalid OLED asset size");
            CRC32 checksum = new CRC32();
            checksum.update(bytes);
            if (checksum.getValue() != crc) throw new IllegalArgumentException("Invalid OLED asset CRC");
            if (compactBytes != null) {
                if (!java.util.Arrays.equals(bytes, com.example.ahakey.util.CompactResourceEncoder.expand(compactBytes)))
                    throw new IllegalArgumentException("Compact/expanded OLED identity mismatch");
                compactBytes = compactBytes.clone();
            } else for (int f = 0; f < frames; f++) {
                for (int i = AhaKeyProtocol.OLED_FRAME_BYTES; i < AhaKeyProtocol.OLED_FRAME_SLOT_SIZE; i++)
                    if (bytes[f * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE + i] != 0)
                        throw new IllegalArgumentException("Invalid OLED padding");
            }
            bytes = bytes.clone();
        }
        @Override public byte[] bytes() { return bytes.clone(); }
        @Override public byte[] compactBytes() { return compactBytes == null ? null : compactBytes.clone(); }
        public boolean compact() { return compactBytes != null; }
        public String modeText() { return compact() ? "快速上传 · 16色 / 80×40" : "原画质上传 · RGB565 / 160×80"; }
        public int transferBytes() { return compact() ? compactBytes.length : bytes.length; }
        public int durationMillis(int frame) {
            if (frame < 0 || frame >= frames) throw new IllegalArgumentException("frame");
            return compact() ? Short.toUnsignedInt(java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN).getShort(frame * 28672 + 25608)) : 100;
        }
        public static Asset fromCompact(byte[] object) {
            byte[] expanded = com.example.ahakey.util.CompactResourceEncoder.expand(object);
            return new Asset(expanded, expanded.length / 28672, com.example.ahakey.protocol.CompactUploadProtocol.crc(expanded), object);
        }
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
        if(uploadIdentity!=null&&(asset==null||uploadIdentity.frames()!=asset.frames()))throw new IllegalArgumentException("Upload identity asset mismatch");
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
        return new OledResourceState(entry, asset, localStatus, device, false, true, false, "", uploadIdentity);
    }
    public OledResourceState failed(String reason, boolean uncertainCommit) {
        return new OledResourceState(entry, asset, asset == null ? LocalStatus.EMPTY : LocalStatus.FAILED,
                device, false, false, uncertainCommit, reason, uploadIdentity);
    }
    public OledResourceState committing() {
        return new OledResourceState(entry, asset, localStatus, device, false, true, true, "设备保存结果未确认。", uploadIdentity);
    }
    public OledResourceState applied() {
        if (asset == null) throw new IllegalStateException("Missing asset");
        return new OledResourceState(entry, asset, LocalStatus.APPLIED,
                new Metadata(true, 2, asset.frames(), asset.bytes.length, uploadIdentity==null?asset.crc():uploadIdentity.crc()), true, false, false, "", uploadIdentity);
    }
    public OledResourceState unknown() {
        return new OledResourceState(entry, asset, localStatus, device, false, inFlight, commitUncertain, notice, uploadIdentity);
    }
    public OledResourceState merge(Metadata value) {
        LocalStatus status = localStatus;
        String message = notice;
        if (asset != null && localStatus == LocalStatus.APPLIED && !matchesExpected(value)) {
            status = LocalStatus.DRAFT;
            message = "本机预览和当前键盘不一致，已作为草稿保留。";
        } else if (commitUncertain && matchesExpected(value)) {
            status = LocalStatus.APPLIED;
            message = "已应用到 " + targetName() + "。";
        }
        return new OledResourceState(entry, asset, status, value, true, false, false, message, uploadIdentity);
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
