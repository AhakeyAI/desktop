package com.example.ahakey.view;

import javafx.beans.binding.Bindings;
import javafx.beans.value.ObservableValue;
import javafx.geometry.Insets;
import javafx.scene.control.Label;
import javafx.scene.layout.VBox;

enum AccentColor {
    GREEN("#30d158"),
    ORANGE("#ff9f0a"),
    BLUE("#0a84ff"),
    MINT("#67d9a5"),
    INDIGO("#5e5ce6");

    private final String hex;

    AccentColor(String hex) {
        this.hex = hex;
    }

    public String getHex() {
        return hex;
    }
}

public class InfoPill extends VBox {
    public InfoPill(
        ObservableValue<String> titleValue,
        ObservableValue<String> subtitleValue,
        ObservableValue<AccentColor> accentValue
    ) {
        this.setPadding(new Insets(6, 10, 6, 10));
        this.setSpacing(1);
        this.getStyleClass().add("info-pill");

        Label titleLabel = new Label();
        titleLabel.textProperty().bind(titleValue);
        titleLabel.getStyleClass().add("info-pill-title");

        Label subtitleLabel = new Label();
        subtitleLabel.textProperty().bind(subtitleValue);
        subtitleLabel.getStyleClass().add("info-pill-subtitle");

        styleProperty().bind(Bindings.createStringBinding(
            () -> "-fx-border-color: " + accentValue.getValue().getHex() + ";",
            accentValue
        ));

        this.getChildren().addAll(titleLabel, subtitleLabel);
    }
}
