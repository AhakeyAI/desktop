package com.example.ahakey.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.*;
import java.net.*;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Kimi built-in AhaKey bridge server on port 9000.
 *
 * Kimi's approval.py connects here to read switch state:
 *   PKT_QUERY_STATUS (0x03) → respond 0x82 with status bytes [1,0,0,1]
 *   PKT_QUERY_INFO   (0x04) → respond 0x83 with info bytes where index 6 = switchState
 *
 * Packet format: [type:1][length:2 LE][data:length]
 */
public class KimiAhaKeyBridge {
    private static final Logger logger = LoggerFactory.getLogger(KimiAhaKeyBridge.class);

    private static final int PORT = 9000;
    private static final byte PKT_QUERY_STATUS = 0x03;
    private static final byte PKT_QUERY_INFO   = 0x04;
    private static final byte RSP_STATUS        = (byte) 0x82;
    private static final byte RSP_INFO          = (byte) 0x83;

    private final BleManager bleManager;
    private final int port;
    private Session session;
    private long blockedThroughGeneration = Long.MIN_VALUE;
    private boolean closed;
    private java.util.function.Consumer<String> problemHandler = message -> {};

    public synchronized void setProblemHandler(java.util.function.Consumer<String> handler) {
        problemHandler = java.util.Objects.requireNonNull(handler);
    }

    private static final class Session {
        final ServerSocket listener;
        final ExecutorService executor = Executors.newCachedThreadPool(r -> {
            Thread t = new Thread(r, "kimi-bridge");
            t.setDaemon(true);
            return t;
        });
        final Set<Socket> clients = new HashSet<>(); // guarded by the bridge monitor
        Session(ServerSocket listener) { this.listener = listener; }
    }

    public KimiAhaKeyBridge(BleManager bleManager) {
        this(bleManager, PORT);
    }

    KimiAhaKeyBridge(BleManager bleManager, int port) {
        this.bleManager = bleManager;
        this.port = port;
    }

    /** Reconcile current transport, rather than replaying a possibly delayed callback. */
    public synchronized void connectionChanged() {
        // Reserve the native approval endpoint even when disconnected or in maintenance.
        // Only the verified current target may produce AUTO, regardless of USB/BLE transport.
        if (!closed) start();
    }

    /** Invalidate old approval queries without releasing the dedicated native endpoint. */
    public synchronized void prepareForConnection() {
        blockedThroughGeneration = bleManager.connectionGeneration();
        if (session != null) for (Socket client : session.clients) closeSocket(client);
    }

    public synchronized void close() {
        closed = true;
        stop();
    }

    public synchronized void start() {
        if (closed || session != null) return;
        ServerSocket listener = null;
        try {
            listener = new ServerSocket();
            listener.setReuseAddress(false);
            listener.bind(new InetSocketAddress("127.0.0.1", port));
            Session started = new Session(listener);
            session = started;
            started.executor.submit(() -> acceptLoop(started));
            logger.info("KimiAhaKeyBridge started on 127.0.0.1:{}", listener.getLocalPort());
            problemHandler.accept("");
        } catch (IOException e) {
            closeSocket(listener);
            logger.warn("KimiAhaKeyBridge: port {} unavailable: {}", port, e.getMessage());
            problemHandler.accept("Kimi 审批端口 " + port + " 被占用，审批状态无法确认。请正常退出旧版 BLE 桥或占用该端口的程序，再重新连接设备；请勿依赖当前 Kimi 拨杆审批。");
        }
    }

    public synchronized void stop() {
        Session stopped = session;
        session = null;
        if (stopped == null) return;
        closeSocket(stopped.listener);
        for (Socket client : stopped.clients) closeSocket(client);
        stopped.clients.clear();
        stopped.executor.shutdownNow();
    }

    private static void closeSocket(Closeable socket) {
        try { if (socket != null) socket.close(); } catch (IOException ignored) { }
    }

    private synchronized boolean isCurrent(Session expected) { return session == expected; }

