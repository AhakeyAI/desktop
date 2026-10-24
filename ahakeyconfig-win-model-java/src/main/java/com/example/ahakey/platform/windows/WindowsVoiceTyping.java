package com.example.ahakey.platform.windows;

import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinUser;

/** 通过 SendInput 触发 Windows 语音输入快捷键 Win+H。 */
public final class WindowsVoiceTyping {
    private static final int VK_LWIN = 0x5B;
    private static final int VK_H = 0x48;

    private WindowsVoiceTyping() {
    }

    public static boolean isWindows() {
        String os = System.getProperty("os.name", "");
        return os.toLowerCase().contains("win");
    }

    public static void trigger() {
        if (!isWindows()) {
            return;
        }
        WinUser.INPUT[] inputs = (WinUser.INPUT[]) new WinUser.INPUT().toArray(4);
        fillKey(inputs[0], VK_LWIN, false);
        fillKey(inputs[1], VK_H, false);
        fillKey(inputs[2], VK_H, true);
        fillKey(inputs[3], VK_LWIN, true);
        User32.INSTANCE.SendInput(new WinUser.DWORD(inputs.length), inputs, inputs[0].size());
    }

    private static void fillKey(WinUser.INPUT input, int vk, boolean keyUp) {
        input.type = new WinUser.DWORD(WinUser.INPUT.INPUT_KEYBOARD);
        input.input.setType("ki");
        input.input.ki.wVk = new WinUser.WORD(vk);
        input.input.ki.dwFlags = new WinUser.DWORD(keyUp ? 0x0002 : 0);
    }
}
