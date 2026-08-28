package com.example.ahakey;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.RandomAccessFile;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

/** File-lock ownership plus a loopback SHOW_WINDOW activation endpoint. */
public final class SingleInstanceChecker {
    private static final Logger logger = LoggerFactory.getLogger(SingleInstanceChecker.class);
    private static final Path STATE_DIR =
        Path.of(System.getProperty("user.home"), ".ahakey");
    private static final Path LOCK_PATH = STATE_DIR.resolve(".ahakey-studio.lock");
    private static final Path PORT_PATH = STATE_DIR.resolve(".ahakey-studio.port");
    private static FileLock fileLock;
    private static FileChannel lockChannel;
    private static RandomAccessFile lockFile;
    private static ServerSocket activationServer;

    private SingleInstanceChecker() {}

    public static synchronized boolean acquireOrActivate(Runnable showWindow) {
        try {
            Files.createDirectories(STATE_DIR);
            lockFile = new RandomAccessFile(LOCK_PATH.toFile(), "rw");
            lockChannel = lockFile.getChannel();
            try {
                fileLock = lockChannel.tryLock();
            } catch (java.nio.channels.OverlappingFileLockException locked) {
                fileLock = null;
            }
            if (fileLock == null) {
                closeLockResources();
                sendShowWindow();
                return true;
            }
            startActivationServer(showWindow);
            Runtime.getRuntime().addShutdownHook(
                new Thread(SingleInstanceChecker::closeOwnedResources, "single-instance-close"));
            return false;
        } catch (Exception failure) {
            logger.warn("单实例检测失败: {}", failure.getMessage());
            closeOwnedResources();
            return false;
        }
    }

    public static boolean isAlreadyRunning() {
        return acquireOrActivate(() -> {});
    }

    private static void startActivationServer(Runnable showWindow) throws Exception {
        activationServer = new ServerSocket(0, 8, InetAddress.getLoopbackAddress());
        Path temporary = PORT_PATH.resolveSibling(PORT_PATH.getFileName() + ".tmp");
        Files.writeString(temporary, Integer.toString(activationServer.getLocalPort()));
        try {
            Files.move(temporary, PORT_PATH, StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING);
        } catch (java.nio.file.AtomicMoveNotSupportedException unsupported) {
            Files.move(temporary, PORT_PATH, StandardCopyOption.REPLACE_EXISTING);
        }
        Thread listener = new Thread(() -> {
            while (!activationServer.isClosed()) {
                try (Socket client = activationServer.accept();
                     DataInputStream input = new DataInputStream(client.getInputStream())) {
                    if ("SHOW_WINDOW".equals(input.readUTF())) showWindow.run();
                } catch (Exception failure) {
                    if (!activationServer.isClosed())
                        logger.debug("窗口激活请求失败: {}", failure.getMessage());
                }
            }
        }, "single-instance-activation");
        listener.setDaemon(true);
        listener.start();
    }

    private static void sendShowWindow() {
        try {
            int port = Integer.parseInt(Files.readString(PORT_PATH).trim());
            try (Socket socket = new Socket(InetAddress.getLoopbackAddress(), port);
                 DataOutputStream output = new DataOutputStream(socket.getOutputStream())) {
                output.writeUTF("SHOW_WINDOW");
                output.flush();
            }
        } catch (Exception failure) {
            logger.warn("已有实例存在，但发送显示窗口请求失败: {}", failure.getMessage());
        }
    }

    private static synchronized void closeOwnedResources() {
        try { if (activationServer != null) activationServer.close(); } catch (Exception ignored) {}
        activationServer = null;
        try { Files.deleteIfExists(PORT_PATH); } catch (Exception ignored) {}
        try { if (fileLock != null && fileLock.isValid()) fileLock.release(); } catch (Exception ignored) {}
        fileLock = null;
        closeLockResources();
        try { Files.deleteIfExists(LOCK_PATH); } catch (Exception ignored) {}
    }

    private static void closeLockResources() {
        try { if (lockChannel != null) lockChannel.close(); } catch (Exception ignored) {}
        try { if (lockFile != null) lockFile.close(); } catch (Exception ignored) {}
        lockChannel = null;
        lockFile = null;
    }
}
