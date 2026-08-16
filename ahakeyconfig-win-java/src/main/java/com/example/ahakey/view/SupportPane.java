package com.example.ahakey.view;

import javafx.geometry.Insets;
import javafx.scene.control.Label;
import javafx.scene.image.Image;
import javafx.scene.image.ImageView;
import javafx.scene.layout.VBox;

import java.net.URL;
import java.util.Locale;

/** Bundled customer-support QR code; no external link is required. */
public final class SupportPane {
    private static final String SUPPORT_QR_RESOURCE =
        "/images/support-service-qr.png";
    private final boolean chinese =
        Locale.getDefault().getLanguage().equalsIgnoreCase("zh");

    public VBox create() {
        VBox card = new VBox(10);
        card.getStyleClass().add("dialog-card");
        card.setPadding(new Insets(12));

        Label title = new Label(text("帮助与客服", "Help & Support"));
        title.getStyleClass().add("dialog-card-title");

        Label instruction = new Label(text(
            "遇到问题，请使用手机扫描下方二维码联系客服。",
            "If you need help, scan the QR code below to contact support."
        ));
        instruction.getStyleClass().add("dialog-text");
        instruction.setWrapText(true);

        ImageView qr = new ImageView();
        qr.setFitWidth(220);
        qr.setFitHeight(220);
        qr.setPreserveRatio(true);

        Label status = new Label();
        status.getStyleClass().add("dialog-text");
        status.setWrapText(true);

        URL resource = SupportPane.class.getResource(SUPPORT_QR_RESOURCE);
        if (resource == null) {
            qr.setVisible(false);
            qr.setManaged(false);
            status.setText(text(
                "客服二维码资源缺失，请重新安装 AhaKeyStudio。",
                "The support QR code is missing. Please reinstall AhaKeyStudio."
            ));
        } else {
            qr.setImage(new Image(resource.toExternalForm(), true));
            status.setText(text(
                "扫码后即可与客服沟通。",
                "Scan the code to start a support conversation."
            ));
        }

        card.getChildren().addAll(title, instruction, qr, status);
        return card;
    }

    private String text(String zh, String en) {
        return chinese ? zh : en;
    }
}
