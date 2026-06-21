package com.example.ahakey.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 语音输入管理器
 * 统一管理语音识别、AhaType服务和键盘注入
 */
public class VoiceInputManager {
    
    private static final Logger logger = LoggerFactory.getLogger(VoiceInputManager.class);
    
    private SpeechService speechService;
    private KeyboardInjector keyboardInjector;
    private volatile boolean isEnabled = false;
    private volatile boolean isActivated = false;  // 服务是否已激活
    private volatile boolean isRecording = false;  // 是否正在录音
    private volatile boolean keyDownTriggered = false;  // 按键按下防抖标志
    private Consumer<String> resultCallback;
    private Consumer<String> partialCallback;
    private Consumer<String> statusCallback;  // 状态回调，通知UI当前状态
    private StringBuilder accumulatedResult = new StringBuilder();  // 累积的中间识别结果
    
    public interface Consumer<T> {
        void accept(T t);
    }
    
    /**
     * 语音状态枚举
     */
    public enum VoiceStatus {
        IDLE("idle", "语音未启动"),           // 空闲状态
        READY("ready", "语音已就绪"),         // 服务已激活，等待按键
        RECORDING("recording", "语音输入中"), // 正在录音
        RECOGNIZING("recognizing", "识别中"), // 语音识别中
        PROCESSING("processing", "处理中"),   // 处理文本中
        STOPPED("stopped", "语音已停止");    // 已停止
        
        private final String code;
        private final String message;
        
        VoiceStatus(String code, String message) {
            this.code = code;
            this.message = message;
        }
        
        public String getCode() { return code; }
        public String getMessage() { return message; }
    }
    
    /**
     * 初始化语音输入管理器
     */
    public void initialize() {
        try {
            // 初始化语音识别服务
            speechService = new SpeechService();
            
            // 获取资源文件路径（支持从 JAR 包内或外部目录加载）
            // 优先在 models/ 目录下查找
            String modelPath = findModelFile("models/model_q8.onnx");
            String tokensPath = findModelFile("models/tokens.txt");
            
            logger.info("模型文件路径: {}", modelPath);
            logger.info("词汇表路径: {}", tokensPath);
            
            // 初始化语音识别
            speechService.initialize(modelPath, tokensPath);
            
            // 初始化键盘注入器
            keyboardInjector = new KeyboardInjector();
            
            isEnabled = true;
            logger.info("VoiceInputManager 初始化成功");
        } catch (Exception e) {
            logger.error("VoiceInputManager 初始化失败: {}", e.getMessage(), e);
            isEnabled = false;
        }
    }
    
    /**
     * 查找模型文件路径
     */
    private String findModelFile(String fileName) throws Exception {
        // 首先尝试从类路径加载（完整路径，例如 models/model_q8.onnx）
        var resource = getClass().getResource("/" + fileName);
        if (resource != null) {
            logger.debug("从类路径加载模型文件: {}", resource.getPath());
            return resource.getPath();
        }
        
        // 获取 JAR 文件所在目录（处理可能的 null 情况）
        String baseDir = null;
        try {
            var codeSource = getClass().getProtectionDomain().getCodeSource();
            if (codeSource != null && codeSource.getLocation() != null) {
                String jarPath = codeSource.getLocation().getPath();
                java.io.File jarFile = new java.io.File(jarPath);
                baseDir = jarFile.getParentFile().getAbsolutePath();
                logger.debug("JAR 所在目录: {}", baseDir);
            }
        } catch (Exception e) {
            logger.debug("获取 JAR 路径失败: {}", e.getMessage());
        }
        
        // 尝试从 app 目录下直接加载（jpackage 打包后的标准位置，fileName 已包含 models/）
        if (baseDir != null) {
            String appPath = new java.io.File(baseDir, fileName).getAbsolutePath();
            if (new java.io.File(appPath).exists()) {
                logger.debug("从 app 目录加载: {}", appPath);
                return appPath;
            }
        }
        
        // 尝试从当前工作目录加载
        if (new java.io.File(fileName).exists()) {
            String absPath = new java.io.File(fileName).getAbsolutePath();
            logger.debug("从当前目录加载: {}", absPath);
            return absPath;
        }
        
        // 尝试从 EXE 所在目录查找（jpackage 打包后，app 目录的父目录）
        if (baseDir != null) {
            java.io.File exeDir = new java.io.File(baseDir).getParentFile();
            if (exeDir != null) {
                String exePath = new java.io.File(exeDir, fileName).getAbsolutePath();
                if (new java.io.File(exePath).exists()) {
                    logger.debug("从 EXE 目录加载: {}", exePath);
                    return exePath;
                }
            }
        }
        
        throw new Exception("无法找到文件: " + fileName + "。请确保模型文件位于以下位置之一：\n- JAR 包内的 " + fileName + "\n- app 目录下的 " + fileName + "\n- 当前工作目录下的 " + fileName + "\n- EXE 所在目录下的 " + fileName);
    }
    
