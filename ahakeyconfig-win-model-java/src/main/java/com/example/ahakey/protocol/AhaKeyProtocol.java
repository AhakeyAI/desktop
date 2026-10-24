package com.example.ahakey.protocol;

import com.example.ahakey.model.DeviceStatus;

public class AhaKeyProtocol {
    private static final byte[] HEADER = {(byte) 0xAA, (byte) 0xBB};
    private static final byte[] TRAILER = {(byte) 0xCC, (byte) 0xDD};
    
    // 命令定义
    public static final byte CMD_QUERY_STATUS = 0x00;
    public static final byte CMD_CHANGE_NAME = 0x01;
    public static final byte CMD_CHANGE_APPEARANCE = 0x02;
    public static final byte CMD_SAVE_CONFIG = 0x04;
    public static final byte CMD_UPDATE_CUSTOM_KEY = 0x73;
    public static final byte CMD_PREPARE_WRITE = (byte) 0x80;
    public static final byte CMD_WRITE_RESULT = (byte) 0x81;
    public static final byte CMD_UPDATE_PIC = (byte) 0x82;
    public static final byte CMD_READ_PIC_STATE = (byte) 0x83;
    public static final byte CMD_SET_AI_LIGHT_CONFIG = (byte) 0x84;
    public static final byte CMD_SET_LIGHT_BRIGHTNESS = (byte) 0x85;
    public static final byte CMD_UPDATE_STATE = (byte) 0x90;
    public static final byte CMD_SET_LIGHT_EFFECT = (byte) 0x91;
    public static final byte CMD_SET_WORK_MODE = (byte) 0x92;
    public static final byte CMD_QUERY_KEY_BINDING = (byte) 0x97;
    public static final byte CMD_READ_KEY_BINDING_CHUNK = (byte) 0x98;
    public static final byte CMD_ENTER_BOOT = (byte) 0x9A;

    // 按键子类型
    public static final byte SUB_SHORTCUT = 0x73;
    public static final byte SUB_MACRO = 0x74;
    public static final byte SUB_DESCRIPTION = 0x75;
    
    // OLED 常量（与 Swift / Windows Python 客户端一致）
    public static final int OLED_WIDTH = 160;
    public static final int OLED_HEIGHT = 80;
    public static final int OLED_FRAME_BYTES = OLED_WIDTH * OLED_HEIGHT * 2;
    public static final int OLED_FRAME_SLOT_SIZE = 28_672;
    // PY25Q64HA is 64 Mbit / 8 MB. Firmware stores each OLED frame in a 7-sector slot.
    public static final int OLED_MAX_FRAMES = 292;
    public static final int OLED_MAX_SOURCE_FILE_BYTES = 2 * 1024 * 1024;
    public static final int OLED_CHUNK_SIZE = 4096;
    public static final int OLED_PACKET_SIZE = 180;
    
    public static byte[] buildFrame(byte cmd, byte[] data) {
        byte[] frame = new byte[HEADER.length + 1 + (data != null ? data.length : 0) + TRAILER.length];
        int offset = 0;
        
        System.arraycopy(HEADER, 0, frame, offset, HEADER.length);
        offset += HEADER.length;
        
        frame[offset++] = cmd;
        
        if (data != null && data.length > 0) {
            System.arraycopy(data, 0, frame, offset, data.length);
            offset += data.length;
        }
        
        System.arraycopy(TRAILER, 0, frame, offset, TRAILER.length);
        return frame;
    }
    
    public static byte[] queryDeviceStatus() {
        return buildFrame(CMD_QUERY_STATUS, new byte[0]);
    }
    
    public static byte[] updateState(byte state) {
        return buildFrame(CMD_UPDATE_STATE, new byte[]{state});
    }
    
    public static byte[] setLightEffect(byte effectCode) {
        return buildFrame(CMD_SET_LIGHT_EFFECT, new byte[]{effectCode});
    }

    public static byte[] setLightBrightness(int brightness) {
        int value = Math.max(1, Math.min(100, brightness));
        return buildFrame(CMD_SET_LIGHT_BRIGHTNESS, new byte[]{(byte) value});
    }

