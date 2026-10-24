package com.example.ahakey.util;

import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.model.MacroAction;
import com.example.ahakey.model.MacroStep;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.VoicePreset;
import com.example.ahakey.protocol.AhaKeyResponseParser;

import java.util.ArrayList;
import java.util.List;

/**
 * 比对"EEPROM 实际数据" vs "StudioState 期望数据",返回 diff 列表。
 *
 * <p>用于 sync 前弹窗展示"哪些键位会变",sync 后验证"是否真的同步成功"。
 */
public final class KeyBindingDiffer {

    /**
     * diff 条目,描述单个键位的"现在 vs 之后"对比。
     */
    public record DiffEntry(
        int mode,
        StudioPart part,
        String before,   // EEPROM 现状
        String after,    // StudioState 期望
        boolean changed  // 是否真有差异
    ) {
        public String getModeName() {
            return ModeSlot.fromIndex(mode).getShortName();
        }
    }

    private KeyBindingDiffer() {
    }

    /**
     * 给定 16 个 FullKeyBinding(4 mode × 4 key)和 StudioState,返回 16 个 DiffEntry。
     *
     * @param bindings EEPROM 实际数据,按 (mode, keyIndex) 排,共 16 项
     * @param state    StudioState 本地期望
     * @return DiffEntry 列表,固定 16 项,顺序: mode 0..3, key 0..3
     */
    public static List<DiffEntry> diff(List<AhaKeyResponseParser.FullKeyBinding> bindings, StudioState state) {
        List<DiffEntry> out = new ArrayList<>(16);
        if (bindings == null || bindings.size() != 16 || state == null) {
            return out;
        }
        StudioPart[] parts = {StudioPart.KEY1, StudioPart.KEY2, StudioPart.KEY3, StudioPart.KEY4};
        for (int m = 0; m < 4; m++) {
            ModeSlot mode = ModeSlot.fromIndex(m);
            for (int k = 0; k < 4; k++) {
                AhaKeyResponseParser.FullKeyBinding binding = bindings.get(m * 4 + k);
                KeyConfig expected = state.getKeyConfig(mode, parts[k]);
                // 统一两边的描述格式,避免"未配置" vs "未设置" / "宏 (11 步)" vs "宏(↓Q...)"
                // 之类字面值差异造成的误报。
                String before = formatUnified(binding);
                String after = formatUnified(expected);
                boolean changed = !before.equals(after);
                out.add(new DiffEntry(m, parts[k], before, after, changed));
            }
        }
        return out;
    }

    /** 空配置的统一显示文本(避免 EEPROM 侧"未配置"和 StudioState 侧"未设置" 误报)。 */
    public static final String EMPTY_LABEL = "(空)";

    /** 把 EEPROM 端 FullKeyBinding 转成统一格式字符串。 */
    private static String formatUnified(AhaKeyResponseParser.FullKeyBinding binding) {
        if (binding == null || binding.sub() == 0x00 || binding.bindLen() == 0) {
            return EMPTY_LABEL;
        }
        if (binding.sub() == 0x74) {
            return "宏(" + formatMacroShort(binding.hidBytes()) + ")";
        }
        if (binding.sub() == 0x73) {
            return HidBindingFormatter.formatShortcut(binding.hidBytes());
        }
        return HidBindingFormatter.format(binding);
    }

    /** 把 StudioState 端 KeyConfig 转成统一格式字符串。 */
    private static String formatUnified(KeyConfig key) {
        if (key == null) {
            return EMPTY_LABEL;
        }
        if (key.getVoicePreset() != com.example.ahakey.model.VoicePreset.CUSTOM) {
            return key.getVoicePreset().getDisplayName();
        }
        if (key.usesMacro() && !key.getMacro().isEmpty()) {
            return "宏(" + formatMacroShort(key) + ")";
        }
        int hid = key.getHidCode();
        if (hid == 0) {
            return EMPTY_LABEL;
        }
        // hidCode 是 16-bit 拼出来的:高字节是修饰键位(0x100/0x200/.../0x8000),
        // 低字节是基础键(0x04..0x73)。需要拆成 hid bytes 再复用
        // HidBindingFormatter.formatShortcut 做修饰键 + 基础键的人话翻译。
        int modifiers = hid & 0xFF00;
        int baseCode = hid & 0xFF;
        java.util.List<Byte> keyCodes = new java.util.ArrayList<>();
        if ((modifiers & 0x200) != 0) keyCodes.add((byte) 0xE0);   // Left Ctrl
        if ((modifiers & 0x2000) != 0) keyCodes.add((byte) 0xE4);  // Right Ctrl
        if ((modifiers & 0x100) != 0) keyCodes.add((byte) 0xE1);   // Left Shift
        if ((modifiers & 0x1000) != 0) keyCodes.add((byte) 0xE5);  // Right Shift
        if ((modifiers & 0x400) != 0) keyCodes.add((byte) 0xE2);   // Left Alt
        if ((modifiers & 0x4000) != 0) keyCodes.add((byte) 0xE6);  // Right Alt
        if ((modifiers & 0x800) != 0) keyCodes.add((byte) 0xE3);   // Left Win
        if ((modifiers & 0x8000) != 0) keyCodes.add((byte) 0xE7);  // Right Win
        if (baseCode != 0) {
            keyCodes.add((byte) baseCode);
        }
        byte[] hidBytes = new byte[keyCodes.size()];
        for (int i = 0; i < keyCodes.size(); i++) {
            hidBytes[i] = keyCodes.get(i);
        }
        return HidBindingFormatter.formatShortcut(hidBytes);
    }

