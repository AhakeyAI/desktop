package com.example.ahakey.service;

import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;
import java.util.function.BooleanSupplier;
import java.util.function.LongConsumer;

/**
 * Serializes physical status requests and pairs each request with one status
 * frame from the same transport session. Frame arrival time is captured by
 * the transport receive entry point and is never regenerated here.
 */
final class PhysicalStatusFreshness {
    @FunctionalInterface
    interface QuerySender {
        /**
         * Calls the marker exactly once with the monotonic timestamp captured
         * after the physical write/flush has successfully returned.
         */
        boolean send(LongConsumer markSuccessfulPhysicalWrite);
    }

    private enum State {
        IDLE,
        WRITING,
        WAITING,
        TIMED_OUT_UNRESOLVED,
        COMPLETED
    }

    // Fair ordering lets an approval queued behind a poll obtain its own
    // transaction instead of repeatedly losing to the scheduled poller.
    private final ReentrantLock queryLock = new ReentrantLock(true);
    private final ReentrantLock stateLock = new ReentrantLock();
    private final Condition changed = stateLock.newCondition();
    private long session = 1;
    private State state = State.IDLE;
    private long writeBoundaryNanos;
    private long querySession;

    boolean queryAndWait(
        long timeoutMillis,
        QuerySender sender,
        BooleanSupplier connected,
        Runnable captureFreshResult
    ) {
        if (timeoutMillis <= 0) {
            return false;
        }
        try {
            queryLock.lockInterruptibly();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return false;
        }
        try {
            stateLock.lock();
            try {
                if (state == State.TIMED_OUT_UNRESOLVED) {
                    return false;
                }
                state = State.WRITING;
                writeBoundaryNanos = 0;
                querySession = session;
                boolean sent;
                try {
                    sent = sender.send(writeCompletedAtNanos -> {
                        if (writeCompletedAtNanos > 0 && state == State.WRITING
                            && session == querySession) {
                            writeBoundaryNanos = writeCompletedAtNanos;
                            state = State.WAITING;
                        }
                    });
                } catch (RuntimeException exception) {
                    state = State.IDLE;
                    writeBoundaryNanos = 0;
                    return false;
                }
                if (!sent || state != State.WAITING || session != querySession) {
                    state = State.IDLE;
                    writeBoundaryNanos = 0;
                    return false;
                }

                long remaining = TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
                while (state == State.WAITING && session == querySession) {
                    if (remaining <= 0) {
                        state = State.TIMED_OUT_UNRESOLVED;
                        return false;
                    }
                    try {
                        remaining = changed.awaitNanos(remaining);
                    } catch (InterruptedException exception) {
                        Thread.currentThread().interrupt();
                        state = State.TIMED_OUT_UNRESOLVED;
                        return false;
                    }
                }
                boolean fresh = session == querySession
                    && state == State.COMPLETED
                    && connected.getAsBoolean();
                if (fresh) {
                    captureFreshResult.run();
                }
                state = State.IDLE;
                writeBoundaryNanos = 0;
                return fresh;
            } finally {
                stateLock.unlock();
            }
        } finally {
            queryLock.unlock();
        }
    }

    void recordPhysicalStatus(
        long receivedAtNanos,
        long frameSession,
        boolean connected,
        Runnable captureStatus
    ) {
        stateLock.lock();
        try {
            if (frameSession != session || frameSession != querySession
                // Equality cannot prove that the response followed the write.
                || receivedAtNanos <= writeBoundaryNanos || !connected) {
                return;
            }
            if (state == State.WAITING) {
                captureStatus.run();
                state = State.COMPLETED;
                changed.signalAll();
            } else if (state == State.TIMED_OUT_UNRESOLVED) {
                // A late frame may resolve only the old transaction. It can
                // never be retained for or applied to a later query.
                state = State.IDLE;
                writeBoundaryNanos = 0;
                changed.signalAll();
            }
        } finally {
            stateLock.unlock();
        }
    }

    boolean requiresRecovery() {
        stateLock.lock();
        try {
            return state == State.TIMED_OUT_UNRESOLVED;
        } finally {
            stateLock.unlock();
        }
    }

    void invalidateSession(long newSession) {
        stateLock.lock();
        try {
            session = newSession;
            state = State.IDLE;
            writeBoundaryNanos = 0;
            querySession = 0;
            changed.signalAll();
        } finally {
            stateLock.unlock();
        }
    }
}
