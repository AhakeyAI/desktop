package com.example.ahakey.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.sun.jna.Native;
import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinDef;
import com.sun.jna.platform.win32.WinUser;

/**
 * 键盘注入器
 * 使用 Windows API 模拟键盘输入
 */
public class KeyboardInjector {
    
    private static final Logger logger = LoggerFactory.getLogger(KeyboardInjector.class);
    
    private User32 user32;
    
    // 默认延迟配置（毫秒）
    private static final int POST_RECORD_DELAY = 300;  // 录音停止后等待窗口切换的时间
    private static final int CHAR_DELAY = 20;          // 字符间延迟
    private static final int SPECIAL_KEY_DELAY = 50;   // 特殊键延迟
    
    public KeyboardInjector() {
        user32 = User32.INSTANCE;
    }
    
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
        
        // 保存当前键盘状态（CapsLock、NumLock等）
        boolean originalCapsLock = isKeyPressed(VK_CAPITAL);
        boolean originalNumLock = isKeyPressed(VK_NUMLOCK);
        boolean originalScrollLock = isKeyPressed(VK_SCROLL);
        
        logger.debug("KeyboardInjector - 初始键盘状态: CapsLock={}, NumLock={}, ScrollLock={}", 
                     originalCapsLock, originalNumLock, originalScrollLock);
        
        // 确保 CapsLock 处于关闭状态，避免影响输入
        if (originalCapsLock) {
            toggleCapsLock();
        }
        
        try {
            // 等待目标窗口获得焦点（增加延迟时间，确保窗口切换完成）
            logger.debug("KeyboardInjector - 等待 {}ms 确保窗口焦点", POST_RECORD_DELAY);
            Thread.sleep(POST_RECORD_DELAY);
            
            // 获取当前活动窗口标题，用于调试
            WinDef.HWND foregroundWindow = user32.GetForegroundWindow();
            char[] windowTitle = new char[256];
            user32.GetWindowText(foregroundWindow, windowTitle, 256);
            String activeWindowTitle = Native.toString(windowTitle);
            logger.debug("KeyboardInjector - 当前活动窗口: {}", activeWindowTitle);
            
            // 逐个字符发送
            for (char c : text.toCharArray()) {
                try {
                    // 处理特殊字符
                    if (c == '\n') {
                        // 换行
                        sendKey(VK_RETURN, true);
                        sendKey(VK_RETURN, false);
                        Thread.sleep(SPECIAL_KEY_DELAY);
                    } else if (c == '\t') {
                        // Tab
                        sendKey(VK_TAB, true);
                        sendKey(VK_TAB, false);
                        Thread.sleep(SPECIAL_KEY_DELAY);
                    } else if (c == ' ') {
                        // 空格 - 使用Unicode方式发送，避免Shift状态影响
                        sendUnicodeChar(c);
                        Thread.sleep(CHAR_DELAY);
                    } else if (Character.isUpperCase(c)) {
                        // 大写字母，需要按住 Shift
                        sendKey(VK_SHIFT, true);
                        sendChar(Character.toLowerCase(c));
                        sendKey(VK_SHIFT, false);
                        Thread.sleep(CHAR_DELAY);
                    } else {
                        // 普通字符 - 统一使用Unicode方式发送，确保兼容性
                        sendUnicodeChar(c);
                        Thread.sleep(CHAR_DELAY);
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    logger.error("KeyboardInjector - 字符发送被中断");
                    break;
                }
            }
            
            logger.debug("KeyboardInjector - 文本注入完成");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            logger.error("KeyboardInjector - 等待被中断");
        } finally {
            // 恢复原始键盘状态
            if (originalCapsLock != isKeyPressed(VK_CAPITAL)) {
                toggleCapsLock();
            }
            logger.debug("KeyboardInjector - 已恢复键盘状态");
        }
    }
    
    /**
     * 检查指定键是否被按下
     */
    private boolean isKeyPressed(int vkCode) {
        // 使用 GetAsyncKeyState 替代 GetKeyState，因为 JNA 的 User32 接口可能不直接暴露 GetKeyState
        short result = com.sun.jna.platform.win32.User32.INSTANCE.GetAsyncKeyState(vkCode);
        return (result & 0x8000) != 0;
    }
    
