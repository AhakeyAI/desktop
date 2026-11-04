package com.example.ahakey.service;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.protocol.AhaKeyProtocol;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

/** 对齐 Swift `commandsForModes` + `writeCommandsSequentially`。 */
public final class DeviceSyncService {
    public record LabeledCommand(byte[] data, String label) {
    }

    private DeviceSyncService() {
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
                int i = 0;
                for (LabeledCommand cmd : commands) {
                    i++;
                    if (onProgress != null) {
                        onProgress.accept("保存中 (" + i + "/" + commands.size() + ") " + cmd.label());
                    }
                    ble.sendCommand(cmd.data());
                    Thread.sleep(50);
                }
                Thread.sleep(250);
                if (onComplete != null) {
                    onComplete.run();
                }
            } catch (Exception e) {
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
