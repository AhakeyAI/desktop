package com.example.ahakey.model;

public enum AiRuntimeDisplayMode {
    SINGLE(0, "单任务"),
    MULTI(1, "多任务");

    private final int protocolValue;
    private final String title;

    AiRuntimeDisplayMode(int protocolValue, String title) {
        this.protocolValue = protocolValue;
        this.title = title;
    }

    public int getProtocolValue() {
        return protocolValue;
    }

    public String getTitle() {
        return title;
    }

    public static AiRuntimeDisplayMode fromName(String name) {
        if (name != null) {
            for (AiRuntimeDisplayMode mode : values()) {
                if (mode.name().equalsIgnoreCase(name)) {
                    return mode;
                }
            }
        }
        return SINGLE;
    }
}
