package com.example.ahakey.protocol;

import java.util.Set;

/** Fixed offline protocol profiles, separate from the firmware installation trust catalog. */
public record FirmwareCapabilities(boolean extended, boolean legacyWrites) {
    private static final Set<String> FULL = Set.of(
            "x1-c582-hw1-p1-1.0.0-r001", "x1-c582-hw1-p1-1.0.1-r001", "x1-c582-hw2-p1-1.0.1-r001");
    public static final FirmwareCapabilities UNKNOWN = new FirmwareCapabilities(false, false);
    public static final FirmwareCapabilities LEGACY = new FirmwareCapabilities(false, true);
    public static FirmwareCapabilities catalog(String key) {
        return FULL.contains(key == null ? "" : key) ? new FirmwareCapabilities(true, false) : UNKNOWN;
    }
    public static boolean legacyIdentityAck(byte[] frame) {
        return AhaKeyProtocol.isValidFrame(frame) && frame.length == 6 && frame[2] == (byte) 0x9F && frame[3] == 0;
    }
    public boolean admits(String capability) {
        return extended && Set.of("keys", "side", "lights", "display", "k1").contains(capability);
    }
}
