package com.example.ahakey.service;

import org.junit.jupiter.api.Test;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PhysicalStatusFreshnessTest {
    @Test
    void receiveTimestampBeforePhysicalWriteCannotSatisfyQuery() {
        PhysicalStatusFreshness coordinator = new PhysicalStatusFreshness();
        long oldArrival = System.nanoTime();

        assertFalse(coordinator.queryAndWait(20, marker -> {
            marker.accept(System.nanoTime());
            coordinator.recordPhysicalStatus(oldArrival, 1, true, () -> {});
            return true;
        }, () -> true, () -> {}));
        assertTrue(coordinator.requiresRecovery());
    }

    @Test
    void physicalResponseAfterSuccessfulWriteCanSatisfyQuery() {
        PhysicalStatusFreshness coordinator = new PhysicalStatusFreshness();
        AtomicBoolean captured = new AtomicBoolean();

        assertTrue(coordinator.queryAndWait(200, marker -> {
            marker.accept(System.nanoTime());
            new Thread(() -> coordinator.recordPhysicalStatus(
                System.nanoTime(), 1, true, () -> {})).start();
            return true;
        }, () -> true, () -> captured.set(true)));
        assertTrue(captured.get());
    }

    @Test
    void responseArrivingDuringWriteIsRejectedAndLaterResponseIsAccepted()
        throws Exception {
        PhysicalStatusFreshness coordinator = new PhysicalStatusFreshness();
        CountDownLatch receiveEntered = new CountDownLatch(1);
        CountDownLatch receiveReturned = new CountDownLatch(1);
        AtomicBoolean fresh = new AtomicBoolean();
        AtomicBoolean staleCaptured = new AtomicBoolean();

        Thread query = new Thread(() -> fresh.set(coordinator.queryAndWait(
            300,
            marker -> {
                Thread quickResponse = new Thread(() -> {
                    long receivedDuringWrite = System.nanoTime();
                    receiveEntered.countDown();
                    coordinator.recordPhysicalStatus(
                        receivedDuringWrite, 1, true,
                        () -> staleCaptured.set(true));
                    receiveReturned.countDown();
                });
                quickResponse.start();
                await(receiveEntered);
                marker.accept(System.nanoTime());
                new Thread(() -> {
                    await(receiveReturned);
                    coordinator.recordPhysicalStatus(
                        System.nanoTime(), 1, true, () -> {});
                }).start();
                return true;
            },
            () -> true,
            () -> {}
        )));
        query.start();
        query.join(1_000);

        assertFalse(query.isAlive());
        assertTrue(fresh.get());
        assertFalse(staleCaptured.get());
    }

    @Test
    void candidateResponseIsDiscardedWhenPhysicalWriteFails() throws Exception {
        PhysicalStatusFreshness coordinator = new PhysicalStatusFreshness();
        CountDownLatch receiveEntered = new CountDownLatch(1);
        CountDownLatch receiveReturned = new CountDownLatch(1);
        AtomicBoolean candidateCaptured = new AtomicBoolean();

        assertFalse(coordinator.queryAndWait(100, marker -> {
            Thread candidate = new Thread(() -> {
                long receivedDuringWrite = System.nanoTime();
                receiveEntered.countDown();
                coordinator.recordPhysicalStatus(
                    receivedDuringWrite, 1, true, () -> candidateCaptured.set(true));
                receiveReturned.countDown();
            });
            candidate.start();
            await(receiveEntered);
            return false;
        }, () -> true, () -> {}));

        assertTrue(receiveReturned.await(1, TimeUnit.SECONDS));
        assertFalse(candidateCaptured.get());
        assertFalse(coordinator.requiresRecovery());
    }

    @Test
    void timestampEqualToWriteCompletionIsRejected() throws Exception {
        PhysicalStatusFreshness coordinator = new PhysicalStatusFreshness();
        AtomicBoolean equalCaptured = new AtomicBoolean();
        CountDownLatch equalEntered = new CountDownLatch(1);
        CountDownLatch equalReturned = new CountDownLatch(1);

        assertTrue(coordinator.queryAndWait(100, marker -> {
            new Thread(() -> {
                equalEntered.countDown();
                coordinator.recordPhysicalStatus(
                    100, 1, true, () -> equalCaptured.set(true));
                equalReturned.countDown();
            }).start();
            await(equalEntered);
            marker.accept(100);
            new Thread(() -> {
                await(equalReturned);
                coordinator.recordPhysicalStatus(101, 1, true, () -> {});
            }).start();
            return true;
        }, () -> true, () -> {}));
        assertFalse(equalCaptured.get());
    }

    @Test
    void immediateResponseStrictlyAfterWriteCompletionIsAccepted() throws Exception {
        PhysicalStatusFreshness coordinator = new PhysicalStatusFreshness();
        CountDownLatch responseEntered = new CountDownLatch(1);

        assertTrue(coordinator.queryAndWait(100, marker -> {
            marker.accept(200);
            new Thread(() -> {
                responseEntered.countDown();
                coordinator.recordPhysicalStatus(201, 1, true, () -> {});
            }).start();
            await(responseEntered);
            return true;
        }, () -> true, () -> {}));
    }

    @Test
    void failedSendNeverLeavesWaitingState() {
        PhysicalStatusFreshness coordinator = new PhysicalStatusFreshness();

        assertFalse(coordinator.queryAndWait(
            20, marker -> false, () -> true, () -> {}));
        assertFalse(coordinator.requiresRecovery());
    }

    @Test
    void fairSerializationGivesApprovalItsOwnTransactionAfterPoll() throws Exception {
        PhysicalStatusFreshness coordinator = new PhysicalStatusFreshness();
        CountDownLatch pollSent = new CountDownLatch(1);
        CountDownLatch approvalSent = new CountDownLatch(1);
        AtomicBoolean pollFresh = new AtomicBoolean();
        AtomicBoolean approvalFresh = new AtomicBoolean();

        Thread poll = new Thread(() -> pollFresh.set(coordinator.queryAndWait(
            500,
            marker -> {
                marker.accept(System.nanoTime());
                pollSent.countDown();
                return true;
            },
            () -> true,
            () -> {}
        )));
        poll.start();
        assertTrue(pollSent.await(1, TimeUnit.SECONDS));

        Thread approval = new Thread(() -> approvalFresh.set(coordinator.queryAndWait(
            500,
            marker -> {
                marker.accept(System.nanoTime());
                approvalSent.countDown();
                return true;
            },
            () -> true,
            () -> {}
        )));
        approval.start();
        coordinator.recordPhysicalStatus(System.nanoTime(), 1, true, () -> {});
        assertTrue(approvalSent.await(1, TimeUnit.SECONDS));
        coordinator.recordPhysicalStatus(System.nanoTime(), 1, true, () -> {});

        poll.join(1000);
        approval.join(1000);
        assertTrue(pollFresh.get());
        assertTrue(approvalFresh.get());
    }

    @Test
    void sessionChangeRejectsOldFrameAndCancelsInFlightQuery() throws Exception {
        PhysicalStatusFreshness coordinator = new PhysicalStatusFreshness();
        CountDownLatch sent = new CountDownLatch(1);
        AtomicBoolean fresh = new AtomicBoolean(true);
        Thread query = new Thread(() -> fresh.set(coordinator.queryAndWait(
            500,
            marker -> {
                marker.accept(System.nanoTime());
                sent.countDown();
                return true;
            },
            () -> true,
            () -> {}
        )));
        query.start();
        assertTrue(sent.await(1, TimeUnit.SECONDS));

        coordinator.invalidateSession(2);
        coordinator.recordPhysicalStatus(System.nanoTime(), 1, true, () -> {});
        query.join(1000);
        assertFalse(fresh.get());
    }

    private static void await(CountDownLatch latch) {
        try {
            latch.await(1, TimeUnit.SECONDS);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
        }
    }
}
