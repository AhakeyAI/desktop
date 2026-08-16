package com.example.ahakey.service;

import com.example.ahakey.model.IDEState;
import javafx.application.Platform;
import javafx.beans.property.ReadOnlyListProperty;
import javafx.beans.property.ReadOnlyListWrapper;
import javafx.collections.FXCollections;
import java.util.*;
import java.util.concurrent.*;

/** Maps AI hook sessions to the four physical task-light/GIF slots. */
public final class TaskActivityService implements AutoCloseable {
    public record TaskSnapshot(int slot, int profile, int state, boolean foreground,
                               String platform, String title, String taskId, long updatedAt) {}
    private final BleManager ble;
    private final Map<String, MutableTask> tasks = new LinkedHashMap<>();
    private final ReadOnlyListWrapper<TaskSnapshot> visibleTasks =
        new ReadOnlyListWrapper<>(FXCollections.observableArrayList());
    private final ScheduledExecutorService worker = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r, "task-activity-sync"); t.setDaemon(true); return t;
    });
    private volatile boolean multiMode;
    private volatile boolean lastConnected;
    static final long COMPLETED_VISIBLE_MILLIS = 30_000L;
    private static final class MutableTask {
        String taskId, platform, title; int profile, state, slot = -1; boolean foreground; long updatedAt;
    }
    public TaskActivityService(BleManager ble) {
        this.ble = ble;
        worker.scheduleAtFixedRate(this::heartbeatAndReconcile, 2, 2, TimeUnit.SECONDS);
    }
    public ReadOnlyListProperty<TaskSnapshot> visibleTasksProperty() { return visibleTasks.getReadOnlyProperty(); }
    public List<TaskSnapshot> getVisibleTasks() { return List.copyOf(visibleTasks); }
    public boolean isMultiMode() { return multiMode; }
    public void setMultiMode(boolean enabled) {
        multiMode = enabled;
        worker.execute(() -> {
            if (ble.getCachedStatus().isConnected()) {
                try {
                    ble.setTaskDisplayMode(enabled ? 1 : 0);
                    clearHardwareSlots();
                    if (enabled) resendSnapshot();
                    lastConnected = true;
                } catch (Exception ignored) {}
            }
            publish();
        });
    }
    public void accept(String platform, int profile, String taskId, String title, IDEState ideState) {
        worker.execute(() -> {
            long now = System.currentTimeMillis();
            String stableId = normalizedTaskId(taskId);
            MutableTask found = stableId.isEmpty()
                ? mostRecentTask(platform) : tasks.get(platform + ':' + stableId);
            if (found == null && stableId.isEmpty()) {
                publish();
                return;
            }
            if (found == null) {
                found = new MutableTask();
                tasks.put(platform + ':' + stableId, found);
            }
            MutableTask task = found;
            String effectiveId = stableId.isEmpty() ? task.taskId : stableId;
            for (MutableTask item : tasks.values()) {
                if (item != task && item.foreground) {
                    item.foreground = false;
                    send(item);
                }
            }
            int nextState = toTaskState(ideState);
            int nextProfile = Math.max(0, Math.min(3, profile));
            String nextTitle = title == null || title.isBlank()
                ? (task.title == null || task.title.isBlank() ? platform + " · " + effectiveId : task.title)
                : title;
            boolean changed = task.state != nextState || task.profile != nextProfile
                || !Objects.equals(task.title, nextTitle) || !task.foreground;
            task.taskId = effectiveId;
            task.platform = platform;
            task.profile = nextProfile;
            task.title = nextTitle;
            task.state = nextState;
            task.foreground = true;
            if (changed) task.updatedAt = now;
            if (task.state == 0) {
                release(task);
                tasks.values().removeIf(item -> item == task);
            } else {
                allocate(task);
                if (changed) send(task);
            }
            publish();
        });
    }
    private static String normalizedTaskId(String taskId) {
        if (taskId == null) return "";
        String value = taskId.trim();
        return value.isEmpty() || value.equalsIgnoreCase("default")
            || value.equalsIgnoreCase("unknown") || value.equalsIgnoreCase("null")
            || value.matches("^[A-Za-z]:[\\\\/].*") || value.startsWith("/") ? "" : value;
    }
    private MutableTask mostRecentTask(String platform) {
        return tasks.values().stream().filter(task -> Objects.equals(task.platform, platform))
            .max(Comparator.comparingLong(task -> task.updatedAt)).orElse(null);
    }
    private static int toTaskState(IDEState state) {
        return switch (state) {
            case SESSION_END -> 0;
            case PERMISSION_REQUEST, NOTIFICATION -> 2;
            case TASK_COMPLETED, STOP -> 3;
            default -> 1;
        };
    }
    private void allocate(MutableTask task) {
        if (task.slot >= 0) return;
        boolean[] occupied = new boolean[4];
        tasks.values().stream().filter(t -> t.slot >= 0).forEach(t -> occupied[t.slot] = true);
        for (int i = 0; i < 4; i++) if (!occupied[i]) { task.slot = i; return; }
        MutableTask victim = tasks.values().stream().filter(t -> t.slot >= 0 && t.state != 2)
            .min(Comparator.comparingLong(t -> t.updatedAt)).orElse(null);
        if (victim != null) { task.slot = victim.slot; victim.slot = -1; }
    }
    private void release(MutableTask task) {
        if (task.slot < 0) return;
        int old = task.slot; task.slot = -1;
        try { if (ble.getCachedStatus().isConnected()) ble.updateTaskSlot(old, task.profile, 0, false); }
        catch (Exception ignored) {}
    }
    private void send(MutableTask task) {
        if (!multiMode || task.slot < 0 || !ble.getCachedStatus().isConnected()) return;
        try { ble.updateTaskSlot(task.slot, task.profile, task.state, task.foreground); }
        catch (Exception ignored) {}
    }
    private void heartbeatAndReconcile() {
        heartbeatAndReconcile(System.currentTimeMillis());
    }
    private void heartbeatAndReconcile(long now) {
        List<MutableTask> expired = tasks.values().stream()
            .filter(task -> task.state == 3 && now - task.updatedAt >= COMPLETED_VISIBLE_MILLIS)
            .toList();
        expired.forEach(this::release);
        for (MutableTask task : expired) {
            tasks.values().removeIf(item -> item == task);
        }
        if (!expired.isEmpty()) publish();

        boolean connected = ble.getCachedStatus().isConnected();
        if (!connected) {
            lastConnected = false;
            return;
        }
        if (!lastConnected) {
            try {
                ble.setTaskDisplayMode(multiMode ? 1 : 0);
                clearHardwareSlots();
                if (multiMode) resendSnapshot();
            } catch (Exception ignored) {}
            lastConnected = true;
        }
        if (multiMode) {
            try { ble.sendTaskHeartbeat(); } catch (Exception ignored) {}
        }
    }
    private void clearHardwareSlots() {
        for (int slot = 0; slot < 4; slot++) {
            try { ble.updateTaskSlot(slot, 0, 0, false); }
            catch (Exception ignored) {}
        }
    }
    private void resendSnapshot() {
        tasks.values().stream().filter(task -> task.slot >= 0 && task.state != 0).forEach(this::send);
    }
    private void publish() {
        List<TaskSnapshot> snapshot = new ArrayList<>();
        tasks.values().stream().filter(t -> t.slot >= 0 && t.state != 0)
            .sorted(Comparator.comparingInt(t -> t.slot)).forEach(t -> snapshot.add(
                new TaskSnapshot(t.slot, t.profile, t.state, t.foreground, t.platform, t.title, t.taskId, t.updatedAt)));
        try {
            Platform.runLater(() -> visibleTasks.setAll(snapshot));
        } catch (IllegalStateException toolkitNotStarted) {
            visibleTasks.setAll(snapshot);
        }
    }
    void awaitIdleForTest() throws Exception {
        worker.submit(() -> {}).get(2, TimeUnit.SECONDS);
    }
    void reconcileAtForTest(long now) throws Exception {
        worker.submit(() -> heartbeatAndReconcile(now)).get(2, TimeUnit.SECONDS);
    }
    @Override public void close() { worker.shutdownNow(); }
}
