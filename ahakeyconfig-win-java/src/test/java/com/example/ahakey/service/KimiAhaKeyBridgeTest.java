package com.example.ahakey.service;

import org.junit.jupiter.api.Test;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.net.ServerSocket;
import java.net.Socket;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KimiAhaKeyBridgeTest {
    @Test
    void onlyFreshAutoIsExposedAsAuto() throws Exception {
        assertEquals(0, querySwitch(snapshot(ApprovalState.AUTO, true, true)));
        assertEquals(1, querySwitch(snapshot(ApprovalState.AUTO, true, false)));
        assertEquals(1, querySwitch(snapshot(ApprovalState.MANUAL, true, true)));
        assertEquals(1, querySwitch(snapshot(ApprovalState.DISCONNECTED, false, false)));
        assertEquals(1, querySwitch(snapshot(ApprovalState.UNKNOWN, false, false)));
    }

    @Test
    void providerExceptionFailsClosed() throws Exception {
        ApprovalService approvals = new ApprovalService(timeout -> {
            throw new IllegalStateException("transport failed");
        }, 20);
        assertEquals(1, querySwitch(approvals));
    }

    @Test
    void stopAndRestartSupportsUsbBlePortOwnershipSwitching() throws Exception {
        ApprovalService approvals = service(snapshot(ApprovalState.MANUAL, true, true));
        KimiAhaKeyBridge bridge = new KimiAhaKeyBridge(approvals, 0);
        bridge.start();
        assertTrue(bridge.isRunning());
        assertTrue(bridge.getBoundPort() > 0);
        bridge.stop();
        assertFalse(bridge.isRunning());
        bridge.start();
        assertTrue(bridge.isRunning());
        bridge.stop();
    }

    @Test
    void occupiedPortDoesNotClaimRunningState() throws Exception {
        try (ServerSocket owner = new ServerSocket(0)) {
            KimiAhaKeyBridge bridge = new KimiAhaKeyBridge(
                service(snapshot(ApprovalState.MANUAL, true, true)), owner.getLocalPort());
            bridge.start();
            assertFalse(bridge.isRunning());
            bridge.stop();
        }
    }

    private int querySwitch(ApprovalSnapshot snapshot) throws Exception {
        return querySwitch(service(snapshot));
    }

    private ApprovalService service(ApprovalSnapshot snapshot) {
        return new ApprovalService(timeout -> snapshot, 20);
    }

    private ApprovalSnapshot snapshot(
        ApprovalState state, boolean connected, boolean fresh
    ) {
        return new ApprovalSnapshot(state, connected, fresh, 1);
    }

    private int querySwitch(ApprovalService approvals) throws Exception {
        KimiAhaKeyBridge bridge = new KimiAhaKeyBridge(approvals, 0);
        bridge.start();
        try (Socket socket = new Socket("127.0.0.1", bridge.getBoundPort());
             DataOutputStream out = new DataOutputStream(socket.getOutputStream());
             DataInputStream in = new DataInputStream(socket.getInputStream())) {
            sendQuery(out, 0x03);
            readPacket(in);
            sendQuery(out, 0x04);
            byte[] info = readPacket(in);
            return info[6] & 0xff;
        } finally {
            bridge.stop();
        }
    }

    private void sendQuery(DataOutputStream out, int type) throws Exception {
        out.writeByte(type);
        out.writeByte(0);
        out.writeByte(0);
        out.flush();
    }

    private byte[] readPacket(DataInputStream in) throws Exception {
        in.readUnsignedByte();
        int length = in.readUnsignedByte() | (in.readUnsignedByte() << 8);
        return in.readNBytes(length);
    }
}
