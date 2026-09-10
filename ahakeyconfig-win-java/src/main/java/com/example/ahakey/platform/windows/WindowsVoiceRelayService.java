package com.example.ahakey.platform.windows;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.VoicePreset;
import com.example.ahakey.firmware.FirmwareCapabilities;
import com.example.ahakey.update.SemanticVersion;
import com.example.ahakey.platform.voice.VoiceAction;
import com.example.ahakey.platform.voice.VoiceActionRouter;
import com.example.ahakey.platform.voice.VoiceButtonEvent;
import com.example.ahakey.platform.voice.VoiceButtonStateMachine;
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

import java.util.function.IntSupplier;
import java.util.function.Supplier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/**
 * Windows voice adapter: consumes the physical F18 HID key and routes
 * short/long semantic events to Desktop actions.
 */
public final class WindowsVoiceRelayService {
    /** Keys held by an in-app test; never includes the physical keyboard. */
    private final java.util.Set<Integer> simulatedKeysDown =
        java.util.Collections.synchronizedSet(new java.util.LinkedHashSet<>());
    private static final int WH_KEYBOARD_LL = 13;
    private static final int WM_KEYDOWN = 0x0100;
    private static final int WM_KEYUP = 0x0101;
    private static final int WM_SYSKEYDOWN = 0x0104;
    private static final int WM_SYSKEYUP = 0x0105;
    public static final int VK_F18 = 0x81;
    private final VoiceKeyPressState pressedVoiceKeys = new VoiceKeyPressState();
    private final ExecutorService voiceCommandQueue = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "win-voice-command");
        thread.setDaemon(true);
        return thread;
    });
    private final ScheduledExecutorService voiceThresholdScheduler =
        Executors.newSingleThreadScheduledExecutor(r -> {
            Thread thread = new Thread(r, "win-voice-threshold");
            thread.setDaemon(true);
            return thread;
        });
    private final VoiceActionRouter actionRouter = new VoiceActionRouter();
    private volatile VoiceButtonStateMachine buttonStateMachine = new VoiceButtonStateMachine();
    private volatile int configuredThresholdMs = 350;
    private volatile ScheduledFuture<?> thresholdTask;
    private long pressGeneration;
    private volatile SemanticVersion firmwareVersion;
    private volatile boolean rawF18RoutingEnabled;
    private volatile boolean ahaKeyVoiceAvailable;

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
    private Consumer<VoiceButtonEvent> onVoiceAction;

    private WindowsVoiceRelayService() {
        actionRouter.setExecutor(VoiceAction.SYSTEM_VOICE, event -> {
            if (event.type() == VoiceButtonEvent.Type.SHORT_PRESS
                || event.type() == VoiceButtonEvent.Type.LONG_PRESS_START) {
                WindowsVoiceTyping.trigger();
            }
        });
        actionRouter.setExecutor(VoiceAction.AHAKEY_VOICE, event -> {
            if (event.type() != VoiceButtonEvent.Type.LONG_PRESS_START
                && event.type() != VoiceButtonEvent.Type.LONG_PRESS_END) {
                return;
            }
            Consumer<VoiceButtonEvent> callback = onVoiceAction;
            if (ahaKeyVoiceAvailable && callback != null) {
                callback.accept(event);
                // The callback can discover that the model stopped between
                // queueing and execution.  Re-check availability before
                // treating the event as handled; a failed START must still
                // take the visible Windows fallback below.
                if (ahaKeyVoiceAvailable) {
                    if (event.type() == VoiceButtonEvent.Type.LONG_PRESS_START
                        && onVoiceKeyDown != null) {
                        onVoiceKeyDown.run();
                    } else if (event.type() == VoiceButtonEvent.Type.LONG_PRESS_END
                        && onVoiceKeyUp != null) {
                        onVoiceKeyUp.run();
                    }
                    return;
                }
            }
            // A local model that is disabled, not activated, or failed to
            // initialize must not disappear as a silent no-op.  The safe
            // configured fallback is the one-shot Windows voice action.
            if (event.type() == VoiceButtonEvent.Type.LONG_PRESS_START) {
                statusMessage.set("AhaKey 本地语音当前不可用，已回退 Windows 语音（Win+H）。");
                WindowsVoiceTyping.trigger();
            }
        });
        actionRouter.setExecutor(VoiceAction.CUSTOM_SHORTCUT, event -> {
            if (event.type() == VoiceButtonEvent.Type.SHORT_PRESS
                || event.type() == VoiceButtonEvent.Type.LONG_PRESS_START) {
                statusMessage.set("自定义快捷键尚未实现，已回退 Windows 语音（Win+H）。");
                WindowsVoiceTyping.trigger();
            }
        });
    }

    private record VoiceRoute(int vkCode, ModeSlot mode, boolean factoryFallback) {
    }

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

    /** Installs desktop action semantics for the physical F18 key. */
    public synchronized void configureVoiceActions(
        VoiceAction shortAction, VoiceAction longAction, int thresholdMs
    ) {
        actionRouter.setActions(shortAction, longAction);
        buttonStateMachine = new VoiceButtonStateMachine(thresholdMs);
        configuredThresholdMs = thresholdMs;
        pressGeneration++;
        cancelThresholdTask();
        activeRouteSummary.set("固定 F18（短按=" + shortAction + "，长按=" + longAction
            + "，阈值=" + thresholdMs + "ms）");
        refreshStatus();
    }

    public void setOnVoiceAction(Consumer<VoiceButtonEvent> callback) {
        this.onVoiceAction = callback;
    }

    /** Enables local push-to-talk only while VoiceInputManager is active. */
    public void setAhaKeyVoiceAvailable(boolean available) {
        this.ahaKeyVoiceAvailable = available;
        refreshStatus();
    }

    public boolean isAhaKeyVoiceAvailable() {
        return ahaKeyVoiceAvailable;
    }

    /**
     * Updates the version learned from the existing 0x9F query. Unknown or
     * older firmware leaves the raw F18 route disabled and is passed through
     * to the firmware's legacy behavior.
     */
    public synchronized void setFirmwareVersion(SemanticVersion version) {
        firmwareVersion = version;
        rawF18RoutingEnabled = FirmwareCapabilities.supportsRawF18DesktopRouting(version);
        if (!rawF18RoutingEnabled) {
            pressedVoiceKeys.clear();
            cancelThresholdTask();
            buttonStateMachine.reset();
            pressGeneration++;
        }
        refreshStatus();
    }

    public SemanticVersion getFirmwareVersion() {
        return firmwareVersion;
    }

    public boolean isRawF18RoutingEnabled() {
        return rawF18RoutingEnabled;
    }

    public void updateRoutes(StudioState state) {
        if (state == null) {
            activeRouteSummary.set("未配置路由。");
            return;
        }
        configureVoiceActions(state.getVoiceShortAction(), state.getVoiceLongAction(),
            state.getVoiceThresholdMs());
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
        pressedVoiceKeys.clear();
        synchronized (this) {
            cancelThresholdTask();
            buttonStateMachine.reset();
            pressGeneration++;
        }
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
        WindowsVoiceTyping.trigger();
        lastSimulateHint.set("已模拟 Windows 语音（" + mode.getShortName() + "，物理 F18）");
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
                            Thread.sleep(3000); // 录制3秒
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                        if (onSimulateRecordStop != null) {
                            onSimulateRecordStop.run();
                        }
                    }).start();
                    lastSimulateHint.set("已开始录音（模拟 F18，录制3秒）");
                } else {
                    lastSimulateHint.set("Windows 不执行 macOS 原生语音，也不会合成 F18。");
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

        int sent = User32.INSTANCE.SendInput(
            new WinUser.DWORD(total), inputs, inputs[0].size()).intValue();
        if (sent != total) {
            forceReleaseVirtualKeys(baseVk, modVks);
            lastSimulateHint.set("Key simulation was incomplete; all keys were released.");
            return;
        }
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

    public void simulateMacro(com.example.ahakey.model.KeyConfig config) {
        if (config == null || !config.usesMacro()) return;
        new Thread(() -> {
            try {
                for (int i = 0; i < config.getMacroStepCount(); i++) {
                    String action = config.getMacroStepAction(i);
                    int value = config.getMacroStepParam(i);
                    if ("DELAY".equals(action)) Thread.sleep(Math.max(0, value * 3L));
                    else if ("DOWN_KEY".equals(action)) sendRawHid(value, false);
                    else if ("UP_KEY".equals(action)) sendRawHid(value, true);
                }
                lastSimulateHint.set("宏按键模拟完成。");
            } catch (Exception e) {
                lastSimulateHint.set("宏按键模拟失败：" + e.getMessage());
            } finally {
                releaseAllSimulatedKeys();
            }
        }, "macro-simulator").start();
    }

    private void sendRawHid(int hidCode, boolean keyUp) {
        int vk = hidBaseToVk(hidCode & 0xFF);
        if (vk < 0) return;
        WinUser.INPUT[] input = (WinUser.INPUT[]) new WinUser.INPUT().toArray(1);
        fillKey(input[0], vk, keyUp);
        int sent = User32.INSTANCE.SendInput(new WinUser.DWORD(1), input, input[0].size()).intValue();
        if (sent == 1) {
            if (keyUp) simulatedKeysDown.remove(vk);
            else simulatedKeysDown.add(vk);
        }
    }

    /** Presses a configured shortcut and keeps it down until releaseKeyByHid. */
    public void pressKeyByHid(int hidCode) {
        if (sendHidState(hidCode, true)) {
            lastSimulateHint.set("模拟按键已按下；松开测试按钮时释放。");
        }
    }

    /** Releases a shortcut previously pressed by pressKeyByHid. */
    public void releaseKeyByHid(int hidCode) {
        if (sendHidState(hidCode, false)) {
            lastSimulateHint.set("模拟按键已释放。");
        }
    }

    private boolean sendHidState(int hidCode, boolean down) {
        if (hidCode == 0) {
            lastSimulateHint.set("未设置按键，无法模拟。");
            return false;
        }
        java.util.List<Integer> modifierVks = new java.util.ArrayList<>();
        if ((hidCode & 0x100) != 0) modifierVks.add(0x10);
        if ((hidCode & 0x200) != 0) modifierVks.add(0x11);
        if ((hidCode & 0x400) != 0) modifierVks.add(0x12);
        if ((hidCode & 0x800) != 0) modifierVks.add(0x5B);
        if ((hidCode & 0x1000) != 0) modifierVks.add(0xA1);
        if ((hidCode & 0x2000) != 0) modifierVks.add(0xA3);
        if ((hidCode & 0x4000) != 0) modifierVks.add(0xA5);
        if ((hidCode & 0x8000) != 0) modifierVks.add(0x5C);
        int baseVk = hidBaseToVk(hidCode & 0xFF);
        int total = modifierVks.size() + (baseVk >= 0 ? 1 : 0);
        if (total == 0) {
            lastSimulateHint.set("无法识别当前按键，无法模拟。");
            return false;
        }
        WinUser.INPUT[] inputs = (WinUser.INPUT[]) new WinUser.INPUT().toArray(total);
        int index = 0;
        if (down) {
            for (int vk : modifierVks) fillKey(inputs[index++], vk, false);
            if (baseVk >= 0) fillKey(inputs[index], baseVk, false);
        } else {
            if (baseVk >= 0) fillKey(inputs[index++], baseVk, true);
            for (int i = modifierVks.size() - 1; i >= 0; i--) {
                fillKey(inputs[index++], modifierVks.get(i), true);
            }
        }
        int sent = User32.INSTANCE.SendInput(
            new WinUser.DWORD(total), inputs, inputs[0].size()).intValue();
        if (sent != total) {
            forceReleaseVirtualKeys(baseVk, modifierVks);
            releaseAllSimulatedKeys();
            lastSimulateHint.set("Key simulation was incomplete; all keys were released.");
            return false;
        }
        if (down) {
            simulatedKeysDown.addAll(modifierVks);
            if (baseVk >= 0) simulatedKeysDown.add(baseVk);
        } else {
            if (baseVk >= 0) simulatedKeysDown.remove(baseVk);
            simulatedKeysDown.removeAll(modifierVks);
        }
        return true;
    }

    /** Safe to invoke repeatedly on focus loss, disconnect, and shutdown. */
    public void releaseAllSimulatedKeys() {
        java.util.List<Integer> keys;
        synchronized (simulatedKeysDown) {
            keys = new java.util.ArrayList<>(simulatedKeysDown);
            simulatedKeysDown.clear();
        }
        for (int i = keys.size() - 1; i >= 0; i--) sendVirtualKeyUp(keys.get(i));
    }

    private void forceReleaseVirtualKeys(int baseVk, java.util.List<Integer> modifiers) {
        if (baseVk >= 0) sendVirtualKeyUp(baseVk);
        for (int i = modifiers.size() - 1; i >= 0; i--) sendVirtualKeyUp(modifiers.get(i));
        if (baseVk >= 0) simulatedKeysDown.remove(baseVk);
        simulatedKeysDown.removeAll(modifiers);
    }

    private void sendVirtualKeyUp(int vk) {
        WinUser.INPUT[] input = (WinUser.INPUT[]) new WinUser.INPUT().toArray(1);
        fillKey(input[0], vk, true);
        User32.INSTANCE.SendInput(new WinUser.DWORD(1), input, input[0].size());
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
        if (message == WM_KEYUP || message == WM_SYSKEYUP) {
            if (pressedVoiceKeys.firstKeyUp(vk)) {
                voiceCommandQueue.execute(() -> {
                    // The firmware gate may close after the hook callback was
                    // queued (disconnect, version refresh, or shutdown).
                    // Drop the stale event rather than routing it under a
                    // newer/unknown session.
                    if (!rawF18RoutingEnabled) return;
                    java.util.List<VoiceButtonEvent> events =
                        buttonStateMachine.onKeyUp(System.nanoTime());
                    synchronized (WindowsVoiceRelayService.this) {
                        cancelThresholdTask();
                        pressGeneration++;
                    }
                    events.forEach(WindowsVoiceRelayService.this::dispatchVoiceEvent);
                });
            }
            return new LRESULT(1);
        }
        if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN) {
            if (pressedVoiceKeys.firstKeyDown(vk)) {
                voiceCommandQueue.execute(() -> {
                    if (!rawF18RoutingEnabled) return;
                    buttonStateMachine.onKeyDown(System.nanoTime());
                    final long generation;
                    synchronized (WindowsVoiceRelayService.this) {
                        generation = ++pressGeneration;
                        cancelThresholdTask();
                        thresholdTask = voiceThresholdScheduler.schedule(() ->
                            voiceCommandQueue.execute(() -> {
                                synchronized (WindowsVoiceRelayService.this) {
                                    if (generation != pressGeneration) return;
                                }
                                dispatchVoiceEvent(buttonStateMachine.onThreshold(System.nanoTime()));
                            }),
                            buttonStateMachine.thresholdNanos(), TimeUnit.NANOSECONDS);
                    }
                });
            }
            // Auto-repeat is swallowed but never queued twice.
            return new LRESULT(1);
        }
        return new LRESULT(1);
    }

    private VoiceRoute matchRoute(int vkCode) {
        // F18 is a physical transport event, independent of the selected
        // mode and the legacy per-mode KEY1 mapping.
        return rawF18RoutingEnabled && vkCode == VK_F18
            ? new VoiceRoute(VK_F18, ModeSlot.MODE0, true) : null;
    }

    private void dispatchVoiceEvent(VoiceButtonEvent event) {
        if (event == null) return;
        actionRouter.route(event);
    }

    private synchronized void cancelThresholdTask() {
        if (thresholdTask != null) {
            thresholdTask.cancel(false);
            thresholdTask = null;
        }
    }

    private void refreshStatus() {
        if (!WindowsVoiceTyping.isWindows()) {
            statusMessage.set("非 Windows 平台。");
            return;
        }
        if (!rawF18RoutingEnabled) {
            String version = firmwareVersion == null ? "未知" : firmwareVersion.toString();
            statusMessage.set("物理 F18 桌面语音未启用（固件 " + version
                + "；需要 1.4.8 或更高版本）。");
            return;
        }
        if (hookHandle == null) {
            statusMessage.set("语音桥未运行；进入编辑配置或启动应用后会自动安装钩子。");
            return;
        }
        statusMessage.set("正在监听物理 F18；Desktop 负责短按/长按语义（阈值 "
            + configuredThresholdMs + "ms）。");
    }

}
