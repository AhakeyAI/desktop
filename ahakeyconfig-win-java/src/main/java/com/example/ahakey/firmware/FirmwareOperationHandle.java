package com.example.ahakey.firmware;

import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/** Ownership and cancellation handle for exactly one firmware operation. */
public final class FirmwareOperationHandle {
    private final UUID operationId;
    private final AtomicReference<FirmwareUpdateState> state =
        new AtomicReference<>(FirmwareUpdateState.IDLE);
    private final AtomicBoolean cancelled = new AtomicBoolean();
    private final CompletableFuture<FirmwareUpdateResult> completion =
        new CompletableFuture<>();
    private final Runnable cancellation;

    FirmwareOperationHandle(UUID operationId, Runnable cancellation) {
        this.operationId = Objects.requireNonNull(operationId, "operationId");
        this.cancellation = Objects.requireNonNull(cancellation, "cancellation");
    }

    public UUID operationId() {
        return operationId;
    }

    public FirmwareUpdateState state() {
        return state.get();
    }

    public boolean cancel() {
        if (state.get().terminal()) {
            return false;
        }
        boolean changed = cancelled.compareAndSet(false, true);
        if (changed) {
            cancellation.run();
        }
        return changed;
    }

    public boolean isCancelled() {
        return cancelled.get();
    }

    public CompletableFuture<FirmwareUpdateResult> completion() {
        return completion;
    }

    boolean transition(FirmwareUpdateState expected, FirmwareUpdateState next) {
        if (!FirmwareUpdateService.isLegalTransition(expected, next)) {
            return false;
        }
        return state.compareAndSet(expected, next);
    }

    void forceState(FirmwareUpdateState next) {
        state.set(next);
    }

    void complete(FirmwareUpdateResult result) {
        state.set(result.state());
        completion.complete(result);
    }
}
