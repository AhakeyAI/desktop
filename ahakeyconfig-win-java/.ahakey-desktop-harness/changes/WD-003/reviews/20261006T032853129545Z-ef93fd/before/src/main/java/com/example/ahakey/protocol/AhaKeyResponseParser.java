package com.example.ahakey.protocol;

import java.nio.charset.StandardCharsets;

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
}
