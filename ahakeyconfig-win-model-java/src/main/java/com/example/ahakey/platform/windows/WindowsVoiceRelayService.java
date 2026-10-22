package com.example.ahakey.platform.windows;

import com.example.ahakey.model.HIDUsage;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.VoicePreset;
import com.sun.jna.Structure;
import com.sun.jna.platform.win32.Kernel32;
import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinDef.LRESULT;
import com.sun.jna.platform.win32.WinDef.LPARAM;
import com.sun.jna.platform.win32.WinDef.WPARAM;
import com.sun.jna.platform.win32.WinUser;

import javafx.application.Platform;
import javafx.beans.property.BooleanProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

import java.util.ArrayList;
import java.util.List;
import java.util.function.IntSupplier;
import java.util.function.Supplier;

/**
 * 对齐 macOS {@code VoiceRelayService} 的 Windows 子集：低级别键盘钩子吞掉 F17/F18，触发 Win+H。
 */
public final class WindowsVoiceRelayService {
    private static final int WH_KEYBOARD_LL = 13;
    private static final int WM_KEYDOWN = 0x0100;
    private static final int WM_KEYUP = 0x0101;
    private static final int VK_F17 = 0x80;
    private static final int VK_F18 = 0x81;

    private static WindowsVoiceRelayService instance;

    private final BooleanProperty listening = new SimpleBooleanProperty(false);
    private final StringProperty statusMessage = new SimpleStringProperty("语音桥尚未启动。");
    private final StringProperty activeRouteSummary = new SimpleStringProperty("未配置路由。");
    private final StringProperty lastSimulateHint = new SimpleStringProperty(null);

    private WinUser.HHOOK hookHandle;
    private WinUser.LowLevelKeyboardProc hookProc;
    private Thread messagePump;
    private volatile int hookThreadId;
    private Supplier<StudioState> studioStateSupplier = () -> null;
    private IntSupplier workModeSupplier = () -> 0;
    private Runnable onVoiceKeyDown;
    private Runnable onVoiceKeyUp;
    private Runnable onSimulateRecordStart;
    private Runnable onSimulateRecordStop;

    private record VoiceRoute(int vkCode, ModeSlot mode, boolean factoryFallback) {
    }

    private final List<VoiceRoute> routes = new ArrayList<>();

    public static synchronized WindowsVoiceRelayService getInstance() {
        if (instance == null) {
            instance = new WindowsVoiceRelayService();
        }
        return instance;
    }

    public BooleanProperty listeningProperty() {
        return listening;
    }

    public StringProperty statusMessageProperty() {
        return statusMessage;
    }

    public StringProperty activeRouteSummaryProperty() {
        return activeRouteSummary;
    }

    public StringProperty lastSimulateHintProperty() {
        return lastSimulateHint;
    }

    public void configure(Supplier<StudioState> studioState, IntSupplier workMode) {
        this.studioStateSupplier = studioState;
        this.workModeSupplier = workMode;
    }
    
    /**
     * 设置语音键按下时的回调
     */
    public void setOnVoiceKeyDown(Runnable callback) {
        this.onVoiceKeyDown = callback;
    }
    
    /**
     * 设置语音键释放时的回调
     */
    public void setOnVoiceKeyUp(Runnable callback) {
        this.onVoiceKeyUp = callback;
    }
    
    /**
     * 设置模拟录音开始的回调（用于模拟按钮直接触发录音）
     */
    public void setOnSimulateRecordStart(Runnable callback) {
        this.onSimulateRecordStart = callback;
    }
    
    /**
     * 设置模拟录音停止的回调（用于模拟按钮直接停止录音）
     */
    public void setOnSimulateRecordStop(Runnable callback) {
        this.onSimulateRecordStop = callback;
    }

