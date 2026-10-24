package com.example.ahakey.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Properties;

public class ModelConfig {
    
    private static final Logger logger = LoggerFactory.getLogger(ModelConfig.class);
    
    private static ModelConfig instance;
    private Properties properties;
    
    private static final String MODEL_ENABLED = "model.enabled";
    private static final String MODEL_PATH = "model.path";
    private static final String TOKENS_PATH = "tokens.path";
    private static final String MODEL_TYPE = "model.type";
    private static final String NUM_THREADS = "num_threads";
    private static final String SAMPLE_RATE = "sample_rate";
    private static final String STATUS_POLL_PERIOD = "status.poll.period.seconds";
    private static final String VAD_ENABLED = "vad.enabled";
    private static final String VAD_MODEL_PATH = "vad.model.path";
    private static final String PUNCT_ENABLED = "punct.enabled";
    private static final String PUNCT_MODEL_PATH = "punct.model.path";
    private static final String VOICE_TRIGGER_MODE = "voice.trigger.mode";
    private static final String VOICE_CHINESE_MODE = "voice.chinese.mode";
    
    private static final boolean DEFAULT_MODEL_ENABLED = false;
    private static final String DEFAULT_MODEL_PATH = "models";
    private static final String DEFAULT_TOKENS_PATH = "tokens.txt";
    private static final String DEFAULT_MODEL_TYPE = "SENSE_VOICE";
    private static final int DEFAULT_NUM_THREADS = 4;
    private static final int DEFAULT_SAMPLE_RATE = 16000;
    private static final int DEFAULT_STATUS_POLL_PERIOD = 3;
    private static final boolean DEFAULT_VAD_ENABLED = false;
    private static final String DEFAULT_VAD_MODEL_PATH = "models/silero_vad.onnx";
    private static final boolean DEFAULT_PUNCT_ENABLED = true;
    private static final String DEFAULT_PUNCT_MODEL_PATH = "models/punct_model.onnx";
    
    private ModelConfig() {
        loadConfig();
    }
    
    public static synchronized ModelConfig getInstance() {
        if (instance == null) {
            instance = new ModelConfig();
        }
        return instance;
    }
    
    public void reload() {
        loadConfig();
    }
    
    private void loadConfig() {
        properties = new Properties();
        
        String appDir = getAppDir();
        logger.info("[Config] 应用程序目录: {}", appDir);
        
        File externalConfig = new File(appDir, "model_config.properties");
        logger.info("[Config] 外部配置文件路径: {}", externalConfig.getAbsolutePath());
        
        if (externalConfig.exists()) {
            try (FileInputStream fis = new FileInputStream(externalConfig)) {
                properties.load(fis);
                logger.info("[Config] 从外部配置文件加载成功");
                return;
            } catch (IOException e) {
                logger.error("[Config] 读取外部配置文件失败: {}", e.getMessage());
            }
        }
        
        try (InputStream is = getClass().getResourceAsStream("/model_config.properties")) {
            if (is != null) {
                properties.load(is);
                logger.info("[Config] 从JAR包加载配置文件成功");
                
                copyDefaultConfigToExternal(appDir);
            } else {
                logger.warn("[Config] 未找到模型配置文件，使用默认配置");
            }
        } catch (IOException e) {
            logger.error("[Config] 加载模型配置文件失败: {}", e.getMessage(), e);
        }
    }
    
