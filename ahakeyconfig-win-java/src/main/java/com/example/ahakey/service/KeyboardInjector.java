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
                    } else {
                        // Unicode injection is independent of CapsLock/Shift.
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
        }
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
     * 释放资源
     */
    public void release() {
        // JNA 资源由系统自动管理
    }
    
    // Windows 虚拟键码常量
    private static final int VK_RETURN = 0x0D;
    private static final int VK_TAB = 0x09;
}