    public void updateRoutes(StudioState state) {
        routes.clear();
        if (state == null) {
            activeRouteSummary.set("未配置路由。");
            return;
        }
        for (ModeSlot mode : ModeSlot.values()) {
            var key = state.getKeyConfig(mode, StudioPart.KEY1);
            VoicePreset preset = key.getVoicePreset();
            
            // 只处理支持的语音预设：Windows 原生、macOS 原生、自定义
            if (preset != VoicePreset.WINDOWS_NATIVE && 
                preset != VoicePreset.MACOS_NATIVE && 
                preset != VoicePreset.CUSTOM) {
                continue;
            }
            
            int vk = hidToVk(key.getHidCode());
            if (vk <= 0) {
                continue;
            }
            routes.add(new VoiceRoute(vk, mode, false));
            if (mode == ModeSlot.MODE0 && vk != VK_F18) {
                routes.add(new VoiceRoute(VK_F18, ModeSlot.MODE0, true));
            }
        }
        if (routes.isEmpty()) {
            activeRouteSummary.set("未启用 Windows 语音路由（Key1 需选 Win+H 预设）。");
        } else {
            StringBuilder sb = new StringBuilder();
            for (VoiceRoute r : routes) {
                if (!sb.isEmpty()) {
                    sb.append(" · ");
                }
                sb.append(r.mode.getShortName()).append(" VK=").append(String.format("0x%02X", r.vkCode));
            }
            activeRouteSummary.set(sb.toString());
        }
        refreshStatus();
    }

    public void start() {
        if (!WindowsVoiceTyping.isWindows()) {
            statusMessage.set("当前系统不是 Windows，语音桥未启动。");
            return;
        }
        if (messagePump != null && messagePump.isAlive()) {
            listening.set(true);
            return;
        }
        hookProc = (code, wParam, event) -> {
            if (code >= 0 && hookHandle != null) {
                event.read();
                LRESULT handled = handleHookEvent(wParam.intValue(), event);
                if (handled != null) {
                    return handled;
                }
            }
            return User32.INSTANCE.CallNextHookEx(
                hookHandle,
                code,
                wParam,
                new LPARAM(com.sun.jna.Pointer.nativeValue(event.getPointer()))
            );
        };
        messagePump = new Thread(this::messageLoop, "win-voice-hook-pump");
        messagePump.setDaemon(true);
        messagePump.start();
    }

    public void stop() {
        if (hookThreadId != 0) {
            User32.INSTANCE.PostThreadMessage(hookThreadId, WinUser.WM_QUIT, new WPARAM(0), new LPARAM(0));
        }
        if (messagePump != null) {
            messagePump.interrupt();
            messagePump = null;
        }
        hookHandle = null;
        hookThreadId = 0;
        listening.set(false);
        statusMessage.set("语音桥已停止。");
    }

    public void simulateVoiceKeyTap(ModeSlot mode) {
        VoiceRoute route = routes.stream().filter(r -> r.mode == mode && !r.factoryFallback).findFirst()
            .orElse(routes.stream().filter(r -> r.mode == mode).findFirst().orElse(null));
        if (route == null) {
            // 检查是否是 macOS 原生语音模式（使用 F18）
            lastSimulateHint.set("当前 Mode 没有 Win+H 语音路由。");
            return;
        }
        WindowsVoiceTyping.trigger();
        lastSimulateHint.set("已模拟 Win+H（" + mode.getShortName() + "）");
    }
    
