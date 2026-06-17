package com.example.ahakey.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Ubuntu/Linux 平台键盘注入器
 * 使用 xdotool 工具模拟键盘输入
 */
public class KeyboardInjector {
    
    private static final Logger logger = LoggerFactory.getLogger(KeyboardInjector.class);
    
    // 默认延迟配置（毫秒）
    private static final int POST_RECORD_DELAY = 300;
    private static final int CHAR_DELAY = 20;

    /**
     * 将文本注入到当前活动窗口
     * @param text 要注入的文本
     */
    public void injectText(String text) {
        if (text == null || text.isEmpty()) {
            logger.debug("KeyboardInjector - 文本为空，跳过注入");
            return;
        }
        
        logger.debug("KeyboardInjector - 开始注入文本: \"{}\"", text);
        
        try {
            // 等待目标窗口获得焦点
            logger.debug("KeyboardInjector - 等待 {}ms 确保窗口焦点", POST_RECORD_DELAY);
            Thread.sleep(POST_RECORD_DELAY);
            
            // 使用 xdotool 注入文本
            injectTextWithXdotool(text);
            
            logger.debug("KeyboardInjector - 文本注入完成");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            logger.error("KeyboardInjector - 等待被中断");
        }
    }
    
    /**
     * 使用 xdotool 注入文本
     */
    private void injectTextWithXdotool(String text) {
        // 转义特殊字符
        String escapedText = escapeForXdotool(text);
        
        String command = String.format("xdotool type '%s'", escapedText);
        try {
            Process process = Runtime.getRuntime().exec(new String[]{"sh", "-c", command});
            int exitCode = process.waitFor();
            
            if (exitCode != 0) {
                logger.error("xdotool 执行失败，返回码: {}", exitCode);
                // 尝试备选方案
                injectTextWithXdotoolAlternative(text);
            }
        } catch (Exception e) {
            logger.error("xdotool 注入失败: {}", e.getMessage());
            injectTextWithXdotoolAlternative(text);
        }
    }
    
    /**
     * 备选方案：逐个字符发送
     */
    private void injectTextWithXdotoolAlternative(String text) {
        try {
            for (char c : text.toCharArray()) {
                String escapedChar = escapeForXdotool(String.valueOf(c));
                String command = String.format("xdotool type '%s'", escapedChar);
                Process process = Runtime.getRuntime().exec(new String[]{"sh", "-c", command});
                process.waitFor();
                Thread.sleep(CHAR_DELAY);
            }
        } catch (Exception e) {
            logger.error("备选注入方案失败: {}", e.getMessage());
        }
    }
    
    /**
     * 转义 xdotool 命令中的特殊字符
     */
    private String escapeForXdotool(String text) {
        // 转义单引号和其他特殊字符
        return text
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\t", "\\t");
    }
    
    /**
     * 释放资源
     */
    public void release() {
        // 无需特殊清理
    }
}
