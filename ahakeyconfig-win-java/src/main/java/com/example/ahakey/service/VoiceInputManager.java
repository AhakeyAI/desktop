package com.example.ahakey.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/** Coordinates the existing activation / F18 recording / final text injection flow. */
public class VoiceInputManager {
    private static final Logger logger = LoggerFactory.getLogger(VoiceInputManager.class);
    private SpeechService speechService;
    private KeyboardInjector keyboardInjector;
    private volatile boolean isEnabled;
    private volatile boolean isActivated;
    private volatile boolean isRecording;
    private long generation;
    private long finalClaimedGeneration = -1;
    private String lastError = "本地语音尚未初始化";
    private Consumer<String> resultCallback;
    private Consumer<String> partialCallback;
    private Consumer<String> statusCallback;
    private final java.util.function.Supplier<SpeechService> speechFactory;
    private final java.util.function.Supplier<KeyboardInjector> injectorFactory;
    private final Consumer<String> textOutput;
    private final java.util.function.Function<String,AhaTypeService.ProcessResult> finalProcessor;
    private final java.util.concurrent.Executor processing;
    private final java.util.concurrent.ExecutorService ownedProcessing;

    public interface Consumer<T> { void accept(T value); }
    public enum VoiceStatus {
        IDLE("idle", "语音未启动"), READY("ready", "语音已就绪"),
        RECORDING("recording", "语音输入中"), RECOGNIZING("recognizing", "识别中"),
        PROCESSING("processing", "处理中"), STOPPED("stopped", "语音已停止");
        private final String code;
        private final String message;
        VoiceStatus(String code, String message) { this.code = code; this.message = message; }
        public String getCode() { return code; }
        public String getMessage() { return message; }
    }

    public VoiceInputManager() { this(SpeechService::new, KeyboardInjector::new, null,
            text -> AhaTypeService.getInstance().process(text), null); }
    VoiceInputManager(java.util.function.Supplier<SpeechService> speechFactory,
                      java.util.function.Supplier<KeyboardInjector> injectorFactory, Consumer<String> textOutput) {
        this(speechFactory, injectorFactory, textOutput, text -> new AhaTypeService.ProcessResult(text, ""), Runnable::run);
    }
    public VoiceInputManager(java.util.function.Supplier<SpeechService> speechFactory,
            java.util.function.Supplier<KeyboardInjector> injectorFactory, Consumer<String> textOutput,
            java.util.function.Function<String,AhaTypeService.ProcessResult> processor, java.util.concurrent.Executor executor) {
        this.speechFactory = speechFactory;
        this.injectorFactory = injectorFactory;
        this.textOutput = textOutput;
        this.finalProcessor = processor;
        ownedProcessing = executor == null ? java.util.concurrent.Executors.newCachedThreadPool(r -> {
            Thread t=new Thread(r,"ahatype-final");t.setDaemon(true);return t;
        }) : null;
        processing = executor == null ? ownedProcessing : executor;
    }

    public void initialize() {
        String error = null;
        synchronized (this) {
            if (isEnabled) return;
            if (speechService != null) { isEnabled = true; return; }
            try {
                speechService = speechFactory.get();
                speechService.initialize();
                keyboardInjector = injectorFactory.get();
                isEnabled = true;
                lastError = null;
            } catch (Exception | LinkageError e) {
                logger.error("本地语音初始化失败", e);
                lastError = "本地语音未启用: " + e.getMessage();
                isEnabled = false;
                if (speechService != null) speechService.release();
                speechService = null;
                error = lastError;
            }
        }
        if (error != null) notifyError(error);
    }

    public void startVoiceInput() { startVoiceInput(null, null); }
    public void startVoiceInput(Consumer<String> callback) { startVoiceInput(callback, null); }
    public synchronized void setStatusCallback(Consumer<String> callback) { statusCallback = callback; }
    public void startVoiceInput(Consumer<String> result, Consumer<String> partial) {
        String error = null;
        synchronized (this) {
            if (!isEnabled || speechService == null) {
                error = lastError == null ? "本地语音未启用" : lastError;
            } else {
                if (isActivated) return;
                resultCallback = result;
                partialCallback = partial;
                isActivated = true;
            }
        }
        if (error != null) notifyError(error);
        else notifyStatus(VoiceStatus.READY);
    }

    public void stopVoiceInput() {
        synchronized (this) { deactivate(); }
        notifyStatus(VoiceStatus.STOPPED);
    }

    // Caller holds the manager monitor; no external callback or text injection here.
    private void deactivate() {
        isActivated = false;
        isRecording = false;
        generation++; // Invalidate any uncommitted final result before stopping the worker.
        if (speechService != null) speechService.stopListening();
        resultCallback = null;
        partialCallback = null;
    }

