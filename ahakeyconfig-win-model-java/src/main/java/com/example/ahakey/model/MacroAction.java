package com.example.ahakey.model;

/**
 * 宏步骤的动作类型。原本作为 KeyConfig 内部 package-private enum,
 * 但 util/KeyBindingDiffer 跨包需要访问,因此独立成 public 文件。
 */
public enum MacroAction {
    NO_OP("无操作", false, false),
    DOWN_KEY("按下键", true, false),
    UP_KEY("释放键", true, false),
    UP_ALL_KEYS("释放所有", false, false),
    DELAY("延时", false, true);

    private final String title;
    private final boolean takesKeycodeParam;
    private final boolean takesDelayParam;

    MacroAction(String title, boolean takesKeycodeParam, boolean takesDelayParam) {
        this.title = title;
        this.takesKeycodeParam = takesKeycodeParam;
        this.takesDelayParam = takesDelayParam;
    }

    public String getTitle() {
        return title;
    }

    public boolean takesKeycodeParam() {
        return takesKeycodeParam;
    }

    public boolean takesDelayParam() {
        return takesDelayParam;
    }
}
