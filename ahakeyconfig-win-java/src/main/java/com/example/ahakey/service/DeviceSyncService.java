package com.example.ahakey.service;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;

import java.util.ArrayList;
import java.util.Arrays;
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
                
                if (key.usesMacro()) {
                    out.add(new LabeledCommand(
                        AhaKeyProtocol.setKeyMacro(modeIndex, keyIndex, encodeKeyActionPayload(key)),
                        mode.getTitle() + " " + part.getTitle() + " 宏"
                    ));
                } else {
                    out.add(new LabeledCommand(
                        AhaKeyProtocol.setKeyMapping(modeIndex, keyIndex, encodeKeyActionPayload(key)),
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

    public static byte[] encodeKeyActionPayload(KeyConfig key) {
        if (key.usesMacro()) {
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
            return macroData;
        }

        int hidCode = key.getHidCode();
        int modifiers = hidCode & 0xFF00;
        int baseCode = hidCode & 0xFF;
        List<Byte> keyCodes = new ArrayList<>();
        if ((modifiers & 0x200) != 0) keyCodes.add((byte) 0xE0);
        if ((modifiers & 0x2000) != 0) keyCodes.add((byte) 0xE4);
        if ((modifiers & 0x100) != 0) keyCodes.add((byte) 0xE1);
        if ((modifiers & 0x1000) != 0) keyCodes.add((byte) 0xE5);
        if ((modifiers & 0x400) != 0) keyCodes.add((byte) 0xE2);
        if ((modifiers & 0x4000) != 0) keyCodes.add((byte) 0xE6);
        if ((modifiers & 0x800) != 0) keyCodes.add((byte) 0xE3);
        if ((modifiers & 0x8000) != 0) keyCodes.add((byte) 0xE7);
        if (baseCode != 0) {
            keyCodes.add((byte) baseCode);
        }
        byte[] hid = new byte[keyCodes.size()];
        for (int i = 0; i < keyCodes.size(); i++) {
            hid[i] = keyCodes.get(i);
        }
        return hid;
    }

    public static byte[] encodeSideSwitchActionPayload(KeyConfig key) {
        KeyConfig safeKey = key == null ? new KeyConfig(0, "") : key;
        byte[] rawPayload = encodeKeyActionPayload(safeKey);
        if (rawPayload.length > 255) {
            throw new IllegalArgumentException("侧拨 Custom 动作内容超过 255 字节");
        }
        byte[] wrapped = new byte[2 + rawPayload.length];
        wrapped[0] = safeKey.usesMacro() ? AhaKeyProtocol.SUB_MACRO : AhaKeyProtocol.SUB_SHORTCUT;
        wrapped[1] = (byte) rawPayload.length;
        System.arraycopy(rawPayload, 0, wrapped, 2, rawPayload.length);
        return wrapped;
    }

    public static KeyConfig keyConfigFromReadback(AhaKeyResponseParser.OrdinaryKeyReadback readback) {
        KeyConfig key = keyConfigFromActionPayload(
            readback.actionPayload(),
            readback.actionType() == (AhaKeyProtocol.SUB_MACRO & 0xFF)
        );
        key.setDescription(readback.description());
        return key;
    }

    public static KeyConfig keyConfigFromSideSwitchActionPayload(byte[] actionPayload, boolean macroFallback) {
        byte[] safePayload = actionPayload == null ? new byte[0] : actionPayload;
        if (isSideSwitchActionEnvelope(safePayload)) {
            int len = safePayload[1] & 0xFF;
            byte[] rawPayload = Arrays.copyOfRange(safePayload, 2, 2 + len);
            return keyConfigFromActionPayload(rawPayload, safePayload[0] == AhaKeyProtocol.SUB_MACRO);
        }
        return keyConfigFromActionPayload(safePayload, macroFallback);
    }

    public static KeyConfig keyConfigFromActionPayload(byte[] actionPayload, boolean macro) {
        KeyConfig key = new KeyConfig(0, "");
        byte[] safePayload = actionPayload == null ? new byte[0] : actionPayload;
        if (macro) {
            for (int i = 0; i + 1 < safePayload.length; i += 2) {
                int action = safePayload[i] & 0xFF;
                int param = safePayload[i + 1] & 0xFF;
                String actionType = switch (action) {
                    case 0x01 -> "DOWN_KEY";
                    case 0x02 -> "UP_KEY";
                    case 0x03 -> "DELAY";
                    default -> "DELAY";
                };
                key.addMacroStep(actionType, param);
            }
        } else {
            key.setHidCode(decodeShortcutPayload(safePayload));
        }
        return key;
    }

    public static boolean isMacroActionPayload(byte[] actionPayload) {
        if (actionPayload == null || actionPayload.length == 0 || actionPayload.length % 2 != 0) {
            return false;
        }
        for (int i = 0; i < actionPayload.length; i += 2) {
            int action = actionPayload[i] & 0xFF;
            if (action != 0x01 && action != 0x02 && action != 0x03) {
                return false;
            }
        }
        return true;
    }

    public static boolean isSideSwitchMacroActionPayload(byte[] actionPayload) {
        byte[] safePayload = actionPayload == null ? new byte[0] : actionPayload;
        if (isSideSwitchActionEnvelope(safePayload)) {
            return safePayload[0] == AhaKeyProtocol.SUB_MACRO;
        }
        return isMacroActionPayload(safePayload);
    }

    private static boolean isSideSwitchActionEnvelope(byte[] actionPayload) {
        if (actionPayload == null || actionPayload.length < 2) {
            return false;
        }
        int type = actionPayload[0] & 0xFF;
        if (type != (AhaKeyProtocol.SUB_SHORTCUT & 0xFF) && type != (AhaKeyProtocol.SUB_MACRO & 0xFF)) {
            return false;
        }
        int len = actionPayload[1] & 0xFF;
        return len <= actionPayload.length - 2;
    }

    public static boolean matchesReadback(KeyConfig key, AhaKeyResponseParser.OrdinaryKeyReadback readback) {
        int expectedType = key.usesMacro() ? AhaKeyProtocol.SUB_MACRO & 0xFF : AhaKeyProtocol.SUB_SHORTCUT & 0xFF;
        byte[] expectedPayload = encodeKeyActionPayload(key);
        boolean expectedEmptyShortcut = !key.usesMacro() && expectedPayload.length == 0;
        boolean typeMatches = readback.actionType() == expectedType
            || (expectedEmptyShortcut && readback.actionType() == AhaKeyProtocol.ORDINARY_KEY_ACTION_EMPTY);
        return typeMatches
            && Arrays.equals(expectedPayload, readback.actionPayload())
            && sanitizeDescription(key.getDescription()).equals(sanitizeDescription(readback.description()));
    }

    private static int decodeShortcutPayload(byte[] payload) {
        int modifiers = 0;
        int baseCode = 0;
        for (byte item : payload) {
            int code = item & 0xFF;
            switch (code) {
                case 0xE0 -> modifiers |= 0x200;
                case 0xE4 -> modifiers |= 0x2000;
                case 0xE1 -> modifiers |= 0x100;
                case 0xE5 -> modifiers |= 0x1000;
                case 0xE2 -> modifiers |= 0x400;
                case 0xE6 -> modifiers |= 0x4000;
                case 0xE3 -> modifiers |= 0x800;
                case 0xE7 -> modifiers |= 0x8000;
                default -> {
                    if (code != 0) {
                        baseCode = code;
                    }
                }
            }
        }
        return modifiers | baseCode;
    }

    private static String sanitizeDescription(String value) {
        if (value == null) {
            return "";
        }
        String ascii = value.chars()
            .filter(c -> c >= 0x20 && c <= 0x7E)
            .limit(20)
            .collect(StringBuilder::new, StringBuilder::appendCodePoint, StringBuilder::append)
            .toString();
        return ascii.stripTrailing();
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
