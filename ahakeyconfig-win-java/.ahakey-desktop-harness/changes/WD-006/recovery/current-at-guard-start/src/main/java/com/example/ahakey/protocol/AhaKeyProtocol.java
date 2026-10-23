package com.example.ahakey.protocol;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.AiRuntimeDisplayMode;
import com.example.ahakey.model.AiRuntimeSlotBinding;
import com.example.ahakey.model.AiRuntimeSlotState;

public class AhaKeyProtocol {
    public static final byte CMD_DISPLAY_READ = (byte) 0x88;
    public static final byte CMD_DISPLAY_PREVIEW = (byte) 0x89;
    public static final byte CMD_RESOURCE_BEGIN = (byte) 0x8A;
    public static final byte CMD_RESOURCE_CHUNK = (byte) 0x8B;
    public static final byte CMD_RESOURCE_COMMIT = (byte) 0x8C;
    public static final byte CMD_DISPLAY_SAVE = (byte) 0x8E;
    public static final int RESOURCE_COUNT = 19;
    public static final int RESOURCE_CHUNK_BYTES = 48;

    public static int resourceCapacity(int entry) {
        requireRange(entry, 0, 18, "entry");
        return entry < 16 && entry % 4 == 0 ? 8 : 12;
    }

    public static byte[] displayRead(int kind, int... selectors) {
        requireRange(kind, 0, 3, "read kind");
        int count = kind == 0 ? 0 : kind == 1 ? 2 : 1;
        if (selectors.length != count) throw new IllegalArgumentException("selectors");
        if (kind == 1) {
            requireRange(selectors[0], 0, 3, "mode");
            requireRange(selectors[1], 0, 8, "AI state");
        } else if (kind > 1) requireRange(selectors[0], 0, 18, "entry");
        byte[] data = new byte[count + 1];
        data[0] = (byte) kind;
        for (int i = 0; i < count; i++) data[i + 1] = (byte) selectors[i];
        return buildFrame(CMD_DISPLAY_READ, data);
    }

    public static byte[] previewBrightness(int brightness) {
        requireRange(brightness, 1, 100, "brightness");
        return buildFrame(CMD_DISPLAY_PREVIEW, new byte[]{0, (byte) brightness});
    }

    public static byte[] previewLight(int effect, int brightness) {
        requireRange(effect, 1, 16, "effect");
        requireRange(brightness, 1, 100, "brightness");
        return buildFrame(CMD_DISPLAY_PREVIEW, new byte[]{1, (byte) effect, (byte) brightness});
    }

    public static byte[] saveDisplayBrightness(int brightness) {
        requireRange(brightness, 1, 100, "brightness");
        return buildFrame(CMD_DISPLAY_SAVE, new byte[]{0, (byte) brightness});
    }

    public static byte[] saveDisplayLight(int mode, int ai, int effect) {
        requireRange(mode, 0, 3, "mode");
        requireRange(ai, 0, 8, "AI state");
        requireRange(effect, 0, 16, "effect");
        return buildFrame(CMD_DISPLAY_SAVE, new byte[]{1, (byte) mode, (byte) ai, (byte) effect});
    }

    public static byte[] resourceBegin(int entry, int frames, long crc) {
        requireRange(frames, 1, resourceCapacity(entry), "frames");
        if (crc < 0 || crc > 0xffffffffL) throw new IllegalArgumentException("CRC32");
        java.nio.ByteBuffer data = java.nio.ByteBuffer.allocate(11).order(java.nio.ByteOrder.LITTLE_ENDIAN);
        data.put((byte) entry).putInt(frames * OLED_FRAME_SLOT_SIZE).putShort((short) frames).putInt((int) crc);
        return buildFrame(CMD_RESOURCE_BEGIN, data.array());
    }

    public static byte[] resourceChunk(int entry, int offset, byte[] payload) {
        int capacity = resourceCapacity(entry) * OLED_FRAME_SLOT_SIZE;
        requireRange(payload.length, 1, RESOURCE_CHUNK_BYTES, "chunk length");
        requireRange(offset, 0, capacity - payload.length, "offset");
        java.nio.ByteBuffer data = java.nio.ByteBuffer.allocate(6 + payload.length).order(java.nio.ByteOrder.LITTLE_ENDIAN);
        data.put((byte) entry).putInt(offset).put((byte) payload.length).put(payload);
        return buildFrame(CMD_RESOURCE_CHUNK, data.array());
    }

    public static byte[] resourceCommit(int entry) {
        resourceCapacity(entry);
        return buildFrame(CMD_RESOURCE_COMMIT, new byte[]{(byte) entry});
    }

    private static void requireRange(int value, int min, int max, String field) {
        if (value < min || value > max) throw new IllegalArgumentException(field + ": " + value);
    }
    private static final byte[] HEADER = {(byte) 0xAA, (byte) 0xBB};
    private static final byte[] TRAILER = {(byte) 0xCC, (byte) 0xDD};
    
