package com.example.ahakey.model;

public enum ModeSlot {
    MODE0(0, "Mode 1", "Claude", ""),
    MODE1(1, "Mode 2", "Cursor", ""),
    MODE2(2, "Mode 3", "Codex", ""),
    MODE3(3, "Mode 4", "Mode 4", "");

    private final int index;
    private final String title;
    private final String shortName;
    private final String guidance;

    ModeSlot(int index, String title, String shortName, String guidance) {
        this.index = index;
        this.title = title;
        this.shortName = shortName;
        this.guidance = guidance;
    }

    public int getIndex() {
        return index;
    }

    public String getTitle() {
        return title;
    }

    public String getShortName() {
        return shortName;
    }

    public String getGuidance() {
        return guidance;
    }

    public static ModeSlot fromIndex(int index) {
        for (ModeSlot slot : values()) {
            if (slot.index == index) {
                return slot;
            }
        }
        return MODE0;
    }
}
