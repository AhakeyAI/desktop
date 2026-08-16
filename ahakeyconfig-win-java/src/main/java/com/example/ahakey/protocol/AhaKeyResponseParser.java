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

    public record AiOledState(
        int mode,
        int asset,
        int startIndex,
        int frameCount,
        int frameInterval,
        int totalFrameSlots
    ) {
    }

    public record DeviceCapabilities(
        int protocolMajor,
        int protocolMinor,
        int firmwareMajor,
        int firmwareMinor,
        int hardwareRevision,
        long capabilityBits,
        int firmwarePatch,
        int deviceModel
    ) {
        public boolean supports(long capability) {
            return (capabilityBits & capability) == capability;
        }
    }

    public record VoiceKeyConfig(byte[] shortCodes, byte[] longCodes, int longPressMs) {
        public boolean matches(int shortHidCode, int longHidCode) {
            return java.util.Arrays.equals(shortCodes, AhaKeyProtocol.hidCodesForShortcut(shortHidCode))
                && java.util.Arrays.equals(longCodes, AhaKeyProtocol.hidCodesForShortcut(longHidCode))
                && longPressMs == AhaKeyProtocol.VOICE_KEY_LONG_PRESS_MS;
        }
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
        int offset = 0;
        int mode = payload[offset] & 0xFF;
        int startIndex = (payload[offset + 1] & 0xFF) | ((payload[offset + 2] & 0xFF) << 8);
        int picLength = (payload[offset + 3] & 0xFF) | ((payload[offset + 4] & 0xFF) << 8);
        int frameInterval = (payload[offset + 5] & 0xFF) | ((payload[offset + 6] & 0xFF) << 8);
        int allModeMaxPic = (payload[offset + 7] & 0xFF) | ((payload[offset + 8] & 0xFF) << 8);
        return new PictureState(mode, startIndex, picLength, frameInterval, allModeMaxPic);
    }

    public static DeviceCapabilities parseDeviceCapabilities(byte[] payload) {
        if (payload == null || payload.length < 9) {
            return null;
        }
        long capabilityBits = (payload[5] & 0xFFL)
            | ((payload[6] & 0xFFL) << 8)
            | ((payload[7] & 0xFFL) << 16)
            | ((payload[8] & 0xFFL) << 24);
        return new DeviceCapabilities(
            payload[0] & 0xFF,
            payload[1] & 0xFF,
            payload[2] & 0xFF,
            payload[3] & 0xFF,
            payload[4] & 0xFF,
            capabilityBits,
            payload.length >= 10 ? payload[9] & 0xFF : 0,
            payload.length >= 11 ? payload[10] & 0xFF : 0
        );
    }

    public record ModeSync(int mode, int source, int sequence) {}
    public record GifLayout(int profiles, int assetsPerProfile, int maxFrames,
                            int frameBytes, int sectorsPerFrame, int width, int height,
                            int flashId, long flashBytes, int frameSlots, int[] assetCapacities) {
        public boolean hasPhysicalFlashDiagnostics() {
            return flashBytes > 0 && frameSlots > 0;
        }

        public int capacityForAsset(int asset) {
            if (asset < 0 || asset >= assetsPerProfile) return 0;
            if (assetCapacities != null && asset < assetCapacities.length)
                return assetCapacities[asset];
            return maxFrames;
        }

        public boolean hasVariableAssetCapacities() {
            return assetCapacities != null && assetCapacities.length == assetsPerProfile;
        }
    }

    public static ModeSync parseModeSync(byte[] payload) {
        if (payload == null || payload.length < 2) return null;
        return new ModeSync(payload[0] & 0xFF, payload[1] & 0xFF,
            payload.length >= 3 ? payload[2] & 0xFF : 0);
    }

    public static GifLayout parseGifLayout(byte[] payload) {
        if (payload == null || payload.length < 8) return null;
        int flashId = payload.length >= 10
            ? (payload[8] & 0xFF) | ((payload[9] & 0xFF) << 8)
            : 0;
        long flashBytes = payload.length >= 14
            ? (payload[10] & 0xFFL)
                | ((payload[11] & 0xFFL) << 8)
                | ((payload[12] & 0xFFL) << 16)
                | ((payload[13] & 0xFFL) << 24)
            : 0;
        int frameSlots = payload.length >= 16
            ? (payload[14] & 0xFF) | ((payload[15] & 0xFF) << 8)
            : 0;
        int[] assetCapacities = null;
        int assets = payload[1] & 0xFF;
        if (assets > 0 && payload.length >= 16 + assets) {
            assetCapacities = new int[assets];
            for (int asset = 0; asset < assets; asset++)
                assetCapacities[asset] = payload[16 + asset] & 0xFF;
        }
        return new GifLayout(payload[0] & 0xFF, payload[1] & 0xFF, payload[2] & 0xFF,
            (payload[3] & 0xFF) | ((payload[4] & 0xFF) << 8), payload[5] & 0xFF,
            payload[6] & 0xFF, payload[7] & 0xFF, flashId, flashBytes, frameSlots,
            assetCapacities);
    }

    public static AiOledState parseAiOledState(byte[] payload) {
        if (payload == null || payload.length < 10) return null;
        return new AiOledState(
            payload[0] & 0xFF,
            payload[1] & 0xFF,
            (payload[2] & 0xFF) | ((payload[3] & 0xFF) << 8),
            (payload[4] & 0xFF) | ((payload[5] & 0xFF) << 8),
            (payload[6] & 0xFF) | ((payload[7] & 0xFF) << 8),
            (payload[8] & 0xFF) | ((payload[9] & 0xFF) << 8)
        );
    }

    public static Integer parseStandbyTimeoutMinutes(byte[] payload) {
        if (payload == null || payload.length < 2) {
            return null;
        }
        return (payload[0] & 0xFF) | ((payload[1] & 0xFF) << 8);
    }

    public static VoiceKeyConfig parseVoiceKeyConfig(byte[] payload) {
        if (payload == null || payload.length < 4) {
            return null;
        }
        int offset = 0;
        int shortCount = payload[offset++] & 0xFF;
        if (shortCount > AhaKeyProtocol.VOICE_KEY_MAX_CODES || offset + shortCount >= payload.length) {
            return null;
        }
        byte[] shortCodes = java.util.Arrays.copyOfRange(payload, offset, offset + shortCount);
        offset += shortCount;
        int longCount = payload[offset++] & 0xFF;
        if (longCount > AhaKeyProtocol.VOICE_KEY_MAX_CODES || offset + longCount + 2 != payload.length) {
            return null;
        }
        byte[] longCodes = java.util.Arrays.copyOfRange(payload, offset, offset + longCount);
        offset += longCount;
        int threshold = (payload[offset] & 0xFF) | ((payload[offset + 1] & 0xFF) << 8);
        return new VoiceKeyConfig(shortCodes, longCodes, threshold);
    }
}
