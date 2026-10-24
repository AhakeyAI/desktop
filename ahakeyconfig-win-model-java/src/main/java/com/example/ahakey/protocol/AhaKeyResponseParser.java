package com.example.ahakey.protocol;

public final class AhaKeyResponseParser {
    public record CommandResponse(byte cmd, byte status, byte[] payload) {
    }

    public record PictureState(
        int mode,
        int startIndex,
        int picLength,
        int frameInterval,
        int allModeMaxPic
    ) {
    }

    /**
     * 单键键位绑定查询响应(对应固件 0x97 命令)。
     *
     * <p><b>注意</b>:B 方案下固件只返前 10 字节 bind(sub + len + hid[8]),响应总长 19 字节,
     * 装得下 BLE notify 单包(MTU 20)。完整 100 字节需要后续 MTU 协商后升级。
     *
     * @param mode     模式 (0..3)
     * @param keyIndex 键位 (0..3)
     * @param sub      子类型:0x73 单键 / 0x74 组合键(同 hid_bytes 槽位,语义不同) / 0x75 描述(走 desc 槽)
     * @param bindLen  HID 有效字节数 (0..98,可能 > 8 表示实际 bindLen > 8 但本次只返了前 8 字节)
     * @param hidBytes 固定 8 字节槽位(本次读到的),如 bindLen > 8 表示 EEPROM 里还有更多但本次没读全
     */
    public record KeyBinding(
        int mode,
        int keyIndex,
        byte sub,
        int bindLen,
        byte[] hidBytes
    ) {
    }

    /**
     * 单键键位绑定的 8 字节 chunk(对应固件 0x98 命令)。
     */
    public record KeyBindingChunk(
        int mode,
        int keyIndex,
        int offset,
        byte[] chunk
    ) {
    }

    /**
     * 单键键位绑定的完整 100 字节(0x97 + 0x98 拼装结果)。
     * <p>{@code hidBytes} 长度为 {@code bindLen}(EEPROM 实际长度,可能 < 100)。
     */
    public record FullKeyBinding(
        int mode,
        int keyIndex,
        byte sub,
        int bindLen,
        byte[] hidBytes
    ) {
    }

    private AhaKeyResponseParser() {
    }

    public static CommandResponse parseCommandResponse(byte[] frame) {
        if (!AhaKeyProtocol.isValidFrame(frame) || frame.length < 6) {
            return null;
        }
        byte cmd = frame[2];
        byte status = frame[3];
        int payloadLen = frame.length - 6;
        byte[] payload = new byte[payloadLen];
        if (payloadLen > 0) {
            System.arraycopy(frame, 4, payload, 0, payloadLen);
        }
        return new CommandResponse(cmd, status, payload);
    }

    public static PictureState parsePictureState(byte[] payload) {
        if (payload == null || payload.length < 9) {
            return null;
        }
        int offset = payload[0] == 0 ? 1 : 0;
        if (payload.length < offset + 9) {
            return null;
        }
        int mode = payload[offset] & 0xFF;
        int startIndex = (payload[offset + 1] & 0xFF) | ((payload[offset + 2] & 0xFF) << 8);
        int picLength = (payload[offset + 3] & 0xFF) | ((payload[offset + 4] & 0xFF) << 8);
        int frameInterval = (payload[offset + 5] & 0xFF) | ((payload[offset + 6] & 0xFF) << 8);
        int allModeMaxPic = (payload[offset + 7] & 0xFF) | ((payload[offset + 8] & 0xFF) << 8);
        return new PictureState(mode, startIndex, picLength, frameInterval, allModeMaxPic);
    }

    /**
     * 解析单键键位绑定响应(payload 来源于 0x97 命令响应)。
     * <p>payload 格式: {@code [mode(1B)][key(1B)][bind_first_10B(10B)]} = 12 字节,
     * bind 前 2 字节为 {@code [sub, len]},后 8 字节为 HID(只读前 8 字节,因 MTU 限制)。
     *
     * @return 解析失败返回 null
     */
    public static KeyBinding parseKeyBinding(byte[] payload) {
        if (payload == null || payload.length < 2 + 10) {
            return null;
        }
        int mode = payload[0] & 0xFF;
        int keyIndex = payload[1] & 0xFF;
        byte sub = payload[2];
        int bindLen = payload[3] & 0xFF;
        byte[] hid = new byte[8];
        System.arraycopy(payload, 4, hid, 0, 8);
        return new KeyBinding(mode, keyIndex, sub, bindLen, hid);
    }

    /**
     * 解析单键键位绑定 chunk 响应(payload 来源于 0x98 命令响应)。
     * <p>payload 格式: {@code [mode(1B)][key(1B)][offset(1B)][chunk(8B)]} = 11 字节。
     */
    public static KeyBindingChunk parseKeyBindingChunk(byte[] payload) {
        if (payload == null || payload.length < 3 + 8) {
            return null;
        }
        int mode = payload[0] & 0xFF;
        int keyIndex = payload[1] & 0xFF;
        int offset = payload[2] & 0xFF;
        byte[] chunk = new byte[8];
        System.arraycopy(payload, 3, chunk, 0, 8);
        return new KeyBindingChunk(mode, keyIndex, offset, chunk);
    }
}