    public static byte[] setWorkMode(int mode) {
        return buildFrame(CMD_SET_WORK_MODE, new byte[]{(byte) Math.max(0, Math.min(3, mode))});
    }

    public static byte[] setAiLightConfig(int mode, byte[] effectCodes) {
        byte[] payload = new byte[1 + effectCodes.length];
        payload[0] = (byte) mode;
        System.arraycopy(effectCodes, 0, payload, 1, effectCodes.length);
        return buildFrame(CMD_SET_AI_LIGHT_CONFIG, payload);
    }
    
    public static byte[] saveConfig() {
        return buildFrame(CMD_SAVE_CONFIG, new byte[0]);
    }

    public static byte[] readPicState(int mode) {
        return buildFrame(CMD_READ_PIC_STATE, new byte[]{(byte) mode});
    }

    /**
     * 查询单键键位绑定(对应固件 0x97 命令)。
     * <p>请求 payload: {@code [mode, key]}。
     * <p>响应 payload: {@code [mode, key, bind[100]]},其中 bind 前 2 字节为 {@code [sub, len]},
     * 后 98 字节为 HID 字节(有效前 {@code len} 字节)。
     */
    public static byte[] queryKeyBinding(int mode, int keyIndex) {
        if (mode < 0 || mode > 3 || keyIndex < 0 || keyIndex > 3) {
            throw new IllegalArgumentException("mode 必须在 0..3,keyIndex 必须在 0..3");
        }
        return buildFrame(CMD_QUERY_KEY_BINDING, new byte[]{(byte) mode, (byte) keyIndex});
    }

    /**
     * 查询单键键位绑定的指定 offset 起的 8 字节(对应固件 0x98 命令)。
     * <p>请求 payload: {@code [mode, key, offset]}。
     * <p>响应 payload: {@code [mode, key, offset, chunk[8]]}。
     * <p>配合 {@link #queryKeyBinding} 使用,可读出完整 100 字节 bind(0x97 + 0x98*N)。
     *
     * @param offset 起始字节偏移,0..92(8..99 留给 0x97,100 - 8 = 92)
     */
    public static byte[] queryKeyBindingChunk(int mode, int keyIndex, int offset) {
        if (mode < 0 || mode > 3) throw new IllegalArgumentException("mode 必须在 0..3");
        if (keyIndex < 0 || keyIndex > 3) throw new IllegalArgumentException("keyIndex 必须在 0..3");
        if (offset < 0 || offset > 92) throw new IllegalArgumentException("offset 必须在 0..92(0x98 单包返 8B)");
        return buildFrame(CMD_READ_KEY_BINDING_CHUNK, new byte[]{(byte) mode, (byte) keyIndex, (byte) offset});
    }

    /**
     * 触发设备进入 USB ISP 模式(对应固件 0x9A 命令)。
     * <p>收到后设备会立刻回 ack,然后拉低 BOOT 引脚 + 软 reset → 进 BOOT ROM。
     * <p>注意:调用方发完命令后**不要等响应**,设备马上 reset 会断 BLE 链路。
     */
    public static byte[] enterBoot() {
        return buildFrame(CMD_ENTER_BOOT, new byte[0]);
    }

    public static byte[] prepareWrite(int chunkLength, long address) {
        byte[] payload = new byte[7];
        payload[0] = 0;
        payload[1] = (byte) (chunkLength & 0xFF);
        payload[2] = (byte) ((chunkLength >> 8) & 0xFF);
        payload[3] = (byte) (address & 0xFF);
        payload[4] = (byte) ((address >> 8) & 0xFF);
        payload[5] = (byte) ((address >> 16) & 0xFF);
        payload[6] = (byte) ((address >> 24) & 0xFF);
        return buildFrame(CMD_PREPARE_WRITE, payload);
    }

    public static byte[] updatePicture(int mode, int startIndex, int frameCount, int timeDelayMs) {
        byte[] payload = new byte[7];
        payload[0] = (byte) mode;
        payload[1] = (byte) (startIndex & 0xFF);
        payload[2] = (byte) ((startIndex >> 8) & 0xFF);
        payload[3] = (byte) (frameCount & 0xFF);
        payload[4] = (byte) ((frameCount >> 8) & 0xFF);
        payload[5] = (byte) (timeDelayMs & 0xFF);
        payload[6] = (byte) ((timeDelayMs >> 8) & 0xFF);
        return buildFrame(CMD_UPDATE_PIC, payload);
    }
    
