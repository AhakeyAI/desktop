package com.example.ahakey.service;

import com.example.ahakey.config.ModelConfig;
import com.example.ahakey.sherpa.LibraryLoader;
import com.k2fsa.sherpa.onnx.EndpointConfig;
import com.k2fsa.sherpa.onnx.EndpointRule;
import com.k2fsa.sherpa.onnx.OnlineModelConfig;
import com.k2fsa.sherpa.onnx.OnlineParaformerModelConfig;
import com.k2fsa.sherpa.onnx.OnlineRecognizer;
import com.k2fsa.sherpa.onnx.OnlineRecognizerConfig;
import com.k2fsa.sherpa.onnx.OnlineRecognizerResult;
import com.k2fsa.sherpa.onnx.OnlineStream;
import com.k2fsa.sherpa.onnx.Vad;
import com.k2fsa.sherpa.onnx.VadModelConfig;
import com.k2fsa.sherpa.onnx.SileroVadModelConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.sound.sampled.AudioFormat;
import javax.sound.sampled.AudioSystem;
import javax.sound.sampled.DataLine;
import javax.sound.sampled.TargetDataLine;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.Objects;

/** Local offline speech service backed by Sherpa-ONNX streaming Paraformer. */
public class SpeechService {
    private static final Logger logger = LoggerFactory.getLogger(SpeechService.class);
    private static final int READ_BUFFER_BYTES = 4096;

    public interface Consumer<T> { void accept(T value); }

    private OnlineRecognizer recognizer;
    private OnlineStream stream;
    private Vad vad;
    private volatile TargetDataLine activeLine;
    private volatile Thread recognitionThread;
    private volatile boolean running;
    private volatile boolean paused;
    private Consumer<String> partialCallback;
    private Consumer<String> finalCallback;
    private ModelConfig config;
    private int sampleRate;
    private boolean vadEnabled;
    private Path modelDirectory;

    /** Initialize using model_config.properties and the deployed model tree. */
    public synchronized void initialize() throws Exception {
        config = ModelConfig.getInstance();
        config.printConfig();
        sampleRate = config.getSampleRate();
        vadEnabled = config.isVadEnabled();
        modelDirectory = resolveModelDirectory(config.getModelPath());

        Path tokens = required(modelDirectory.resolve(config.getTokensPath()), "tokens.txt");
        Path encoder = required(modelDirectory.resolve("encoder.int8.onnx"), "encoder.int8.onnx");
        Path decoder = required(modelDirectory.resolve("decoder.int8.onnx"), "decoder.int8.onnx");
        logger.info("Sherpa 模型目录: {}", modelDirectory);
        logger.info("Sherpa encoder: {}", encoder);
        logger.info("Sherpa decoder: {}", decoder);
        logger.info("Sherpa tokens: {}", tokens);
        LibraryLoader.load();
        createRecognizer(encoder, decoder, tokens);

        if (vadEnabled) {
            Path vadPath = required(modelDirectory.resolve(config.getVadModelPath()), "silero_vad.onnx");
            SileroVadModelConfig silero = SileroVadModelConfig.builder()
                .setModel(vadPath.toString()).setThreshold(0.5f)
                .setMinSilenceDuration(0.5f).setMinSpeechDuration(0.25f)
                .setWindowSize(512).setMaxSpeechDuration(20f).build();
            vad = new Vad(VadModelConfig.builder().setSileroVadModelConfig(silero)
                .setSampleRate(sampleRate).setNumThreads(config.getNumThreads())
                .setDebug(false).build());
            logger.info("Sherpa Silero VAD 加载成功: {}", vadPath);
        }
        logger.info("Sherpa OnlineRecognizer 初始化成功 (STREAMING_PARAFORMER)");
    }

    /** Compatibility overload; the first argument may be a model directory or file. */
    public synchronized void initialize(String modelPath, String tokensPath) throws Exception {
        Path configured = Path.of(Objects.requireNonNull(modelPath, "modelPath"));
        Path directory = Files.isDirectory(configured) ? configured : configured.getParent();
        if (directory == null) throw new IOException("无法从模型路径推导 Sherpa 模型目录: " + modelPath);
        config = ModelConfig.getInstance();
        sampleRate = config.getSampleRate();
        vadEnabled = config.isVadEnabled();
        modelDirectory = directory.toAbsolutePath().normalize();
        Path configuredTokens = Path.of(Objects.requireNonNull(tokensPath, "tokensPath"));
        Path tokens = Files.isRegularFile(configuredTokens)
            ? configuredTokens.toAbsolutePath().normalize()
            : required(modelDirectory.resolve(configuredTokens.toString()), "tokens.txt");
        Path encoder = required(modelDirectory.resolve("encoder.int8.onnx"), "encoder.int8.onnx");
        Path decoder = required(modelDirectory.resolve("decoder.int8.onnx"), "decoder.int8.onnx");
        LibraryLoader.load();
        createRecognizer(encoder, decoder, tokens);
    }

