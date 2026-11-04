package com.example.ahakey.service;

import ai.onnxruntime.*;
import com.example.ahakey.config.ModelConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.FloatBuffer;
import java.util.*;
import javax.sound.sampled.*;

/**
 * 语音识别服务
 * 使用 ONNX Runtime 运行本地语音识别模型
 * 支持通过配置文件切换不同的 SenseVoice 模型（Small/Medium/Large）
 */
public class SpeechService {
    
    private static final Logger logger = LoggerFactory.getLogger(SpeechService.class);
    
    private OrtEnvironment env;
    private OrtSession session;
    private List<String> tokens;
    private Thread recognitionThread;
    private volatile boolean isRunning = false;
    private volatile boolean isPaused = false;
    private Consumer<String> partialCallback;
    private Consumer<String> finalCallback;
    
    // 从配置管理器获取参数
    private ModelConfig config;
    private int sampleRate;
    private int nFft;
    private int hopLength;
    private int nMels;
    private int featureDim;
    private int framesPerChunk;
    private int language;
    private int textNorm;
    
    private static final float MAX_WAV_VALUE = 32768.0f;
    private static final float PRE_EMPHASIS = 0.97f;
    
    public interface Consumer<T> {
        void accept(T t);
    }
    
    /**
     * 初始化语音识别服务（使用配置文件）
     */
    public void initialize() throws Exception {
        // 加载配置
        config = ModelConfig.getInstance();
        config.printConfig();
        
        // 从配置读取参数
        sampleRate = config.getSampleRate();
        nFft = config.getNFFT();
        hopLength = config.getHopLength();
        nMels = config.getNMels();
        featureDim = config.getFeatureDim();
        framesPerChunk = config.getFramesPerChunk();
        language = config.getLanguage();
        textNorm = config.getTextNorm();
        
        // 加载词汇表
        loadTokens(config.getTokensPath());
        
        // 初始化 ONNX Runtime
        env = OrtEnvironment.getEnvironment();
        OrtSession.SessionOptions options = new OrtSession.SessionOptions();
        options.setIntraOpNumThreads(config.getNumThreads());
        // 禁用图优化以避免兼容性问题
        options.addConfigEntry("session.enable_ort_model_ops", "false");
        
        // 加载模型
        session = env.createSession(new File(config.getModelPath()).getAbsolutePath(), options);
        
        logger.info("{} 模型加载成功", config.getModelType());
    }
    
    /**
     * 初始化语音识别服务（兼容旧API）
     * @param modelPath ONNX模型文件路径
     * @param tokensPath 词汇表文件路径
     */
    public void initialize(String modelPath, String tokensPath) throws Exception {
        // 加载配置（但使用传入的路径）
        config = ModelConfig.getInstance();
        
        // 从配置读取参数
        sampleRate = config.getSampleRate();
        nFft = config.getNFFT();
        hopLength = config.getHopLength();
        nMels = config.getNMels();
        featureDim = config.getFeatureDim();
        framesPerChunk = config.getFramesPerChunk();
        language = config.getLanguage();
        textNorm = config.getTextNorm();
        
        // 加载词汇表
        loadTokens(tokensPath);
        
        // 初始化 ONNX Runtime
        env = OrtEnvironment.getEnvironment();
        OrtSession.SessionOptions options = new OrtSession.SessionOptions();
        options.setIntraOpNumThreads(config.getNumThreads());
        options.addConfigEntry("session.enable_ort_model_ops", "false");
        
        // 加载模型
        session = env.createSession(new File(modelPath).getAbsolutePath(), options);
        
        logger.info("模型加载成功: {}", modelPath);
    }
    
    /**
     * 加载词汇表文件
     * 支持从类路径或文件系统路径加载
     */
    private void loadTokens(String tokensPath) throws IOException {
        tokens = new ArrayList<>();
        
        BufferedReader reader = createReader(tokensPath);
        
        String line;
        while ((line = reader.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty()) continue;
            // 解析格式: "token index" 或直接 "token"
            String[] parts = line.split("\\s+");
            if (parts.length >= 2) {
                // 有索引号的情况，取第一部分作为token
                tokens.add(parts[0]);
            } else {
                // 只有token的情况
                tokens.add(line);
            }
        }
        reader.close();
        logger.info("词汇表加载完成，共 {} 个词", tokens.size());
    }
    
