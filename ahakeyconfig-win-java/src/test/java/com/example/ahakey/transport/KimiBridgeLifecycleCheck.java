package com.example.ahakey.service;

import java.io.*;
import java.net.*;
import java.lang.reflect.Field;
import java.util.Arrays;

/** Isolated loopback ports only; never calls connect(), HID discovery, or the application. */
public final class KimiBridgeLifecycleCheck {
    private static int checks;
    private static final class Transport extends BleManager {
        long generation = 1;
        boolean connected = true;
        boolean usb = true;
        Transport() { super(null); getCachedStatus().setSwitchState(0); }
        @Override public long connectionGeneration() { return generation; }
        @Override public boolean isConnected() { return connected; }
        @Override public boolean isUsbConnected() { return usb; }
        @Override public void connect() { throw new AssertionError("Hardware forbidden"); }
        @Override protected boolean isUsbDevicePresent() { throw new AssertionError("HID forbidden"); }
    }
    private static Object field(Object value, String name) throws Exception {
        Field field = value.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(value);
    }
    private static int port(KimiAhaKeyBridge bridge) throws Exception {
        return ((ServerSocket) field(field(bridge, "session"), "listener")).getLocalPort();
    }
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
        checks++;
    }
    private static Socket client(int port) throws Exception {
        Socket socket = new Socket("127.0.0.1", port);
        socket.setSoTimeout(2000);
        return socket;
    }
    private static byte[] query(Socket client, int type) throws Exception {
        client.getOutputStream().write(new byte[]{(byte)type, 0, 0});
        DataInputStream in = new DataInputStream(client.getInputStream());
        int response = in.readUnsignedByte();
        int length = in.readUnsignedByte() | in.readUnsignedByte() << 8;
        check(response == (type == 3 ? 0x82 : 0x83), "unchanged response type");
        return in.readNBytes(length);
    }
    public static void main(String[] args) throws Exception {
        Transport transport = new Transport();
        KimiAhaKeyBridge bridge = new KimiAhaKeyBridge(transport, 0);
        try {
            bridge.connectionChanged();
            for (int round = 0; round < 30; round++) {
                int oldPort = port(bridge);
                try (Socket oldClient = client(oldPort)) {
                    check(Arrays.equals(query(oldClient, 3), new byte[]{1,0,0,1}), "status payload");
                    bridge.prepareForConnection();
                    oldClient.setSoTimeout(200);
                    check(oldClient.getInputStream().read() == -1, "stop closes accepted clients immediately");
                    // Same-generation late connect callback cannot reclaim the BLE port.
                    bridge.connectionChanged();
                    check(field(bridge,"session") == null, "late USB callback blocked while switching");
                    try (ServerSocket bleListener = new ServerSocket()) {
                        bleListener.setReuseAddress(true);
                        bleListener.bind(new InetSocketAddress("127.0.0.1", oldPort));
                        transport.generation++;
                        transport.usb = false;
                        bridge.connectionChanged();
                        check(field(bridge,"session") == null, "BLE keeps internal listener stopped");
                    }
                    transport.generation++;
                    transport.usb = true;
                    bridge.connectionChanged();
                    Object newSession = field(bridge,"session");
                    bridge.connectionChanged(); // delayed disconnect notification reconciles current USB
                    check(field(bridge,"session") == newSession, "late disconnect cannot stop current USB");
                    try (Socket fresh = client(port(bridge))) {
                        query(fresh, 3);
                        byte[] info = query(fresh, 4);
                        check(info.length == 10 && info[6] == 0, "USB reconnect preserves Kimi auto state");
                    }
                }
            }
            transport.connected = false;
            bridge.connectionChanged();
            check(field(bridge,"session") == null, "disconnect stops service");
            bridge.stop(); bridge.stop();
            transport.connected = true;
            transport.generation++;
            bridge.connectionChanged();
            bridge.close();
            bridge.connectionChanged(); bridge.start();
            check(field(bridge,"session") == null, "shutdown rejects late start");
        } finally { bridge.close(); }
        try (ServerSocket occupied = new ServerSocket(0,10,InetAddress.getLoopbackAddress())) {
            int busyPort = occupied.getLocalPort();
            KimiAhaKeyBridge retry = new KimiAhaKeyBridge(transport, busyPort);
            try {
                retry.start();
                check(field(retry,"session") == null, "occupied external port not taken over");
                occupied.close();
                retry.start();
                try (Socket socket = client(busyPort)) { query(socket, 3); query(socket, 4); }
            } finally { retry.close(); }
        }
        System.out.println("PASS " + checks + " Kimi checks; 30 USB/BLE/USB rounds; ephemeral ports only");
    }
}