    private void createRecognizer(Path encoder, Path decoder, Path tokens) {
        OnlineParaformerModelConfig paraformer = OnlineParaformerModelConfig.builder()
            .setEncoder(encoder.toString()).setDecoder(decoder.toString()).build();
        OnlineModelConfig onlineModel = OnlineModelConfig.builder()
            .setParaformer(paraformer).setTokens(tokens.toString())
            .setNumThreads(config.getNumThreads()).setDebug(false).build();
        EndpointConfig endpoint = EndpointConfig.builder()
            .setRule1(EndpointRule.builder().setMustContainNonSilence(false)
                .setMinTrailingSilence(2.4f).setMinUtteranceLength(0f).build())
            .setRule2(EndpointRule.builder().setMustContainNonSilence(true)
                .setMinTrailingSilence(1.2f).setMinUtteranceLength(0f).build())
            .setRule3(EndpointRule.builder().setMustContainNonSilence(false)
                .setMinTrailingSilence(0f).setMinUtteranceLength(20f).build()).build();
        OnlineRecognizerConfig recognizerConfig = OnlineRecognizerConfig.builder()
            .setOnlineModelConfig(onlineModel).setEndpointConfig(endpoint)
            .setEnableEndpoint(true).build();
        try {
            recognizer = new OnlineRecognizer(recognizerConfig);
        } catch (Throwable failure) {
            throw new IllegalStateException("Sherpa OnlineRecognizer 创建失败", failure);
        }
    }

    private static Path required(Path path, String label) throws IOException {
        if (!Files.isRegularFile(path) || Files.size(path) == 0)
            throw new IOException("缺少或为空的 Sherpa 资源 " + label + ": " + path.toAbsolutePath());
        return path.toAbsolutePath().normalize();
    }

    /** Resolve deployed app/models without assuming a developer machine path. */
    static Path resolveModelDirectory(String configuredPath) throws IOException {
        Path configured = Path.of(configuredPath == null ? "models" : configuredPath);
        LinkedHashSet<Path> candidates = new LinkedHashSet<>();
        if (configured.isAbsolute()) candidates.add(configured);
        Path codeLocation;
        try {
            codeLocation = Path.of(SpeechService.class.getProtectionDomain().getCodeSource()
                .getLocation().toURI());
        } catch (Exception e) {
            codeLocation = Path.of(System.getProperty("user.dir", "."));
        }
        Path codeDir = Files.isDirectory(codeLocation) ? codeLocation : codeLocation.getParent();
        if (codeDir != null) {
            candidates.add(codeDir.resolve(configured));
            candidates.add(codeDir.resolve("app").resolve(configured));
            if (codeDir.getParent() != null) {
                candidates.add(codeDir.getParent().resolve(configured));
                candidates.add(codeDir.getParent().resolve("app").resolve(configured));
            }
        }
        candidates.add(Path.of(System.getProperty("user.dir", ".")).resolve(configured));
        candidates.add(Path.of("src/main/resources").resolve(configured));
        candidates.add(Path.of("target/classes").resolve(configured));
        for (Path candidate : candidates) {
            Path normalized = candidate.toAbsolutePath().normalize();
            if (Files.isDirectory(normalized)
                && hasBytes(normalized.resolve("tokens.txt"))
                && hasBytes(normalized.resolve("encoder.int8.onnx"))
                && hasBytes(normalized.resolve("decoder.int8.onnx"))) return normalized;
        }
        throw new IOException("无法找到完整 Sherpa 模型目录: " + configuredPath
            + " (需要 encoder.int8.onnx、decoder.int8.onnx、tokens.txt)");
    }

    private static boolean hasBytes(Path path) {
        try { return Files.isRegularFile(path) && Files.size(path) > 0; }
        catch (IOException ignored) { return false; }
    }

    public synchronized void startListening(Consumer<String> onPartial, Consumer<String> onFinal) {
        if (recognizer == null) throw new IllegalStateException("语音识别服务尚未初始化");
        if (running) return;
        partialCallback = onPartial;
        finalCallback = onFinal;
        running = true;
        paused = false;
        recognitionThread = new Thread(this::runMicrophoneRecognition, "speech-recognition");
        recognitionThread.setDaemon(true);
        recognitionThread.start();
    }