    /**
     * 创建词汇表文件读取器
     */
    private BufferedReader createReader(String tokensPath) throws IOException {
        // 优先尝试从类路径加载（以 "/" 开头或不含路径分隔符）
        if (tokensPath.startsWith("/") || !tokensPath.contains("/") && !tokensPath.contains("\\")) {
            var resource = getClass().getResource(tokensPath);
            if (resource != null) {
                return new BufferedReader(new InputStreamReader(resource.openStream()));
            }
        }
        
        // 如果类路径加载失败，尝试从文件系统加载
        File tokenFile = new File(tokensPath);
        if (tokenFile.exists()) {
            return new BufferedReader(new FileReader(tokenFile));
        }
        
        throw new IOException("无法找到词汇表文件: " + tokensPath);
    }
    
    /**
     * 开始语音识别（流式）
     */
    public void startListening(Consumer<String> onPartial, Consumer<String> onFinal) {
        this.partialCallback = onPartial;
        this.finalCallback = onFinal;
        this.isRunning = true;
        this.isPaused = false;
        
        recognitionThread = new Thread(() -> {
            try {
                startMicrophoneRecognition();
            } catch (Exception e) {
                logger.error("语音识别错误: {}", e.getMessage(), e);
            }
        }, "speech-recognition");
        recognitionThread.start();
    }
    
