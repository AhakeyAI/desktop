package com.example.ahakey.platform.linux;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.example.ahakey.config.LinuxVoiceConfig;
import com.example.ahakey.platform.VoiceRelayService;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.VoicePreset;
import javafx.beans.property.BooleanProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

/**
 * Ubuntu 平台语音服务
 * 负责：
 * - 监听小键盘录音按键 (F17/F18)
 * - 映射到讯飞输入法快捷键
 * - 通过 xdotool 发送快捷键命令
 */
public final class LinuxVoiceRelayService implements VoiceRelayService {
    private static final Logger logger = LoggerFactory.getLogger(LinuxVoiceRelayService.class);

    private final BooleanProperty listening = new SimpleBooleanProperty(false);
    private final StringProperty statusMessage = new SimpleStringProperty("语音桥尚未启动。");
    private final StringProperty activeRouteSummary = new SimpleStringProperty("未配置路由。");
    private final StringProperty lastSimulateHint = new SimpleStringProperty(null);

    // 语音键回调
    private Runnable onVoiceKeyDown;
    private Runnable onVoiceKeyUp;
    private Runnable onSimulateRecordStart;
    private Runnable onSimulateRecordStop;

    // 配置管理
    private final LinuxVoiceConfig voiceConfig;
    
    // 当前工作模式
    private int workMode = 0;

    public LinuxVoiceRelayService() {
        this.voiceConfig = LinuxVoiceConfig.getInstance();
    }

    /**
     * 设置语音键按下回调
     */
    public void setOnVoiceKeyDown(Runnable callback) {
        this.onVoiceKeyDown = callback;
    }

    /**
     * 设置语音键释放回调
     */
    public void setOnVoiceKeyUp(Runnable callback) {
        this.onVoiceKeyUp = callback;
    }

    /**
     * 设置模拟录音开始回调
     */
    public void setOnSimulateRecordStart(Runnable callback) {
        this.onSimulateRecordStart = callback;
    }

    /**
     * 设置模拟录音停止回调
     */
    public void setOnSimulateRecordStop(Runnable callback) {
        this.onSimulateRecordStop = callback;
    }

    /**
     * 获取当前讯飞输入法语音快捷键
     */
    public String getVoiceShortcut() {
        return voiceConfig.getVoiceShortcut();
    }

    /**
     * 设置讯飞输入法语音快捷键
     */
    public void setVoiceShortcut(String shortcut) {
        voiceConfig.setVoiceShortcut(shortcut);
        logger.info("讯飞语音快捷键已更新为: {}", shortcut);
        updateActiveRouteSummary();
    }

    private void updateActiveRouteSummary() {
        activeRouteSummary.set("已配置讯飞输入法语音快捷键: " + getVoiceShortcut());
    }

    /**
     * 初始化服务
     */
    public void initialize() {
        logger.info("LinuxVoiceRelayService 初始化");
        
        // 检查 xdotool 是否安装
        if (!voiceConfig.isXdotoolAvailable()) {
            logger.warn("xdotool 未安装，请运行: sudo apt-get install xdotool");
            statusMessage.set("错误: xdotool 未安装");
            return;
        }
        
        // 检查讯飞输入法
        if (!voiceConfig.isSogouInstalled()) {
            logger.warn("讯飞输入法未检测到，请先安装");
            statusMessage.set("警告: 讯飞输入法未安装");
        }
        
        statusMessage.set("就绪");
        updateActiveRouteSummary();
    }

