package com.example.ahakey.service;

import com.example.ahakey.model.KeyConfig;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;

/** Executes an immutable editor snapshot. This class never accesses a device or changes focus. */
public final class KeySimulationService {
    public record Step(String action, int value) {}
    public record Action(List<Step> steps) {
        public Action { steps = List.copyOf(steps); }
    }
    @FunctionalInterface public interface Sender { void send(int hid, boolean down) throws Exception; }
    @FunctionalInterface public interface Delay { void waitMillis(long millis) throws InterruptedException; }

    public static Action snapshot(KeyConfig key) {
        List<Step> steps = new ArrayList<>();
        if (key.usesMacro()) {
            for (int i = 0; i < key.getMacroStepCount(); i++)
                steps.add(new Step(key.getMacroStepAction(i), key.getMacroStepParam(i)));
        } else {
            int code = key.getHidCode();
            int[] bits = {0x200, 0x100, 0x400, 0x800, 0x2000, 0x1000, 0x4000, 0x8000};
            List<Integer> keys = new ArrayList<>();
            for (int i = 0; i < bits.length; i++) if ((code & bits[i]) != 0) keys.add(0xE0 + i);
            if ((code & 255) != 0) keys.add(code & 255);
            for (int hid : keys) steps.add(new Step("DOWN_KEY", hid));
            for (int i = keys.size() - 1; i >= 0; i--) steps.add(new Step("UP_KEY", keys.get(i)));
        }
        if (steps.isEmpty()) throw new IllegalArgumentException("未设置动作，无法模拟。");
        for (Step step : steps) {
            if (step.value < 0 || step.value > 255 || !List.of("DOWN_KEY", "UP_KEY", "DELAY").contains(step.action))
                throw new IllegalArgumentException("宏步骤无效。");
        }
        return new Action(steps);
    }

    public static void execute(Action action, Sender sender, Delay delay) throws Exception {
        LinkedHashSet<Integer> pressed = new LinkedHashSet<>();
        Exception failure = null;
        try {
            for (Step step : action.steps) {
                if (Thread.currentThread().isInterrupted()) throw new InterruptedException("模拟已取消");
                switch (step.action) {
                    case "DELAY" -> delay.waitMillis(step.value * 3L);
                    case "DOWN_KEY" -> {
                        // A native failure may still have delivered the key; always attempt its release.
                        pressed.add(step.value);
                        sender.send(step.value, true);
                    }
                    case "UP_KEY" -> {
                        // Do not release a key held by the user, outside this simulation.
                        if (pressed.contains(step.value)) {
                            sender.send(step.value, false);
                            pressed.remove(step.value);
                        }
                    }
                    default -> throw new IllegalArgumentException("未知宏步骤");
                }
            }
        } catch (Exception e) { failure = e; }
        finally {
            var keys = new ArrayList<>(pressed);
            for (int i = keys.size() - 1; i >= 0; i--) {
                try { sender.send(keys.get(i), false); }
                catch (Exception e) { if (failure == null) failure = e; else failure.addSuppressed(e); }
            }
        }
        if (failure != null) throw failure;
    }
    private KeySimulationService() {}
}