    private synchronized boolean targetCurrent(Session expected, long generation, long maintenanceEpoch) {
        return session == expected && !closed && generation > blockedThroughGeneration
                && generation == bleManager.connectionGeneration() && bleManager.isConnected()
                && maintenanceEpoch == bleManager.maintenance().epoch() && bleManager.maintenance().normalAllowed();
    }

    private boolean confirmedAuto(Session expected, long generation, long maintenanceEpoch) {
        return targetCurrent(expected, generation, maintenanceEpoch) && bleManager.refreshAutoApproval()
                && targetCurrent(expected, generation, maintenanceEpoch);
    }

    private void acceptLoop(Session expected) {
        while (isCurrent(expected)) {
            try {
                Socket client = expected.listener.accept();
                synchronized (this) {
                    if (session != expected) { closeSocket(client); return; }
                    try {
                        client.setSoTimeout(500);
                        expected.clients.add(client);
                        expected.executor.submit(() -> handle(expected, client));
                    } catch (IOException | RuntimeException e) {
                        expected.clients.remove(client);
                        closeSocket(client);
                        throw e;
                    }
                }
            } catch (IOException e) {
                if (isCurrent(expected)) logger.debug("KimiAhaKeyBridge accept: {}", e.getMessage());
            }
        }
    }

    private void handle(Session expected, Socket client) {
        try (client) {
            DataInputStream in  = new DataInputStream(client.getInputStream());
            DataOutputStream out = new DataOutputStream(client.getOutputStream());
            long generation = bleManager.connectionGeneration();
            long maintenanceEpoch = bleManager.maintenance().epoch();

            // Kimi sends two packets per query session: QUERY_STATUS then QUERY_INFO
            for (int i = 0; i < 2; i++) {
                byte[] header = new byte[3];
                in.readFully(header);
                int type   = header[0] & 0xFF;
                int length = ((header[2] & 0xFF) << 8) | (header[1] & 0xFF); // little-endian
                if (length > 0) in.readFully(new byte[length]); // discard complete body
                if (!isCurrent(expected)) return;

                if (type == (PKT_QUERY_STATUS & 0xFF)) {
                    // Respond 0x82: status[0]==1, status[-1]==1, len>=4
                    // Unavailable means native defer, not a forced manual override.
                    if (!confirmedAuto(expected, generation, maintenanceEpoch)) { sendPacket(out, RSP_STATUS, new byte[]{0, 0, 0, 0}); return; }
                    byte[] data = {1, 0, 0, 1};
                    sendCurrentPacket(expected, generation, maintenanceEpoch, out, RSP_STATUS, data);
                } else if (type == (PKT_QUERY_INFO & 0xFF)) {
                    if (!confirmedAuto(expected, generation, maintenanceEpoch)) { sendPacket(out, RSP_INFO, new byte[0]); return; }
                    byte[] data = new byte[10];
                    data[6] = 0; // Only confirmed AUTO is an override; never export physical position.
                    sendCurrentPacket(expected, generation, maintenanceEpoch, out, RSP_INFO, data);
                }
            }
        } catch (IOException e) {
            logger.debug("KimiAhaKeyBridge client: {}", e.getMessage());
        } finally {
            synchronized (this) { expected.clients.remove(client); }
        }
    }

    private synchronized void sendCurrentPacket(Session expected, long generation, long epoch,
                                               DataOutputStream out, byte type, byte[] data) throws IOException {
        if (!targetCurrent(expected, generation, epoch)) throw new IOException("Kimi approval target changed");
        sendPacket(out, type, data);
    }

    private void sendPacket(DataOutputStream out, byte type, byte[] data) throws IOException {
        // The bundled consumer reads its three-byte header in one recv call.
        // Emit the complete small frame together instead of three independent header writes.
        byte[] packet = new byte[3 + data.length];
        packet[0] = type;
        packet[1] = (byte) data.length;
        packet[2] = (byte) (data.length >>> 8);
        System.arraycopy(data, 0, packet, 3, data.length);
        out.write(packet);
        out.flush();
    }
}
