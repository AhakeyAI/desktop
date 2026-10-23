package com.example.ahakey.service;

import com.example.ahakey.config.ModelConfig;
import com.example.ahakey.sherpa.LibraryLoader;
import com.k2fsa.sherpa.onnx.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.sound.sampled.*;
import java.io.IOException;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.HexFormat;

/** Streaming Paraformer adapted from the main model edition. Only key release commits text. */
public class SpeechService {
    private static final Logger logger = LoggerFactory.getLogger(SpeechService.class);
    private static final int SAMPLE_RATE = 16000;
    private final Object lock = new Object();
    private Engine engine;
    private final CaptureFactory captureFactory;
    private Thread worker;
    private Capture capture;
    private volatile boolean stopping;
    private volatile boolean paused;
    private volatile boolean closed;
    private volatile Consumer<String> errorCallback;

    public interface Consumer<T> { void accept(T value); }
    interface Engine {
        Session open();
        void close();
    }
    interface Session extends AutoCloseable {
        String accept(float[] samples);
        String finish();
        void close();
    }
    interface Capture extends AutoCloseable {
        int read(byte[] buffer);
        void close();
    }
    interface CaptureFactory { Capture open() throws Exception; }

    public SpeechService() { this(null, SpeechService::openMicrophone); }
    SpeechService(Engine engine, CaptureFactory captureFactory) {
        this.engine = engine;
        this.captureFactory = captureFactory;
    }

    public void initialize() throws Exception {
        ModelConfig config = ModelConfig.getInstance();
        if (!config.isEnabled()) throw new IllegalStateException("此版本未启用本地语音模型");
        if (!"STREAMING_PARAFORMER".equalsIgnoreCase(config.getModelType()))
            throw new IllegalArgumentException("不支持的本地模型: " + config.getModelType());
        if (config.getSampleRate() != SAMPLE_RATE)
            throw new IllegalArgumentException("Paraformer 需要 16000 Hz 采样率");
        initialize(config.getEncoderPath(), config.getDecoderPath(), config.getTokensPath(), config.getNumThreads());
    }

    /** Compatibility entry: encoder path plus tokens; decoder comes from configuration. */
    public void initialize(String encoder, String tokens) throws Exception {
        ModelConfig config = ModelConfig.getInstance();
        initialize(encoder, config.getDecoderPath(), tokens, config.getNumThreads());
    }

    public void initialize(String encoder, String decoder, String tokens, int threads) throws Exception {
        synchronized (lock) {
            if (closed) throw new IllegalStateException("语音服务已关闭");
            if (engine != null) return;
            String encoderFile = nativeModelPath(resolveModelFile(encoder));
            String decoderFile = nativeModelPath(resolveModelFile(decoder));
            String tokenFile = nativeModelPath(resolveModelFile(tokens));
            LibraryLoader.load();
            OnlineModelConfig model = OnlineModelConfig.builder()
                    .setParaformer(OnlineParaformerModelConfig.builder()
                            .setEncoder(encoderFile).setDecoder(decoderFile).build())
                    .setTokens(tokenFile).setNumThreads(Math.max(1, threads)).setDebug(false).build();
            OnlineRecognizer recognizer = new OnlineRecognizer(OnlineRecognizerConfig.builder()
                    .setOnlineModelConfig(model).setEnableEndpoint(false).build());
            engine = new SherpaEngine(recognizer);
        }
    }

    /** Paths are URI-decoded, independent of the launcher's working directory. */
    static Path resolveModelFile(String value) throws Exception {
        Path requested = Path.of(value);
        Path location = Path.of(SpeechService.class.getProtectionDomain().getCodeSource().getLocation().toURI());
        Path base = Files.isDirectory(location) ? location : location.getParent();
        Path[] candidates = requested.isAbsolute() ? new Path[]{requested} :
                new Path[]{base.resolve(requested), requested.toAbsolutePath(), Path.of("src/main/resources").resolve(requested)};
        for (Path candidate : candidates) {
            if (Files.isRegularFile(candidate)) {
                if (Files.size(candidate) == 0) throw new IOException("模型文件为空: " + candidate);
                return candidate.toRealPath();
            }
        }
        throw new IOException("找不到本地模型文件: " + value);
    }

    // Windows native model readers may use narrow paths. Cache by content, never by filename alone.
    static String nativeModelPath(Path source) throws Exception {
        if (source.toString().chars().allMatch(c -> c < 128)) return source.toString();
        Path root = Path.of(System.getProperty("java.io.tmpdir"), "ahakey-sherpa-models").toAbsolutePath();
        Files.createDirectories(root);
        if (!root.toString().chars().allMatch(c -> c < 128)) {
            char[] shortPath = new char[32768];
            int length = com.sun.jna.platform.win32.Kernel32.INSTANCE.GetShortPathName(root.toString(), shortPath, shortPath.length);
            if (length > 0 && length < shortPath.length) root = Path.of(new String(shortPath, 0, length));
            if (!root.toString().chars().allMatch(c -> c < 128))
                throw new IOException("本地模型需要可写的英文临时目录，请设置 java.io.tmpdir");
        }
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (var in = Files.newInputStream(source)) {
            byte[] bytes = new byte[65536];
            for (int n; (n = in.read(bytes)) != -1;) digest.update(bytes, 0, n);
        }
        Path destination = root.resolve(HexFormat.of().formatHex(digest.digest()) + ".bin");
        if (!Files.exists(destination) || Files.mismatch(source, destination) != -1) {
            Path temporary = Files.createTempFile(root, "copy-", ".tmp");
            try {
                Files.copy(source, temporary, StandardCopyOption.REPLACE_EXISTING);
                Files.move(temporary, destination, StandardCopyOption.REPLACE_EXISTING);
            } finally { Files.deleteIfExists(temporary); }
        }
        return destination.toString();
    }

