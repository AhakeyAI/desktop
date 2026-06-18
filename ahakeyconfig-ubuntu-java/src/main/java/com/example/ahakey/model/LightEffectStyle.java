package com.example.ahakey.model;

public enum LightEffectStyle {
    OFF("off", "关闭", (byte) 0x00),
    SINGLE_MOVE("singleMove", "单点流动", (byte) 0x01),
    RAINBOW_MOVE("rainbowMove", "彩虹流动", (byte) 0x02),
    RAINBOW_WAVE("rainbowWave", "彩虹波浪", (byte) 0x03),
    RAINBOW_WAVE_SLOW("rainbowWaveSlow", "慢速彩虹", (byte) 0x04),
    BREATHING("breathing", "呼吸灯", (byte) 0x05),
    MIDDLE_LIGHT("middleLight", "中间常亮", (byte) 0x06),
    TYPING_RIPPLE("typingRipple", "输入涟漪", (byte) 0x07),
    COMET("comet", "彗星拖尾", (byte) 0x08),
    SCAN_BAR("scanBar", "扫描灯条", (byte) 0x09),
    PULSE_CENTER("pulseCenter", "中心脉冲", (byte) 0x0A),
    WARNING_BLINK("warningBlink", "警示闪烁", (byte) 0x0B),
    SUCCESS_SWEEP("successSweep", "完成扫光", (byte) 0x0C),
    BLUE_THINKING("blueThinking", "蓝色思考", (byte) 0x0D),
    LOW_BATTERY("lowBattery", "低电提醒", (byte) 0x0E),
    CHARGING_FLOW("chargingFlow", "充电流动", (byte) 0x0F),
    APPROVAL_WAIT("approvalWait", "等待批准", (byte) 0x10);

    private final String id;
    private final String title;
    private final byte code;

    LightEffectStyle(String id, String title, byte code) {
        this.id = id;
        this.title = title;
        this.code = code;
    }

    public String getId() {
        return id;
    }

    public byte getCode() {
        return code;
    }

    public String getTitle() {
        return title;
    }

    public String getDetail() {
        return switch (this) {
            case OFF -> "灯条熄灭。";
            case SINGLE_MOVE -> "单点来回流动，适合执行中状态。";
            case RAINBOW_MOVE -> "彩色单点流动，适合更活跃的提示。";
            case RAINBOW_WAVE -> "整条彩虹波浪，视觉最明显。";
            case RAINBOW_WAVE_SLOW -> "更慢的彩虹波浪，适合环境反馈。";
            case BREATHING -> "整条均匀呼吸，适合等待确认。";
            case MIDDLE_LIGHT -> "中间更亮，两侧较弱，适合停止或待命。";
            case TYPING_RIPPLE -> "从输入方向扩散的涟漪，适合用户提交。";
            case COMET -> "带拖尾的移动光点。";
            case SCAN_BAR -> "横向扫描，适合工具执行前后。";
            case PULSE_CENTER -> "中心脉冲，适合思考或聚焦。";
            case WARNING_BLINK -> "警示闪烁，适合通知。";
            case SUCCESS_SWEEP -> "完成扫光，适合任务完成。";
            case BLUE_THINKING -> "蓝色思考效果。";
            case LOW_BATTERY -> "低电量提醒。";
            case CHARGING_FLOW -> "充电流动效果。";
            case APPROVAL_WAIT -> "等待批准提示。";
        };
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
        return title;
    }
}
