package com.example.ahakey.platform.voice;

import com.example.ahakey.model.HIDUsage;

import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Locale;
import java.util.function.Consumer;

/** Routes semantic press events to platform-independent action executors. */
public final class VoiceActionRouter {
    private final Map<VoiceButtonEvent.Type, VoiceAction> actions =
        new EnumMap<>(VoiceButtonEvent.Type.class);
    private final Map<VoiceAction, Consumer<VoiceButtonEvent>> executors =
        new EnumMap<>(VoiceAction.class);

    public VoiceActionRouter() {
        setActions(VoiceAction.CUSTOM_SHORTCUT, VoiceAction.AHAKEY_VOICE);
    }

    /** Implemented one-shot actions exposed by the desktop voice UI. */
    public static List<VoiceAction> shortActionChoices() {
        return List.of(VoiceAction.CUSTOM_SHORTCUT, VoiceAction.NONE);
    }

    /** Implemented push-to-talk actions exposed by the desktop voice UI. */
    public static List<VoiceAction> longActionChoices() {
        return List.of(VoiceAction.AHAKEY_VOICE, VoiceAction.CUSTOM_SHORTCUT, VoiceAction.NONE);
    }

    /** Default desktop shortcut for the short action (Win+H). */
    public static int defaultWindowsVoiceShortcut() {
        return 0x800 | HIDUsage.getCode("H");
    }

    /**
     * Converts a user-facing Windows shortcut into the existing HID-plus-
     * modifier representation used by the keyboard editor and SendInput.
     * Only ordinary keyboard keys are accepted; the physical F18 voice key
     * is deliberately reserved and can never be a custom target.
     */
    public static int parseShortcut(String text) {
        if (text == null || text.isBlank()) return 0;
        int modifiers = 0;
        int base = 0;
        for (String rawToken : text.split("\\+")) {
            String token = rawToken.trim();
            if (token.isEmpty()) return 0;
            String normalized = token.toUpperCase(Locale.ROOT);
            int modifier = switch (normalized) {
                case "SHIFT", "LSHIFT", "RSHIFT" ->
                    normalized.startsWith("R") ? 0x1000 : 0x100;
                case "CTRL", "CONTROL", "LCTRL", "LCONTROL" -> 0x200;
                case "RCTRL", "RCONTROL" -> 0x2000;
                case "ALT", "LALT" -> 0x400;
                case "RALT" -> 0x4000;
                case "WIN", "WINDOWS", "LWIN", "META" -> 0x800;
                case "RWIN", "RWINDOWS" -> 0x8000;
                default -> 0;
            };
            if (modifier != 0) {
                modifiers |= modifier;
                continue;
            }
            if (base != 0) return 0;
            base = HIDUsage.getCode(token);
            if (base == 0) return 0;
        }
        int hidCode = modifiers | base;
        return isValidCustomShortcut(hidCode) ? hidCode : 0;
    }

    /** Formats the shared HID representation for display in the editor. */
    public static String formatShortcut(int hidCode) {
        if (hidCode == 0) return "未设置";
        int base = hidCode & 0xFF;
        if (base == 0) return "未设置";
        java.util.List<String> parts = new java.util.ArrayList<>();
        if ((hidCode & 0x800) != 0) parts.add("Win");
        if ((hidCode & 0x200) != 0) parts.add("Ctrl");
        if ((hidCode & 0x400) != 0) parts.add("Alt");
        if ((hidCode & 0x100) != 0) parts.add("Shift");
        parts.add(HIDUsage.getName(base));
        return String.join("+", parts);
    }

    /** Custom shortcuts must have one known base key and cannot target F18. */
    public static boolean isValidCustomShortcut(int hidCode) {
        int allowedModifiers = 0xFF00;
        int base = hidCode & 0xFF;
        boolean modifierOnlyBase = base >= HIDUsage.LEFT_CONTROL
            && base <= HIDUsage.RIGHT_GUI;
        if (base == 0 || modifierOnlyBase || base == HIDUsage.F18
            || (hidCode & ~(allowedModifiers | 0xFF)) != 0) {
            return false;
        }
        return HIDUsage.getCode(HIDUsage.getName(base)) == base;
    }

    /** Compatibility migration for actions persisted by earlier Voice builds. */
    public static VoiceAction migrateShortAction(VoiceAction action) {
        return action == null || action == VoiceAction.NONE
            ? (action == null ? VoiceAction.NONE : action)
            : VoiceAction.CUSTOM_SHORTCUT;
    }

    /** Compatibility migration for the former system-voice long action. */
    public static VoiceAction migrateLongAction(VoiceAction action) {
        return action == VoiceAction.SYSTEM_VOICE ? VoiceAction.CUSTOM_SHORTCUT
            : (action == null ? VoiceAction.NONE : action);
    }

    public synchronized void setActions(VoiceAction shortAction, VoiceAction longAction) {
        // AhaKey local voice is a push-to-talk stream and therefore has no
        // meaningful one-shot SHORT_PRESS operation.  Do not allow a
        // persisted/legacy value to turn a short press into a silent no-op.
        VoiceAction effectiveShort = migrateShortAction(shortAction);
        VoiceAction effectiveLong = migrateLongAction(longAction);
        actions.put(VoiceButtonEvent.Type.SHORT_PRESS,
            Objects.requireNonNull(effectiveShort, "shortAction"));
        actions.put(VoiceButtonEvent.Type.LONG_PRESS_START,
            Objects.requireNonNull(effectiveLong, "longAction"));
        actions.put(VoiceButtonEvent.Type.LONG_PRESS_END,
            Objects.requireNonNull(effectiveLong, "longAction"));
    }

    public synchronized void setExecutor(VoiceAction action, Consumer<VoiceButtonEvent> executor) {
        Objects.requireNonNull(action, "action");
        if (executor == null) executors.remove(action);
        else executors.put(action, executor);
    }

    public synchronized VoiceAction actionFor(VoiceButtonEvent.Type type) {
        return actions.getOrDefault(type, VoiceAction.NONE);
    }

    /** Returns the selected action; execution is deliberately outside the lock. */
    public void route(VoiceButtonEvent event) {
        if (event == null) return;
        Consumer<VoiceButtonEvent> executor;
        synchronized (this) {
            executor = executors.get(actionFor(event.type()));
        }
        if (executor != null) executor.accept(event);
    }
}
