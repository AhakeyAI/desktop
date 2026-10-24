package com.example.ahakey.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.regex.Pattern;

/**
 * 将键盘拨杆状态与 Kimi {@code config.toml} 的 {@code default_yolo} 字段对齐：
 * 自动档 → {@code default_yolo = true}，手动档 → {@code default_yolo = false}。
 *
 * <p>配置文件路径：{@code %USERPROFILE%\.kimi\config.toml}（Windows）
 */
public class KimiConfigLeverSync {
    private static final Logger logger = LoggerFactory.getLogger(KimiConfigLeverSync.class);

    private static final Pattern DEFAULT_YOLO_PATTERN =
            Pattern.compile("(?m)^\\s*default_yolo\\s*=\\s*[^\\r\\n]*\\s*$");

    private static Path configPath() {
        String home = System.getProperty("user.home");
        return Paths.get(home, ".kimi", "config.toml");
    }

    private static Path snapshotPath() {
        return configPath().resolveSibling("config.toml.ahakey.lever0.bak");
    }

    public static void apply(boolean isAuto) {
        if (isAuto) {
            enableYolo();
        } else {
            disableYolo();
        }
    }

    private static void enableYolo() {
        Path cfg = configPath();
        if (!Files.exists(cfg)) {
            logger.warn("KimiConfigLeverSync: 未找到 {}，跳过。", cfg);
            return;
        }

        Path snap = snapshotPath();
        if (!Files.exists(snap)) {
            try {
                Files.copy(cfg, snap, StandardCopyOption.REPLACE_EXISTING);
                logger.debug("KimiConfigLeverSync: 已备份到 {}", snap);
            } catch (IOException e) {
                logger.warn("KimiConfigLeverSync: 备份失败 {}", e.getMessage());
            }
        }

        rewriteYolo(cfg, "default_yolo = true  # AhaKey: dial auto; run /reload in Kimi after changing dial");
        logger.info("KimiConfigLeverSync: default_yolo=true (自动档)");
    }

    private static void disableYolo() {
        Path snap = snapshotPath();
        if (Files.exists(snap)) {
            try {
                Files.delete(snap);
                logger.debug("KimiConfigLeverSync: 已删除旧快照 {}", snap);
            } catch (IOException e) {
                logger.warn("KimiConfigLeverSync: 删除快照失败 {}", e.getMessage());
            }
        }

        Path cfg = configPath();
        if (!Files.exists(cfg)) return;

        rewriteYolo(cfg, "default_yolo = false  # AhaKey: dial manual; run /reload in Kimi after changing dial");
        logger.info("KimiConfigLeverSync: default_yolo=false (手动档); 请在 Kimi 中执行 /reload 生效。");
    }

    private static void rewriteYolo(Path cfg, String line) {
        try {
            String raw = Files.readString(cfg, StandardCharsets.UTF_8);
            String updated;
            if (DEFAULT_YOLO_PATTERN.matcher(raw).find()) {
                updated = DEFAULT_YOLO_PATTERN.matcher(raw).replaceAll(line);
            } else {
                String trimmed = raw.stripTrailing();
                updated = trimmed.isEmpty() ? line + "\n" : line + "\n\n" + raw;
            }
            Files.writeString(cfg, updated, StandardCharsets.UTF_8,
                    StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING);
        } catch (IOException e) {
            logger.error("KimiConfigLeverSync: 写回配置失败 {}", e.getMessage());
        }
    }
}