    /**
     * 停止语音识别
     */
    public void stopListening() {
        isRunning = false;
        isPaused = false;
        if (recognitionThread != null) {
            try {
                recognitionThread.join(2000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }
    
    /**
     * 暂停识别
     */
    public void pauseListening() {
        isPaused = true;
    }
    
    /**
     * 恢复识别
     */
    public void resumeListening() {
        isPaused = false;
    }
    
    /**
     * 麦克风语音识别主循环
     */
    private void startMicrophoneRecognition() throws Exception {
        AudioFormat format = new AudioFormat(sampleRate, 16, 1, true, false);
        DataLine.Info info = new DataLine.Info(TargetDataLine.class, format);
        
        if (!AudioSystem.isLineSupported(info)) {
            throw new Exception("不支持的音频格式");
        }
        
        try (TargetDataLine line = (TargetDataLine) AudioSystem.getLine(info)) {
            line.open(format);
            line.start();
            
            ByteArrayOutputStream audioBuffer = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int bytesRead;
            
            while (isRunning) {
                if (!isPaused) {
                    bytesRead = line.read(buffer, 0, buffer.length);
                    if (bytesRead > 0) {
                        audioBuffer.write(buffer, 0, bytesRead);
                        
                        // 每收集约1秒音频进行一次识别
                        if (audioBuffer.size() >= sampleRate * 2 * 2) { // 2秒音频（16位）
                            byte[] audioData = audioBuffer.toByteArray();
                            String result = recognize(audioData);
                            
                            if (partialCallback != null && result != null && !result.isEmpty()) {
                                partialCallback.accept(result);
                            }
                            
                            // 保留最后500ms音频作为重叠
                            int overlapSize = sampleRate * 2 / 2;
                            if (audioBuffer.size() > overlapSize) {
                                byte[] remaining = new byte[overlapSize];
                                System.arraycopy(audioData, audioData.length - overlapSize, remaining, 0, overlapSize);
                                audioBuffer.reset();
                                audioBuffer.write(remaining);
                            }
                        }
                    }
                } else {
                    Thread.sleep(100);
                }
            }
            
            // 处理剩余音频
            if (audioBuffer.size() > 0) {
                logger.debug("处理剩余音频，大小: {} bytes", audioBuffer.size());
                String finalResult = recognize(audioBuffer.toByteArray());
                logger.debug("最终识别结果: {}", finalResult != null ? finalResult : "null");
                // 无论结果是否为空都调用回调，让 VoiceInputManager 处理累积结果
                if (finalCallback != null) {
                    finalCallback.accept(finalResult);
                } else {
                    logger.debug("finalCallback 为空");
                }
            } else {
                logger.debug("没有剩余音频需要处理");
                // 即使没有剩余音频，也调用回调（可能有累积的中间结果）
                if (finalCallback != null) {
                    finalCallback.accept(null);
                }
            }
        }
    }
    
    /**
     * 执行语音识别
     * @param audioData PCM音频数据（16位，16kHz，单声道）
     * @return 识别结果文本
     */
    public String recognize(byte[] audioData) {
        try {
            // 将字节转换为浮点数组
            float[] floatData = bytesToFloat(audioData);
            
            // 提取 Mel 频谱特征
            float[][] features = extractMelSpectrogram(floatData);
            
            int numFrames = features.length;
            
            // 计算拼接后的序列长度
            int inputSeqLen = Math.max(1, numFrames - framesPerChunk + 1);
            
            logger.debug("原始特征: {} frames x {} dims", numFrames, nMels);
            logger.debug("拼接后: {} frames x {} dims", inputSeqLen, featureDim);
            
            // 准备输入张量 - 形状: [1, inputSeqLen, featureDim]
            long[] inputShape = {1, inputSeqLen, featureDim};
            FloatBuffer inputBuffer = FloatBuffer.allocate(inputSeqLen * featureDim);
            
            // 将多帧拼接成1帧
            for (int i = 0; i < inputSeqLen; i++) {
                for (int j = 0; j < framesPerChunk; j++) {
                    int frameIdx = i + j;
                    if (frameIdx < numFrames) {
                        inputBuffer.put(features[frameIdx]);
                    } else {
                        // 填充0
                        inputBuffer.put(new float[nMels]);
                    }
                }
            }
            inputBuffer.flip();
            
            OnnxTensor inputTensor = OnnxTensor.createTensor(env, inputBuffer, inputShape);
            
            // 准备 x_length 输入 (模型期望 int32 类型)
            long[] lengthShape = {1};
            java.nio.IntBuffer lengthBuffer = java.nio.IntBuffer.allocate(1);
            lengthBuffer.put(inputSeqLen);
            lengthBuffer.flip();
            OnnxTensor lengthTensor = OnnxTensor.createTensor(env, lengthBuffer, lengthShape);
            
            // 运行模型 - 使用正确的输入名称
            Map<String, OnnxTensor> inputs = new HashMap<>();
            inputs.put("x", inputTensor);
            inputs.put("x_length", lengthTensor);
            
            // 添加 language 输入 (0=自动检测, 1=中文, 2=英文, 3=日文, 4=韩文, 5=粤语)
            long[] langShape = {1};
            java.nio.IntBuffer langBuffer = java.nio.IntBuffer.allocate(1);
            langBuffer.put(language);
            langBuffer.flip();
            OnnxTensor langTensor = OnnxTensor.createTensor(env, langBuffer, langShape);
            inputs.put("language", langTensor);
            
            // 添加 text_norm 输入 (0 = 不规范化, 1 = 规范化)
            long[] normShape = {1};
            java.nio.IntBuffer normBuffer = java.nio.IntBuffer.allocate(1);
            normBuffer.put(textNorm);
            normBuffer.flip();
            OnnxTensor normTensor = OnnxTensor.createTensor(env, normBuffer, normShape);
            inputs.put("text_norm", normTensor);
            
            try (OrtSession.Result result = session.run(inputs)) {
                // 获取输出
                float[][][] output = (float[][][]) result.get(0).getValue();
                logger.debug("输出维度: [{}][{}][{}]", output.length, output[0].length, output[0][0].length);
                
                // 提取 logits (batch=1, seq_len, vocab_size)
                float[][] logits = output[0];
                
                // 解码结果
                return decodeLogits(logits);
            }
        } catch (Exception e) {
            logger.error("识别失败: {}", e.getMessage(), e);
            return "";
        }
    }
    
    /**
     * 将字节数组转换为浮点数组
     * Java Sound API 录制的是小端序（little-endian）有符号16位PCM
     */
    private float[] bytesToFloat(byte[] bytes) {
        float[] result = new float[bytes.length / 2];
        for (int i = 0; i < result.length; i++) {
            // 小端序：低字节在前，高字节在后
            int lowByte = bytes[2*i] & 0xFF;
            int highByte = bytes[2*i+1] & 0xFF;
            // 组合成有符号16位整数
            int sample = (highByte << 8) | lowByte;
            // 转换为有符号值（补码）
            if (sample > 32767) {
                sample -= 65536;
            }
            // 归一化到 [-1.0, 1.0]
            result[i] = sample / MAX_WAV_VALUE;
        }
        return result;
    }
    
    /**
     * 提取 Mel 频谱特征
     */
    private float[][] extractMelSpectrogram(float[] audio) {
        // 应用预加重处理
        float[] preEmphasized = preEmphasis(audio);
        
        int numFrames = (preEmphasized.length - nFft) / hopLength + 1;
        if (numFrames <= 0) {
            numFrames = 1;
        }
        float[][] melSpectrogram = new float[numFrames][nMels];
        
        // 预计算汉明窗
        float[] hammingWindow = new float[nFft];
        for (int i = 0; i < nFft; i++) {
            hammingWindow[i] = (float)(0.54 - 0.46 * Math.cos(2 * Math.PI * i / (nFft - 1)));
        }
        
        // 预计算 Mel 滤波器组
        float[][] melFilterBank = createMelFilterBank();
        
        for (int i = 0; i < numFrames; i++) {
            float[] frame = new float[nFft];
            int startIdx = i * hopLength;
            int copyLen = Math.min(nFft, preEmphasized.length - startIdx);
            System.arraycopy(preEmphasized, startIdx, frame, 0, copyLen);
            // 剩余部分填0
            for (int j = copyLen; j < nFft; j++) {
                frame[j] = 0;
            }
            
            // 应用汉明窗
            for (int j = 0; j < nFft; j++) {
                frame[j] *= hammingWindow[j];
            }
            
            // 计算 FFT
            float[] spectrum = computeFFT(frame);
            
            // 应用 Mel 滤波器组
            for (int j = 0; j < nMels; j++) {
                float sum = 0;
                for (int k = 0; k < nFft / 2; k++) {
                    sum += spectrum[k] * melFilterBank[j][k];
                }
                // 取对数能量 (log，不是 log10)
                melSpectrogram[i][j] = (float)Math.log(Math.max(sum, 1e-10));
            }
        }
        
        // 特征归一化 - CMVN (Cepstral Mean and Variance Normalization)
        normalizeFeaturesCMVN(melSpectrogram);
        
        return melSpectrogram;
    }
    
    /**
     * 预加重处理 - 增强高频部分
     */
    private float[] preEmphasis(float[] audio) {
        float[] result = new float[audio.length];
        result[0] = audio[0];
        for (int i = 1; i < audio.length; i++) {
            result[i] = audio[i] - PRE_EMPHASIS * audio[i - 1];
        }
        return result;
    }
    
    /**
     * 特征归一化 - CMVN (Cepstral Mean and Variance Normalization)
     * 对整段音频计算均值和方差进行归一化
     */
    private void normalizeFeaturesCMVN(float[][] features) {
        if (features.length == 0) return;
        
        int numFrames = features.length;
        int dim = features[0].length;
        
        // 计算每个维度的均值
        float[] mean = new float[dim];
        for (int j = 0; j < dim; j++) {
            float sum = 0;
            for (int i = 0; i < numFrames; i++) {
                sum += features[i][j];
            }
            mean[j] = sum / numFrames;
        }
        
        // 计算每个维度的标准差
        float[] std = new float[dim];
        for (int j = 0; j < dim; j++) {
            float sumSq = 0;
            for (int i = 0; i < numFrames; i++) {
                float diff = features[i][j] - mean[j];
                sumSq += diff * diff;
            }
            std[j] = (float)Math.sqrt(sumSq / numFrames);
        }
        
        // 归一化: (x - mean) / (std + eps)
        float eps = 1e-5f;
        for (int i = 0; i < numFrames; i++) {
            for (int j = 0; j < dim; j++) {
                features[i][j] = (features[i][j] - mean[j]) / (std[j] + eps);
            }
        }
    }
    
    /**
     * 创建 Mel 滤波器组
     */
    private float[][] createMelFilterBank() {
        float[][] filterBank = new float[nMels][nFft / 2];
        
        // 将频率转换为 Mel 刻度
        float lowMel = freqToMel(0);
        float highMel = freqToMel(sampleRate / 2);
        
        // 在 Mel 刻度上均匀分布的中心频率
        float[] melPoints = new float[nMels + 2];
        for (int i = 0; i < nMels + 2; i++) {
            melPoints[i] = lowMel + (highMel - lowMel) * i / (nMels + 1);
        }
        
        // 转换回频率
        float[] freqPoints = new float[nMels + 2];
        for (int i = 0; i < nMels + 2; i++) {
            freqPoints[i] = melToFreq(melPoints[i]);
        }
        
        // 转换为 FFT bin 索引
        int[] binIndices = new int[nMels + 2];
        for (int i = 0; i < nMels + 2; i++) {
            binIndices[i] = (int) Math.round(freqPoints[i] * nFft / sampleRate);
        }
        
        // 创建三角形滤波器
        for (int i = 0; i < nMels; i++) {
            for (int j = binIndices[i]; j < binIndices[i + 1]; j++) {
                if (j < nFft / 2) {
                    filterBank[i][j] = (float)(j - binIndices[i]) / (binIndices[i + 1] - binIndices[i]);
                }
            }
            for (int j = binIndices[i + 1]; j < binIndices[i + 2]; j++) {
                if (j < nFft / 2) {
                    filterBank[i][j] = (float)(binIndices[i + 2] - j) / (binIndices[i + 2] - binIndices[i + 1]);
                }
            }
        }
        
        return filterBank;
    }
    
    /**
     * 频率转 Mel
     */
    private float freqToMel(float freq) {
        return (float)(2595 * Math.log10(1 + freq / 700));
    }
    
    /**
     * Mel 转频率
     */
    private float melToFreq(float mel) {
        return (float)(700 * (Math.pow(10, mel / 2595) - 1));
    }
    
    /**
     * 计算 FFT（简化实现）
     */
    private float[] computeFFT(float[] input) {
        int n = input.length;
        float[] real = new float[n];
        float[] imag = new float[n];
        
        System.arraycopy(input, 0, real, 0, n);
        
        // 位反转
        int j = 0;
        for (int i = 1; i < n; i++) {
            int bit = n >> 1;
            for (; j >= bit; bit >>= 1) {
                j -= bit;
            }
            j += bit;
            if (i < j) {
                float temp = real[i];
                real[i] = real[j];
                real[j] = temp;
                temp = imag[i];
                imag[i] = imag[j];
                imag[j] = temp;
            }
        }
        
        // Cooley-Tukey FFT
        for (int s = 1; s <= Math.log(n) / Math.log(2); s++) {
            int m = 1 << s;
            float wmReal = (float)Math.cos(-2 * Math.PI / m);
            float wmImag = (float)Math.sin(-2 * Math.PI / m);
            
            for (int k = 0; k < n; k += m) {
                float wReal = 1;
                float wImag = 0;
                
                for (int jj = 0; jj < m / 2; jj++) {
                    float tReal = wReal * real[k + jj + m / 2] - wImag * imag[k + jj + m / 2];
                    float tImag = wReal * imag[k + jj + m / 2] + wImag * real[k + jj + m / 2];
                    
                    real[k + jj + m / 2] = real[k + jj] - tReal;
                    imag[k + jj + m / 2] = imag[k + jj] - tImag;
                    real[k + jj] += tReal;
                    imag[k + jj] += tImag;
                    
                    float tempReal = wReal;
                    wReal = wReal * wmReal - wImag * wmImag;
                    wImag = tempReal * wmImag + wImag * wmReal;
                }
            }
        }
        
        // 计算幅度谱
        float[] magnitude = new float[n / 2];
        for (int i = 0; i < n / 2; i++) {
            magnitude[i] = (float)Math.sqrt(real[i] * real[i] + imag[i] * imag[i]);
        }
        
        return magnitude;
    }
    
    /**
     * 解码模型输出 - SenseVoice特有格式
     * SenseVoice输出: <|language|><|emo|><|event|>文本内容
     */
    private String decodeLogits(float[][] logits) {
        StringBuilder result = new StringBuilder();
        int prevIndex = -1;
        boolean speechStarted = false;
        
        logger.debug("解码开始，帧数: {}, 词汇表大小: {}", logits.length, tokens.size());
        
        int blankCount = 0;
        int specialCount = 0;
        int textCount = 0;
        
        for (int t = 0; t < logits.length; t++) {
            float[] frame = logits[t];
            
            // 找到概率最大的token索引
            int maxIndex = 0;
            float maxValue = frame[0];
            for (int i = 1; i < frame.length; i++) {
                if (frame[i] > maxValue) {
                    maxValue = frame[i];
                    maxIndex = i;
                }
            }
            
            // 统计各类token数量
            if (maxIndex == 0) {
                blankCount++;
            } else if (maxIndex < tokens.size()) {
                String token = tokens.get(maxIndex);
                if (token.startsWith("<") && token.endsWith(">")) {
                    specialCount++;
                } else {
                    textCount++;
                }
            }
            
            // 打印前几帧和后几帧用于调试
            if (t < 5 || t > logits.length - 5) {
                String token = maxIndex < tokens.size() ? tokens.get(maxIndex) : "UNKNOWN_" + maxIndex;
                logger.debug("帧 {}: index={}, token=\"{}\", prob={}", t, maxIndex, token, String.format("%.4f", maxValue));
            }
            
            // CTC解码：跳过blank（0），跳过重复
            if (maxIndex != 0 && maxIndex != prevIndex) {
                if (maxIndex < tokens.size()) {
                    String token = tokens.get(maxIndex);
                    
                    // 跳过特殊标记
                    if (token == null || token.isEmpty() ||
                        token.equals("<pad>") || token.equals("<sos>") || token.equals("<eos>") || 
                        token.equals("<unk>") || token.equals("<s>") || token.equals("</s>")) {
                        prevIndex = maxIndex;
                        continue;
                    }
                    
                    // 跳过SenseVoice特殊控制标记
                    if (token.startsWith("<|") && token.endsWith("|>")) {
                        // 但记录语言信息
                        if (token.contains("zh")) {
                            // System.out.println("[DEBUG] 检测到中文");
                        }
                        prevIndex = maxIndex;
                        continue;
                    }
                    
                    // 跳过其他特殊标记
                    if (token.matches("^<[^>]+>$")) {
                        prevIndex = maxIndex;
                        continue;
                    }
                    
                    // 这是实际的文本内容
                    speechStarted = true;
                    result.append(token);
                    
                    // 打印前几个token用于调试
                    if (result.length() < 20) {
                        // System.out.println("[DEBUG] Token[" + t + "]: " + token + " (idx=" + maxIndex + ")");
                    }
                }
            }
            
            prevIndex = maxIndex;
        }
        
        String finalResult = result.toString().replace("▁", " ").trim();
        
        // 输出统计信息
        logger.debug("解码统计: blank={}, special={}, text={}", blankCount, specialCount, textCount);
        logger.debug("解码结果长度: {}, 内容: \"{}\"", finalResult.length(), finalResult);
        
        return finalResult;
    }
    
    /**
     * 释放资源
     */
    public void release() {
        stopListening();
        if (session != null) {
            try {
                session.close();
            } catch (Exception e) {
                // 忽略关闭异常
            }
        }
        if (env != null) {
            try {
                env.close();
            } catch (Exception e) {
                // 忽略关闭异常
            }
        }
    }
    
    /**
     * 测试方法：从文件识别
     */
    public String recognizeFromFile(String filePath) throws Exception {
        File audioFile = new File(filePath);
        byte[] audioData = new byte[(int)audioFile.length()];
        
        try (FileInputStream fis = new FileInputStream(audioFile)) {
            fis.read(audioData);
        }
        
        return recognize(audioData);
    }
}
