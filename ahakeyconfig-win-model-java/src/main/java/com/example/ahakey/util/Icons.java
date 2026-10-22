package com.example.ahakey.util;

import javafx.scene.text.Text;
import javafx.scene.paint.Color;

public class Icons {
    private static final String FONT_FAMILY = "Segoe MDL2 Assets";

    public static Text createIcon(String glyph, String size, Color color) {
        Text text = new Text(glyph);
        text.setFill(color);
        double fontSize = Double.parseDouble(size.replace("px", ""));
        text.setStyle("-fx-font-size: " + fontSize + "px; -fx-font-family: '" + FONT_FAMILY + "';");
        return text;
    }

    public static Text createIcon(String glyph, String size) {
        return createIcon(glyph, size, Color.WHITE);
    }

    public static Text bluetooth(String size) {
        return createIcon("\uE138", size, Color.web("#6b7280"));
    }

    public static Text bluetoothConnected(String size) {
        return createIcon("\uE138", size, Color.web("#30d158"));
    }

    public static Text battery(String size, int level) {
        String icon;
        if (level >= 40) {
            icon = "\uE1A3";
        } else {
            icon = "\uE1A4";
        }

        Color color;
        if (level >= 40) color = Color.web("#30d158");
        else if (level >= 20) color = Color.web("#ff9f0a");
        else color = Color.web("#ff453a");

        return createIcon(icon, size, color);
    }

    public static Text settings(String size) {
        return createIcon("\uE713", size, Color.web("#6b7280"));
    }

    public static Text info(String size) {
        return createIcon("\uE946", size, Color.web("#0a84ff"));
    }

    public static Text cloud(String size) {
        return createIcon("\uE14B", size, Color.web("#6b7280"));
    }

    public static Text refresh(String size) {
        return createIcon("\uE1E4", size, Color.web("#6b7280"));
    }

    public static Text power(String size) {
        return createIcon("\uE700", size, Color.web("#6b7280"));
    }

    public static Text moreHorizontal(String size) {
        return createIcon("\uE1D8", size, Color.web("#445065"));
    }

    public static Text keyboard(String size) {
        return createIcon("\uE150", size, Color.web("#6b7280"));
    }

    public static Text display(String size) {
        return createIcon("\uE1D5", size, Color.web("#6b7280"));
    }

    public static Text lightbulb(String size) {
        return createIcon("\uE3AF", size, Color.web("#ffd60a"));
    }

    public static Text toggleLeft(String size) {
        return createIcon("\uE701", size, Color.web("#6b7280"));
    }

    public static Text checkCircle(String size) {
        return createIcon("\uE73E", size, Color.web("#30d158"));
    }

    public static Text xCircle(String size) {
        return createIcon("\uE711", size, Color.web("#ff453a"));
    }

    public static Text alertTriangle(String size) {
        return createIcon("\uE7BA", size, Color.web("#ff9f0a"));
    }
}