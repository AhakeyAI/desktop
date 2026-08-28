package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.protocol.BleTcpPacket;
import org.junit.jupiter.api.Test;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BleManagerApprovalPathTest {
    @Test
    void oldFrameEnteredBeforeWriteButParsedAfterWriteIsRejected() throws Exception {
        QueryHarness harness = new QueryHarness();
        BleManager manager = harness.manager();
        makeBleLinkAvailable(manager);

        CountDownLatch oldEntered = new CountDownLatch(1);
        CountDownLatch resumeOld = new CountDownLatch(1);
        AtomicBoolean pauseOnce = new AtomicBoolean(true);
        manager.setReceiveEntryHookForTest(() -> {
            if (pauseOnce.compareAndSet(true, false)) {
                oldEntered.countDown();
                await(resumeOld);
            }
        });
        Thread oldFrame = new Thread(() ->
            manager.handlePacket(BleTcpPacket.BLE_NOTIFY, statusFrame(0)));
        oldFrame.start();
        assertTrue(oldEntered.await(1, TimeUnit.SECONDS));

        QueryResult query = startApproval(manager, 500);
        assertTrue(harness.awaitSends(1));
        resumeOld.countDown();
        oldFrame.join(1000);
        Thread.sleep(30);
        assertTrue(query.thread.isAlive(), "pre-write frame completed the query");

        manager.handlePacket(BleTcpPacket.BLE_NOTIFY, statusFrame(1));
        query.join();
        assertTrue(query.fresh.get());
        assertEquals(1, query.switchState.get());
    }

    @Test
    void newFrameReceivedAfterWriteIsAcceptedForAutoAndManual() throws Exception {
        QueryHarness harness = new QueryHarness();
        BleManager manager = harness.manager();
        makeBleLinkAvailable(manager);

        assertFreshSwitch(manager, harness, 0, 1);
        assertFreshSwitch(manager, harness, 1, 2);
    }

    @Test
    void timedOutLateFrameCannotSatisfyNewSession() throws Exception {
        QueryHarness harness = new QueryHarness();
        BleManager manager = harness.manager();
        makeBleLinkAvailable(manager);

        CountDownLatch oldEntered = new CountDownLatch(1);
        CountDownLatch resumeOld = new CountDownLatch(1);
        manager.setReceiveEntryHookForTest(() -> {
            manager.setReceiveEntryHookForTest(null);
            oldEntered.countDown();
            await(resumeOld);
        });
        Thread oldFrame = new Thread(() ->
            manager.handlePacket(BleTcpPacket.BLE_NOTIFY, statusFrame(0)));

        QueryResult first = startApproval(manager, 40);
        assertTrue(harness.awaitSends(1));
        oldFrame.start();
        assertTrue(oldEntered.await(1, TimeUnit.SECONDS));
        first.join();
        assertFalse(first.fresh.get());
        assertTrue(harness.awaitRecoveries(1));
        awaitRecoveryComplete(manager);

        resumeOld.countDown();
        oldFrame.join(1000);
        QueryResult second = startApproval(manager, 400);
        assertTrue(harness.awaitSends(2));
        Thread.sleep(20);
        assertTrue(second.thread.isAlive(), "late old-session frame satisfied new query");
        manager.handlePacket(BleTcpPacket.BLE_NOTIFY, statusFrame(1));
        second.join();
        assertTrue(second.fresh.get());
        assertEquals(1, second.switchState.get());
    }

    @Test
    void lostResponseTriggersSingleRecoveryAndQueriesResume() throws Exception {
        QueryHarness harness = new QueryHarness();
        BleManager manager = harness.manager();
        makeBleLinkAvailable(manager);

        assertFalse(manager.queryStatusAndWait(30));
        assertTrue(harness.awaitRecoveries(1));
        awaitRecoveryComplete(manager);
        assertEquals(1, harness.recoveries.get());

        assertFreshSwitch(manager, harness, 0, 2);
    }

    @Test
    void concurrentRecoveryDoesNotReconnectMultipleTimes() throws Exception {
        QueryHarness harness = new QueryHarness();
        BleManager manager = harness.manager();
        makeBleLinkAvailable(manager);
        CountDownLatch start = new CountDownLatch(1);
        Thread poll = new Thread(() -> {
            await(start);
            manager.queryStatus();
        });
        Thread hook = new Thread(() -> {
            await(start);
            new ApprovalService(manager).refresh();
        });
        Thread kimi = new Thread(() -> {
            await(start);
            new ApprovalService(manager).refresh();
        });
        poll.start();
        hook.start();
        kimi.start();
        start.countDown();
        poll.join(2000);
        hook.join(2000);
        kimi.join(2000);

        assertTrue(harness.awaitRecoveries(1));
        awaitRecoveryComplete(manager);
        assertEquals(1, harness.recoveries.get());
        assertEquals(1, harness.sends.get());
    }

    @Test
    void manualDisconnectAndShutdownDoNotAutoReconnect() throws Exception {
        QueryHarness manualHarness = new QueryHarness();
        BleManager manual = manualHarness.manager();
        makeBleLinkAvailable(manual);
        assertFalse(manual.queryStatusAndWait(25));
        manual.disconnect();
        Thread.sleep(180);
        assertEquals(0, manualHarness.recoveries.get());

        QueryHarness shutdownHarness = new QueryHarness();
        BleManager shutdown = shutdownHarness.manager();
        makeBleLinkAvailable(shutdown);
        assertFalse(shutdown.queryStatusAndWait(25));
        shutdown.shutdown();
        Thread.sleep(180);
        assertEquals(0, shutdownHarness.recoveries.get());
    }

    @Test
    void pollingCannotCauseFreshAutoApproval() throws Exception {
        QueryHarness harness = new QueryHarness();
        BleManager manager = harness.manager();
        makeBleLinkAvailable(manager);

        AtomicBoolean pollFresh = new AtomicBoolean();
        Thread poll = new Thread(() -> pollFresh.set(manager.queryStatus()));
        poll.start();
        assertTrue(harness.awaitSends(1));

        AtomicReference<ApprovalSnapshot> approval = new AtomicReference<>();
        Thread approvalThread = new Thread(() ->
            approval.set(new ApprovalService(manager).refresh()));
        approvalThread.start();
        manager.handlePacket(BleTcpPacket.BLE_NOTIFY, statusFrame(0));
        poll.join(1000);
        assertTrue(pollFresh.get());
        assertTrue(harness.awaitSends(2));
        assertTrue(approvalThread.isAlive());

        manager.handlePacket(BleTcpPacket.BLE_NOTIFY, statusFrame(1));
        approvalThread.join(2000);
        assertFalse(approvalThread.isAlive());
        assertEquals(ApprovalState.MANUAL, approval.get().state());
        assertTrue(approval.get().fresh());
    }

    @Test
    void deviceInfoAndBleStatusNeverCompleteApprovalFreshness() throws Exception {
        QueryHarness harness = new QueryHarness();
        BleManager manager = harness.manager();
        makeBleLinkAvailable(manager);

        QueryResult query = startApproval(manager, 60);
        assertTrue(harness.awaitSends(1));
        manager.handlePacket(BleTcpPacket.DEVICE_INFO_RESP,
            new byte[]{80, 0, 0, 0, 2, 0, 0, 0});
        manager.handlePacket(BleTcpPacket.BLE_STATUS_RESP, new byte[]{1});
        query.join();
        assertFalse(query.fresh.get());
    }

    @Test
    void activeOledGifOrConfigTransactionFinishesBeforeStatusRecoveryCanStart()
        throws Exception {
        for (String transactionName : List.of("OLED", "GIF", "CONFIG")) {
            QueryHarness harness = new QueryHarness();
            BleManager manager = harness.manager();
            makeBleLinkAvailable(manager);
            CountDownLatch transactionStarted = new CountDownLatch(1);
            CountDownLatch releaseTransaction = new CountDownLatch(1);
            Thread transaction = new Thread(() -> {
                try {
                    manager.executeDeviceTransaction(() -> {
                        transactionStarted.countDown();
                        await(releaseTransaction);
                        return null;
                    });
                } catch (Exception exception) {
                    throw new AssertionError(exception);
                }
            }, transactionName + "-transaction");
            transaction.start();
            assertTrue(transactionStarted.await(1, TimeUnit.SECONDS));

            assertFalse(manager.queryStatusAndWait(40));
            assertEquals(0, harness.sends.get());
            assertEquals(0, harness.recoveries.get(),
                transactionName + " was interrupted by status recovery");

            releaseTransaction.countDown();
            transaction.join(1_000);
            assertFalse(transaction.isAlive());
        }
    }

    @Test
    void unresolvedBlocksNewTransactionsAndApprovalUntilRecoveryCompletes()
        throws Exception {
        CountDownLatch recoveryStarted = new CountDownLatch(1);
        CountDownLatch releaseRecovery = new CountDownLatch(1);
        QueryHarness harness = new QueryHarness();
        BleManager manager = harness.manager(() -> {
            recoveryStarted.countDown();
            await(releaseRecovery);
        });
        makeBleLinkAvailable(manager);

        assertFalse(manager.queryStatusAndWait(30));
        assertTrue(recoveryStarted.await(1, TimeUnit.SECONDS));
        assertTrue(manager.isRecoveryPending());
        int sendsAtTimeout = harness.sends.get();

        assertFalse(manager.queryStatusAndWait(50));
        AtomicBoolean ordinaryStarted = new AtomicBoolean();
        try {
            manager.executeDeviceTransaction(() -> {
                ordinaryStarted.set(true);
                return null;
            });
        } catch (Exception expected) {
            // Explicit failure is required while recovery owns the lifecycle.
        }
        assertFalse(ordinaryStarted.get());
        assertEquals(sendsAtTimeout, harness.sends.get());

        releaseRecovery.countDown();
        awaitRecoveryComplete(manager);
        assertEquals(1, harness.recoveries.get());
    }

    @Test
    void pollClaudeCursorCodexAndKimiUseFairSeparatePhysicalTransactions()
        throws Exception {
        QueryHarness harness = new QueryHarness();
        BleManager manager = harness.manager();
        makeBleLinkAvailable(manager);
        List<Thread> callers = new ArrayList<>();
        callers.add(new Thread(manager::queryStatus, "poll"));
        for (String name : List.of("claude", "cursor", "codex", "kimi")) {
            callers.add(new Thread(() -> new ApprovalService(manager).refresh(), name));
        }

        callers.get(0).start();
        assertTrue(harness.awaitSends(1));
        callers.subList(1, callers.size()).forEach(Thread::start);
        for (int expectedSend = 1; expectedSend <= callers.size(); expectedSend++) {
            assertTrue(harness.awaitSends(expectedSend));
            manager.handlePacket(BleTcpPacket.BLE_NOTIFY, statusFrame(1));
        }
        for (Thread caller : callers) {
            caller.join(2_000);
            assertFalse(caller.isAlive());
        }
        assertEquals(5, harness.sends.get());
        assertEquals(0, harness.recoveries.get());
    }

    private static void assertFreshSwitch(
        BleManager manager, QueryHarness harness, int switchState, int sendCount
    ) throws Exception {
        QueryResult query = startApproval(manager, 400);
        assertTrue(harness.awaitSends(sendCount));
        manager.handlePacket(BleTcpPacket.BLE_NOTIFY, statusFrame(switchState));
        query.join();
        assertTrue(query.fresh.get());
        assertEquals(switchState, query.switchState.get());
    }

    private static QueryResult startApproval(BleManager manager, long timeoutMillis) {
        QueryResult result = new QueryResult();
        result.thread = new Thread(() -> {
            boolean fresh = manager.queryStatusAndWait(timeoutMillis);
            result.fresh.set(fresh);
            DeviceStatus accepted = manager.getApprovalQueryStatus();
            if (fresh && accepted != null) {
                result.switchState.set(accepted.getSwitchState());
            }
        });
        result.thread.start();
        return result;
    }

    private static void makeBleLinkAvailable(BleManager manager) {
        manager.handlePacket(BleTcpPacket.BLE_STATUS_RESP, new byte[]{1});
    }

    private static void awaitRecoveryComplete(BleManager manager) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2);
        while (manager.isRecoveryInFlight() && System.nanoTime() < deadline) {
            Thread.sleep(5);
        }
        assertFalse(manager.isRecoveryInFlight());
    }

    private static void await(CountDownLatch latch) {
        try {
            latch.await(2, TimeUnit.SECONDS);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
        }
    }

    private static byte[] statusFrame(int switchState) {
        return new byte[]{
            (byte) 0xAA, (byte) 0xBB, 0,
            94, 50, 1, 3, 2, 1, (byte) switchState, 35, 3,
            (byte) 0xCC, (byte) 0xDD
        };
    }

    private static final class QueryResult {
        Thread thread;
        final AtomicBoolean fresh = new AtomicBoolean();
        final AtomicInteger switchState = new AtomicInteger(-1);

        void join() throws InterruptedException {
            thread.join(2000);
            assertFalse(thread.isAlive(), "query thread did not finish");
        }
    }

    private static final class QueryHarness {
        final AtomicInteger sends = new AtomicInteger();
        final AtomicInteger recoveries = new AtomicInteger();
        private final Object monitor = new Object();

        BleManager manager() {
            return manager(() -> {});
        }

        BleManager manager(Runnable recoveryBody) {
            Executor executor = command -> {
                Thread thread = new Thread(command, "test-recovery");
                thread.setDaemon(true);
                thread.start();
            };
            return new BleManager(
                new NoOpCallback(),
                marker -> {
                    marker.accept(System.nanoTime());
                    sends.incrementAndGet();
                    signal();
                    return true;
                },
                () -> {
                    recoveries.incrementAndGet();
                    signal();
                    recoveryBody.run();
                },
                executor
            );
        }

        boolean awaitSends(int expected) throws InterruptedException {
            return awaitCount(sends, expected);
        }

        boolean awaitRecoveries(int expected) throws InterruptedException {
            return awaitCount(recoveries, expected);
        }

        private boolean awaitCount(AtomicInteger counter, int expected)
            throws InterruptedException {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2);
            synchronized (monitor) {
                while (counter.get() < expected) {
                    long remaining = deadline - System.nanoTime();
                    if (remaining <= 0) {
                        return false;
                    }
                    TimeUnit.NANOSECONDS.timedWait(monitor, remaining);
                }
                return true;
            }
        }

        private void signal() {
            synchronized (monitor) {
                monitor.notifyAll();
            }
        }
    }

    private static final class NoOpCallback implements BleManager.BleCallback {
        @Override public void onConnected() {}
        @Override public void onDisconnected() {}
        @Override public void onStatusReceived(DeviceStatus status) {}
        @Override public void onError(String message) {}
    }
}