    /**
     * 切换 CapsLock 状态
     */
    private void toggleCapsLock() {
        sendKey(VK_CAPITAL, true);
        sendKey(VK_CAPITAL, false);
        try {
            Thread.sleep(50);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
    
    /**
     * 发送字符
     */
    private void sendChar(char c) {
        // 统一使用 Unicode 方式发送所有字符
        // 这种方式更可靠，避免虚拟键码转换的问题，同时支持中文等非ASCII字符
        sendUnicodeChar(c);
    }
    
    /**
     * 使用 Unicode 方式发送字符（支持中文等非ASCII字符）
     */
    private void sendUnicodeChar(char c) {
        WinUser.INPUT input = new WinUser.INPUT();
        input.type = new WinDef.DWORD(WinUser.INPUT.INPUT_KEYBOARD);
        input.input.setType("ki");
        input.input.ki.wScan = new WinDef.WORD(c); // Unicode 字符
        input.input.ki.dwFlags = new WinDef.DWORD(0x0004); // KEYEVENTF_UNICODE
        
        // 按下
        user32.SendInput(new WinDef.DWORD(1), new WinUser.INPUT[]{input}, input.size());
        
        // 释放
        input.input.ki.dwFlags = new WinDef.DWORD(0x0004 | 0x0002); // KEYEVENTF_UNICODE | KEYEVENTF_KEYUP
        user32.SendInput(new WinDef.DWORD(1), new WinUser.INPUT[]{input}, input.size());
    }
    
    /**
     * 发送按键事件
     */
    private void sendKey(int vkCode, boolean isDown) {
        WinUser.INPUT input = new WinUser.INPUT();
        input.type = new WinDef.DWORD(WinUser.INPUT.INPUT_KEYBOARD);
        input.input.setType("ki");
        input.input.ki.wVk = new WinDef.WORD(vkCode);
        input.input.ki.dwFlags = new WinDef.DWORD(isDown ? 0 : 0x0002); // KEYEVENTF_KEYUP = 0x0002
        
        user32.SendInput(new WinDef.DWORD(1), new WinUser.INPUT[]{input}, input.size());
    }
    
    /**
     * 将字符转换为虚拟键码
     */
    private int charToVkCode(char c) {
        // 小写字母
        if (c >= 'a' && c <= 'z') {
            return c - 'a' + 0x41; // VK_A = 0x41
        }
        // 大写字母（已在调用处处理Shift）
        if (c >= 'A' && c <= 'Z') {
            return c - 'A' + 0x41;
        }
        // 数字
        if (c >= '0' && c <= '9') {
            return c - '0' + 0x30; // VK_0 = 0x30
        }
        // 特殊字符
        switch (c) {
            case '!': return 0x31; // 1 + Shift
            case '@': return 0x32; // 2 + Shift
            case '#': return 0x33; // 3 + Shift
            case '$': return 0x34; // 4 + Shift
            case '%': return 0x35; // 5 + Shift
            case '^': return 0x36; // 6 + Shift
            case '&': return 0x37; // 7 + Shift
            case '*': return 0x38; // 8 + Shift
            case '(': return 0x39; // 9 + Shift
            case ')': return 0x30; // 0 + Shift
            case '-': return VK_OEM_MINUS;
            case '_': return VK_OEM_MINUS; // + Shift
            case '=': return VK_OEM_PLUS;
            case '+': return VK_OEM_PLUS; // + Shift
            case '[': return VK_OEM_4;
            case '{': return VK_OEM_4; // + Shift
            case ']': return VK_OEM_6;
            case '}': return VK_OEM_6; // + Shift
            case '\\': return VK_OEM_5;
            case '|': return VK_OEM_5; // + Shift
            case ';': return VK_OEM_1;
            case ':': return VK_OEM_1; // + Shift
            case '\'': return VK_OEM_7;
            case '"': return VK_OEM_7; // + Shift
            case ',': return VK_OEM_COMMA;
            case '<': return VK_OEM_COMMA; // + Shift
            case '.': return VK_OEM_PERIOD;
            case '>': return VK_OEM_PERIOD; // + Shift
            case '/': return VK_OEM_2;
            case '?': return VK_OEM_2; // + Shift
            default: return 0;
        }
    }
    
    /**
     * 释放资源
     */
    public void release() {
        // JNA 资源由系统自动管理
    }
    
    // Windows 虚拟键码常量
    private static final int VK_SHIFT = 0x10;
    private static final int VK_RETURN = 0x0D;
    private static final int VK_TAB = 0x09;
    private static final int VK_SPACE = 0x20;
    private static final int VK_OEM_MINUS = 0xBD;
    private static final int VK_OEM_PLUS = 0xBB;
    private static final int VK_OEM_1 = 0xBA;
    private static final int VK_OEM_2 = 0xBF;
    private static final int VK_OEM_3 = 0xC0;
    private static final int VK_OEM_4 = 0xDB;
    private static final int VK_OEM_5 = 0xDC;
    private static final int VK_OEM_6 = 0xDD;
    private static final int VK_OEM_7 = 0xDE;
    private static final int VK_OEM_COMMA = 0xBC;
    private static final int VK_OEM_PERIOD = 0xBE;
    private static final int VK_CAPITAL = 0x14;   // CapsLock
    private static final int VK_NUMLOCK = 0x90;   // NumLock
    private static final int VK_SCROLL = 0x91;    // ScrollLock
}