    public void setErrorCallback(Consumer<String> callback) { errorCallback = callback; }

    public void startListening(Consumer<String> partial, Consumer<String> result) {
        synchronized (lock) {
            if (closed || engine == null) throw new IllegalStateException("本地语音未就绪");
            if (worker != null) throw new IllegalStateException("上一段语音仍在处理中");
            stopping = false;
            paused = false;
            worker = new Thread(() -> record(partial, result), "ahakey-local-speech");
            worker.setDaemon(true);
            worker.start();
        }
    }

    private void record(Consumer<String> partial, Consumer<String> result) {
        String text = null;
        String failure = null;
        try (Session session = engine.open(); Capture input = captureFactory.open()) {
            synchronized (lock) {
                if (closed || stopping) input.close();
                else capture = input;
            }
            byte[] bytes = new byte[3200];
            String previous = "";
            while (!stopping && !closed) {
                int count;
                try { count = input.read(bytes); }
                catch (RuntimeException e) {
                    if (stopping || closed) break;
                    throw e;
                }
                if (count < 0) {
                    if (stopping || closed) break;
                    throw new IOException("麦克风已断开");
                }
                if (count == 0 || paused) continue;
                String current = session.accept(pcmSamples(bytes, count));
                if (!closed && !current.equals(previous)) {
                    emit(partial, current);
                    previous = current;
                }
            }
            if (!closed) text = session.finish();
        } catch (Exception | LinkageError e) {
            logger.error("本地语音录音/识别失败", e);
            failure = "本地语音失败: " + e.getMessage();
        } finally {
            synchronized (lock) { capture = null; }
        }
        // Keep worker reserved through callbacks: a new key press cannot overlap final injection.
        try {
            if (!closed) {
                if (failure != null) emit(errorCallback, failure);
                else emit(result, text == null ? "" : text);
            }
        } finally {
            synchronized (lock) {
                worker = null;
                if (closed) closeEngine();
                lock.notifyAll();
            }
        }
    }

    public void stopListening() {
        synchronized (lock) {
            stopping = true;
            if (capture != null) capture.close(); // Unblocks TargetDataLine.read; never waits on FX thread.
        }
    }
    public void pauseListening() { paused = true; }
    public void resumeListening() { paused = false; }
    public boolean isBusy() { synchronized (lock) { return worker != null; } }

    /** Decode signed 16-bit little-endian mono PCM without accessing audio devices. */
    public String recognize(byte[] audioData) {
        synchronized (lock) {
            if (closed || engine == null || worker != null) throw new IllegalStateException("语音服务不可用于离线识别");
            try (Session session = engine.open()) {
                for (int offset = 0; offset < audioData.length; offset += 3200) {
                    int count = Math.min(3200, audioData.length - offset);
                    byte[] chunk = java.util.Arrays.copyOfRange(audioData, offset, offset + count);
                    session.accept(pcmSamples(chunk, count));
                }
                return session.finish();
            }
        }
    }

    public String recognizeFromFile(String path) throws Exception {
        try (AudioInputStream source = AudioSystem.getAudioInputStream(Path.of(path).toFile())) {
            AudioFormat desired = pcmFormat();
            try (AudioInputStream pcm = AudioSystem.getAudioInputStream(desired, source)) {
                return recognize(pcm.readAllBytes());
            }
        }
    }

    public void release() {
        synchronized (lock) {
            closed = true;
            stopListening();
            if (worker == null) closeEngine(); // Active stream closes first on its owning worker.
        }
    }
    private void closeEngine() {
        if (engine != null) {
            try { engine.close(); } finally { engine = null; }
        }
    }
    private static void emit(Consumer<String> callback, String text) {
        if (callback != null) {
            try { callback.accept(text); }
            catch (RuntimeException e) { logger.error("语音回调失败", e); }
        }
    }
    static float[] pcmSamples(byte[] bytes, int count) {
        if ((count & 1) != 0) throw new IllegalArgumentException("PCM 必须是完整的 16-bit 样本");
        float[] result = new float[count / 2];
        for (int i = 0; i < result.length; i++)
            result[i] = (short) ((bytes[i * 2] & 255) | (bytes[i * 2 + 1] << 8)) / 32768.0f;
        return result;
    }
    private static AudioFormat pcmFormat() { return new AudioFormat(SAMPLE_RATE, 16, 1, true, false); }
    private static Capture openMicrophone() throws LineUnavailableException {
        TargetDataLine line = AudioSystem.getTargetDataLine(pcmFormat());
        try {
            line.open(pcmFormat());
            line.start();
        } catch (LineUnavailableException | RuntimeException e) { line.close(); throw e; }
        return new Capture() {
            public int read(byte[] bytes) { return line.read(bytes, 0, bytes.length); }
            public void close() { line.stop(); line.close(); }
        };
    }
    private static final class SherpaEngine implements Engine {
        private final OnlineRecognizer recognizer;
        SherpaEngine(OnlineRecognizer recognizer) { this.recognizer = recognizer; }
        public Session open() {
            OnlineStream stream = recognizer.createStream();
            return new Session() {
                public String accept(float[] samples) {
                    stream.acceptWaveform(samples, SAMPLE_RATE);
                    while (recognizer.isReady(stream)) recognizer.decode(stream);
                    return recognizer.getResult(stream).getText();
                }
                public String finish() {
                    accept(new float[SAMPLE_RATE / 2]);
                    stream.inputFinished();
                    while (recognizer.isReady(stream)) recognizer.decode(stream);
                    return recognizer.getResult(stream).getText();
                }
                public void close() { stream.release(); }
            };
        }
        public void close() { recognizer.release(); }
    }
}
