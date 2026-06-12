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
}
