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
    public static final byte CMD_SET_AI_OLED_CONFIG = (byte) 0x93;
    public static final byte CMD_READ_AI_OLED_CONFIG = (byte) 0x94;
    public static final byte CMD_STANDBY_TIMEOUT = (byte) 0x95;
    public static final byte CMD_FACTORY_RESET = (byte) 0x96;
    public static final byte CMD_VOICE_KEY_CONFIG = (byte) 0x97;
    public static final byte CMD_TASK_LIGHT_MODE = (byte) 0x98;
    public static final byte CMD_TASK_SLOT_UPDATE = (byte) 0x99;
    public static final byte CMD_TASK_HEARTBEAT = (byte) 0x9A;
    public static final byte CMD_MODE_SYNC = (byte) 0x9B;
    public static final byte CMD_GIF_LAYOUT = (byte) 0x9C;
    public static final byte CMD_QUERY_CAPABILITIES = (byte) 0x9F;

    // 0x86 曾被不同固件分支重复用于“GIF 套图”和“待机时间”。
    // Protocol v2 中保留该值，不再发送；待机时间统一使用 0x95。
    public static final byte CMD_LEGACY_CONFLICT = (byte) 0x86;

    // 0x9F 能力位
    public static final long CAP_STANDBY_TIMEOUT_V2 = 1L << 0;
    public static final long CAP_FACTORY_RESET_V1 = 1L << 1;
    public static final long CAP_VOICE_KEY_DUAL_V1 = 1L << 2;
    public static final long CAP_STANDBY_NEVER_V1 = 1L << 3;
    public static final long CAP_TASK_LIGHT_MODE_V1 = 1L << 4;
    public static final long CAP_TASK_SLOTS_V1 = 1L << 5;
    public static final long CAP_GIF_LAYOUT_V1 = 1L << 6;
    public static final long CAP_MODE_SYNC_V1 = 1L << 7;
    public static final long CAP_DEVICE_MODEL_V1 = 1L << 8;
    public static final long CAP_CONNECTION_READY_V1 = 1L << 9;
    public static final int CONNECTION_BLE_LINK = 1 << 0;
    public static final int CONNECTION_HID_READY = 1 << 1;
    public static final int CONNECTION_USB_READY = 1 << 2;
    public static final int VOICE_KEY_LONG_PRESS_MS = 350;
    public static final int VOICE_KEY_MAX_CODES = 9;
    public static final int[] STANDBY_TIMEOUT_OPTIONS_MINUTES = {0, 5, 10, 15, 30};
    public static final int TASK_DISPLAY_SINGLE = 0;
    public static final int TASK_DISPLAY_MULTI = 1;
    public static final int TASK_STATE_IDLE = 0;
    public static final int TASK_STATE_RUNNING = 1;
    public static final int TASK_STATE_WAITING = 2;
    public static final int TASK_STATE_DONE = 3;
    public static final int TASK_STATE_ERROR = 4;
    public static final int TASK_FLAG_FOREGROUND = 1;
    public static final int GIF_PROFILE_COUNT = 4;
    public static final int GIF_ASSET_COUNT = 4;
    public static final int GIF_DEFAULT_FRAMES = 8;
    public static final int GIF_STATE_FRAMES = 12;
    public static final int GIF_FRAMES_PER_ASSET = GIF_STATE_FRAMES;
    public static final int GIF_FRAMES_PER_PROFILE = GIF_DEFAULT_FRAMES + GIF_STATE_FRAMES * 3;
    public static final int GIF_TOTAL_PLANNED_FRAMES = GIF_PROFILE_COUNT * GIF_FRAMES_PER_PROFILE;
    private static final int[] GIF_ASSET_OFFSETS = {0, 8, 20, 32};
    private static final int[] GIF_ASSET_CAPACITIES = {8, 12, 12, 12};
    
    // 按键子类型
    public static final byte SUB_SHORTCUT = 0x73;
    public static final byte SUB_MACRO = 0x74;
    public static final byte SUB_DESCRIPTION = 0x75;
    
    // OLED 常量（与 Swift / Windows Python 客户端一致）
    public static final int OLED_WIDTH = 160;
    public static final int OLED_HEIGHT = 80;
    public static final int OLED_FRAME_BYTES = OLED_WIDTH * OLED_HEIGHT * 2;
    public static final int OLED_FRAME_SLOT_SIZE = 28_672;
    // Physical capacity is queried from the device; each frame occupies seven sectors.
    public static final int OLED_MAX_FRAMES = GIF_TOTAL_PLANNED_FRAMES;
    public static final int OLED_MAX_SOURCE_FILE_BYTES = 2 * 1024 * 1024;
    public static final int OLED_CHUNK_SIZE = 4096;
    public static final int OLED_TRANSFER_BATCH_SIZE = 1024;
    public static final int OLED_TRANSFER_BATCH_DELAY_MS = 12;
    public static final int OLED_BLOCK_MAX_ATTEMPTS = 3;
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

    public static byte[] queryCapabilities() {
        return buildFrame(CMD_QUERY_CAPABILITIES, new byte[0]);
    }

    public static byte[] queryStandbyTimeout() {
        return buildFrame(CMD_STANDBY_TIMEOUT, new byte[0]);
    }

    public static byte[] setStandbyTimeoutMinutes(int minutes) {
        boolean supported = false;
        for (int option : STANDBY_TIMEOUT_OPTIONS_MINUTES) {
            if (minutes == option) {
                supported = true;
                break;
            }
        }
        if (!supported) {
            throw new IllegalArgumentException(
                "Standby timeout must be one of 0, 5, 10, 15, or 30 minutes"
            );
        }
        return buildFrame(
            CMD_STANDBY_TIMEOUT,
            new byte[]{(byte) (minutes & 0xFF), (byte) ((minutes >> 8) & 0xFF)}
        );
    }

    public static byte[] factoryReset() {
        return buildFrame(CMD_FACTORY_RESET, new byte[]{(byte) 0xA5, 0x5A});
    }

    public static byte[] queryTaskDisplayMode() {
        return buildFrame(CMD_TASK_LIGHT_MODE, new byte[0]);
    }

    public static byte[] setTaskDisplayMode(int mode) {
        if (mode != TASK_DISPLAY_SINGLE && mode != TASK_DISPLAY_MULTI) {
            throw new IllegalArgumentException("Task display mode must be 0 or 1");
        }
        return buildFrame(CMD_TASK_LIGHT_MODE, new byte[]{(byte) mode});
    }

    public static byte[] updateTaskSlot(int slot, int profile, int state, boolean foreground) {
        if (slot < 0 || slot >= 4 || profile < 0 || profile >= 4 || state < 0 || state > TASK_STATE_ERROR) {
            throw new IllegalArgumentException("Invalid task slot update");
        }
        return buildFrame(CMD_TASK_SLOT_UPDATE, new byte[]{
            (byte) slot, (byte) profile, (byte) state,
            (byte) (foreground ? TASK_FLAG_FOREGROUND : 0)
        });
    }

    public static byte[] taskHeartbeat() {
        return buildFrame(CMD_TASK_HEARTBEAT, new byte[]{0});
    }

    public static byte[] queryModeSync() {
        return buildFrame(CMD_MODE_SYNC, new byte[0]);
    }

    public static byte[] queryGifLayout() {
        return buildFrame(CMD_GIF_LAYOUT, new byte[0]);
    }

    public static int gifPartitionStart(int profile, int asset) {
        if (profile < 0 || profile >= GIF_PROFILE_COUNT || asset < 0 || asset >= GIF_ASSET_COUNT) {
            throw new IllegalArgumentException("Invalid GIF partition");
        }
        return profile * GIF_FRAMES_PER_PROFILE + GIF_ASSET_OFFSETS[asset];
    }

    public static int gifAssetCapacity(int asset) {
        if (asset < 0 || asset >= GIF_ASSET_COUNT) {
            throw new IllegalArgumentException("Invalid GIF asset");
        }
        return GIF_ASSET_CAPACITIES[asset];
    }

    public static byte[] queryVoiceKeyConfig() {
        return buildFrame(CMD_VOICE_KEY_CONFIG, new byte[0]);
    }

    public static byte[] setVoiceKeyConfig(int shortHidCode, int longHidCode) {
        byte[] shortCodes = hidCodesForShortcut(shortHidCode);
        byte[] longCodes = hidCodesForShortcut(longHidCode);
        if (shortCodes.length > VOICE_KEY_MAX_CODES || longCodes.length > VOICE_KEY_MAX_CODES) {
            throw new IllegalArgumentException("Voice shortcut contains too many HID codes");
        }
        byte[] payload = new byte[2 + shortCodes.length + longCodes.length];
        int offset = 0;
        payload[offset++] = (byte) shortCodes.length;
        System.arraycopy(shortCodes, 0, payload, offset, shortCodes.length);
        offset += shortCodes.length;
        payload[offset++] = (byte) longCodes.length;
        System.arraycopy(longCodes, 0, payload, offset, longCodes.length);
        return buildFrame(CMD_VOICE_KEY_CONFIG, payload);
    }

    public static byte[] hidCodesForShortcut(int hidCode) {
        java.util.ArrayList<Byte> codes = new java.util.ArrayList<>();
        if ((hidCode & 0x200) != 0) codes.add((byte) 0xE0);
        if ((hidCode & 0x100) != 0) codes.add((byte) 0xE1);
        if ((hidCode & 0x400) != 0) codes.add((byte) 0xE2);
        if ((hidCode & 0x800) != 0) codes.add((byte) 0xE3);
        if ((hidCode & 0x2000) != 0) codes.add((byte) 0xE4);
        if ((hidCode & 0x1000) != 0) codes.add((byte) 0xE5);
        if ((hidCode & 0x4000) != 0) codes.add((byte) 0xE6);
        if ((hidCode & 0x8000) != 0) codes.add((byte) 0xE7);
        int baseCode = hidCode & 0xFF;
        if (baseCode != 0) codes.add((byte) baseCode);
        byte[] result = new byte[codes.size()];
        for (int i = 0; i < codes.size(); i++) result[i] = codes.get(i);
        return result;
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

    public static byte[] readAiOledPicture(int mode, int state) {
        if (mode < 0 || mode >= GIF_PROFILE_COUNT || state < 1 || state >= GIF_ASSET_COUNT) {
            throw new IllegalArgumentException("Invalid AI OLED partition");
        }
        return buildFrame(CMD_READ_AI_OLED_CONFIG, new byte[]{(byte) mode, (byte) state});
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

    public static byte[] setAiOledPicture(int mode, int state, int startIndex, int frameCount, int timeDelayMs) {
        if (mode < 0 || mode >= GIF_PROFILE_COUNT || state < 1 || state >= GIF_ASSET_COUNT) {
            throw new IllegalArgumentException("Invalid AI OLED partition");
        }
        byte[] payload = new byte[8];
        payload[0] = (byte) mode;
        payload[1] = (byte) state;
        payload[2] = (byte) startIndex;
        payload[3] = (byte) (startIndex >> 8);
        payload[4] = (byte) frameCount;
        payload[5] = (byte) (frameCount >> 8);
        payload[6] = (byte) timeDelayMs;
        payload[7] = (byte) (timeDelayMs >> 8);
        return buildFrame(CMD_SET_AI_OLED_CONFIG, payload);
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
        if (data.length >= 14) {
            int flags = data[base + 8] & 0xFF;
            status.setConnectionReadinessKnown(true);
            status.setBleLinkConnected((flags & CONNECTION_BLE_LINK) != 0);
            status.setHidInputReady((flags & CONNECTION_HID_READY) != 0);
            status.setUsbConfigReady((flags & CONNECTION_USB_READY) != 0);
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
