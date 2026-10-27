package com.example.ahakey.firmware;

import java.io.IOException;
import java.util.Set;
import java.util.UUID;

/** Shared admission gate. Never calls device/UI code while holding its monitor. */
public final class DeviceMaintenanceCoordinator {
    public enum Stage { BACKUP, PREPARED, DOWNLOAD_MODE, FLASH, VERIFY, RECONNECT, RESTORE, INSTALL, UNCERTAIN }
    public record Identity(long generation, String transport, String devicePath, String container, String port, String catalog) {
        public boolean samePhysicalDevice(Identity other) {
            if (other == null) return false;
            if (!container.isBlank() && !other.container.isBlank()) return container.equalsIgnoreCase(other.container)
                    && (port.isBlank() || other.port.isBlank() || port.equalsIgnoreCase(other.port));
            return !port.isBlank() && port.equalsIgnoreCase(other.port);
        }
    }
    public final class Operation {
        private final UUID id = UUID.randomUUID();
        private final Identity source;
        private final String targetHash;
        private final String profile;
        private String backupHash = "";
        private Stage stage;
        private long generation;
        private boolean processAlive;
        private Operation(Identity source, String hash, String profile, Stage stage) {
            this.source = source; this.targetHash = hash; this.profile = profile; this.stage = stage;
            this.generation = source == null ? -1 : source.generation();
        }
        public UUID id() { return id; }
        public Identity source() { return source; }
        public String targetHash() { return targetHash; }
        public String profile() { return profile; }
        public Stage stage() { synchronized (DeviceMaintenanceCoordinator.this) { return stage; } }
        public String backupHash() { synchronized (DeviceMaintenanceCoordinator.this) { return backupHash; } }
    }
    @FunctionalInterface public interface Task<T> { T run() throws Exception; }
    private Operation active;
    private final ThreadLocal<Operation> caller = new ThreadLocal<>();
    private int normalTransactions;
    private boolean exiting;
    private long epoch;
    public synchronized long epoch() { return epoch; }
    public synchronized boolean active() { return active != null; }
    public synchronized boolean normalAllowed() { return active == null && !exiting; }
    public synchronized Operation current() { return active; }
    public synchronized Operation begin(Identity source, String hash, String profile, boolean install) throws IOException {
        if (!normalAllowed() || normalTransactions != 0) throw new IOException("设备或应用正忙，请等待当前操作完成。");
        epoch++;
        active = new Operation(source, hash, profile, install ? Stage.INSTALL : Stage.BACKUP);
        return active;
    }
    public synchronized AutoCloseable normalTransaction() throws IOException {
        if (!normalAllowed()) throw new IOException("维护期间暂停普通设备操作。");
        normalTransactions++;
        return new AutoCloseable() {
            private boolean closed;
            @Override public void close() {
                synchronized (DeviceMaintenanceCoordinator.this) {
                    if (!closed) { closed = true; normalTransactions--; }
                }
            }
        };
    }
    public <T> T within(Operation operation, Task<T> task) throws Exception {
        synchronized (this) { require(operation); }
        if (caller.get() != null) throw new IOException("维护权限不可嵌套。");
        caller.set(operation);
        try { return task.run(); } finally { caller.remove(); }
    }
    public synchronized void admit(int opcode, long generation) throws IOException {
        if (exiting) throw new IOException("应用正在退出。");
        if (active == null) return;
        Operation op = caller.get();
        require(op);
        if (generation != op.generation) throw new IOException("设备连接已改变，维护授权失效。");
        Set<Integer> allowed = switch (op.stage) {
            case BACKUP -> Set.of(0x00, 0x9F, 0x87, 0x97, 0x88);
            case RECONNECT -> Set.of(0x00, 0x9F);
            case RESTORE -> Set.of(0x00, 0x9F, 0x87, 0x97, 0x88, 0x73, 0x04, 0x8E);
            default -> Set.of();
        };
        if (!allowed.contains(opcode)) throw new IOException("当前维护阶段不允许此设备命令。");
    }
    public synchronized void admitFrame(byte[] frame, long generation) throws IOException {
        if (frame == null || frame.length < 5) throw new IOException("设备帧无效。");
        int opcode = frame[2] & 255;
        admit(opcode, generation);
        if (active == null) return;
        if (active.stage == Stage.BACKUP && opcode == 0x97 && frame.length != 5)
            throw new IOException("备份阶段禁止写入侧拨。");
        if (opcode == 0x88 && (frame.length < 6 || (frame[3] & 255) > 1))
            throw new IOException("维护不读取 OLED 内容。");
        if (opcode == 0x8E && (frame.length < 7 || (frame[3] & 255) > 1))
            throw new IOException("恢复只允许亮度和灯效。");
    }
    public synchronized void stage(Operation op, Stage expected, Stage next) throws IOException {
        require(op);
        if (op.stage != expected) throw new IOException("维护阶段已改变。");
        op.stage = next;
    }
    public synchronized void bindBackup(Operation op, String hash) throws IOException {
        require(op);
        if (op.stage != Stage.BACKUP || !hash.matches("[a-f0-9]{64}")) throw new IOException("备份未就绪。");
        op.backupHash = hash;
    }
    public synchronized void bindReconnection(Operation op, Identity identity) throws IOException {
        require(op);
        if (op.stage != Stage.RECONNECT || !op.source.samePhysicalDevice(identity)) throw new IOException("无法确认是原键盘。");
        op.generation = identity.generation();
    }
    public synchronized void processAlive(Operation op, boolean alive) throws IOException { require(op); op.processAlive = alive; }
    public synchronized void uncertain(Operation op) throws IOException { require(op); op.stage = Stage.UNCERTAIN; }
    public synchronized void finish(Operation op, boolean acknowledged) throws IOException {
        require(op);
        if (op.processAlive || ((op.stage == Stage.FLASH || op.stage == Stage.VERIFY || op.stage == Stage.UNCERTAIN) && !acknowledged))
            throw new IOException("工具仍可能执行或结果未处置，继续保持维护锁。");
        active = null; epoch++;
    }
    public synchronized boolean requestExit(Operation installation) {
        if (normalTransactions != 0 || (active != null && (active != installation || active.stage != Stage.INSTALL))) return false;
        exiting = true; return true;
    }
    private void require(Operation op) throws IOException {
        if (op == null || active != op) throw new IOException("维护会话已失效。");
    }
}