    // 命令定义
    public static final byte CMD_QUERY_STATUS = 0x00;
    public static final byte CMD_CHANGE_NAME = 0x01;
    public static final byte CMD_CHANGE_APPEARANCE = 0x02;
    public static final byte CMD_SAVE_CONFIG = 0x04;
    public static final byte CMD_UPDATE_CUSTOM_KEY = 0x73;
    public static final byte CMD_ORDINARY_KEY_READBACK = (byte) 0x87;
    public static final byte CMD_PREPARE_WRITE = (byte) 0x80;
    public static final byte CMD_WRITE_RESULT = (byte) 0x81;
    public static final byte CMD_UPDATE_PIC = (byte) 0x82;
    public static final byte CMD_READ_PIC_STATE = (byte) 0x83;
    public static final byte CMD_SET_AI_LIGHT_CONFIG = (byte) 0x84;
    public static final byte CMD_SET_LIGHT_BRIGHTNESS = (byte) 0x85;
    public static final byte CMD_UPDATE_STATE = (byte) 0x90;
    public static final byte CMD_SET_LIGHT_EFFECT = (byte) 0x91;
    public static final byte CMD_SET_WORK_MODE = (byte) 0x92;
    public static final byte CMD_SLEEP_WAIT_TIME = (byte) 0x95;
    public static final byte CMD_SIDE_SWITCH_CONFIG = (byte) 0x97;
    public static final byte CMD_RUNTIME_DISPLAY_MODE = (byte) 0x98;
    public static final byte CMD_MULTI_RUNTIME_SNAPSHOT = (byte) 0x99;
    public static final byte CMD_RUNTIME_COMPAT_ACK = (byte) 0x9A;
    public static final byte CMD_FIRMWARE_CATALOG_KEY = (byte) 0x9F;
    public static final int STATUS_OK = 0;
    public static final int STATUS_INVALID_PAYLOAD = 1;
    public static final int STATUS_OUT_OF_RANGE = 2;
    public static final int STATUS_TOO_LARGE = 3;
    public static final int ORDINARY_KEY_READBACK_FRAME_MAX = 64;
    public static final int ORDINARY_KEY_READBACK_ACTION_DESC_MAX = 53;
    public static final int ORDINARY_KEY_ACTION_EMPTY = 0x00;
    public static final int SIDE_SWITCH_POSITION_UP = 0;
    public static final int SIDE_SWITCH_POSITION_DOWN = 1;
    public static final int SIDE_SWITCH_BINDING_AUTO = 0;
    public static final int SIDE_SWITCH_BINDING_MANUAL = 1;
    public static final int SIDE_SWITCH_BINDING_DISABLED = 2;
    public static final int SIDE_SWITCH_BINDING_CUSTOM = 3;
    public static final int SIDE_SWITCH_ACTION_BIND_LEN = 100;
    public static final int SIDE_SWITCH_READBACK_ACTION_TOTAL_MAX = 52;
    private static final String CP4C_CATALOG_KEY = "x1-c582-hw1-p1-1.0.0-r001";
    public static final int MULTI_RUNTIME_SNAPSHOT_VERSION = 1;
    
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

    public static byte[] querySleepWaitTime() {
        return buildFrame(CMD_SLEEP_WAIT_TIME, new byte[0]);
    }

    public static byte[] queryFirmwareCatalogKey() {
        return buildFrame(CMD_FIRMWARE_CATALOG_KEY, new byte[0]);
    }

    public static boolean isCp4cCatalogKey(String catalogKey) {
        return CP4C_CATALOG_KEY.equals(catalogKey);
    }

    public static boolean isWs3Cp1RuntimeDisplaySupported(String catalogKey) {
        return CP4C_CATALOG_KEY.equals(catalogKey);
    }

    public static boolean isDisplayCapabilityResponse(byte[] frame) {
        if (!isValidFrame(frame) || frame.length < 6 || frame[2] != CMD_FIRMWARE_CATALOG_KEY) return false;
        int offset = frame[3] == 0 ? 4 : 3;
        byte[] key = CP4C_CATALOG_KEY.getBytes(java.nio.charset.StandardCharsets.US_ASCII);
        if (frame.length - 2 - offset < key.length) return false;
        for (byte value : key) if (frame[offset++] != value) return false;
        while (offset < frame.length - 2) if (frame[offset++] != 0) return false;
        return true;
    }

    public static byte[] setRuntimeDisplayMode(AiRuntimeDisplayMode mode) {
        AiRuntimeDisplayMode safeMode = mode == null ? AiRuntimeDisplayMode.SINGLE : mode;
        return buildFrame(CMD_RUNTIME_DISPLAY_MODE, new byte[]{(byte) safeMode.getProtocolValue()});
    }

