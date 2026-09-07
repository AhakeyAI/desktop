package com.example.ahakey.firmware;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Locale;

/** Single source of truth for the CH582 WCHISP CONFIG binary layout. */
public final class WchIspConfigLayout {
    public static final int CONFIG_SIZE = 66841;
    public static final int SLOT_COUNT = 5;
    public static final int SLOT_SIZE = 520;
    public static final int CH582_SLOT_INDEX = 0;
    public static final int[] SLOT_OFFSETS = {36486, 37006, 37526, 63172, 63692};
    public static final String ENCODING = "UTF-16BE";
    public static final String FINGERPRINT =
        "4dd3ac5911ff428b92200745a26c34c674235c04ac40a77f7cfb61d6fb6241e8";

    private WchIspConfigLayout() {}

    public static String fingerprint(byte[] bytes) throws IOException {
        validateLength(bytes);
        byte[] normalized = bytes.clone();
        for (int offset : SLOT_OFFSETS) {
            if (offset < 0 || offset + SLOT_SIZE > normalized.length) {
                throw new IOException("path slot boundary invalid");
            }
            Arrays.fill(normalized, offset, offset + SLOT_SIZE, (byte) 0);
        }
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(normalized);
            StringBuilder result = new StringBuilder(digest.length * 2);
            for (byte value : digest) result.append(String.format(Locale.ROOT,
                "%02x", value & 0xFF));
            return result.toString();
        } catch (java.security.NoSuchAlgorithmException impossible) {
            throw new IOException("JVM lacks SHA-256", impossible);
        }
    }

    public static void validateLength(byte[] bytes) throws IOException {
        if (bytes == null || bytes.length != CONFIG_SIZE) {
            throw new IOException("configuration length mismatch");
        }
    }

    public static byte[] patchSlot(byte[] original, int slot, String value)
        throws IOException {
        validateLength(original);
        if (slot < 0 || slot >= SLOT_COUNT) throw new IOException("slot index invalid");
        if (value == null) throw new IOException("slot value is null");
        byte[] replacement = value.getBytes(StandardCharsets.UTF_16BE);
        if (replacement.length + 2 > SLOT_SIZE) throw new IOException("path slot is too long");
        byte[] result = original.clone();
        int offset = SLOT_OFFSETS[slot];
        Arrays.fill(result, offset, offset + SLOT_SIZE, (byte) 0);
        System.arraycopy(replacement, 0, result, offset, replacement.length);
        return result;
    }

    public static Layout inspect(byte[] bytes) throws IOException {
        validateLength(bytes);
        if (!FINGERPRINT.equals(fingerprint(bytes))) {
            throw new IOException("layout fingerprint mismatch");
        }
        String[] values = new String[SLOT_COUNT];
        for (int slot = 0; slot < SLOT_COUNT; slot++) {
            int offset = SLOT_OFFSETS[slot];
            String value = decodeSlot(bytes, offset);
            if (!value.isBlank() && !value.toLowerCase(Locale.ROOT).endsWith(".hex")
                && !value.toLowerCase(Locale.ROOT).endsWith(".bin")) {
                throw new IOException("path slot " + slot + " is not a UTF-16BE .hex/.bin field");
            }
            values[slot] = value;
        }
        return new Layout(Arrays.copyOf(SLOT_OFFSETS, SLOT_OFFSETS.length), values);
    }

    private static String decodeSlot(byte[] bytes, int offset) throws IOException {
        if ((offset & 1) != 0 || offset < 0 || offset + SLOT_SIZE > bytes.length) {
            throw new IOException("path slot boundary invalid");
        }
        StringBuilder value = new StringBuilder();
        boolean terminated = false;
        for (int index = offset; index < offset + SLOT_SIZE; index += 2) {
            int codeUnit = ((bytes[index] & 0xFF) << 8) | (bytes[index + 1] & 0xFF);
            if (codeUnit == 0) {
                terminated = true;
                for (int rest = index + 2; rest < offset + SLOT_SIZE; rest++) {
                    if (bytes[rest] != 0) throw new IOException("path slot tail is not zero-filled");
                }
                break;
            }
            if (codeUnit < 0x20 || codeUnit > 0x7E) {
                throw new IOException("path slot contains invalid UTF-16 character");
            }
            value.append((char) codeUnit);
        }
        if (!terminated) throw new IOException("path slot has no UTF-16 NUL terminator");
        return value.toString();
    }

    public record Layout(int[] slotOffsets, String[] slotValues) {
        public Layout {
            slotOffsets = Arrays.copyOf(slotOffsets, slotOffsets.length);
            slotValues = Arrays.copyOf(slotValues, slotValues.length);
        }
    }
}
