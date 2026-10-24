package com.example.ahakey.service;

/** 充值套餐（与 macOS 版一致） */
public enum CloudRechargePlan {
    monthly("monthly", "按月订阅", "30 天", "包月充值", 100),
    quarterly("quarterly", "按季订阅", "90 天", "包季充值", 270),
    yearly("yearly", "按年订阅", "365 天", "包年充值", 999);

    public final String rawValue;
    public final String title;
    public final String subtitle;
    public final String orderDescription;
    public final int fallbackAmountFen;

    CloudRechargePlan(String rawValue, String title, String subtitle, String orderDescription, int fallbackAmountFen) {
        this.rawValue = rawValue;
        this.title = title;
        this.subtitle = subtitle;
        this.orderDescription = orderDescription;
        this.fallbackAmountFen = fallbackAmountFen;
    }
}