    public static byte[] multiRuntimeSnapshot(AiRuntimeSlotBinding[] slots) {
        byte[] payload = new byte[1 + 4 * 3];
        payload[0] = (byte) MULTI_RUNTIME_SNAPSHOT_VERSION;
        for (int i = 0; i < 4; i++) {
            AiRuntimeSlotBinding slot = slots != null && i < slots.length ? slots[i] : null;
            boolean valid = slot != null && slot.isBound();
            AiRuntimeSlotState state = valid ? slot.runtimeState() : AiRuntimeSlotState.EMPTY;
            if (state == AiRuntimeSlotState.EMPTY) {
                valid = false;
            }
            int offset = 1 + i * 3;
            payload[offset] = (byte) (valid ? 1 : 0);
            payload[offset + 1] = (byte) state.getProtocolValue();
            payload[offset + 2] = (byte) (slot != null && slot.isForeground() ? 1 : 0);
        }
        return buildFrame(CMD_MULTI_RUNTIME_SNAPSHOT, payload);
    }

    public static byte[] readOrdinaryKeyConfig(int mode, int keyIndex) {
        return buildFrame(CMD_ORDINARY_KEY_READBACK, new byte[]{
            (byte) Math.max(0, Math.min(3, mode)),
            (byte) Math.max(0, Math.min(3, keyIndex))
        });
    }

    public static byte[] readSideSwitchConfig() {
        return buildFrame(CMD_SIDE_SWITCH_CONFIG, new byte[0]);
    }

    public static byte[] setSideSwitchConfig(
        int upBinding,
        byte[] upAction,
        int downBinding,
        byte[] downAction
    ) {
        int safeUpBinding = normalizeSideSwitchBinding(upBinding);
        int safeDownBinding = normalizeSideSwitchBinding(downBinding);
        byte[] safeUpAction = normalizeSideSwitchAction(safeUpBinding, upAction);
        byte[] safeDownAction = normalizeSideSwitchAction(safeDownBinding, downAction);
        int actionTotal = safeUpAction.length + safeDownAction.length;
        if (actionTotal > SIDE_SWITCH_READBACK_ACTION_TOTAL_MAX) {
            throw new IllegalArgumentException(
                "侧拨自定义动作过长：" + actionTotal + " 字节，当前固件 0x97 回读上限为 "
                    + SIDE_SWITCH_READBACK_ACTION_TOTAL_MAX + " 字节"
            );
        }
        byte[] payload = new byte[1 + 2 + safeUpAction.length + 2 + safeDownAction.length];
        int offset = 0;
        payload[offset++] = 0x01;
        payload[offset++] = (byte) safeUpBinding;
        payload[offset++] = (byte) safeUpAction.length;
        System.arraycopy(safeUpAction, 0, payload, offset, safeUpAction.length);
        offset += safeUpAction.length;
        payload[offset++] = (byte) safeDownBinding;
        payload[offset++] = (byte) safeDownAction.length;
        System.arraycopy(safeDownAction, 0, payload, offset, safeDownAction.length);
        return buildFrame(CMD_SIDE_SWITCH_CONFIG, payload);
    }

    public static byte[] setSleepWaitTime(int minutes) {
        if (!isSupportedSleepWaitTime(minutes)) {
            throw new IllegalArgumentException("Unsupported sleep wait time: " + minutes);
        }
        byte[] payload = new byte[2];
        payload[0] = (byte) (minutes & 0xFF);
        payload[1] = (byte) ((minutes >> 8) & 0xFF);
        return buildFrame(CMD_SLEEP_WAIT_TIME, payload);
    }

    public static boolean isSupportedSleepWaitTime(int minutes) {
        return minutes == 0 || minutes == 30 || minutes == 60 || minutes == 120;
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

    private static int normalizeSideSwitchBinding(int binding) {
        return switch (binding) {
            case SIDE_SWITCH_BINDING_AUTO,
                 SIDE_SWITCH_BINDING_MANUAL,
                 SIDE_SWITCH_BINDING_DISABLED,
                 SIDE_SWITCH_BINDING_CUSTOM -> binding;
            default -> SIDE_SWITCH_BINDING_DISABLED;
        };
    }

    private static byte[] normalizeSideSwitchAction(int binding, byte[] action) {
        if (binding != SIDE_SWITCH_BINDING_CUSTOM) {
            return new byte[0];
        }
        if (action == null || action.length == 0) {
            throw new IllegalArgumentException("侧拨 Custom 动作缺少 0x73/0x74 动作包");
        }
        if (action.length < 2) {
            throw new IllegalArgumentException("侧拨 Custom 动作缺少长度字段");
        }
        if (action.length > SIDE_SWITCH_ACTION_BIND_LEN) {
            throw new IllegalArgumentException(
                "侧拨 Custom 动作超过固件存储上限：" + action.length + " 字节"
            );
        }
        int actionType = action[0] & 0xFF;
        if (actionType != (SUB_SHORTCUT & 0xFF) && actionType != (SUB_MACRO & 0xFF)) {
            throw new IllegalArgumentException("侧拨 Custom 动作必须以 0x73 或 0x74 开头");
        }
        int declaredLength = action[1] & 0xFF;
        if (declaredLength != action.length - 2) {
            throw new IllegalArgumentException(
                "侧拨 Custom 动作长度不匹配：声明 " + declaredLength + " 字节，实际 "
                    + (action.length - 2) + " 字节"
            );
        }
        byte[] out = new byte[action.length];
        System.arraycopy(action, 0, out, 0, action.length);
        return out;
    }
}
