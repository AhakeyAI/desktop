package com.example.ahakey.model;

public enum StudioPart {
    LIGHT_BAR("lightBar", "灯条", "AI 状态灯效"),
    OLED("oledDisplay", "OLED 屏幕", "GIF / 图片"),
    KEY1("key1", "Key 1", "快捷键"),
    KEY2("key2", "Key 2", "快捷键"),
    KEY3("key3", "Key 3", "快捷键"),
    KEY4("key4", "Key 4", "快捷键"),
    TOGGLE_SWITCH("toggleSwitch", "拨杆", "审批模式");

    private final String id;
    private final String title;
    private final String subtitle;

    StudioPart(String id, String title, String subtitle) {
        this.id = id;
        this.title = title;
        this.subtitle = subtitle;
    }

    public String getId() {
        return id;
    }

    public String getTitle() {
        return title;
    }

    public String getSubtitle() {
        return subtitle;
    }

    public String getDisplayTitle() {
        return title + " · " + subtitle;
    }

    public boolean isKey() {
        return this == KEY1 || this == KEY2 || this == KEY3 || this == KEY4;
    }
}
