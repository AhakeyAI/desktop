package com.example.ahakey.protocol;

/** 与 Windows/macOS `BleTcpBridge` 一致：[Type:1][Length:2 LE][Data:N] */
public final class BleTcpPacket {
    public static final byte WRITE_DATA = 0x01;
    public static final byte WRITE_COMMAND = 0x02;
    public static final byte QUERY_BLE_STATUS = 0x03;
    public static final byte QUERY_DEVICE_INFO = 0x04;
    public static final byte BLE_NOTIFY = (byte) 0x81;
    public static final byte BLE_STATUS_RESP = (byte) 0x82;
    public static final byte DEVICE_INFO_RESP = (byte) 0x83;

    private BleTcpPacket() {
    }

    public static byte[] encode(byte type, byte[] data) {
        int len = data == null ? 0 : data.length;
        byte[] packet = new byte[3 + len];
        packet[0] = type;
        packet[1] = (byte) (len & 0xFF);
        packet[2] = (byte) ((len >> 8) & 0xFF);
        if (len > 0) {
            System.arraycopy(data, 0, packet, 3, len);
        }
        return packet;
    }

    public record ParsedPacket(byte type, byte[] data) {
    }

    public static ParsedPacket decode(byte[] header, byte[] body) {
        if (header == null || header.length < 3) {
            return null;
        }
        byte type = header[0];
        int len = (header[1] & 0xFF) | ((header[2] & 0xFF) << 8);
        if (body == null || body.length != len) {
            return null;
        }
        return new ParsedPacket(type, body);
    }
}