    public void startRecording() {
        long recording;
        String error = null;
        synchronized (this) {
            if (!isEnabled || !isActivated || speechService == null || isRecording || speechService.isBusy()) return;
            recording = ++generation;
            isRecording = true;
        }
        notifyStatus(VoiceStatus.RECORDING);
        synchronized (this) {
            // Key release/deactivation can win while an external status callback runs.
            if (!current(recording) || !isRecording || speechService == null) return;
            speechService.setErrorCallback(message -> onFailure(recording, message));
            try {
                speechService.startListening(text -> onPartial(recording, text), text -> onFinal(recording, text));
            } catch (Exception | LinkageError e) {
                logger.error("无法开始本地录音", e);
                isRecording = false;
                error = "无法开始录音: " + e.getMessage();
            }
        }
        if (error != null) onFailure(recording, error);
    }

    public void stopRecording() {
        synchronized (this) {
            if (!isRecording) return;
            isRecording = false;
            speechService.stopListening();
        }
        notifyStatus(VoiceStatus.RECOGNIZING);
    }

    private void onPartial(long recording, String text) {
        Consumer<String> callback;
        synchronized (this) {
            if (!current(recording)) return;
            callback = partialCallback;
        }
        // Sherpa partials replace the hypothesis; they must never be concatenated or injected.
        emit(callback, text);
    }
    private void onFinal(long recording, String text) {
        Consumer<String> callback;
        synchronized (this) {
            if (!current(recording) || finalClaimedGeneration == recording) return;
            finalClaimedGeneration = recording; // A final result can be claimed only once.
            isRecording = false;
            callback = resultCallback;
        }
        notifyState("processing:正在整理文字…");
        String original = text == null ? "" : text.trim();
        processing.execute(() -> {
            synchronized(this) { if (!current(recording)) return; }
            AhaTypeService.ProcessResult processed;
            try { processed = original.isEmpty() ? new AhaTypeService.ProcessResult("", "") : finalProcessor.apply(original); }
            catch (RuntimeException e) { processed = new AhaTypeService.ProcessResult(original, "已使用原文：整理失败"); }
            synchronized(this) { if (!current(recording)) return; }
            deliverFinal(recording, callback, processed);
        });
    }
    private void deliverFinal(long recording, Consumer<String> callback, AhaTypeService.ProcessResult processed) {
        if(!processed.deliverable())return;
        String result = processed.text();
        if (!result.isEmpty()) {
            emit(callback, result);
            KeyboardInjector injector;
            synchronized (this) {
                if (!current(recording)||!processed.deliverable()) return;
                // Output commitment linearizes here against deactivate/shutdown. Cancellation
                // that wins this monitor suppresses output. Already committed output may finish.
                injector = keyboardInjector;
            }
            try {
                if (textOutput != null) textOutput.accept(result);
                else if (injector != null) injector.injectText(result);
            } catch (Exception | LinkageError e) {
                logger.error("语音文本注入失败", e);
                onFailure(recording, "语音文本输入失败: " + e.getMessage());
                return;
            }
        }
        synchronized (this) { if (!current(recording)||!processed.deliverable()) return; }
        // Retain UI callbacks for the next F18 press. Slow callbacks/output never own the monitor.
        notifyState("stopped:" + (processed.message().isBlank() ? VoiceStatus.STOPPED.message : processed.message()));
    }
    private boolean current(long recording) { return recording == generation && isActivated; }
    private void onFailure(long recording, String error) {
        synchronized (this) {
            if (!current(recording)) return;
            isRecording = false;
        }
        notifyError(error);
    }
    private void notifyStatus(VoiceStatus status) { notifyState(status.code + ":" + status.message); }
    private void notifyError(String error) { notifyState("error:" + error); }
    private void notifyState(String value) {
        Consumer<String> callback;
        synchronized (this) { callback = statusCallback; }
        emit(callback, value);
    }
    private static void emit(Consumer<String> callback, String text) {
        if (callback == null) return;
        try { callback.accept(text); }
        catch (RuntimeException e) { logger.error("语音界面回调失败", e); }
    }
    public void toggleEnabled() {
        boolean initialize;
        boolean stopped = false;
        synchronized (this) {
            initialize = !isEnabled && speechService == null;
            if (isEnabled) { deactivate(); isEnabled = false; stopped = true; }
            else if (speechService != null) isEnabled = true;
        }
        if (stopped) notifyStatus(VoiceStatus.STOPPED);
        if (initialize) initialize();
    }
    public boolean isEnabled() { return isEnabled; }
    public boolean isActivated() { return isActivated; }
    public boolean isRecording() { return isRecording; }
    public void shutdown() {
        synchronized (this) {
            deactivate();
            isEnabled = false;
            if (speechService != null) { speechService.release(); speechService = null; }
            if (keyboardInjector != null) { keyboardInjector.release(); keyboardInjector = null; }
        }
        if (ownedProcessing != null) ownedProcessing.shutdownNow();
        notifyStatus(VoiceStatus.STOPPED);
    }
    public SpeechService getSpeechService() { return speechService; }
    public KeyboardInjector getKeyboardInjector() { return keyboardInjector; }
}