    /**
     * 启动语音输入（无回调版本）
     */
    public void startVoiceInput() {
        startVoiceInput(null, null);
    }
    
    /**
     * 启动语音输入（带结果回调版本）
     * @param callback 识别结果回调
     */
    public void startVoiceInput(Consumer<String> callback) {
        startVoiceInput(callback, null);
    }
    
    /**
     * 设置状态回调
     * @param statusCallback 状态变化回调
     */
    public void setStatusCallback(Consumer<String> statusCallback) {
        this.statusCallback = statusCallback;
    }
    
    /**
     * 通知状态变化
     */
    private void notifyStatus(VoiceStatus status) {
        if (statusCallback != null) {
            try {
                statusCallback.accept(status.getCode() + ":" + status.getMessage());
            } catch (Exception e) {
                logger.error("状态回调失败: {}", e.getMessage());
            }
        }
    }
    
    /**
     * 启动语音输入（带完整回调版本）
     * 注意：这只是激活服务，需要调用 startRecording 才会开始录音
     * @param resultCallback 最终识别结果回调
     * @param partialCallback 中间结果回调
     */
    public void startVoiceInput(Consumer<String> resultCallback, Consumer<String> partialCallback) {
        if (!isEnabled || speechService == null) {
            logger.warn("语音输入未启用或未初始化");
            return;
        }
        
        if (isActivated) {
            logger.warn("语音输入服务已激活");
            return;
        }
        
        this.resultCallback = resultCallback;
        this.partialCallback = partialCallback;
        this.isActivated = true;
        
        notifyStatus(VoiceStatus.READY);
        logger.info("语音输入服务已激活，等待按键触发...");
    }
    
    /**
     * 停止语音输入服务
     */
    public void stopVoiceInput() {
        if (!isActivated) {
            logger.warn("语音输入服务未激活");
            return;
        }
        
        // 如果正在录音，先停止录音
        if (isRecording) {
            stopRecording();
        }
        
        this.isActivated = false;
        logger.info("语音输入服务已停用");
    }
    
    /**
     * 开始录音（由按键触发）
     */
    public void startRecording() {
        if (!isActivated || speechService == null) {
            logger.warn("语音输入服务未激活，无法开始录音");
            return;
        }
        
        if (isRecording) {
            // 防抖处理：如果已经在录音且按键按下标志已设置，直接忽略
            if (keyDownTriggered) {
                return;
            }
            logger.warn("已在录音中");
            return;
        }
        
        this.isRecording = true;
        this.keyDownTriggered = true;  // 设置按键按下标志
        this.accumulatedResult = new StringBuilder();  // 重置累积结果
        
        notifyStatus(VoiceStatus.RECORDING);
        logger.info("开始录音...");
        
        speechService.startListening(
            this::onPartialResult,
            this::onFinalResult
        );
    }
    
    /**
     * 停止录音（由按键释放触发）
     */
    public void stopRecording() {
        if (!isRecording) {
            logger.warn("未在录音中");
            return;
        }
        
        if (speechService != null) {
            speechService.stopListening();
            this.isRecording = false;
            this.keyDownTriggered = false;  // 重置按键按下标志，允许下次触发
            logger.info("停止录音");
        }
    }
    
    /**
     * 处理中间识别结果（Partial）
     */
    private void onPartialResult(String text) {
        logger.info("[语音识别中] {}", text);
        
        // 通知UI识别中状态
        notifyStatus(VoiceStatus.RECOGNIZING);
        
        // 累积中间结果
        if (text != null && !text.isEmpty()) {
            accumulatedResult.append(text);
            logger.debug("累积结果更新: \"{}\"", accumulatedResult.toString());
        }
        
        // 通知UI更新中间结果
        if (partialCallback != null && text != null && !text.isEmpty()) {
            try {
                partialCallback.accept(text);
            } catch (Exception e) {
                logger.error("中间结果回调失败: {}", e.getMessage());
            }
        }
    }
    
