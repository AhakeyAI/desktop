package com.example.ahakey.service;

import com.example.ahakey.model.KeyConfig;
import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinUser;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;

/** Executes an immutable editor snapshot. No device transport or focus changes. */
public final class KeySimulationService {
    public record Step(String action, int param) {}
    public record Plan(List<Step> steps) {
        public Plan { steps = List.copyOf(steps); }
    }
    @FunctionalInterface public interface KeySink { void send(int hid, boolean up) throws Exception; }
    @FunctionalInterface public interface Delay { void sleep(long milliseconds) throws InterruptedException; }

    private KeySimulationService() {}

    /** Call on the editor thread, before handing work to the background executor. */
    public static Plan snapshot(KeyConfig key) {
        List<Step> steps = new ArrayList<>();
        if (key.usesMacro()) {
            for (int i = 0; i < key.getMacroStepCount(); i++)
                steps.add(new Step(key.getMacroStepAction(i), key.getMacroStepParam(i)));
        } else {
            int code = key.getHidCode();
            int[] masks = {0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000, 0x4000, 0x8000};
            int[] modifiers = {0xE1, 0xE0, 0xE2, 0xE3, 0xE5, 0xE4, 0xE6, 0xE7};
            for (int i = 0; i < masks.length; i++)
                if ((code & masks[i]) != 0) steps.add(new Step("DOWN_KEY", modifiers[i]));
            if ((code & 0xFF) != 0) steps.add(new Step("DOWN_KEY", code & 0xFF));
            for (int i = steps.size() - 1; i >= 0; i--) steps.add(new Step("UP_KEY", steps.get(i).param()));
        }
        if (steps.isEmpty()) throw new IllegalArgumentException("未设置按键，无法模拟。");
        // Validate the entire plan before sending even its first key.
        for (Step step : steps) {
            if ("DELAY".equals(step.action())) {
                if (step.param() < 0 || step.param() > 255) throw new IllegalArgumentException("宏延时超出范围。");
            } else if ("DOWN_KEY".equals(step.action()) || "UP_KEY".equals(step.action())) {
                virtualKey(step.param());
            } else throw new IllegalArgumentException("不支持的模拟动作：" + step.action());
        }
        return new Plan(steps);
    }

    public static void execute(Plan plan, KeySink sink, Delay delay) throws Exception {
        LinkedHashSet<Integer> held = new LinkedHashSet<>();
        Exception failure = null;
        try {
            for (Step step : plan.steps()) {
                if (Thread.currentThread().isInterrupted()) throw new InterruptedException("模拟已取消");
                switch (step.action()) {
                    case "DOWN_KEY" -> { held.add(step.param()); sink.send(step.param(), false); }
                    case "UP_KEY" -> { sink.send(step.param(), true); held.remove(step.param()); }
                    // Firmware macro units and KeyConfig preview both use 3 ms ticks.
                    case "DELAY" -> delay.sleep(step.param() * 3L);
                    default -> throw new IllegalArgumentException("不支持的模拟动作：" + step.action());
                }
            }
        } catch (Exception e) {
            failure = e;
        } finally {
            List<Integer> remaining = new ArrayList<>(held);
            for (int i = remaining.size() - 1; i >= 0; i--) {
                try { sink.send(remaining.get(i), true); }
                catch (Exception e) { if (failure == null) failure = e; else failure.addSuppressed(e); }
            }
        }
        if (failure != null) throw failure;
    }

    /** Used by menu exit; hiding the window does not cancel simulation. */
    public static boolean cancelAndAwait(Thread worker, long timeoutMs) {
        if (worker == null || !worker.isAlive()) return true;
        worker.interrupt();
        if (worker == Thread.currentThread()) return false;
        try { worker.join(Math.max(1, timeoutMs)); }
        catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); }
        return !worker.isAlive();
    }

    public static KeySink windowsSink() {
        return (hid, up) -> {
            if (!System.getProperty("os.name", "").toLowerCase(java.util.Locale.ROOT).startsWith("windows"))
                throw new IllegalStateException("按键模拟仅支持 Windows。");
            WinUser.INPUT[] input = (WinUser.INPUT[]) new WinUser.INPUT().toArray(1);
            input[0].type = new WinUser.DWORD(WinUser.INPUT.INPUT_KEYBOARD);
            input[0].input.setType("ki");
            input[0].input.ki.wVk = new WinUser.WORD(virtualKey(hid));
            input[0].input.ki.dwFlags = new WinUser.DWORD((up ? 2 : 0) | (extendedKey(hid) ? 1 : 0));
            if (User32.INSTANCE.SendInput(new WinUser.DWORD(1), input, input[0].size()).intValue() != 1)
                throw new IllegalStateException("系统未接受模拟按键，请检查目标窗口权限。");
        };
    }

    public static boolean extendedKey(int hid) {
        return (hid >= 0x49 && hid <= 0x54) || hid == 0x58 || hid == 0x46
                || hid == 0xE3 || hid == 0xE4 || hid == 0xE6 || hid == 0xE7;
    }

    public static int virtualKey(int hid) {
        if (hid >= 0x04 && hid <= 0x1D) return 0x41 + hid - 0x04;
        if (hid >= 0x1E && hid <= 0x26) return 0x31 + hid - 0x1E;
        if (hid >= 0x3A && hid <= 0x45) return 0x70 + hid - 0x3A;
        if (hid >= 0x68 && hid <= 0x73) return 0x7C + hid - 0x68;
        if (hid >= 0x59 && hid <= 0x61) return 0x61 + hid - 0x59;
        return switch (hid) {
            case 0x27, 0x62 -> hid == 0x27 ? 0x30 : 0x60;
            case 0x28, 0x58 -> 0x0D; case 0x29 -> 0x1B; case 0x2A -> 0x08;
            case 0x2B -> 0x09; case 0x2C -> 0x20; case 0x2D -> 0xBD; case 0x2E -> 0xBB;
            case 0x2F -> 0xDB; case 0x30 -> 0xDD; case 0x31 -> 0xDC; case 0x33 -> 0xBA;
            case 0x34 -> 0xDE; case 0x35 -> 0xC0; case 0x36 -> 0xBC; case 0x37 -> 0xBE;
            case 0x38 -> 0xBF; case 0x39 -> 0x14; case 0x46 -> 0x2C; case 0x47 -> 0x91;
            case 0x48 -> 0x13; case 0x49 -> 0x2D; case 0x4A -> 0x24; case 0x4B -> 0x21;
            case 0x4C -> 0x2E; case 0x4D -> 0x23; case 0x4E -> 0x22; case 0x4F -> 0x27;
            case 0x50 -> 0x25; case 0x51 -> 0x28; case 0x52 -> 0x26; case 0x53 -> 0x90;
            case 0x54 -> 0x6F; case 0x55 -> 0x6A; case 0x56 -> 0x6D; case 0x57 -> 0x6B;
            case 0x63 -> 0x6E;
            case 0xE0 -> 0xA2; case 0xE1 -> 0xA0; case 0xE2 -> 0xA4; case 0xE3 -> 0x5B;
            case 0xE4 -> 0xA3; case 0xE5 -> 0xA1; case 0xE6 -> 0xA5; case 0xE7 -> 0x5C;
            default -> throw new IllegalArgumentException("无法模拟 HID 0x" + Integer.toHexString(hid));
        };
    }
}
