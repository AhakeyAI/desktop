package com.example.ahakey.firmware;

import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Immutable launch data prepared before a device is asked to enter ISP.
 *
 * <p>The session contains no running process.  It is deliberately armed only
 * after the short-lived ISP presence probe succeeds, and it can be consumed at
 * most once.  This keeps the explicit user click as the only transition that
 * can launch the vendor download command.</p>
 */
public final class PreparedFlashSession {
    public enum State { PREPARED, ARMED, LAUNCHING, COMPLETED, CANCELLED }

    private final UUID operationId;
    private final RuntimeBundle runtime;
    private final Path configPath;
    private final Path hexPath;
    private final WchIspRunner.WchIspCommand command;
    private final Instant createdAt;
    private final boolean elevatedWorkerPrepared;
    private final String workerOwner;
    private final AtomicReference<State> state = new AtomicReference<>(State.PREPARED);
    private final AtomicReference<List<Long>> ownedProcessIds =
        new AtomicReference<>(List.of());

    public PreparedFlashSession(UUID operationId,
                                RuntimeBundle runtime,
                                Path configPath,
                                Path hexPath,
                                WchIspRunner.WchIspCommand command,
                                Instant createdAt,
                                boolean elevatedWorkerPrepared,
                                String workerOwner) {
        this.operationId = Objects.requireNonNull(operationId, "operationId");
        this.runtime = Objects.requireNonNull(runtime, "runtime");
        this.configPath = Objects.requireNonNull(configPath, "configPath")
            .toAbsolutePath().normalize();
        this.hexPath = Objects.requireNonNull(hexPath, "hexPath")
            .toAbsolutePath().normalize();
        this.command = Objects.requireNonNull(command, "command");
        if (!operationId.equals(command.operationId())) {
            throw new IllegalArgumentException("command operation does not match session");
        }
        this.createdAt = createdAt == null ? Instant.now() : createdAt;
        this.elevatedWorkerPrepared = elevatedWorkerPrepared;
        this.workerOwner = workerOwner == null || workerOwner.isBlank()
            ? "firmware-operation:" + operationId : workerOwner;
    }

    public UUID operationId() { return operationId; }
    public RuntimeBundle runtime() { return runtime; }
    public Path configPath() { return configPath; }
    public Path hexPath() { return hexPath; }
    public WchIspRunner.WchIspCommand command() { return command; }
    public Instant createdAt() { return createdAt; }
    public boolean elevatedWorkerPrepared() { return elevatedWorkerPrepared; }
    public String workerOwner() { return workerOwner; }
    public State state() { return state.get(); }
    public List<Long> ownedProcessIds() { return ownedProcessIds.get(); }

    /** Arms this session after the operation-local ISP probe reports present. */
    public boolean markDeviceDetected() {
        return state.compareAndSet(State.PREPARED, State.ARMED);
    }

    /** Prevents a not-yet-launched session from ever running a write command. */
    public boolean cancel() {
        while (true) {
            State current = state.get();
            if (current == State.CANCELLED || current == State.COMPLETED) return false;
            if (state.compareAndSet(current, State.CANCELLED)) return true;
        }
    }

    /** Claims the one launch slot owned by this operation. */
    public boolean beginLaunch() {
        return state.compareAndSet(State.ARMED, State.LAUNCHING);
    }

    public void complete(WchIspRunner.WchIspProcessResult result) {
        if (result != null) ownedProcessIds.set(result.ownedProcessIds());
        state.updateAndGet(current -> current == State.CANCELLED ? current : State.COMPLETED);
    }

    public void failLaunch() {
        state.updateAndGet(current -> current == State.CANCELLED ? current : State.COMPLETED);
    }
}