    /**
     * 触发讯飞输入法的语音输入
     * 模拟按下讯飞的快捷键
     */
    public void triggerVoiceInput() {
        String shortcut = getVoiceShortcut();
        try {
            logger.info("触发讯飞语音输入，快捷键: {}", shortcut);
            String command = String.format("xdotool key %s", shortcut);
            Process process = Runtime.getRuntime().exec(new String[]{"sh", "-c", command});
            
            // 读取错误输出以便调试
            String stderr = new String(process.getErrorStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
            int exitCode = process.waitFor();

            if (exitCode == 0) {
                statusMessage.set("语音输入已激活");
                lastSimulateHint.set("已触发讯飞语音输入");
            } else {
                String errorMsg = stderr.isEmpty() ? ("返回码 " + exitCode) : stderr.trim();
                logger.error("xdotool 执行失败: {}", errorMsg);
                statusMessage.set("语音输入失败");
                lastSimulateHint.set("语音输入失败: " + errorMsg);
            }
        } catch (Exception e) {
            logger.error("触发讯飞语音输入失败", e);
            statusMessage.set("错误: " + e.getMessage());
            lastSimulateHint.set("语音输入错误: " + e.getMessage());
        }
    }

    // 语音键 HID 码定义
    private static final int F17_HID_CODE = 0x6C;
    private static final int F18_HID_CODE = 0x6D;
    
    // 防止重复触发的标志
    private volatile boolean isVoiceKeyPressed = false;

    /**
     * 处理来自 BLE 的语音键事件
     * @param hidCode HID 按键码 (F17=0x6C, F18=0x6D)
     * @param isKeyDown true=按下, false=释放
     */
    public void handleVoiceKeyEvent(int hidCode, boolean isKeyDown) {
        logger.debug("收到语音键事件: HID=0x{}, down={}", Integer.toHexString(hidCode), isKeyDown);
        
        // 只处理 F17 和 F18 按键
        if (hidCode != F17_HID_CODE && hidCode != F18_HID_CODE) {
            logger.debug("忽略非语音键事件: HID=0x{}", Integer.toHexString(hidCode));
            return;
        }
        
        if (isKeyDown) {
            // 防止重复触发
            if (isVoiceKeyPressed) {
                logger.debug("语音键已按下，忽略重复触发");
                return;
            }
            isVoiceKeyPressed = true;
            
            // 触发讯飞语音输入
            triggerVoiceInput();
            
            // 触发语音键按下回调
            if (onVoiceKeyDown != null) {
                try {
                    onVoiceKeyDown.run();
                } catch (Exception e) {
                    logger.error("onVoiceKeyDown 回调执行失败", e);
                }
            }
            
            // 触发模拟录音开始回调
            if (onSimulateRecordStart != null) {
                try {
                    onSimulateRecordStart.run();
                } catch (Exception e) {
                    logger.error("onSimulateRecordStart 回调执行失败", e);
                }
            }
        } else {
            // 重置按键状态
            isVoiceKeyPressed = false;
            
            // 触发语音键释放回调
            if (onVoiceKeyUp != null) {
                try {
                    onVoiceKeyUp.run();
                } catch (Exception e) {
                    logger.error("onVoiceKeyUp 回调执行失败", e);
                }
            }
            
            // 触发模拟录音停止回调
            if (onSimulateRecordStop != null) {
                try {
                    onSimulateRecordStop.run();
                } catch (Exception e) {
                    logger.error("onSimulateRecordStop 回调执行失败", e);
                }
            }
        }
    }

    public void start() {
        initialize();
        listening.set(true);
        statusMessage.set("监听中 - 等待 BLE 语音键事件");
        logger.info("LinuxVoiceRelayService 已启动，工作模式: {}", workMode);
    }

    public void stop() {
        listening.set(false);
        statusMessage.set("已停止");
    }

    // 属性访问方法
    public BooleanProperty listeningProperty() {
        return listening;
    }

    public StringProperty statusMessageProperty() {
        return statusMessage;
    }

    public StringProperty activeRouteSummaryProperty() {
        return activeRouteSummary;
    }

    public StringProperty lastSimulateHintProperty() {
        return lastSimulateHint;
    }

    // 配置方法
    @Override
    public void configure(java.util.function.Supplier<?> studioState, java.util.function.IntSupplier workMode) {
        if (workMode != null) {
            this.workMode = workMode.getAsInt();
            logger.info("工作模式已更新为: {}", this.workMode);
        }
    }

    @Override
    public void updateRoutes(Object state) {
        // Linux 版本路由逻辑简化
        if (state instanceof ModeSlot) {
            ModeSlot mode = (ModeSlot) state;
            logger.debug("路由更新: {}", mode);
        }
    }

    @Override
    public void simulateVoiceKeyTap(Object mode) {
        triggerVoiceInput();
    }

    @Override
    public void simulateVoiceKeyTap(Object mode, Object preset) {
        triggerVoiceInput();
    }

    @Override
    public void simulateKeyByHid(int hidCode) {
        // Linux 版本不支持直接模拟按键
        lastSimulateHint.set("Linux 版本不支持 HID 按键模拟");
    }
    
    /**
     * 获取工作模式
     */
    public int getWorkMode() {
        return workMode;
    }
}
