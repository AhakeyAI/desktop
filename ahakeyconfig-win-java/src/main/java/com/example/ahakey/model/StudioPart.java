package com.example.ahakey.model;

import com.example.ahakey.util.LanguageManager;

public enum StudioPart {
    LIGHT_BAR("lightBar", "studio-part.light-bar", "studio-part.light-bar-sub"),
    OLED("oledDisplay", "studio-part.oled", "studio-part.oled-sub"),
    KEY1("key1", "studio-part.key1", "studio-part.key-sub"),
    KEY2("key2", "studio-part.key2", "studio-part.key-sub"),
    KEY3("key3", "studio-part.key3", "studio-part.key-sub"),
    KEY4("key4", "studio-part.key4", "studio-part.key-sub"),
    TOGGLE_SWITCH("toggleSwitch", "studio-part.toggle-switch", "studio-part.toggle-switch-sub");

    private final String id;
    private final String titleKey;
    private final String subtitleKey;

    StudioPart(String id, String titleKey, String subtitleKey) {
        this.id = id;
        this.titleKey = titleKey;
        this.subtitleKey = subtitleKey;
    }

    public String getId() {
        return id;
    }

    public String getTitle() {
        return LanguageManager.getInstance().getString(titleKey);
    }

    public String getSubtitle() {
        return LanguageManager.getInstance().getString(subtitleKey);
    }

    public String getDisplayTitle() {
        return getTitle() + " · " + getSubtitle();
    }

    public boolean isKey() {
        return this == KEY1 || this == KEY2 || this == KEY3 || this == KEY4;
    }
}
