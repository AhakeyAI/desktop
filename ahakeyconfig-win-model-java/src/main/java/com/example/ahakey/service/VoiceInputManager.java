package com.example.ahakey.service;

import com.example.ahakey.config.ModelConfig;
import com.example.ahakey.util.ChineseTextConverter;
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
    private volatile boolean chineseTraditional = false; // 识别结果是否输出繁体（OpenCC 转换）
    private Consumer<String> resultCallback;
    private Consumer<String> partialCallback;
    private Consumer<String> statusCallback;
    private ModelConfig config;
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
            config = ModelConfig.getInstance();
            speechService = new SpeechService();
            
            speechService.initialize();
            
            keyboardInjector = new KeyboardInjector();
            
            // 读取配置文件中的简繁模式
            chineseTraditional = config.isChineseTraditional();
            
            isEnabled = true;
            logger.info("VoiceInputManager 初始化成功，触发模式: {}, 输出模式: {}",
                config.isToggleMode() ? "toggle" : "hold",
                chineseTraditional ? "繁体" : "简体");
        } catch (Exception e) {
            logger.error("VoiceInputManager 初始化失败: {}", e.getMessage(), e);
            isEnabled = false;
        }
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
     * 设置识别结果简繁模式（由 UI 简/繁切换触发）
     * @param traditional true: 输出繁体，false: 输出简体
     */
    public void setChineseTraditional(boolean traditional) {
        this.chineseTraditional = traditional;
        logger.info("语音输出模式切换: {}", traditional ? "繁体" : "简体");
    }
    
    /**
     * 检查当前是否输出繁体
     */
    public boolean isChineseTraditional() {
        return chineseTraditional;
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
        
        // Toggle 模式：点击切换录音状态
        if (config != null && config.isToggleMode()) {
            if (isRecording) {
                // 正在录音，停止录音
                stopRecordingInternal();
                return;
            }
            // 未录音，开始录音
            startRecordingInternal();
            return;
        }
        
        // Hold 模式：长按开始录音
        if (isRecording) {
            if (keyDownTriggered) {
                return;
            }
            logger.warn("已在录音中");
            return;
        }
        
        startRecordingInternal();
    }
    
    /**
     * 停止录音（由按键释放触发）
     */
    public void stopRecording() {
        // Toggle 模式：按键释放不做操作，录音状态由按键按下时切换
        if (config != null && config.isToggleMode()) {
            return;
        }
        
        // Hold 模式：释放按键停止录音
        stopRecordingInternal();
    }
    
    /**
     * 内部方法：开始录音
     */
    private void startRecordingInternal() {
        this.isRecording = true;
        this.keyDownTriggered = true;
        this.accumulatedResult = new StringBuilder();  // 重置累积结果
        
        if (!speechService.isVadEnabled()) {
            notifyStatus(VoiceStatus.RECOGNIZING);
            logger.info("开始录音（无VAD）...");
        } else {
            notifyStatus(VoiceStatus.RECORDING);
            logger.info("开始录音...");
        }
        
        speechService.startListening(
            this::onPartialResult,
            this::onFinalResult
        );
    }
    
    /**
     * 内部方法：停止录音
     */
    private void stopRecordingInternal() {
        if (!isRecording) {
            logger.warn("未在录音中");
            return;
        }
        
        if (speechService != null) {
            speechService.stopListening();
            this.isRecording = false;
            this.keyDownTriggered = false;
            logger.info("停止录音");
        }
    }
    
    /**
     * 处理中间识别结果(Partial)
     * 累积到 accumulatedResult,通过 partialCallback 推给 UI 浮窗实时显示,
     * 但不注入光标(最终结果出来后统一注入,避免与 AhaType 整理冲突)。
     */
    private void onPartialResult(String text) {
        logger.info("[语音识别中] {}", text);
        
        notifyStatus(VoiceStatus.RECOGNIZING);
        
        // 累积中间结果
        if (text != null && !text.isEmpty()) {
            accumulatedResult.append(text);
        }
        String accumulated = accumulatedResult.toString();
        
        // 繁体模式下实时预览也做转换，保证浮窗/预览与最终输出一致
        String display = chineseTraditional ? ChineseTextConverter.toTraditional(accumulated) : accumulated;
        
        // 通知 UI(浮窗/预览)显示实时转写文字
        if (partialCallback != null) {
            try {
                partialCallback.accept(display);
            } catch (Exception e) {
                logger.error("中间结果回调失败: {}", e.getMessage());
            }
        }
    }
    
    /**
     * 处理最终识别结果(Final)
     * 合并累积的中间结果 + 最后一块,经 AhaType 云端整理后注入光标。
     */
    private void onFinalResult(String text) {
        logger.info("[语音识别完成] {}", text);

        // 合并累积的中间结果 + 最后一块(避免重复)
        String accumulatedStr = accumulatedResult.toString();
        StringBuilder finalResultBuilder = new StringBuilder(accumulatedStr);
        if (text != null && !text.trim().isEmpty()) {
            if (!accumulatedStr.endsWith(text.trim())) {
                finalResultBuilder.append(text.trim());
            }
        }
        String merged = finalResultBuilder.toString().trim();
        logger.debug("合并后的识别结果: \"{}\"", merged);

        if (merged.isEmpty()) {
            logger.debug("识别结果为空");
            notifyStatus(VoiceStatus.STOPPED);
            resetCallbacks();
            return;
        }

        notifyStatus(VoiceStatus.PROCESSING);

        // AhaType 云端整理(启用时阻塞等待,失败降级为原文)
        String output = AhaTypeService.getInstance().processIfEnabled(merged);
        logger.debug("AhaType 整理结果: \"{}\"", output);

        // 繁体模式下对最终输出做 OpenCC 简繁转换(整理完成后统一转换,保证注入与显示一致)
        if (chineseTraditional) {
            output = ChineseTextConverter.toTraditional(output);
            logger.debug("繁体转换结果: \"{}\"", output);
        }

        // 回调 UI 显示最终文本
        if (resultCallback != null) {
            try {
                resultCallback.accept(output);
            } catch (Exception e) {
                logger.error("最终结果回调失败: {}", e.getMessage());
            }
        }

        // 注入到当前光标位置
        injectText(output);

        notifyStatus(VoiceStatus.STOPPED);
        resetCallbacks();
    }

    private void resetCallbacks() {
        // 注意:不清空 resultCallback/partialCallback。
        // 这两个回调在 startVoiceInput(服务激活)时设置一次,
        // 后续每次按 F18 只调 startRecording/stopRecording,不会重建回调。
        // 如果这里清空,第二次录音起浮窗就收不到实时文字了。
        this.accumulatedResult = new StringBuilder();
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
