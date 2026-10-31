package com.example.ahakey.service.connection;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Consumer;

/** Versioned, private loopback IPC. No device selection/reconnection is implicit in startup. */
public final class ManagedBridgeClient implements AutoCloseable {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final class Connection {
        final Socket socket;
        Process owner;
        final ConcurrentMap<String, CompletableFuture<JsonNode>> pending = new ConcurrentHashMap<>();
        final ExecutorService writes = Executors.newSingleThreadExecutor(r -> daemon(r, "bridge-writes"));
        volatile String instance = "";
        long eventSequence;
        Connection(Socket socket) { this.socket = socket; }
        void close() {
            try { socket.close(); } catch (IOException ignored) { }
            pending.values().forEach(f -> f.completeExceptionally(new IOException("桥连接中断")));
            writes.shutdownNow();
        }
    }
    private static Thread daemon(Runnable r, String name) { Thread t = new Thread(r, name); t.setDaemon(true); return t; }
    private final AtomicLong sequence = new AtomicLong();
    private final ExecutorService events = Executors.newSingleThreadExecutor(r -> daemon(r, "bridge-events"));
    private volatile Connection connection;
    private volatile Process ownedProcess;
    private volatile boolean closed;
    private volatile Consumer<JsonNode> eventHandler = event -> {};
    public void onEvent(Consumer<JsonNode> handler) { eventHandler = Objects.requireNonNull(handler); }
    public boolean running() { Connection c = connection; return !closed && c != null && !c.socket.isClosed() && !c.instance.isEmpty(); }
    public static Path applicationDirectory() throws Exception {
        Path path = Path.of(ManagedBridgeClient.class.getProtectionDomain().getCodeSource().getLocation().toURI());
        return Files.isRegularFile(path) ? path.getParent() : Path.of(System.getProperty("user.dir"));
    }
    public synchronized void start() throws Exception {
        if (closed) throw new IOException("桥已关闭");
        if (running()) return;
        stopOwnedProcess(ownedProcess);
        if (ownedProcess != null && ownedProcess.isAlive()) throw new IOException("旧桥进程尚未退出");
        Path root = applicationDirectory();
        Path executable = root.resolve("BLE_tcp_driver.exe");
        Path manifest = root.resolve("bridge-managed.json");
        if (!Files.isRegularFile(executable) || !Files.isRegularFile(manifest)) throw new IOException("随包蓝牙桥版本不匹配，请使用配套安装包。");
        JsonNode identity = JSON.readTree(Files.readAllBytes(manifest));
        String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(executable)));
        if (identity.path("protocolVersion").asInt() != 1 || !hash.equals(identity.path("sha256").asText()))
            throw new IOException("蓝牙桥身份校验失败，未启动旧桥。");
        int port;
        try (ServerSocket reservation = new ServerSocket(0, 1, InetAddress.getLoopbackAddress())) { port = reservation.getLocalPort(); }
        String token = UUID.randomUUID() + "-" + UUID.randomUUID();
        ProcessBuilder builder = new ProcessBuilder(executable.toString(), "--studio", "--minimized", "--port", Integer.toString(port));
        builder.directory(root.toFile());
        builder.environment().put("AHAKEY_BRIDGE_TOKEN", token);
        builder.redirectOutput(ProcessBuilder.Redirect.DISCARD); builder.redirectError(ProcessBuilder.Redirect.DISCARD);
        Process launched = builder.start();
        ownedProcess = launched;
        Socket opened = null;
        try {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
            while (!closed && opened == null && System.nanoTime() < deadline && launched.isAlive()) {
                Socket attempt = new Socket();
                try { attempt.connect(new InetSocketAddress("127.0.0.1", port), 200); opened = attempt; }
                catch (IOException failure) { attempt.close(); Thread.sleep(50); }
            }
            if (closed || opened == null) throw new IOException("蓝牙桥启动超时或端口被占用。");
            attach(opened);
            ObjectNode hello = fields(); hello.put("ownerToken", token); hello.putArray("versions").add(1);
            JsonNode reply = request("hello", hello, 2000);
            if (reply.path("version").asInt() != 1 || reply.path("bridgeInstanceId").asText().isBlank()
                    || !reply.path("capabilities").toString().contains("session-writes"))
                throw new IOException("桥不支持当前连接协议。");
            connection.instance = reply.path("bridgeInstanceId").asText();
        } catch (Exception failure) {
            if (opened != null) try { opened.close(); } catch (IOException ignored) { }
            stopOwnedProcess(launched);
            throw failure;
        }
    }
    // Package seam for loopback tests; production calls only after verifying the bundled executable.
    void attach(Socket opened) throws IOException {
        if (closed) { opened.close(); throw new IOException("桥已关闭"); }
        Connection old = connection;
        if (old != null) old.close();
        opened.setTcpNoDelay(true);
        Connection next = new Connection(opened); next.owner=ownedProcess; connection = next;
        daemon(() -> read(next), "managed-bridge-reader").start();
    }
    public JsonNode request(String op, ObjectNode fields, long timeoutMillis) throws Exception {
        return request(connection, op, fields, timeoutMillis);
    }
    public Object ownerIdentity() { return connection; }
    public boolean ownerRetired(Object identity) {
        Connection captured=(Connection)identity;
        return captured==null || (captured.socket.isClosed() && (captured.owner==null || !captured.owner.isAlive()));
    }
    /** A failed release retires only the captured owned bridge, never a replacement. */
    public void releaseSession(Object identity, ObjectNode fields) throws Exception {
        Connection captured=(Connection)identity;
        if(captured==null)return;
        try { request(captured,"disconnect",fields,2000); }
        catch(Exception failure) {
            captured.close();stopOwnedProcess(captured.owner);
            if(captured.owner!=null && captured.owner.isAlive())throw new IOException("旧桥会话尚未确认撤销",failure);
        }
    }
    private JsonNode request(Connection captured, String op, ObjectNode fields, long timeoutMillis) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
        if (closed || captured == null || captured.socket.isClosed()) throw new IOException("蓝牙桥未连接");
        String id = Long.toString(sequence.incrementAndGet());
        ObjectNode request = fields.deepCopy();
        request.put("version", 1).put("requestId", id).put("bridgeInstanceId", captured.instance).put("op", op);
        byte[] body = JSON.writeValueAsBytes(request);
        if (body.length > 16384) throw new IOException("桥请求过长");
        CompletableFuture<JsonNode> result = new CompletableFuture<>(); captured.pending.put(id, result);
        try {
            captured.writes.execute(() -> {
                try {
                    if (captured != connection || captured.socket.isClosed() || System.nanoTime() >= deadline)
                        throw new IOException("桥连接已变化或发送超时");
                    OutputStream out = captured.socket.getOutputStream();
                    out.write(0x10); out.write(body.length & 255); out.write(body.length >>> 8); out.write(body); out.flush();
                } catch (Exception failure) { result.completeExceptionally(failure); }
            });
            long remaining = deadline - System.nanoTime();
            if (remaining <= 0) throw new TimeoutException();
            JsonNode reply = result.get(remaining, TimeUnit.NANOSECONDS);
            if (!reply.path("ok").asBoolean()) throw new IOException("蓝牙桥：" + reply.path("code").asText("请求失败"));
            return reply;
        } catch (TimeoutException | InterruptedException failure) {
            // Covers queueing and blocked writes as well as the response. Closing unblocks the writer.
            captured.close();
            if (failure instanceof InterruptedException) Thread.currentThread().interrupt();
            throw new IOException("蓝牙桥请求已中止，连接已撤销：" + op, failure);
        } finally { captured.pending.remove(id); }
    }
    public JsonNode request(String op, long timeoutMillis) throws Exception { return request(op, fields(), timeoutMillis); }
    public static ObjectNode fields() { return JSON.createObjectNode(); }
    private void read(Connection captured) {
        try {
            DataInputStream in = new DataInputStream(captured.socket.getInputStream());
            while (!captured.socket.isClosed()) {
                int type = in.readUnsignedByte(), length = in.readUnsignedByte() | (in.readUnsignedByte() << 8);
                if (length < 2 || length > 16384 || (type != 0x90 && type != 0x91)) throw new IOException("无效桥封包");
                byte[] bytes = new byte[length]; in.readFully(bytes);
                JsonNode value = JSON.readTree(bytes);
                if (value.path("version").asInt() != 1) throw new IOException("桥版本变化");
                if (!captured.instance.isEmpty() && !captured.instance.equals(value.path("bridgeInstanceId").asText())) throw new IOException("桥实例变化");
                if (type == 0x90) {
                    var future = captured.pending.get(value.path("requestId").asText());
                    if (future != null) future.complete(value);
                } else {
                    long next = value.path("eventSeq").asLong();
                    if (next <= captured.eventSequence) continue;
                    captured.eventSequence = next;
                    dispatch(captured, value);
                }
            }
        } catch (Exception failure) {
            captured.close();
            dispatch(captured, fields().put("event", "bridgeDisconnected").put("bridgeInstanceId", captured.instance));
        }
    }
    private void dispatch(Connection captured, JsonNode event) {
        try { events.execute(() -> { if (connection == captured && !closed) eventHandler.accept(event); }); }
        catch (RejectedExecutionException ignored) { }
    }
    static void stopOwnedProcess(Process process) {
        if (process == null || !process.isAlive()) return;
        try {
            if (process.waitFor(200, TimeUnit.MILLISECONDS)) return;
            process.destroy();
            if (!process.waitFor(200, TimeUnit.MILLISECONDS)) {
                process.destroyForcibly(); process.waitFor(600, TimeUnit.MILLISECONDS);
            }
        } catch (InterruptedException e) { process.destroyForcibly(); Thread.currentThread().interrupt(); }
    }
    public synchronized void restart() throws Exception {
        Connection previous=connection;connection=null;
        if(previous!=null)previous.close();stopOwnedProcess(ownedProcess);start();
    }
    public synchronized void stop() {
        Connection previous=connection;connection=null;
        if(previous!=null)previous.close();stopOwnedProcess(ownedProcess);
    }
    public void close() {
        closed = true;
        Connection captured = connection;
        if (captured != null) captured.close();
        events.shutdownNow();
        stopOwnedProcess(ownedProcess);
    }
}
