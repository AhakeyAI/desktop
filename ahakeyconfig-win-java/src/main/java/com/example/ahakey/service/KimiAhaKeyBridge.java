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
        if (!closed && bleManager.connectionGeneration() > blockedThroughGeneration
                && bleManager.isConnected() && bleManager.isUsbConnected()) start();
        else stop();
    }

    /** Release our listener before the connection worker can attempt the BLE TCP port. */
    public synchronized void prepareForConnection() {
        blockedThroughGeneration = bleManager.connectionGeneration();
        stop();
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
            listener.setReuseAddress(true);
            listener.bind(new InetSocketAddress("127.0.0.1", port));
            Session started = new Session(listener);
            session = started;
            started.executor.submit(() -> acceptLoop(started));
            logger.info("KimiAhaKeyBridge started on 127.0.0.1:{}", listener.getLocalPort());
        } catch (IOException e) {
            closeSocket(listener);
            logger.warn("KimiAhaKeyBridge: port {} unavailable: {}", port, e.getMessage());
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
                    byte[] data = {1, 0, 0, 1};
                    sendPacket(out, RSP_STATUS, data);
                } else if (type == (PKT_QUERY_INFO & 0xFF)) {
                    // Respond 0x83: data[6] = switchState (0=auto, 1=manual)
                    int switchState = bleManager.getCachedStatus().getSwitchState();
                    if (switchState < 0) switchState = 1; // default to manual if unknown
                    byte[] data = new byte[10];
                    data[6] = (byte) switchState;
                    sendPacket(out, RSP_INFO, data);
                    logger.debug("KimiAhaKeyBridge: query → switchState={} isAuto={}",
                            switchState, switchState == 0);
                }
            }
        } catch (IOException e) {
            logger.debug("KimiAhaKeyBridge client: {}", e.getMessage());
        } finally {
            synchronized (this) { expected.clients.remove(client); }
        }
    }

    private void sendPacket(DataOutputStream out, byte type, byte[] data) throws IOException {
        out.writeByte(type);
        // length as little-endian uint16
        out.writeByte(data.length & 0xFF);
        out.writeByte((data.length >> 8) & 0xFF);
        out.write(data);
        out.flush();
    }
}
