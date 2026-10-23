package com.example.ahakey.service;

import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Executable offline regression checks. No microphone, JavaFX, hooks or keyboard injection. */
public final class SpeechLifecycleCheck {
    private static int checks;
    private static void check(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
    private static void await(CountDownLatch latch) throws Exception {
        check(latch.await(5, TimeUnit.SECONDS), "worker timed out");
    }
    private static void idle(SpeechService speech) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (speech.isBusy() && System.nanoTime() < deadline) Thread.sleep(5);
        check(!speech.isBusy(), "worker did not stop");
    }
    public static void main(String[] args) throws Exception {
        float[] pcm = SpeechService.pcmSamples(new byte[]{0, (byte)128, -1, 127}, 4);
        check(pcm[0] == -1 && pcm[1] > .999f, "PCM signed little-endian");
        try { SpeechService.pcmSamples(new byte[]{1}, 1); throw new AssertionError(); }
        catch (IllegalArgumentException expected) { checks++; }
        Path directory = Files.createTempDirectory("wd006-模型 test-");
        try {
            Path empty = directory.resolve("empty.onnx");
            Files.createFile(empty);
            try { SpeechService.resolveModelFile(empty.toString()); throw new AssertionError(); }
            catch (java.io.IOException expected) { checks++; }
            try { SpeechService.resolveModelFile(directory.resolve("absent.onnx").toString()); throw new AssertionError(); }
            catch (java.io.IOException expected) { checks++; }
            Path source = directory.resolve("encoder.int8.onnx");
            Files.writeString(source, "model-one");
            Path copy = Path.of(SpeechService.nativeModelPath(source));
            check(Files.mismatch(source, copy) == -1 && copy.toString().chars().allMatch(c -> c < 128), "Chinese path copy");
            Files.writeString(source, "model-two");
            Path updated = Path.of(SpeechService.nativeModelPath(source));
            check(!copy.equals(updated) && Files.mismatch(source, updated) == -1, "model content cache invalidation");
            Files.delete(copy); Files.delete(updated); Files.delete(source); Files.delete(empty);
        } finally { Files.delete(directory); }

        List<String> events = Collections.synchronizedList(new ArrayList<>());
        CountDownLatch read = new CountDownLatch(1), unblocked = new CountDownLatch(1), result = new CountDownLatch(1);
        SpeechService.Engine engine = engine(events);
        SpeechService speech = new SpeechService(engine, () -> new SpeechService.Capture() {
            public int read(byte[] bytes) {
                read.countDown();
                try { unblocked.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
                return -1;
            }
            public void close() { unblocked.countDown(); }
        });
        speech.startListening(null, value -> { events.add("result:" + value); result.countDown(); });
        await(read);
        try { speech.startListening(null, null); throw new AssertionError(); }
        catch (IllegalStateException expected) { checks++; }
        speech.stopListening(); await(result); idle(speech);
        check(events.equals(List.of("open", "finish", "stream-close", "result:完成")), "release flushes once after stream close: " + events);
        speech.release(); speech.release();
        check(Collections.frequency(events, "engine-close") == 1, "idempotent engine release");

        List<String> closeReadEvents = Collections.synchronizedList(new ArrayList<>());
        CountDownLatch closeReadStarted = new CountDownLatch(1), closeReadDone = new CountDownLatch(1);
        SpeechService closeRead = new SpeechService(engine(closeReadEvents), () -> new SpeechService.Capture() {
            public int read(byte[] bytes) {
                closeReadStarted.countDown();
                try { closeReadDone.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
                throw new IllegalStateException("line closed by stop");
            }
            public void close() { closeReadDone.countDown(); }
        });
        closeRead.startListening(null, text -> closeReadEvents.add("result:" + text));
        await(closeReadStarted); closeRead.stopListening(); idle(closeRead); closeRead.release();
        check(closeReadEvents.contains("result:完成"), "closing blocked read still flushes final recognition");

        List<String> cancelled = Collections.synchronizedList(new ArrayList<>());
        CountDownLatch reading = new CountDownLatch(1), cancelledRead = new CountDownLatch(1);
        SpeechService cancellation = new SpeechService(engine(cancelled), () -> new SpeechService.Capture() {
            public int read(byte[] bytes) {
                reading.countDown();
                try { cancelledRead.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
                return -1;
            }
            public void close() { cancelledRead.countDown(); }
        });
        cancellation.startListening(null, value -> cancelled.add("UNEXPECTED-RESULT"));
        await(reading); cancellation.release(); idle(cancellation);
        check(cancelled.equals(List.of("open", "stream-close", "engine-close")), "close cancels callback and frees stream before recognizer: " + cancelled);

        List<String> failures = Collections.synchronizedList(new ArrayList<>());
        CountDownLatch failed = new CountDownLatch(1);
        SpeechService badMic = new SpeechService(engine(failures), () -> { throw new javax.sound.sampled.LineUnavailableException("fake unavailable"); });
        badMic.setErrorCallback(value -> { failures.add(value); failed.countDown(); });
        badMic.startListening(null, value -> failures.add("UNEXPECTED-RESULT"));
        await(failed); idle(badMic); badMic.release();
        check(failures.stream().anyMatch(value -> value.contains("fake unavailable")) && !failures.contains("UNEXPECTED-RESULT"), "mic error delivered without final injection");
        check(failures.indexOf("stream-close") < failures.indexOf("engine-close"), "failed microphone releases stream");

        StubSpeech stub = new StubSpeech(); List<String> output = new ArrayList<>(); List<String> ui = new ArrayList<>();
        VoiceInputManager manager = new VoiceInputManager(() -> stub, () -> null, output::add);
        manager.initialize(); manager.setStatusCallback(ui::add); manager.startVoiceInput(ui::add, ui::add);
        manager.startRecording(); stub.partial.accept("你"); stub.partial.accept("你好");
        check(output.isEmpty(), "partials never inject");
        manager.stopRecording(); stub.complete("你好");
        check(output.equals(List.of("你好")), "final hypothesis injected exactly once, no partial duplication");
        manager.startRecording(); manager.stopRecording(); stub.complete("第二句");
        check(output.equals(List.of("你好", "第二句")) && ui.contains("第二句"), "second press retains callbacks");
        manager.startRecording(); manager.stopVoiceInput(); stub.complete("取消");
        check(output.size() == 2 && !manager.isActivated(), "deactivation suppresses late result");
        manager.startVoiceInput(); manager.startRecording(); stub.error.accept("fake read failure"); stub.busy=false;
        check(!manager.isRecording() && ui.contains("error:fake read failure"), "record failure clears state");
        manager.shutdown(); check(!manager.isEnabled(), "shutdown disables manager");
        List<String> unavailable = new ArrayList<>();
        VoiceInputManager missingJni = new VoiceInputManager(() -> new StubSpeech() {
            public void initialize() { throw new UnsatisfiedLinkError("fake missing DLL"); }
        }, () -> { throw new AssertionError("injector should not initialize"); }, output::add);
        missingJni.initialize(); missingJni.setStatusCallback(unavailable::add); missingJni.startVoiceInput();
        check(!missingJni.isEnabled() && !missingJni.isActivated() && unavailable.get(0).contains("fake missing DLL"), "JNI linkage failure leaves UI unavailable");
        missingJni.shutdown();
        VoiceInputManager disabled = new VoiceInputManager(SpeechService::new,
                () -> { throw new AssertionError("disabled model must not initialize keyboard"); }, output::add);
        disabled.initialize();
        check(!disabled.isEnabled(), "default non-model build stays disabled without JNI");
        disabled.shutdown();
        concurrentOutputCheck();
        System.out.println("PASS SpeechLifecycleCheck: " + checks + " checks; no devices or keyboard injection");
    }

    private static void concurrentOutputCheck() throws Exception {
        ExecutorService workers = Executors.newFixedThreadPool(2);
        CountDownLatch outputStarted = new CountDownLatch(1), allowOutput = new CountDownLatch(1);
        CountDownLatch callbackStarted = new CountDownLatch(1), allowCallback = new CountDownLatch(1);
        try {
            StubSpeech speech = new StubSpeech();
            List<String> statuses = Collections.synchronizedList(new ArrayList<>());
            AtomicInteger outputs = new AtomicInteger();
            VoiceInputManager manager = new VoiceInputManager(() -> speech, () -> null, text -> {
                outputs.incrementAndGet();
                outputStarted.countDown();
                try { allowOutput.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            });
            manager.initialize(); manager.setStatusCallback(statuses::add); manager.startVoiceInput();
            manager.startRecording(); manager.stopRecording();
            Future<?> output = workers.submit(() -> speech.complete("慢输出"));
            await(outputStarted);
            Future<?> hook = workers.submit(() -> {
                manager.startRecording(); manager.stopRecording(); manager.stopVoiceInput(); manager.shutdown();
            });
            hook.get(500, TimeUnit.MILLISECONDS);
            check(!manager.isActivated() && !manager.isEnabled(), "F18/disable/shutdown do not wait for slow committed output");
            int stoppedCount = Collections.frequency(statuses, "stopped:语音已停止");
            allowOutput.countDown(); output.get(5, TimeUnit.SECONDS);
            check(outputs.get() == 1 && Collections.frequency(statuses, "stopped:语音已停止") == stoppedCount,
                    "committed output finishes once without stale completion after shutdown");

            StubSpeech pendingSpeech = new StubSpeech(); AtomicInteger pendingOutputs = new AtomicInteger();
            VoiceInputManager pending = new VoiceInputManager(() -> pendingSpeech, () -> null, text -> pendingOutputs.incrementAndGet());
            pending.initialize();
            pending.startVoiceInput(text -> {
                callbackStarted.countDown();
                try { allowCallback.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            });
            pending.startRecording(); pending.stopRecording();
            Future<?> callback = workers.submit(() -> pendingSpeech.complete("待提交"));
            await(callbackStarted);
            workers.submit(pending::stopVoiceInput).get(500, TimeUnit.MILLISECONDS);
            allowCallback.countDown(); callback.get(5, TimeUnit.SECONDS);
            check(pendingOutputs.get() == 0, "deactivation wins before output commitment even with a blocked result callback");
            pending.shutdown();

            StubSpeech duplicateSpeech = new StubSpeech(); AtomicInteger duplicates = new AtomicInteger();
            VoiceInputManager duplicate = new VoiceInputManager(() -> duplicateSpeech, () -> null, text -> duplicates.incrementAndGet());
            duplicate.initialize(); duplicate.startVoiceInput(); duplicate.startRecording(); duplicate.stopRecording();
            duplicateSpeech.complete("一次"); duplicateSpeech.complete("重复");
            check(duplicates.get() == 1, "same generation final callback cannot inject twice");
            duplicate.shutdown();
        } finally {
            allowOutput.countDown(); allowCallback.countDown(); workers.shutdownNow();
            check(workers.awaitTermination(5, TimeUnit.SECONDS), "concurrency test workers released");
        }
    }
    private static SpeechService.Engine engine(List<String> events) {
        return new SpeechService.Engine() {
            public SpeechService.Session open() {
                events.add("open");
                return new SpeechService.Session() {
                    public String accept(float[] samples) { return "中间"; }
                    public String finish() { events.add("finish"); return "完成"; }
                    public void close() { events.add("stream-close"); }
                };
            }
            public void close() { events.add("engine-close"); }
        };
    }
    private static class StubSpeech extends SpeechService {
        Consumer<String> partial, result, error; volatile boolean busy;
        public void initialize() { }
        public void setErrorCallback(Consumer<String> callback) { error = callback; }
        public void startListening(Consumer<String> p, Consumer<String> r) { partial=p; result=r; busy=true; }
        public void stopListening() { }
        public boolean isBusy() { return busy; }
        public void release() { busy=false; }
        void complete(String text) { result.accept(text); busy=false; }
    }
}
