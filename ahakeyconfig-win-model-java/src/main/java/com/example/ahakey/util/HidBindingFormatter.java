package com.example.ahakey.util;

import com.example.ahakey.model.HIDUsage;
import com.example.ahakey.protocol.AhaKeyResponseParser;

import java.util.ArrayList;
import java.util.List;

/**
 * 把 EEPROM 里的 hid bytes 解析成人话描述,用于 diff 弹窗展示。
 *
 * <p>支持三种格式:
 * <ul>
 *   <li>单键(sub=0x73):hid bytes = 修饰键(0xE0..0xE7)+基础键</li>
 *   <li>宏(sub=0x74):hid bytes = (action, param) 序列,每 2 字节一步</li>
 *   <li>空(sub=0x00 或 hidBytes 全 0):未配置</li>
 * </ul>
 */
public final class HidBindingFormatter {

    private HidBindingFormatter() {
    }

    /**
     * 把 FullKeyBinding 解析成一句话描述。
     * 例: "Ctrl+C"、"宏(↓Q 释放 ↑Q +30ms ↓Q)"、"未配置"。
     */
    public static String format(AhaKeyResponseParser.FullKeyBinding binding) {
        if (binding == null) {
            return "(读取失败)";
        }
        if (binding.sub() == 0x00 || binding.bindLen() == 0) {
            return "未配置";
        }
        if (binding.sub() == 0x74) {
            return formatMacro(binding.hidBytes());
        }
        if (binding.sub() == 0x73) {
            return formatShortcut(binding.hidBytes());
        }
        return String.format("未知类型 0x%02X", binding.sub() & 0xFF);
    }

    /**
     * 把 hid bytes 解析为 "Ctrl+Shift+A" 形式的快捷键描述。
     * 修饰键 0xE0..0xE7 排在前面,基础键排在最后(0x00 表示空)。
     */
    public static String formatShortcut(byte[] hidBytes) {
        if (hidBytes == null || hidBytes.length == 0) {
            return "未设置";
        }
        List<String> modifiers = new ArrayList<>();
        String base = null;
        for (byte b : hidBytes) {
            int code = b & 0xFF;
            if (code == 0) {
                continue;
            }
            if (code >= 0xE0 && code <= 0xE7) {
                modifiers.add(HIDUsage.getName(code));
            } else {
                // 第一个非修饰键作为基础键
                if (base == null) {
                    base = HIDUsage.getName(code);
                }
            }
        }
        if (modifiers.isEmpty() && base == null) {
            return "未设置";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < modifiers.size(); i++) {
            if (i > 0) sb.append("+");
            sb.append(modifiers.get(i));
        }
        if (base != null) {
            if (sb.length() > 0) sb.append("+");
            sb.append(base);
        }
        return sb.toString();
    }

    /**
     * 把宏 bytes 解析为 "↓Q 释放 ↑Q +30ms" 形式的描述。
     * 宏格式:每 2 字节一步 [action, param]。action:0x01=DOWN_KEY,0x02=UP_KEY,0x03=DELAY。
     */
    public static String formatMacro(byte[] hidBytes) {
        if (hidBytes == null || hidBytes.length < 2) {
            return "宏(空)";
        }
        List<String> steps = new ArrayList<>();
        for (int i = 0; i + 1 < hidBytes.length; i += 2) {
            int action = hidBytes[i] & 0xFF;
            int param = hidBytes[i + 1] & 0xFF;
            switch (action) {
                case 0x01 -> steps.add("↓" + HIDUsage.getName(param));
                case 0x02 -> steps.add("↑" + HIDUsage.getName(param));
                case 0x03 -> steps.add("+" + (param * 3) + "ms");
                default -> steps.add("·0x" + String.format("%02X", action));
            }
        }
        if (steps.isEmpty()) {
            return "宏(空)";
        }
        return "宏(" + String.join(" ", steps) + ")";
    }
}
