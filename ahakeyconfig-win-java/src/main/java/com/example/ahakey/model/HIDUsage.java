package com.example.ahakey.model;

import java.util.HashMap;
import java.util.Map;

public class HIDUsage {
    // 修饰键
    public static final int LEFT_CONTROL = 0xE0;
    public static final int LEFT_SHIFT = 0xE1;
    public static final int LEFT_ALT = 0xE2;
    public static final int LEFT_GUI = 0xE3;
    public static final int RIGHT_CONTROL = 0xE4;
    public static final int RIGHT_SHIFT = 0xE5;
    public static final int RIGHT_ALT = 0xE6;
    public static final int RIGHT_GUI = 0xE7;
    
    // 功能键
    public static final int F1 = 0x3A;
    public static final int F2 = 0x3B;
    public static final int F3 = 0x3C;
    public static final int F4 = 0x3D;
    public static final int F5 = 0x3E;
    public static final int F6 = 0x3F;
    public static final int F7 = 0x40;
    public static final int F8 = 0x41;
    public static final int F9 = 0x42;
    public static final int F10 = 0x43;
    public static final int F11 = 0x44;
    public static final int F12 = 0x45;
    public static final int F13 = 0x68;
    public static final int F14 = 0x69;
    public static final int F15 = 0x6A;
    public static final int F16 = 0x6B;
    public static final int F17 = 0x6C;
    public static final int F18 = 0x6D;
    public static final int F19 = 0x6E;
    public static final int F20 = 0x6F;
    public static final int F21 = 0x70;
    public static final int F22 = 0x71;
    public static final int F23 = 0x72;
    public static final int F24 = 0x73;
    
    // 基础键
    public static final int ENTER = 0x28;
    public static final int ESCAPE = 0x29;
    public static final int BACKSPACE = 0x2A;
    public static final int TAB = 0x2B;
    public static final int SPACE = 0x2C;
    public static final int MINUS = 0x2D;
    public static final int EQUAL = 0x2E;
    public static final int LEFT_BRACKET = 0x2F;
    public static final int RIGHT_BRACKET = 0x30;
    public static final int BACKSLASH = 0x31;
    public static final int SEMICOLON = 0x33;
    public static final int QUOTE = 0x34;
    public static final int GRAVE = 0x35;
    public static final int COMMA = 0x36;
    public static final int PERIOD = 0x37;
    public static final int SLASH = 0x38;
    public static final int CAPS_LOCK = 0x39;
    
    // 控制键
    public static final int PRINT_SCREEN = 0x46;
    public static final int SCROLL_LOCK = 0x47;
    public static final int PAUSE = 0x48;
    public static final int INSERT = 0x49;
    public static final int HOME = 0x4A;
    public static final int PAGE_UP = 0x4B;
    public static final int DELETE_FORWARD = 0x4C;
    public static final int END = 0x4D;
    public static final int PAGE_DOWN = 0x4E;
    
    // 方向键
    public static final int RIGHT_ARROW = 0x4F;
    public static final int LEFT_ARROW = 0x50;
    public static final int DOWN_ARROW = 0x51;
    public static final int UP_ARROW = 0x52;
    
    // 小键盘
    public static final int NUM_LOCK = 0x53;
    public static final int KP_SLASH = 0x54;
    public static final int KP_ASTERISK = 0x55;
    public static final int KP_MINUS = 0x56;
    public static final int KP_PLUS = 0x57;
    public static final int KP_ENTER = 0x58;
    public static final int KP_1 = 0x59;
    public static final int KP_2 = 0x5A;
    public static final int KP_3 = 0x5B;
    public static final int KP_4 = 0x5C;
    public static final int KP_5 = 0x5D;
    public static final int KP_6 = 0x5E;
    public static final int KP_7 = 0x5F;
    public static final int KP_8 = 0x60;
    public static final int KP_9 = 0x61;
    public static final int KP_0 = 0x62;
    public static final int KP_PERIOD = 0x63;
    
    private static final Map<Integer, String> codeToName = new HashMap<>();
    
