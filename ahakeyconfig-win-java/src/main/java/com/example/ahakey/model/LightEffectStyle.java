package com.example.ahakey.model;

import com.example.ahakey.util.LanguageManager;

public enum LightEffectStyle {
    OFF("off", "light-effect.off", (byte) 0x00),
    SINGLE_MOVE("singleMove", "light-effect.single-move", (byte) 0x01),
    RAINBOW_MOVE("rainbowMove", "light-effect.rainbow-move", (byte) 0x02),
    RAINBOW_WAVE("rainbowWave", "light-effect.rainbow-wave", (byte) 0x03),
    RAINBOW_WAVE_SLOW("rainbowWaveSlow", "light-effect.rainbow-wave-slow", (byte) 0x04),
    BREATHING("breathing", "light-effect.breathing", (byte) 0x05),
    MIDDLE_LIGHT("middleLight", "light-effect.middle-light", (byte) 0x06),
    TYPING_RIPPLE("typingRipple", "light-effect.typing-ripple", (byte) 0x07),
    COMET("comet", "light-effect.comet", (byte) 0x08),
    SCAN_BAR("scanBar", "light-effect.scan-bar", (byte) 0x09),
    PULSE_CENTER("pulseCenter", "light-effect.pulse-center", (byte) 0x0A),
    WARNING_BLINK("warningBlink", "light-effect.warning-blink", (byte) 0x0B),
    SUCCESS_SWEEP("successSweep", "light-effect.success-sweep", (byte) 0x0C),
    BLUE_THINKING("blueThinking", "light-effect.blue-thinking", (byte) 0x0D),
    LOW_BATTERY("lowBattery", "light-effect.low-battery", (byte) 0x0E),
    CHARGING_FLOW("chargingFlow", "light-effect.charging-flow", (byte) 0x0F),
    APPROVAL_WAIT("approvalWait", "light-effect.approval-wait", (byte) 0x10);

    private final String id;
    private final String titleKey;
    private final byte code;

    LightEffectStyle(String id, String titleKey, byte code) {
        this.id = id;
        this.titleKey = titleKey;
        this.code = code;
    }

    public String getId() {
        return id;
    }

    public byte getCode() {
        return code;
    }

    public String getTitle() {
        return LanguageManager.getInstance().getString(titleKey);
    }

    public String getDetail() {
        return LanguageManager.getInstance().getString(titleKey + "-detail");
    }

    public static LightEffectStyle fromCode(int code) {
        for (LightEffectStyle style : values()) {
            if ((style.code & 0xFF) == code) {
                return style;
            }
        }
        return OFF;
    }

    public static LightEffectStyle fromId(String id) {
        if (id != null) {
            for (LightEffectStyle style : values()) {
                if (style.id.equals(id)) {
                    return style;
                }
            }
        }
        return OFF;
    }

    public static LightEffectStyle defaultFor(IDEState state) {
        return switch (state) {
            case NOTIFICATION -> WARNING_BLINK;
            case PERMISSION_REQUEST -> BREATHING;
            case POST_TOOL_USE -> SINGLE_MOVE;
            case PRE_TOOL_USE -> SINGLE_MOVE;
            case SESSION_START -> SINGLE_MOVE;
            case STOP -> MIDDLE_LIGHT;
            case TASK_COMPLETED -> MIDDLE_LIGHT;
            case USER_PROMPT_SUBMIT -> TYPING_RIPPLE;
            case SESSION_END -> OFF;
        };
    }

    public static LightEffectStyle hardwareEffectFor(LightBarPreviewState state) {
        return defaultFor(state.getIdeState());
    }

    @Override
    public String toString() {
        return getTitle();
    }
}
