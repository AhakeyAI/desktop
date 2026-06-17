package com.example.ahakey.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.*;
import java.net.*;
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
    private ServerSocket serverSocket;
    private ExecutorService executor;
    private volatile boolean running;

    public KimiAhaKeyBridge(BleManager bleManager) {
        this.bleManager = bleManager;
    }

    public void start() {
        if (running) return;
        try {
            serverSocket = new ServerSocket();
            serverSocket.setReuseAddress(true);
            serverSocket.bind(new InetSocketAddress("127.0.0.1", PORT));
            running = true;
            logger.info("KimiAhaKeyBridge started on 127.0.0.1:{}", PORT);
        } catch (IOException e) {
            logger.warn("KimiAhaKeyBridge: port {} unavailable: {}", PORT, e.getMessage());
            return;
        }
        executor = Executors.newCachedThreadPool(r -> {
            Thread t = new Thread(r, "kimi-bridge");
            t.setDaemon(true);
            return t;
        });
        executor.submit(this::acceptLoop);
    }

    public void stop() {
        running = false;
        try { if (serverSocket != null) serverSocket.close(); } catch (IOException ignored) {}
        if (executor != null) executor.shutdownNow();
    }

    private void acceptLoop() {
        while (running && !serverSocket.isClosed()) {
            try {
                Socket client = serverSocket.accept();
                client.setSoTimeout(500);
                executor.submit(() -> handle(client));
            } catch (IOException e) {
                if (running) logger.debug("KimiAhaKeyBridge accept: {}", e.getMessage());
            }
        }
    }

    private void handle(Socket client) {
        try (client) {
            DataInputStream in  = new DataInputStream(client.getInputStream());
            DataOutputStream out = new DataOutputStream(client.getOutputStream());

            // Kimi sends two packets per query session: QUERY_STATUS then QUERY_INFO
            for (int i = 0; i < 2; i++) {
                byte[] header = new byte[3];
                in.readFully(header);
                int type   = header[0] & 0xFF;
                int length = ((header[2] & 0xFF) << 8) | (header[1] & 0xFF); // little-endian
                if (length > 0) in.readNBytes(length); // discard body

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