    public static byte[] setKeyMapping(int mode, int keyIndex, byte[] hidCodes) {
        byte[] payload = new byte[3 + hidCodes.length];
        payload[0] = SUB_SHORTCUT;
        payload[1] = (byte) mode;
        payload[2] = (byte) keyIndex;
        System.arraycopy(hidCodes, 0, payload, 3, hidCodes.length);
        return buildFrame(CMD_UPDATE_CUSTOM_KEY, payload);
    }
    
    public static byte[] setKeyDescription(int mode, int keyIndex, String text) {
        byte[] textBytes = sanitizeASCII(text, 20).getBytes();
        byte[] payload = new byte[3 + textBytes.length];
        payload[0] = SUB_DESCRIPTION;
        payload[1] = (byte) mode;
        payload[2] = (byte) keyIndex;
        System.arraycopy(textBytes, 0, payload, 3, textBytes.length);
        return buildFrame(CMD_UPDATE_CUSTOM_KEY, payload);
    }
    
    public static byte[] setKeyMacro(int mode, int keyIndex, byte[] macroData) {
        byte[] payload = new byte[3 + macroData.length];
        payload[0] = SUB_MACRO;
        payload[1] = (byte) mode;
        payload[2] = (byte) keyIndex;
        System.arraycopy(macroData, 0, payload, 3, macroData.length);
        return buildFrame(CMD_UPDATE_CUSTOM_KEY, payload);
    }
    
    public static byte[] changeName(String name) {
        byte[] nameBytes = name.getBytes();
        if (nameBytes.length > 21) {
            byte[] temp = new byte[21];
            System.arraycopy(nameBytes, 0, temp, 0, 21);
            nameBytes = temp;
        }
        return buildFrame(CMD_CHANGE_NAME, nameBytes);
    }
    
    public static DeviceStatus parseDeviceStatus(byte[] data) {
        if (data.length < 6) return null;
        if (data[0] != (byte) 0xAA || data[1] != (byte) 0xBB) return null;
        if (data[data.length - 2] != (byte) 0xCC || data[data.length - 1] != (byte) 0xDD) return null;
        
        byte cmd = data[2];
        
        // 忽略状态更新通知帧（6字节的0x90命令）
        // 这些帧中的状态值不是实际的拨杆位置，而是命令执行结果/响应
        // 如果处理这些帧，会覆盖正确的拨杆状态
        if (data.length == 6 && cmd == CMD_UPDATE_STATE) {
            return null;  // 忽略这个帧，不更新状态
        }
        
        // 处理完整的状态查询响应（12字节）
        if (data.length < 12) return null;
        if (cmd != CMD_QUERY_STATUS) return null;
        
        int base = 3;  // payloadStart + 1
        DeviceStatus status = new DeviceStatus();
        status.setBatteryLevel(data[base] & 0xFF);
        status.setSignal(data[base + 1]);
        status.setFirmwareMain(data[base + 2] & 0xFF);
        status.setFirmwareSub(data[base + 3] & 0xFF);
        status.setWorkMode(data[base + 4] & 0xFF);
        status.setLightMode(data[base + 5] & 0xFF);
        status.setSwitchState(data[base + 6] & 0xFF);
        if (data.length > base + 7) {
            status.setLightBrightness(data[base + 7] & 0xFF);
        }
        
        return status;
    }
    
    public static boolean isValidFrame(byte[] data) {
        return data.length >= 4
            && data[0] == (byte) 0xAA && data[1] == (byte) 0xBB
            && data[data.length - 2] == (byte) 0xCC && data[data.length - 1] == (byte) 0xDD;
    }
    
    private static String sanitizeASCII(String text, int maxLength) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < text.length() && result.length() < maxLength; i++) {
            char c = text.charAt(i);
            if (c >= 0x20 && c <= 0x7E) {
                result.append(c);
            }
        }
        return result.toString();
    }
}
