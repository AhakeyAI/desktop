package com.example.ahakey.model.connection;

public record DeviceTarget(String transport, String id, String name) {
    public DeviceTarget {
        if (!(transport.equals("USB") || transport.equals("BLE")) || id == null || id.isBlank())
            throw new IllegalArgumentException("设备身份无效");
    }
    public String key() { return transport + ":" + id; }
    @Override public String toString() { return name + " · " + transport + " · " + id; }
}
