package com.example.ahakey.protocol;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;

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

    public record SleepWaitTimeResponse(byte status, Integer minutes) {
    }

    public record OrdinaryKeyReadback(
        int mode,
        int keyIndex,
        int actionType,
        byte[] actionPayload,
        String description
    ) {
        public OrdinaryKeyReadback {
            actionPayload = actionPayload == null ? new byte[0] : Arrays.copyOf(actionPayload, actionPayload.length);
            description = description == null ? "" : description;
        }
    }

    public record SideSwitchPositionConfig(int binding, byte[] actionPayload) {
        public SideSwitchPositionConfig {
            actionPayload = actionPayload == null ? new byte[0] : Arrays.copyOf(actionPayload, actionPayload.length);
        }
    }

    public record SideSwitchConfig(
        int physicalPosition,
        SideSwitchPositionConfig up,
        SideSwitchPositionConfig down
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

    public static SleepWaitTimeResponse parseSleepWaitTime(byte[] frame) {
        CommandResponse response = parseCommandResponse(frame);
        if (response == null || response.cmd() != AhaKeyProtocol.CMD_SLEEP_WAIT_TIME) {
            return null;
        }
        Integer minutes = null;
        byte[] payload = response.payload();
        if (response.status() == 0 && payload.length >= 2) {
            minutes = (payload[0] & 0xFF) | ((payload[1] & 0xFF) << 8);
        }
        return new SleepWaitTimeResponse(response.status(), minutes);
    }

    public static String parseFirmwareCatalogKey(byte[] frame) {
        if (!AhaKeyProtocol.isValidFrame(frame) || frame.length < 6 || frame[2] != AhaKeyProtocol.CMD_FIRMWARE_CATALOG_KEY) {
            return null;
        }
        int payloadOffset = frame[3] == 0 ? 4 : 3;
        int payloadLen = frame.length - payloadOffset - 2;
        if (payloadLen <= 0) {
            return null;
        }
        byte[] payload = new byte[payloadLen];
        System.arraycopy(frame, payloadOffset, payload, 0, payloadLen);
        int len = 0;
        while (len < payload.length && payload[len] != 0) {
            len++;
        }
        if (len == 0) {
            return null;
        }
        String value = new String(payload, 0, len, StandardCharsets.US_ASCII).trim();
        if (value.isEmpty()) {
            return null;
        }
        StringBuilder sanitized = new StringBuilder(value.length());
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (c >= 0x20 && c <= 0x7E) {
                sanitized.append(c);
            }
        }
        return sanitized.isEmpty() ? null : sanitized.toString();
    }

    public static OrdinaryKeyReadback parseOrdinaryKeyReadback(byte[] frame) {
        if (frame == null || frame.length > AhaKeyProtocol.ORDINARY_KEY_READBACK_FRAME_MAX) {
            return null;
        }
        CommandResponse response = parseCommandResponse(frame);
        if (response == null || response.cmd() != AhaKeyProtocol.CMD_ORDINARY_KEY_READBACK || response.status() != 0) {
            return null;
        }
        byte[] payload = response.payload();
        if (payload.length < 5) {
            return null;
        }
        int offset = 0;
        int mode = payload[offset++] & 0xFF;
        int keyIndex = payload[offset++] & 0xFF;
        int actionType = payload[offset++] & 0xFF;
        int actionLen = payload[offset++] & 0xFF;
        if (mode > 3 || keyIndex > 3) {
            return null;
        }
        boolean emptyAction = actionType == AhaKeyProtocol.ORDINARY_KEY_ACTION_EMPTY;
        boolean supportedAction = actionType == (AhaKeyProtocol.SUB_SHORTCUT & 0xFF)
            || actionType == (AhaKeyProtocol.SUB_MACRO & 0xFF);
        if (!emptyAction && !supportedAction) {
            return null;
        }
        if (emptyAction && actionLen != 0) {
            return null;
        }
        if (actionLen > payload.length - offset - 1) {
            return null;
        }
        byte[] actionPayload = Arrays.copyOfRange(payload, offset, offset + actionLen);
        offset += actionLen;
        int descLen = payload[offset++] & 0xFF;
        if (descLen != payload.length - offset) {
            return null;
        }
        if (actionLen + descLen > AhaKeyProtocol.ORDINARY_KEY_READBACK_ACTION_DESC_MAX) {
            return null;
        }
        String description = decodeAsciiTrimmed(payload, offset, descLen);
        return new OrdinaryKeyReadback(mode, keyIndex, actionType, actionPayload, description);
    }

    public static SideSwitchConfig parseSideSwitchConfig(byte[] frame) {
        CommandResponse response = parseCommandResponse(frame);
        if (response == null || response.cmd() != AhaKeyProtocol.CMD_SIDE_SWITCH_CONFIG || response.status() != 0) {
            return null;
        }
        byte[] payload = response.payload();
        if (payload.length < 6) {
            return null;
        }
        int offset = 0;
        int physicalPosition = payload[offset++] & 0xFF;
        int positionCount = payload[offset++] & 0xFF;
        if (positionCount < 2) {
            return null;
        }
        SideSwitchPositionConfig up = parseSideSwitchPosition(payload, offset);
        if (up == null) {
            return null;
        }
        offset += 2 + up.actionPayload().length;
        SideSwitchPositionConfig down = parseSideSwitchPosition(payload, offset);
        if (down == null) {
            return null;
        }
        return new SideSwitchConfig(physicalPosition, up, down);
    }

    private static SideSwitchPositionConfig parseSideSwitchPosition(byte[] payload, int offset) {
        if (offset + 2 > payload.length) {
            return null;
        }
        int binding = payload[offset] & 0xFF;
        int actionLen = payload[offset + 1] & 0xFF;
        if (offset + 2 + actionLen > payload.length) {
            return null;
        }
        byte[] actionPayload = Arrays.copyOfRange(payload, offset + 2, offset + 2 + actionLen);
        return new SideSwitchPositionConfig(binding, actionPayload);
    }

    private static String decodeAsciiTrimmed(byte[] payload, int offset, int len) {
        int end = offset + len;
        while (end > offset && (payload[end - 1] == 0 || payload[end - 1] == 0x20)) {
            end--;
        }
        if (end <= offset) {
            return "";
        }
        return new String(payload, offset, end - offset, StandardCharsets.US_ASCII).trim();
    }
}