    static {
        // 功能键
        codeToName.put(F1, "F1");
        codeToName.put(F2, "F2");
        codeToName.put(F3, "F3");
        codeToName.put(F4, "F4");
        codeToName.put(F5, "F5");
        codeToName.put(F6, "F6");
        codeToName.put(F7, "F7");
        codeToName.put(F8, "F8");
        codeToName.put(F9, "F9");
        codeToName.put(F10, "F10");
        codeToName.put(F11, "F11");
        codeToName.put(F12, "F12");
        codeToName.put(F13, "F13");
        codeToName.put(F14, "F14");
        codeToName.put(F15, "F15");
        codeToName.put(F16, "F16");
        codeToName.put(F17, "F17");
        codeToName.put(F18, "F18");
        codeToName.put(F19, "F19");
        codeToName.put(F20, "F20");
        codeToName.put(F21, "F21");
        codeToName.put(F22, "F22");
        codeToName.put(F23, "F23");
        codeToName.put(F24, "F24");
        
        // 基础键
        codeToName.put(ENTER, "Enter");
        codeToName.put(ESCAPE, "Escape");
        codeToName.put(BACKSPACE, "Backspace");
        codeToName.put(TAB, "Tab");
        codeToName.put(SPACE, "Space");
        codeToName.put(MINUS, "Minus");
        codeToName.put(EQUAL, "Equal");
        codeToName.put(LEFT_BRACKET, "Left Bracket");
        codeToName.put(RIGHT_BRACKET, "Right Bracket");
        codeToName.put(BACKSLASH, "Backslash");
        codeToName.put(SEMICOLON, "Semicolon");
        codeToName.put(QUOTE, "Quote");
        codeToName.put(GRAVE, "Grave");
        codeToName.put(COMMA, "Comma");
        codeToName.put(PERIOD, "Period");
        codeToName.put(SLASH, "Slash");
        codeToName.put(CAPS_LOCK, "Caps Lock");
        
        // 控制键
        codeToName.put(PRINT_SCREEN, "Print Screen");
        codeToName.put(SCROLL_LOCK, "Scroll Lock");
        codeToName.put(PAUSE, "Pause");
        codeToName.put(INSERT, "Insert");
        codeToName.put(HOME, "Home");
        codeToName.put(PAGE_UP, "Page Up");
        codeToName.put(DELETE_FORWARD, "Delete");
        codeToName.put(END, "End");
        codeToName.put(PAGE_DOWN, "Page Down");
        
        // 方向键
        codeToName.put(RIGHT_ARROW, "Right");
        codeToName.put(LEFT_ARROW, "Left");
        codeToName.put(DOWN_ARROW, "Down");
        codeToName.put(UP_ARROW, "Up");
        
        // 小键盘
        codeToName.put(NUM_LOCK, "Num Lock");
        codeToName.put(KP_SLASH, "KP /");
        codeToName.put(KP_ASTERISK, "KP *");
        codeToName.put(KP_MINUS, "KP -");
        codeToName.put(KP_PLUS, "KP +");
        codeToName.put(KP_ENTER, "KP Enter");
        codeToName.put(KP_1, "KP 1");
        codeToName.put(KP_2, "KP 2");
        codeToName.put(KP_3, "KP 3");
        codeToName.put(KP_4, "KP 4");
        codeToName.put(KP_5, "KP 5");
        codeToName.put(KP_6, "KP 6");
        codeToName.put(KP_7, "KP 7");
        codeToName.put(KP_8, "KP 8");
        codeToName.put(KP_9, "KP 9");
        codeToName.put(KP_0, "KP 0");
        codeToName.put(KP_PERIOD, "KP .");
        
        // 修饰键
        codeToName.put(LEFT_CONTROL, "Left Ctrl");
        codeToName.put(LEFT_SHIFT, "Left Shift");
        codeToName.put(LEFT_ALT, "Left Alt");
        codeToName.put(LEFT_GUI, "Left Win");
        codeToName.put(RIGHT_CONTROL, "Right Ctrl");
        codeToName.put(RIGHT_SHIFT, "Right Shift");
        codeToName.put(RIGHT_ALT, "Right Alt");
        codeToName.put(RIGHT_GUI, "Right Win");
        
        // 字母键
        for (int i = 0; i < 26; i++) {
            codeToName.put(0x04 + i, String.valueOf((char) ('A' + i)));
        }
        
        // 数字键
        for (int i = 0; i < 10; i++) {
            codeToName.put(0x1E + i, String.valueOf(i + 1));
        }
        codeToName.put(0x27, "0");
    }
    
    public static String getName(int code) {
        return codeToName.getOrDefault(code, String.format("0x%02X", code));
    }
    
    public static String[] getAllNames() {
        return codeToName.values().toArray(new String[0]);
    }
    
    public static int getCode(String name) {
        for (Map.Entry<Integer, String> entry : codeToName.entrySet()) {
            if (entry.getValue().equalsIgnoreCase(name)) {
                return entry.getKey();
            }
        }
        return 0;
    }
}