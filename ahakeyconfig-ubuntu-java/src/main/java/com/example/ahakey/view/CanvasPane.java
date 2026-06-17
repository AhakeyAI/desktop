package com.example.ahakey.view;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;
import javafx.fxml.FXMLLoader;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Label;
import javafx.scene.control.ToggleButton;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.StackPane;
import javafx.scene.layout.VBox;

import java.io.IOException;

public class CanvasPane extends VBox {
    private final StudioState studioState;
    private final DeviceStatus deviceStatus;
    private final StudioController controller;

    private final Label modeGuidance = new Label();

    public CanvasPane(StudioController controller) {
        this.studioState = controller.getStudioState();
        this.deviceStatus = controller.getDeviceStatus();
        this.controller = controller;
        init();
    }

    private void init() {
        setSpacing(14);
        setPadding(new Insets(16));
        getStyleClass().add("canvas-pane");
        setMinWidth(420);
        setMaxWidth(780);
        HBox.setHgrow(this, Priority.NEVER);

        getChildren().addAll(
            createHeader(),
            createPreviewCard()
        );

        studioState.selectedModeProperty().addListener((obs, oldValue, newValue) -> refreshPreview());
        refreshPreview();
    }

    private VBox createHeader() {
        VBox header = new VBox(8);
        header.getStyleClass().add("mode-header");

        HBox titleRow = new HBox(16);
        titleRow.setAlignment(Pos.CENTER_LEFT);

        Label keyboardMode = new Label("键盘模式");
        keyboardMode.getStyleClass().add("section-title");

        HBox picker = new HBox(4);
        picker.getStyleClass().add("mode-picker");
        for (ModeSlot slot : ModeSlot.values()) {
            ToggleButton button = new ToggleButton(slot.getShortName());
            button.getStyleClass().add("mode-toggle");
            button.setUserData(slot);
            button.setSelected(slot == studioState.getSelectedMode());
            button.setOnAction(event -> {
                for (var node : picker.getChildren()) {
                    if (node instanceof ToggleButton tb && tb.getUserData() instanceof ModeSlot s) {
                        tb.setSelected(s == slot);
                    }
                }
                controller.selectKeyboardMode(slot);
            });
            picker.getChildren().add(button);
        }
        studioState.selectedModeProperty().addListener((obs, oldValue, newValue) -> {
            for (var node : picker.getChildren()) {
                if (node instanceof ToggleButton tb && tb.getUserData() instanceof ModeSlot slot) {
                    tb.setSelected(slot == newValue);
                }
            }
        });

        HBox spacer = new HBox();
        HBox.setHgrow(spacer, Priority.ALWAYS);
        titleRow.getChildren().addAll(keyboardMode, picker, spacer);

        modeGuidance.getStyleClass().add("hero-subtitle");
        header.getChildren().addAll(titleRow, modeGuidance);
        return header;
    }

    private StackPane createPreviewCard() {
        StackPane preview = new StackPane();
        preview.getStyleClass().add("key-preview");

        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/fxml/CanvasLayout.fxml"));
            HBox layout = loader.load();
            CanvasController controller = loader.getController();
            controller.setStudioState(studioState);
            controller.setDeviceStatus(deviceStatus);
            preview.getChildren().add(layout);
        } catch (IOException e) {
            e.printStackTrace();
        }

        return preview;
    }

    private void refreshPreview() {
        ModeSlot mode = studioState.getSelectedMode();
        modeGuidance.setText(mode.getGuidance());
        modeGuidance.setVisible(mode.getGuidance() != null && !mode.getGuidance().isBlank());
        modeGuidance.setManaged(modeGuidance.isVisible());
    }
}
