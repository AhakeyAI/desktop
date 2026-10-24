package com.example.ahakey.app;

import com.example.ahakey.config.ModelConfig;
import com.example.ahakey.service.VoiceInputManager;
import javafx.application.Platform;
import javafx.beans.property.BooleanProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.beans.property.StringProperty;
import javafx.beans.property.SimpleStringProperty;
import javafx.fxml.FXML;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.ToggleButton;
import javafx.scene.control.ToggleGroup;
import javafx.scene.control.Tooltip;
import javafx.scene.layout.HBox;

/**
 * 语音输入控制面板
 * 提供语音转文字功能的UI接口
 */
public class VoiceInputController {
    
    @FXML
    private HBox voiceControlBox;
    
    @FXML
    private Button voiceToggleButton;
    
    @FXML
    private ToggleButton simpleToggleButton;
    
    @FXML
    private ToggleButton traditionalToggleButton;
    
    @FXML
    private Label statusLabel;
    
    @FXML
    private Label resultPreview;
    
    private VoiceInputManager voiceManager;
    private final BooleanProperty isListening = new SimpleBooleanProperty(false);
    private final StringProperty recognitionResult = new SimpleStringProperty("");
    private final StringProperty statusText = new SimpleStringProperty("语音输入已就绪");
    
    /**
     * 初始化控制器
     */
    public void initialize() {
        // 绑定UI属性
        statusLabel.textProperty().bind(statusText);
        resultPreview.textProperty().bind(recognitionResult);
        
        // 设置按钮样式和提示
        voiceToggleButton.setTooltip(new Tooltip("点击开始/停止语音输入"));
        updateButtonState(false);
        
        // 添加按钮事件
        voiceToggleButton.setOnAction(e -> toggleVoiceInput());
        
        // 初始化简体/繁体切换
        initChineseModeToggle();
    }
    
    /**
     * 初始化简体/繁体切换控件
     * 默认模式从 model_config.properties 的 voice.chinese.mode 读取
     */
    private void initChineseModeToggle() {
        ToggleGroup group = new ToggleGroup();
        simpleToggleButton.setToggleGroup(group);
        traditionalToggleButton.setToggleGroup(group);
        
        simpleToggleButton.setTooltip(new Tooltip("识别结果输出简体"));
        traditionalToggleButton.setTooltip(new Tooltip("识别结果输出繁体（OpenCC 转换）"));
        
        boolean traditional = ModelConfig.getInstance().isChineseTraditional();
        simpleToggleButton.setSelected(!traditional);
        traditionalToggleButton.setSelected(traditional);
        
        group.selectedToggleProperty().addListener((obs, oldVal, newVal) -> {
            if (voiceManager != null && newVal != null) {
                boolean trad = (newVal == traditionalToggleButton);
                voiceManager.setChineseTraditional(trad);
                statusText.set(trad ? "输出模式：繁体" : "输出模式：简体");
            }
        });
    }
    
    /**
     * 设置语音输入管理器
     */
    public void setVoiceManager(VoiceInputManager manager) {
        this.voiceManager = manager;
        // 将当前 UI 选中的简繁模式同步给管理器
        if (manager != null && traditionalToggleButton != null) {
            manager.setChineseTraditional(traditionalToggleButton.isSelected());
        }
    }
    
    /**
     * 切换语音输入状态
     */
    private void toggleVoiceInput() {
        if (isListening.get()) {
            stopVoiceInput();
        } else {
            startVoiceInput();
        }
    }
    
    /**
     * 开始语音输入
     */
    public void startVoiceInput() {
        if (voiceManager == null) {
            statusText.set("错误：语音服务未初始化");
            return;
        }
        
        isListening.set(true);
        updateButtonState(true);
        statusText.set("正在听...");
        recognitionResult.set("");
        
        voiceManager.startVoiceInput(text -> {
            Platform.runLater(() -> {
                recognitionResult.set(text);
            });
        });
    }
    
    /**
     * 停止语音输入
     */
    public void stopVoiceInput() {
        if (voiceManager == null) return;
        
        isListening.set(false);
        updateButtonState(false);
        voiceManager.stopVoiceInput();
        
        if (recognitionResult.get().isEmpty()) {
            statusText.set("未检测到语音");
        } else {
            statusText.set("识别完成");
        }
    }
    
    /**
     * 更新按钮状态
     */
    private void updateButtonState(boolean listening) {
        if (listening) {
            voiceToggleButton.getStyleClass().add("voice-active");
            voiceToggleButton.setText("停止");
        } else {
            voiceToggleButton.getStyleClass().remove("voice-active");
            voiceToggleButton.setText("语音输入");
        }
    }
    
    /**
     * 重置状态
     */
    public void reset() {
        isListening.set(false);
        updateButtonState(false);
        recognitionResult.set("");
        statusText.set("语音输入已就绪");
    }
    
    /**
     * 获取监听状态属性
     */
    public BooleanProperty isListeningProperty() {
        return isListening;
    }
    
    /**
     * 获取识别结果属性
     */
    public StringProperty recognitionResultProperty() {
        return recognitionResult;
    }
    
    /**
     * 获取状态文本属性
     */
    public StringProperty statusTextProperty() {
        return statusText;
    }
}
