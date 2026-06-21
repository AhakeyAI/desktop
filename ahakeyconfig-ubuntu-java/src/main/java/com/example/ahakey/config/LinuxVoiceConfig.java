package com.example.ahakey.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Linux 语音配置管理
 * 管理讯飞输入法快捷键等配置
 */
public class LinuxVoiceConfig {
    private static final Logger logger = LoggerFactory.getLogger(LinuxVoiceConfig.class);
    private static final String CONFIG_DIR = ".ahakey";
    private static final String CONFIG_FILE = "linux-voice-config.json";
    
    private static LinuxVoiceConfig instance;
    
    private final ObjectMapper mapper = new ObjectMapper();
    private final Path configPath;
    private ObjectNode config;
    
    // 输入法类型
    public enum InputMethodType {
        SOGOU("sogou"),      // 讯飞输入法
        FCITX("fcitx"),       // fcitx 框架
        IBUS("ibus");         // ibus 框架
        
        private final String value;
        
        InputMethodType(String value) {
            this.value = value;
        }
        
        public String getValue() {
            return value;
        }
        
        public static InputMethodType fromValue(String value) {
            for (InputMethodType type : values()) {
                if (type.value.equalsIgnoreCase(value)) {
                    return type;
                }
            }
            return SOGOU; // 默认讯飞
        }
    }
    
    private LinuxVoiceConfig() {
        String home = System.getProperty("user.home");
        configPath = Paths.get(home, CONFIG_DIR, CONFIG_FILE);
        loadConfig();
    }
    
    public static synchronized LinuxVoiceConfig getInstance() {
        if (instance == null) {
            instance = new LinuxVoiceConfig();
        }
        return instance;
    }
    
    private void loadConfig() {
        try {
            File file = configPath.toFile();
            if (file.exists()) {
                config = (ObjectNode) mapper.readTree(file);
                logger.info("已加载 Linux 语音配置: {}", configPath);
            } else {
                // 创建默认配置
                config = mapper.createObjectNode();
                config.put("inputMethodType", InputMethodType.SOGOU.getValue());
                config.put("voiceShortcut", "ctrl+alt+v");
                saveConfig();
                logger.info("已创建默认 Linux 语音配置");
            }
        } catch (Exception e) {
            logger.error("加载配置失败，使用默认值", e);
            config = mapper.createObjectNode();
            config.put("inputMethodType", InputMethodType.SOGOU.getValue());
            config.put("voiceShortcut", "ctrl+alt+v");
        }
    }
    
    public void saveConfig() {
        try {
            Files.createDirectories(configPath.getParent());
            mapper.writerWithDefaultPrettyPrinter().writeValue(configPath.toFile(), config);
        } catch (IOException e) {
            logger.error("保存配置失败", e);
        }
    }
    
    public InputMethodType getInputMethodType() {
        String type = config.has("inputMethodType") ? config.get("inputMethodType").asText() : InputMethodType.SOGOU.getValue();
        return InputMethodType.fromValue(type);
    }
    
    public void setInputMethodType(InputMethodType type) {
        config.put("inputMethodType", type.getValue());
        saveConfig();
    }
    
    public String getVoiceShortcut() {
        return config.has("voiceShortcut") ? config.get("voiceShortcut").asText() : "ctrl+alt+v";
    }
    
    public void setVoiceShortcut(String shortcut) {
        config.put("voiceShortcut", shortcut);
        saveConfig();
    }
    
    /**
     * 检查讯飞输入法是否安装
     */
    public boolean isSogouInstalled() {
        try {
            Process process = Runtime.getRuntime().exec("which sogou-qimpanel");
            return process.waitFor() == 0;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 检查 fcitx 是否安装
     */
    public boolean isFcitxInstalled() {
        try {
            Process process = Runtime.getRuntime().exec("which fcitx");
            return process.waitFor() == 0;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 检查 xdotool 是否安装
     */
    public boolean isXdotoolAvailable() {
        try {
            Process process = Runtime.getRuntime().exec("which xdotool");
            return process.waitFor() == 0;
        } catch (Exception e) {
            return false;
        }
    }
}