    /**
     * 根据语音预设模拟按键
     */
    public void simulateVoiceKeyTap(ModeSlot mode, VoicePreset preset) {
        switch (preset) {
            case WINDOWS_NATIVE:
                // 使用 Win+H
                simulateVoiceKeyTap(mode);
                break;
            case MACOS_NATIVE:
                // 对于本地模型，直接触发录音回调（模拟的按键不会被键盘钩子捕获）
                if (onSimulateRecordStart != null) {
                    onSimulateRecordStart.run();
                    // 延迟一段时间后自动停止录音
                    new Thread(() -> {
                        try {
                            Thread.sleep(3); // 录制3秒
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                        if (onSimulateRecordStop != null) {
                            onSimulateRecordStop.run();
                        }
                    }).start();
                    lastSimulateHint.set("已开始录音（模拟 F18，录制3秒）");
                } else {
                    // 如果没有设置回调，尝试模拟按键
                    simulateF18Key();
                    lastSimulateHint.set("已模拟 F18（" + mode.getShortName() + "）");
                }
                break;
            default:
                lastSimulateHint.set("当前语音预设不支持模拟。");
        }
    }
    
    /**
     * 模拟按下 F18 键
     */
    /**
     * 根据 HID 组合键码模拟一次按键（修饰键在高位 0x100-0x8000，基础键在低位）
     */
    public void simulateKeyByHid(int hidCode) {
        if (hidCode == 0) {
            lastSimulateHint.set("未设置按键，无法模拟。");
            return;
        }
        java.util.List<Integer> modVks = new java.util.ArrayList<>();
        // Left 修饰键
        if ((hidCode & 0x100) != 0) modVks.add(0x10);  // VK_SHIFT
        if ((hidCode & 0x200) != 0) modVks.add(0x11);  // VK_CONTROL
        if ((hidCode & 0x400) != 0) modVks.add(0x12);  // VK_MENU (Alt)
        if ((hidCode & 0x800) != 0) modVks.add(0x5B);  // VK_LWIN
        // Right 修饰键
        if ((hidCode & 0x1000) != 0) modVks.add(0xA1); // VK_RSHIFT
        if ((hidCode & 0x2000) != 0) modVks.add(0xA3); // VK_RCONTROL
        if ((hidCode & 0x4000) != 0) modVks.add(0xA5); // VK_RMENU
        if ((hidCode & 0x8000) != 0) modVks.add(0x5C); // VK_RWIN

        int baseHid = hidCode & 0xFF;
        int baseVk = hidBaseToVk(baseHid);
        if (baseVk < 0 && modVks.isEmpty()) {
            lastSimulateHint.set("无法识别 HID 0x" + String.format("%02X", baseHid) + " 对应的虚拟键码。");
            return;
        }

        int total = modVks.size() * 2 + (baseVk >= 0 ? 2 : 0);
        WinUser.INPUT[] inputs = (WinUser.INPUT[]) new WinUser.INPUT().toArray(total);
        int idx = 0;
        // modifiers down
        for (int vk : modVks) { fillKey(inputs[idx++], vk, false); }
        // base key down + up
        if (baseVk >= 0) { fillKey(inputs[idx++], baseVk, false); fillKey(inputs[idx++], baseVk, true); }
        // modifiers up (reverse)
        for (int i = modVks.size() - 1; i >= 0; i--) { fillKey(inputs[idx++], modVks.get(i), true); }

        User32.INSTANCE.SendInput(new WinUser.DWORD(total), inputs, inputs[0].size());
        String desc = com.example.ahakey.model.HIDUsage.getName(baseHid);
        if (!modVks.isEmpty()) {
            java.util.List<String> names = new java.util.ArrayList<>();
            if ((hidCode & 0x100) != 0) names.add("LShift");
            if ((hidCode & 0x1000) != 0) names.add("RShift");
            if ((hidCode & 0x200) != 0) names.add("LCtrl");
            if ((hidCode & 0x2000) != 0) names.add("RCtrl");
            if ((hidCode & 0x400) != 0) names.add("LAlt");
            if ((hidCode & 0x4000) != 0) names.add("RAlt");
            if ((hidCode & 0x800) != 0) names.add("LWin");
            if ((hidCode & 0x8000) != 0) names.add("RWin");
            desc = String.join("+", names) + "+" + desc;
        }
        lastSimulateHint.set("已模拟 " + desc);
    }

    private static int hidBaseToVk(int hid) {
        // 字母 A(0x04)–Z(0x1D) → VK 0x41–0x5A
        if (hid >= 0x04 && hid <= 0x1D) return 0x41 + (hid - 0x04);
        // 数字 1(0x1E)–9(0x26) → VK 0x31–0x39; 0(0x27) → 0x30
        if (hid >= 0x1E && hid <= 0x26) return 0x31 + (hid - 0x1E);
        if (hid == 0x27) return 0x30;
        // 基础键
        return switch (hid) {
            case 0x28 -> 0x0D;  // Enter
            case 0x29 -> 0x1B;  // Escape
            case 0x2A -> 0x08;  // Backspace
            case 0x2B -> 0x09;  // Tab
            case 0x2C -> 0x20;  // Space
            case 0x2D -> 0xBD;  // Minus  (VK_OEM_MINUS)
            case 0x2E -> 0xBB;  // Equal  (VK_OEM_PLUS)
            case 0x2F -> 0xDB;  // [      (VK_OEM_4)
            case 0x30 -> 0xDD;  // ]      (VK_OEM_6)
            case 0x31 -> 0xDC;  // \      (VK_OEM_5)
            case 0x33 -> 0xBA;  // ;      (VK_OEM_1)
            case 0x34 -> 0xDE;  // '      (VK_OEM_7)
            case 0x35 -> 0xC0;  // `      (VK_OEM_3)
            case 0x36 -> 0xBC;  // ,      (VK_OEM_COMMA)
            case 0x37 -> 0xBE;  // .      (VK_OEM_PERIOD)
            case 0x38 -> 0xBF;  // /      (VK_OEM_2)
            case 0x39 -> 0x14;  // Caps Lock
            // F1–F12
            case 0x3A -> 0x70; case 0x3B -> 0x71; case 0x3C -> 0x72;
            case 0x3D -> 0x73; case 0x3E -> 0x74; case 0x3F -> 0x75;
            case 0x40 -> 0x76; case 0x41 -> 0x77; case 0x42 -> 0x78;
            case 0x43 -> 0x79; case 0x44 -> 0x7A; case 0x45 -> 0x7B;
            // 控制键
            case 0x46 -> 0x2C;  // Print Screen (VK_SNAPSHOT)
            case 0x47 -> 0x91;  // Scroll Lock
            case 0x48 -> 0x13;  // Pause
            case 0x49 -> 0x2D;  // Insert
            case 0x4A -> 0x24;  // Home
            case 0x4B -> 0x21;  // Page Up
            case 0x4C -> 0x2E;  // Delete
            case 0x4D -> 0x23;  // End
            case 0x4E -> 0x22;  // Page Down
            // 方向键
            case 0x4F -> 0x27;  // Right
            case 0x50 -> 0x25;  // Left
            case 0x51 -> 0x28;  // Down
            case 0x52 -> 0x26;  // Up
            // 小键盘
            case 0x53 -> 0x90;  // Num Lock
            case 0x54 -> 0x6F;  // KP /
            case 0x55 -> 0x6A;  // KP *
            case 0x56 -> 0x6D;  // KP -
            case 0x57 -> 0x6B;  // KP +
            case 0x58 -> 0x0D;  // KP Enter
            case 0x59 -> 0x61; case 0x5A -> 0x62; case 0x5B -> 0x63;
            case 0x5C -> 0x64; case 0x5D -> 0x65; case 0x5E -> 0x66;
            case 0x5F -> 0x67; case 0x60 -> 0x68; case 0x61 -> 0x69;
            case 0x62 -> 0x60;  // KP 0
            case 0x63 -> 0x6E;  // KP .
            // F13–F24
            case 0x68 -> 0x7C; case 0x69 -> 0x7D; case 0x6A -> 0x7E;
            case 0x6B -> 0x7F; case 0x6C -> 0x80; case 0x6D -> 0x81;
            case 0x6E -> 0x82; case 0x6F -> 0x83; case 0x70 -> 0x84;
            case 0x71 -> 0x85; case 0x72 -> 0x86; case 0x73 -> 0x87;
            default -> -1;
        };
    }

    private void simulateF18Key() {
        // F18 的虚拟键码是 0x87
        int VK_F18 = 0x87;
        WinUser.INPUT[] inputs = (WinUser.INPUT[]) new WinUser.INPUT().toArray(2);
        fillKey(inputs[0], VK_F18, false);
        fillKey(inputs[1], VK_F18, true);
        User32.INSTANCE.SendInput(new WinUser.DWORD(inputs.length), inputs, inputs[0].size());
    }
    
    /**
     * 填充按键输入结构
     */
    private void fillKey(WinUser.INPUT input, int vk, boolean keyUp) {
        input.type = new WinUser.DWORD(WinUser.INPUT.INPUT_KEYBOARD);
        input.input.setType("ki");
        input.input.ki.wVk = new WinUser.WORD(vk);
        input.input.ki.dwFlags = new WinUser.DWORD(keyUp ? 0x0002 : 0);
    }

    private void messageLoop() {
        hookThreadId = Kernel32.INSTANCE.GetCurrentThreadId();
        hookHandle = User32.INSTANCE.SetWindowsHookEx(
            WH_KEYBOARD_LL,
            hookProc,
            Kernel32.INSTANCE.GetModuleHandle("user32.dll"),
            0
        );
        if (hookHandle == null) {
            Platform.runLater(() -> {
                statusMessage.set("安装键盘钩子失败；请检查安全软件或以管理员重试。");
                listening.set(false);
            });
            return;
        }
        Platform.runLater(() -> {
            listening.set(true);
            refreshStatus();
        });
        WinUser.MSG msg = new WinUser.MSG();
        while (!Thread.currentThread().isInterrupted()) {
            int r = User32.INSTANCE.GetMessage(msg, null, 0, 0);
            if (r == 0 || r == -1) {
                break;
            }
            User32.INSTANCE.TranslateMessage(msg);
            User32.INSTANCE.DispatchMessage(msg);
        }
        if (hookHandle != null) {
            User32.INSTANCE.UnhookWindowsHookEx(hookHandle);
            hookHandle = null;
        }
    }

    private LRESULT handleHookEvent(int message, WinUser.KBDLLHOOKSTRUCT evt) {
        int vk = evt.vkCode;
        VoiceRoute route = matchRoute(vk);
        if (route == null) {
            return null;
        }
        int upFlag = 0x0080;
        if ((evt.flags & upFlag) != 0) {
            // 按键释放
            if (message == WM_KEYUP && onVoiceKeyUp != null) {
                onVoiceKeyUp.run();
            }
            return new LRESULT(1);
        }
        if ((evt.flags & 0x40000000) != 0) {
            return new LRESULT(1);
        }
        if (message == WM_KEYDOWN) {
            // 按键按下
            // 添加防抖检查，避免重复触发
            if (onVoiceKeyDown != null) {
                onVoiceKeyDown.run();
            } else {
                // 如果没有设置自定义回调，使用默认行为（发送 Win+H）
                WindowsVoiceTyping.trigger();
            }
        }
        return new LRESULT(1);
    }

    private VoiceRoute matchRoute(int vkCode) {
        int workMode = workModeSupplier.getAsInt();
        ModeSlot active = ModeSlot.fromIndex(workMode);
        VoiceRoute preferred = null;
        VoiceRoute fallback = null;
        for (VoiceRoute route : routes) {
            if (route.vkCode != vkCode) {
                continue;
            }
            if (route.mode == active && !route.factoryFallback) {
                preferred = route;
            }
            if (route.mode == active && route.factoryFallback) {
                fallback = route;
            }
        }
        if (preferred != null) {
            return preferred;
        }
        if (fallback != null) {
            return fallback;
        }
        return routes.stream().filter(r -> r.vkCode == vkCode).findFirst().orElse(null);
    }

    private void refreshStatus() {
        if (!WindowsVoiceTyping.isWindows()) {
            statusMessage.set("非 Windows 平台。");
            return;
        }
        if (hookHandle == null) {
            statusMessage.set("语音桥未运行；进入编辑配置或启动应用后会自动安装钩子。");
            return;
        }
        statusMessage.set("正在监听 F17/F18 语音键，匹配后发送 Win+H（路由 " + routes.size() + " 条）。");
    }

    private static int hidToVk(int hid) {
        if (hid == HIDUsage.F17) {
            return VK_F17;
        }
        if (hid == HIDUsage.F18) {
            return VK_F18;
        }
        return -1;
    }
}