    /** 把 EEPROM 端宏 bytes 转成简短可读形式(↓Q 释放 ↑Q +30ms)。 */
    private static String formatMacroShort(byte[] hidBytes) {
        if (hidBytes == null || hidBytes.length < 2) {
            return "空";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i + 1 < hidBytes.length; i += 2) {
            int action = hidBytes[i] & 0xFF;
            int param = hidBytes[i + 1] & 0xFF;
            if (sb.length() > 0) sb.append(" ");
            switch (action) {
                case 0x01 -> sb.append("↓").append(com.example.ahakey.model.HIDUsage.getName(param));
                case 0x02 -> sb.append("释放 ").append(com.example.ahakey.model.HIDUsage.getName(param));
                case 0x03 -> sb.append("+").append(param * 3).append("ms");
                default -> sb.append("·0x").append(String.format("%02X", action));
            }
        }
        return sb.length() == 0 ? "空" : sb.toString();
    }

    /** 把 StudioState 端宏 MacroStep 列表转成简短可读形式。 */
    private static String formatMacroShort(KeyConfig key) {
        if (key == null || key.getMacro() == null || key.getMacro().isEmpty()) {
            return "空";
        }
        StringBuilder sb = new StringBuilder();
        for (com.example.ahakey.model.MacroStep step : key.getMacro()) {
            if (sb.length() > 0) sb.append(" ");
            // MacroAction 已抽到独立 public 文件,可直接类型安全 switch
            switch (step.getAction()) {
                case DOWN_KEY -> sb.append("↓").append(com.example.ahakey.model.HIDUsage.getName(step.getParam()));
                case UP_KEY -> sb.append("释放 ").append(com.example.ahakey.model.HIDUsage.getName(step.getParam()));
                case DELAY -> sb.append("+").append(step.getParam() * 3).append("ms");
                case UP_ALL_KEYS -> sb.append("释放所有");
                default -> sb.append("·");
            }
        }
        return sb.length() == 0 ? "空" : sb.toString();
    }

    /**
     * 统计有变化的条目数。
     */
    public static int countChanged(List<DiffEntry> entries) {
        int n = 0;
        for (DiffEntry e : entries) {
            if (e.changed()) n++;
        }
        return n;
    }

    /**
     * 把 KeyConfig 翻译成统一格式字符串(用于 UI 画布 caption 显示)。
     * <p>对外公开:画布 KEY1..4 卡片需要显示真实键名(而不是 description 标签)。
     * 比如 hidCode=0x223 显示 "Left Ctrl+6",hidCode=0x6D 显示 "F18"。
     */
    public static String formatKeyConfig(KeyConfig key) {
        return formatUnified(key);
    }

    /**
     * 把 FullKeyBinding(EEPROM 实际内容)反向应用到 KeyConfig。
     * <p>用于"撤销修改"按钮:把 StudioState 期望值还原为设备当前值,
     * 撤销后该行 diff.changed 会变成 false,不再出现在变化列表里。
     */
    public static void applyRevert(AhaKeyResponseParser.FullKeyBinding binding, KeyConfig key) {
        if (key == null) {
            return;
        }
        if (binding == null || binding.sub() == 0x00 || binding.bindLen() == 0) {
            // 空配置
            key.setHidCode(0);
            key.setVoicePreset(VoicePreset.CUSTOM);
            key.setMacro(new ArrayList<>());
            return;
        }
        if (binding.sub() == 0x73) {
            // 快捷键:hid bytes = 修饰键(0xE0..0xE7) + 基础键
            int hid = 0;
            byte[] hidBytes = binding.hidBytes();
            for (byte b : hidBytes) {
                int code = b & 0xFF;
                if (code == 0) continue;
                if (code >= 0xE0 && code <= 0xE7) {
                    hid |= modifierBitMask(code);
                } else {
                    hid |= code;  // 基础键(取最后一个非修饰键)
                }
            }
            key.setHidCode(hid);
            key.setVoicePreset(VoicePreset.CUSTOM);
            key.setMacro(new ArrayList<>());
        } else if (binding.sub() == 0x74) {
            // 宏:每 2 字节一步 [action, param]
            List<MacroStep> steps = new ArrayList<>();
            byte[] hidBytes = binding.hidBytes();
            for (int i = 0; i + 1 < hidBytes.length; i += 2) {
                int action = hidBytes[i] & 0xFF;
                int param = hidBytes[i + 1] & 0xFF;
                MacroStep step = new MacroStep();
                step.setAction(switch (action) {
                    case 0x01 -> MacroAction.DOWN_KEY;
                    case 0x02 -> MacroAction.UP_KEY;
                    case 0x03 -> MacroAction.DELAY;
                    default -> MacroAction.DOWN_KEY;
                });
                step.setParam(param);
                steps.add(step);
            }
            key.setMacro(steps);
            key.setHidCode(0);
            key.setVoicePreset(VoicePreset.CUSTOM);
        }
    }

    /** 修饰键 hid byte → hidCode bit mask(对齐 DeviceSyncService 的编码) */
    private static int modifierBitMask(int code) {
        return switch (code) {
            case 0xE0 -> 0x200;  // Left Ctrl
            case 0xE1 -> 0x100;  // Left Shift
            case 0xE2 -> 0x400;  // Left Alt
            case 0xE3 -> 0x800;  // Left Win
            case 0xE4 -> 0x2000; // Right Ctrl
            case 0xE5 -> 0x1000; // Right Shift
            case 0xE6 -> 0x4000; // Right Alt
            case 0xE7 -> 0x8000; // Right Win
            default -> 0;
        };
    }
}
