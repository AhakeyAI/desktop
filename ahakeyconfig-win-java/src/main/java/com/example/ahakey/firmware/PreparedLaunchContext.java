package com.example.ahakey.firmware;

import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Operation-owned launch context prepared before a short-lived ISP window.
 * On Windows this owns the already elevated worker; on non-Windows it is a
 * deterministic test/development boundary that defers only the direct child
 * launch until GO.
 */
public final class PreparedLaunchContext implements AutoCloseable {
    public enum State { READY, GO_SENT, COMPLETED, CANCELLED, FAILED }

    @FunctionalInterface
    interface LaunchAction {
        WchIspRunner.WchIspProcessResult launch(WchIspRunner.CancellationToken cancellation)
            throws Exception;
    }

    @FunctionalInterface
    interface CancelAction {
        void cancel();
    }

    private final UUID operationId;
    private final Path controlDirectory;
    private final String nonce;
    private final Instant createdAt;
    private final long wrapperPid;
    private final long workerPid;
    private final boolean workerRunning;
    private final LaunchAction launchAction;
    private final CancelAction cancelAction;
    private final AtomicReference<State> state = new AtomicReference<>(State.READY);
    private volatile Instant goSignalTime;
    private volatile Instant actualProcessStartTime;
    private volatile List<Long> ownedProcessIds;

    PreparedLaunchContext(UUID operationId, Path controlDirectory, String nonce,
                          Instant createdAt, long wrapperPid, long workerPid,
                          boolean workerRunning, LaunchAction launchAction,
                          CancelAction cancelAction) {
        this.operationId = Objects.requireNonNull(operationId, "operationId");
        this.controlDirectory = Objects.requireNonNull(controlDirectory, "controlDirectory")
            .toAbsolutePath().normalize();
        this.nonce = nonce == null || nonce.isBlank() ? UUID.randomUUID().toString() : nonce;
        this.createdAt = createdAt == null ? Instant.now() : createdAt;
        this.wrapperPid = wrapperPid;
        this.workerPid = workerPid;
        this.workerRunning = workerRunning;
        this.launchAction = Objects.requireNonNull(launchAction, "launchAction");
        this.cancelAction = cancelAction == null ? () -> { } : cancelAction;
        this.ownedProcessIds = List.of(wrapperPid, workerPid).stream()
            .filter(pid -> pid > 0).distinct().toList();
    }

    static PreparedLaunchContext forDirect(UUID operationId, Path controlDirectory,
                                           String nonce, Instant createdAt,
                                           LaunchAction launchAction) {
        return new PreparedLaunchContext(operationId, controlDirectory, nonce, createdAt,
            -1, -1, false, launchAction, () -> { });
    }

    public UUID operationId() { return operationId; }
    public Path controlDirectory() { return controlDirectory; }
    public String nonce() { return nonce; }
    public Instant createdAt() { return createdAt; }
    public long wrapperPid() { return wrapperPid; }
    public long workerPid() { return workerPid; }
    public boolean workerRunning() { return workerRunning && state.get() != State.CANCELLED; }
    public boolean ready() { return state.get() == State.READY; }
    public State state() { return state.get(); }
    public Instant goSignalTime() { return goSignalTime; }
    public Instant actualProcessStartTime() { return actualProcessStartTime; }
    public List<Long> ownedProcessIds() { return ownedProcessIds; }

    /** Sends the one and only GO and waits for the owned worker result. */
    public WchIspRunner.WchIspProcessResult launch(
        WchIspRunner.CancellationToken cancellation) throws Exception {
        if (!state.compareAndSet(State.READY, State.GO_SENT)) {
            throw new IllegalStateException("prepared launch is not ready: " + state());
        }
        goSignalTime = Instant.now();
        try {
            WchIspRunner.WchIspProcessResult result = launchAction.launch(
                cancellation == null ? WchIspRunner.CancellationToken.NONE : cancellation);
            if (result != null) {
                ownedProcessIds = result.ownedProcessIds();
                actualProcessStartTime = result.actualProcessStartTime();
            }
            state.updateAndGet(current -> current == State.CANCELLED ? current : State.COMPLETED);
            return result;
        } catch (Exception failure) {
            state.updateAndGet(current -> current == State.CANCELLED ? current : State.FAILED);
            throw failure;
        }
    }

    /** Cancels only this operation's wrapper/worker/child process tree. */
    public boolean cancel() {
        while (true) {
            State current = state.get();
            if (current == State.CANCELLED || current == State.COMPLETED) return false;
            if (state.compareAndSet(current, State.CANCELLED)) {
                try { cancelAction.cancel(); } catch (RuntimeException ignored) { }
                return true;
            }
        }
    }

    @Override
    public void close() { cancel(); }
}
