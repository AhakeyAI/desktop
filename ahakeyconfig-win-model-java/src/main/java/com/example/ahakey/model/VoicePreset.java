package com.example.ahakey.model;

/** 语音键预设；Windows 版默认使用 {@link #WINDOWS_NATIVE}（Win+H）。 */
public enum VoicePreset {
    CUSTOM("自定义快捷键", false),
    WINDOWS_NATIVE("Windows 语音 (Win+H)", true),
    MACOS_NATIVE("macOS 原生语音", true),
    TYPELESS("Typeless / Fn", true),
    WECHAT("微信语音", true);

    private final String displayName;
    private final boolean locksShortcut;

    VoicePreset(String displayName, boolean locksShortcut) {
        this.displayName = displayName;
        this.locksShortcut = locksShortcut;
    }

    public String getDisplayName() {
        return displayName;
    }

    public boolean locksShortcut() {
        return locksShortcut;
    }

    public String getDetail() {
        return switch (this) {
            case WINDOWS_NATIVE ->
                "AhaKey Studio 在后台拦截语音键（F17/F18），并向系统发送 Win+H 打开 Windows 语音输入。请在「设置 → 时间和语言 → 语音」中启用语音输入。";
            case MACOS_NATIVE ->
                "仅 macOS 完整支持；Windows 请改用「Windows 语音 (Win+H)」。";
            case TYPELESS, WECHAT ->
                "Windows 版暂未实现 Fn 注入；请使用 Windows 语音 (Win+H) 或自定义快捷键。";
            case CUSTOM -> "自行绑定 HID 单键或组合键。";
        };
    }
}