    /**
     * 处理最终识别结果（Final）
     */
    private void onFinalResult(String text) {
        logger.info("[语音识别完成] {}", text);
        
        // 通知UI处理中状态
        notifyStatus(VoiceStatus.PROCESSING);
        
        // 调试：显示累积结果状态
        String accumulatedStr = accumulatedResult.toString();
        logger.debug("onFinalResult - 累积结果: \"{}\", 长度: {}", accumulatedStr, accumulatedStr.length());
        logger.debug("onFinalResult - 最后结果: \"{}\"", text != null ? text : "null");
        
        // 使用累积的中间结果 + 最后一块的识别结果
        StringBuilder finalResultBuilder = new StringBuilder(accumulatedResult);
        
        // 如果最后一块音频有识别结果，添加到累积结果后面
        if (text != null && !text.trim().isEmpty()) {
            // 避免重复（如果最后一块结果和累积结果末尾重复）
            if (!accumulatedStr.endsWith(text)) {
                finalResultBuilder.append(text);
            }
        }
        
        String finalResult = finalResultBuilder.toString().trim();
        logger.debug("onFinalResult - 最终合并结果: \"{}\"", finalResult);
        
        if (!finalResult.isEmpty()) {
            // 使用 AhaType 整理文本（如果启用）
            String processedText = processWithAhaType(finalResult);
            logger.debug("准备注入文本: {}", processedText);
            
            // 通知UI显示最终结果
            if (resultCallback != null) {
                try {
                    resultCallback.accept(processedText);
                } catch (Exception e) {
                    logger.error("最终结果回调失败: {}", e.getMessage());
                }
            }
            
            // 注入到当前光标位置
            injectText(processedText);
        } else {
            logger.debug("识别结果为空或null");
        }
        
        // 通知UI已停止状态
        notifyStatus(VoiceStatus.STOPPED);
        
        // 重置回调和累积结果
        this.resultCallback = null;
        this.partialCallback = null;
        this.accumulatedResult = new StringBuilder();
    }
    
    /**
     * 使用 AhaType 整理文本
     */
    private String processWithAhaType(String text) {
        // TODO: 实现 AhaType 文本整理逻辑
        // 目前直接返回原始文本
        return text;
    }
    
    /**
     * 将文本注入到当前光标位置
     */
    private void injectText(String text) {
        if (keyboardInjector != null && text != null && !text.isEmpty()) {
            try {
                logger.debug("VoiceInputManager - 准备调用键盘注入器，文本长度: {}", text.length());
                keyboardInjector.injectText(text);
                logger.debug("VoiceInputManager - 键盘注入器调用完成");
            } catch (Exception e) {
                logger.error("VoiceInputManager - 文本注入失败: {}", e.getMessage(), e);
            }
        } else {
            logger.debug("VoiceInputManager - 跳过注入，键盘注入器为空或文本为空");
        }
    }
    
    /**
     * 切换语音输入启用状态
     */
    public void toggleEnabled() {
        isEnabled = !isEnabled;
        logger.info("语音输入 {}", isEnabled ? "已启用" : "已禁用");
    }
    
    /**
     * 检查是否已启用
     */
    public boolean isEnabled() {
        return isEnabled;
    }
    
    /**
     * 检查服务是否已激活
     */
    public boolean isActivated() {
        return isActivated;
    }
    
    /**
     * 检查是否正在录音
     */
    public boolean isRecording() {
        return isRecording;
    }
    
    /**
     * 关闭并释放资源
     */
    public void shutdown() {
        stopVoiceInput();
        if (speechService != null) {
            speechService.release();
        }
        if (keyboardInjector != null) {
            keyboardInjector.release();
        }
        this.isEnabled = false;
        this.isActivated = false;
        this.isRecording = false;
        logger.info("VoiceInputManager 已关闭");
    }
    
    /**
     * 获取语音服务实例
     */
    public SpeechService getSpeechService() {
        return speechService;
    }
    
    /**
     * 获取键盘注入器实例
     */
    public KeyboardInjector getKeyboardInjector() {
        return keyboardInjector;
    }
}
