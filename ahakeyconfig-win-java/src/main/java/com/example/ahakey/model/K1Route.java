package com.example.ahakey.model;

import java.util.Arrays;

/** Exact 102-byte firmware record. Consumer routes are observed, never authored by the editor. */
public final class K1Route {
    public static final int SIZE = 102;
    private final byte[] bytes;
    public K1Route(byte[] record) {
        if (record.length != SIZE) throw new IllegalArgumentException("K1 route长度无效");
        int kind = record[0] & 255, length = record[1] & 255;
        if (kind == 0) {
            if (length > 100 || (length != 0 && (length < 2 || length != (record[3] & 255) + 2
                    || (record[2] != 0x73 && record[2] != 0x74)))) throw new IllegalArgumentException("K1普通动作无效");
        } else if (kind == 1) {
            int usage = (record[2] & 255) | ((record[3] & 255) << 8);
            if (length != 2 || usage < 1 || usage > 0x3ff) throw new IllegalArgumentException("K1 Consumer usage无效");
        } else throw new IllegalArgumentException("未知K1 route类型");
        for (int i = length + 2; i < SIZE; i++) if (record[i] != 0) throw new IllegalArgumentException("K1 route填充无效");
        bytes = record.clone();
    }
    public static K1Route ordinary(int type, byte[] action) {
        if ((type != 0x73 && type != 0x74) || action.length > 98) throw new IllegalArgumentException("K1动作最多98字节");
        byte[] bytes = new byte[SIZE]; bytes[1] = (byte)(action.length + 2); bytes[2] = (byte)type; bytes[3] = (byte)action.length;
        System.arraycopy(action, 0, bytes, 4, action.length); return new K1Route(bytes);
    }
    public byte[] bytes() { return bytes.clone(); }
    public boolean consumer() { return bytes[0] == 1; }
    public int usage() { return (bytes[2] & 255) | ((bytes[3] & 255) << 8); }
    public int actionType() { return bytes[1] == 0 ? 0 : bytes[2] & 255; }
    public byte[] action() { return bytes[1] == 0 ? new byte[0] : Arrays.copyOfRange(bytes, 4, 4 + (bytes[3] & 255)); }
    @Override public boolean equals(Object other) { return other instanceof K1Route route && Arrays.equals(bytes, route.bytes); }
    @Override public int hashCode() { return Arrays.hashCode(bytes); }
}