    private String getAppDir() {
        try {
            File jarFile = new File(ModelConfig.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            if (jarFile.getName().endsWith(".jar")) {
                File appDir = jarFile.getParentFile();
                if (appDir != null && appDir.getName().equals("app")) {
                    return appDir.getParentFile().getAbsolutePath();
                }
                return appDir != null ? appDir.getAbsolutePath() : System.getProperty("user.dir");
            }
        } catch (Exception e) {
            logger.warn("[Config] 获取JAR路径失败: {}", e.getMessage());
        }
        return System.getProperty("user.dir");
    }
    
    private void copyDefaultConfigToExternal(String appDir) {
        try {
            File externalConfig = new File(appDir, "model_config.properties");
            if (!externalConfig.exists()) {
                InputStream is = getClass().getResourceAsStream("/model_config.properties");
                if (is != null) {
                    Files.copy(is, externalConfig.toPath());
                    logger.info("[Config] 默认配置文件已复制到安装目录: {}", externalConfig.getAbsolutePath());
                }
            }
        } catch (IOException e) {
            logger.error("[Config] 复制配置文件到安装目录失败: {}", e.getMessage());
        }
    }
    
    public boolean isEnabled() {
        return getBooleanProperty(MODEL_ENABLED, DEFAULT_MODEL_ENABLED);
    }
    
    public String getModelPath() {
        return properties.getProperty(MODEL_PATH, DEFAULT_MODEL_PATH);
    }
    
    public String getTokensPath() {
        return properties.getProperty(TOKENS_PATH, DEFAULT_TOKENS_PATH);
    }
    
    public String getModelType() {
        return properties.getProperty(MODEL_TYPE, DEFAULT_MODEL_TYPE);
    }
    
    public int getNumThreads() {
        return getIntProperty(NUM_THREADS, DEFAULT_NUM_THREADS);
    }
    
    public int getSampleRate() {
        return getIntProperty(SAMPLE_RATE, DEFAULT_SAMPLE_RATE);
    }
    
    public int getStatusPollPeriodSeconds() {
        return getIntProperty(STATUS_POLL_PERIOD, DEFAULT_STATUS_POLL_PERIOD);
    }
    
    public boolean isVadEnabled() {
        return getBooleanProperty(VAD_ENABLED, DEFAULT_VAD_ENABLED);
    }
    
    public String getVadModelPath() {
        return properties.getProperty(VAD_MODEL_PATH, DEFAULT_VAD_MODEL_PATH);
    }
    
    public boolean isPunctEnabled() {
        return getBooleanProperty(PUNCT_ENABLED, DEFAULT_PUNCT_ENABLED);
    }
    
    public String getPunctModelPath() {
        return properties.getProperty(PUNCT_MODEL_PATH, DEFAULT_PUNCT_MODEL_PATH);
    }
    
    public String getVoiceTriggerMode() {
        return properties.getProperty(VOICE_TRIGGER_MODE, "hold");
    }
    
    public boolean isToggleMode() {
        return "toggle".equalsIgnoreCase(getVoiceTriggerMode());
    }
    
    /**
     * 语音识别结果简繁模式
     * simplified: 简体输出（默认）
     * traditional: 繁体输出（识别结果经 OpenCC 转换）
     */
    public String getChineseMode() {
        return properties.getProperty(VOICE_CHINESE_MODE, "simplified");
    }
    
    public boolean isChineseTraditional() {
        return "traditional".equalsIgnoreCase(getChineseMode());
    }
    
    private boolean getBooleanProperty(String key, boolean defaultValue) {
        String value = properties.getProperty(key);
        if (value != null && !value.isEmpty()) {
            return Boolean.parseBoolean(value.trim());
        }
        return defaultValue;
    }
    
    private int getIntProperty(String key, int defaultValue) {
        try {
            String value = properties.getProperty(key);
            if (value != null && !value.isEmpty()) {
                return Integer.parseInt(value.trim());
            }
        } catch (NumberFormatException e) {
            logger.warn("[Config] 配置项 {} 值无效，使用默认值: {}", key, defaultValue);
        }
        return defaultValue;
    }
    
    public void printConfig() {
        logger.debug("[Config] ========== 模型配置 ==========");
        logger.debug("[Config] 模型启用: {}", isEnabled());
        logger.debug("[Config] 模型路径: {}", getModelPath());
        logger.debug("[Config] 词汇表路径: {}", getTokensPath());
        logger.debug("[Config] 模型类型: {}", getModelType());
        logger.debug("[Config] 线程数: {}", getNumThreads());
        logger.debug("[Config] 采样率: {}", getSampleRate());
        logger.debug("[Config] VAD 启用: {}", isVadEnabled());
        logger.debug("[Config] VAD 模型路径: {}", getVadModelPath());
        logger.debug("[Config] 标点符号启用: {}", isPunctEnabled());
        logger.debug("[Config] 标点符号模型路径: {}", getPunctModelPath());
        logger.debug("[Config] ==============================");
    }
}