    public void stopListening() {
        running = false;
        paused = false;
        TargetDataLine line = activeLine;
        if (line != null) {
            try { line.stop(); } catch (Exception ignored) { }
            try { line.close(); } catch (Exception ignored) { }
        }
        Thread thread = recognitionThread;
        if (thread != null && thread != Thread.currentThread()) {
            try { thread.join(2000); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        }
    }

    public void pauseListening() { paused = true; }
    public void resumeListening() { paused = false; }
    public boolean isVadEnabled() { return vad != null; }

    private void runMicrophoneRecognition() {
        String lastText = "";
        try {
            AudioFormat format = new AudioFormat(sampleRate, 16, 1, true, false);
            DataLine.Info info = new DataLine.Info(TargetDataLine.class, format);
            if (!AudioSystem.isLineSupported(info)
                || !(AudioSystem.getLine(info) instanceof TargetDataLine))
                throw new IllegalStateException("系统不支持 16kHz/16-bit/mono 麦克风格式");
            stream = recognizer.createStream();
            try (TargetDataLine line = (TargetDataLine) AudioSystem.getLine(info)) {
                activeLine = line;
                line.open(format);
                line.start();
                byte[] buffer = new byte[READ_BUFFER_BYTES];
                while (running) {
                    if (paused) { Thread.sleep(20); continue; }
                    int count = line.read(buffer, 0, buffer.length);
                    if (count <= 0) continue;
                    float[] samples = pcm16ToFloat(buffer, count);
                    if (vad != null) {
                        vad.acceptWaveform(samples);
                        if (!vad.isSpeechDetected()) continue;
                    }
                    stream.acceptWaveform(samples, sampleRate);
                    while (recognizer.isReady(stream)) recognizer.decode(stream);
                    OnlineRecognizerResult result = recognizer.getResult(stream);
                    String text = result == null ? "" : result.getText();
                    if (text != null && text.length() > lastText.length()) {
                        String delta = text.substring(lastText.length());
                        lastText = text;
                        if (!delta.isEmpty() && partialCallback != null) partialCallback.accept(delta);
                    }
                    if (recognizer.isEndpoint(stream)) {
                        if (!lastText.isEmpty() && finalCallback != null) finalCallback.accept(lastText.trim());
                        recognizer.reset(stream);
                        lastText = "";
                    }
                }
                stream.inputFinished();
                while (recognizer.isReady(stream)) recognizer.decode(stream);
                OnlineRecognizerResult result = recognizer.getResult(stream);
                if (finalCallback != null) finalCallback.accept(result == null ? "" : result.getText().trim());
            } finally {
                activeLine = null;
                if (stream != null) { stream.release(); stream = null; }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (Exception e) {
            logger.error("Sherpa 录音/识别失败", e);
            if (finalCallback != null && !running) finalCallback.accept("");
        } finally {
            running = false;
            recognitionThread = null;
        }
    }

    /** Recognize a PCM16 little-endian 16kHz mono buffer with a fresh stream. */
    public synchronized String recognize(byte[] audioData) {
        if (recognizer == null || audioData == null || audioData.length == 0) return "";
        OnlineStream local = recognizer.createStream();
        try {
            float[] samples = pcm16ToFloat(audioData, audioData.length);
            local.acceptWaveform(samples, sampleRate);
            local.inputFinished();
            while (recognizer.isReady(local)) recognizer.decode(local);
            OnlineRecognizerResult result = recognizer.getResult(local);
            return result == null || result.getText() == null ? "" : result.getText();
        } finally { local.release(); }
    }

    /** Convenience file path retained for diagnostics; accepts 16kHz/16-bit/mono WAV. */
    public String recognizeFromFile(String file) throws Exception {
        try (var input = AudioSystem.getAudioInputStream(Path.of(file).toFile())) {
            AudioFormat source = input.getFormat();
            if (source.getSampleRate() != sampleRate || source.getChannels() != 1
                || source.getSampleSizeInBits() != 16)
                throw new IOException("语音文件必须是 16kHz/16-bit/mono WAV");
            return recognize(input.readAllBytes());
        }
    }

    public void release() {
        stopListening();
        if (stream != null) { stream.release(); stream = null; }
        if (recognizer != null) { recognizer.release(); recognizer = null; }
        if (vad != null) { vad.release(); vad = null; }
        partialCallback = null;
        finalCallback = null;
    }

    private static float[] pcm16ToFloat(byte[] bytes, int length) {
        int samples = length / 2;
        float[] result = new float[samples];
        ByteBuffer buffer = ByteBuffer.wrap(bytes, 0, samples * 2).order(ByteOrder.LITTLE_ENDIAN);
        for (int i = 0; i < samples; i++) result[i] = buffer.getShort() / 32768.0f;
        return result;
    }
}
