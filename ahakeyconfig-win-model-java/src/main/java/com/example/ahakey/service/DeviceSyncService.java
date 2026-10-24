package com.example.ahakey.service;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.protocol.AhaKeyProtocol;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

/** 对齐 Swift `commandsForModes` + `writeCommandsSequentially`。 */
public final class DeviceSyncService {
    private static final Logger logger = LoggerFactory.getLogger(DeviceSyncService.class);

    public record LabeledCommand(byte[] data, String label) {
    }

    private DeviceSyncService() {
    }

    /**
     * 判断一帧是否是 0x04 saveConfig 提交命令。
     * 帧格式: [AA BB CMD ... CC DD] → 第 2 字节 (index 2) 是 CMD。
     */
    private static boolean isSaveConfigCommand(byte[] frame) {
        return frame != null && frame.length >= 3 && frame[2] == AhaKeyProtocol.CMD_SAVE_CONFIG;
    }

    private static String hexHead(byte[] data) {
        int n = Math.min(8, data.length);
        StringBuilder sb = new StringBuilder(n * 3);
        for (int i = 0; i < n; i++) {
            if (i > 0) sb.append(' ');
            sb.append(String.format("%02X", data[i] & 0xFF));
        }
        if (data.length > n) sb.append(" ...");
        return sb.toString();
    }

    public static List<LabeledCommand> commandsForModes(StudioState state, ModeSlot... modes) {
        List<LabeledCommand> out = new ArrayList<>();
        for (ModeSlot mode : modes) {
            int modeIndex = mode.getIndex();
            for (StudioPart part : List.of(
                StudioPart.KEY1, StudioPart.KEY2, StudioPart.KEY3, StudioPart.KEY4
            )) {
                var key = state.getKeyConfig(mode, part);
                int keyIndex = StudioState.keyIndexFor(part);
                
                // 检查是否使用宏
                if (key.usesMacro()) {
                    // 构建宏数据：每个宏步骤占2字节 [action, param]
                    List<Byte> macroBytes = new ArrayList<>();
                    for (int i = 0; i < key.getMacroStepCount(); i++) {
                        String actionType = key.getMacroStepAction(i);
                        int param = key.getMacroStepParam(i);
                        byte action = switch (actionType) {
                            case "DOWN_KEY" -> 0x01;
                            case "UP_KEY" -> 0x02;
                            case "DELAY" -> 0x03;
                            default -> 0x00;
                        };
                        macroBytes.add(action);
                        macroBytes.add((byte) param);
                    }
                    byte[] macroData = new byte[macroBytes.size()];
                    for (int i = 0; i < macroBytes.size(); i++) {
                        macroData[i] = macroBytes.get(i);
                    }
                    
                    out.add(new LabeledCommand(
                        AhaKeyProtocol.setKeyMacro(modeIndex, keyIndex, macroData),
                        mode.getTitle() + " " + part.getTitle() + " 宏"
                    ));
                } else {
                    // 处理快捷键：包含修饰键和基础键
                    int hidCode = key.getHidCode();
                    int modifiers = hidCode & 0xFF00;  // 修饰键位（含 Right 高位）
                    int baseCode = hidCode & 0xFF;    // 基础键码
                    
                    // 创建原始HID键码列表（设备期望的格式）
                    List<Byte> keyCodes = new ArrayList<>();
                    
                    // 将修饰键转换为原始HID码（区分 Left/Right）
                    if ((modifiers & 0x200) != 0) keyCodes.add((byte) 0xE0);  // Left Ctrl
                    if ((modifiers & 0x2000) != 0) keyCodes.add((byte) 0xE4); // Right Ctrl
                    if ((modifiers & 0x100) != 0) keyCodes.add((byte) 0xE1);  // Left Shift
                    if ((modifiers & 0x1000) != 0) keyCodes.add((byte) 0xE5); // Right Shift
                    if ((modifiers & 0x400) != 0) keyCodes.add((byte) 0xE2);  // Left Alt
                    if ((modifiers & 0x4000) != 0) keyCodes.add((byte) 0xE6); // Right Alt
                    if ((modifiers & 0x800) != 0) keyCodes.add((byte) 0xE3);  // Left Win
                    if ((modifiers & 0x8000) != 0) keyCodes.add((byte) 0xE7); // Right Win
                    
                    // 添加基础键码
                    if (baseCode != 0) {
                        keyCodes.add((byte) baseCode);
                    }
                    
                    // 转换为字节数组
                    byte[] hid = new byte[keyCodes.size()];
                    for (int i = 0; i < keyCodes.size(); i++) {
                        hid[i] = keyCodes.get(i);
                    }
                    
                    out.add(new LabeledCommand(
                        AhaKeyProtocol.setKeyMapping(modeIndex, keyIndex, hid),
                        mode.getTitle() + " " + part.getTitle() + " 键码"
                    ));
                }
                
                out.add(new LabeledCommand(
                    AhaKeyProtocol.setKeyDescription(modeIndex, keyIndex, key.getDescription()),
                    mode.getTitle() + " " + part.getTitle() + " 描述"
                ));
            }

            out.add(new LabeledCommand(
                AhaKeyProtocol.setAiLightConfig(modeIndex, state.getAiLightEffectBytes(mode)),
                mode.getTitle() + " AI 状态灯效"
            ));
        }

        out.add(new LabeledCommand(AhaKeyProtocol.setLightBrightness(state.getLightBrightness()), "灯光亮度"));
        out.add(new LabeledCommand(AhaKeyProtocol.saveConfig(), "保存全部配置到设备"));
        return out;
    }

    public static void writeSequentially(
        BleManager ble,
        List<LabeledCommand> commands,
        Runnable onComplete,
        Runnable onError,
        Consumer<String> onProgress
    ) {
        new Thread(() -> {
            try {
                logger.info("[设备同步] 开始: 总命令数={}", commands.size());
                long t0 = System.currentTimeMillis();
                int i = 0;
                for (LabeledCommand cmd : commands) {
                    i++;
                    byte[] data = cmd.data();
                    boolean isSave = isSaveConfigCommand(data);
                    if (onProgress != null) {
                        onProgress.accept("保存中 (" + i + "/" + commands.size() + ") " + cmd.label());
                    }
                    if (isSave) {
                        // 0x04 是关键:RAM → EEPROM 提交。日志高亮,便于排查丢包
                        logger.warn("[设备同步] 准备发送 0x04 saveConfig: {}/{}, label={}, 此前已写 {} 条",
                                i, commands.size(), cmd.label(), i - 1);
                    } else {
                        logger.debug("[设备同步] 发送 {}/{} [{}] {}",
                                i, commands.size(), hexHead(data), cmd.label());
                    }
                    ble.sendCommand(data);
                    Thread.sleep(50);
                }
                logger.info("[设备同步] 全部命令已 sendCommand 排队完成: 计数={}, 耗时={}ms",
                        commands.size(), System.currentTimeMillis() - t0);
                Thread.sleep(250);
                if (onComplete != null) {
                    onComplete.run();
                }
                logger.info("[设备同步] 完成回调已触发, 总耗时={}ms", System.currentTimeMillis() - t0);
            } catch (Exception e) {
                logger.error("[设备同步] 异常中断: {}", e.getMessage(), e);
                if (onProgress != null) {
                    onProgress.accept("保存失败：" + e.getMessage());
                }
                if (onError != null) {
                    onError.run();
                }
            }
        }, "aha-device-sync").start();
    }
}
