package com.example.ahakey.view;

import javafx.geometry.Insets;
import javafx.scene.control.Label;
import javafx.scene.layout.VBox;

/** Shared Windows re-pairing instructions. */
final class BluetoothPairingGuide {
    static final String WINDOWS_STEPS =
        "如果设备反复连接/断开、无法搜索，或刚恢复初始化/重置蓝牙：\n"
            + "1. 打开 Windows 设置 → 蓝牙和设备，找到名称含 AhaKey 的设备并选择“删除设备”；\n"
            + "2. 关闭再开启电脑蓝牙，然后重新搜索并完成配对；\n"
            + "3. 在两台电脑间切换时，先断开当前电脑的蓝牙，再在另一台电脑连接。";

    private BluetoothPairingGuide() {
    }

    static VBox createCard() {
        VBox card = new VBox(8);
        card.getStyleClass().add("dialog-card");
        card.setPadding(new Insets(12));
        Label title = new Label("蓝牙重新配对指南");
        title.getStyleClass().add("dialog-card-title");
        Label body = new Label(WINDOWS_STEPS);
        body.getStyleClass().add("dialog-text");
        body.setWrapText(true);
        card.getChildren().addAll(title, body);
        return card;
    }
}
