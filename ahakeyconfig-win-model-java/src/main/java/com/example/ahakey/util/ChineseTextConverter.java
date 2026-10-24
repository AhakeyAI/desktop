package com.example.ahakey.util;

import com.github.houbb.opencc4j.util.ZhConverterUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 简繁中文转换工具
 * 基于 OpenCC（纯 Java 实现，完全离线，无网络依赖）。
 * 用于将本地语音识别结果（简体为主）转换为繁体输出。
 */
public final class ChineseTextConverter {

    private static final Logger logger = LoggerFactory.getLogger(ChineseTextConverter.class);

    private ChineseTextConverter() {
    }

    /**
     * 简体转繁体
     * 转换失败时降级返回原文，保证语音输入流程不受影响
     */
    public static String toTraditional(String text) {
        if (text == null || text.isEmpty()) {
            return text;
        }
        try {
            return ZhConverterUtil.toTraditional(text);
        } catch (Exception e) {
            logger.warn("简→繁转换失败，返回原文: {}", e.getMessage());
            return text;
        }
    }

    /**
     * 繁体转简体
     * 转换失败时降级返回原文
     */
    public static String toSimplified(String text) {
        if (text == null || text.isEmpty()) {
            return text;
        }
        try {
            return ZhConverterUtil.toSimple(text);
        } catch (Exception e) {
            logger.warn("繁→简转换失败，返回原文: {}", e.getMessage());
            return text;
        }
    }
}
