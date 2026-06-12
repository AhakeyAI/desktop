package com.example.ahakey.view;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.StudioState;
import javafx.beans.binding.Bindings;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Label;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;

public class StatusBar extends HBox {
    public StatusBar(DeviceStatus deviceStatus, StudioState studioState) {
        init(deviceStatus, studioState);
    }

    private void init(DeviceStatus deviceStatus, StudioState studioState) {
        setPadding(new Insets(8, 24, 8, 24));
        setSpacing(16);
        setAlignment(Pos.CENTER_LEFT);
        getStyleClass().add("status-bar");

        Label selection = new Label();
        selection.textProperty().bind(Bindings.createStringBinding(
            () -> "当前选中: " + studioState.getSelectedPart().getDisplayTitle(),
            studioState.selectedPartProperty()
        ));
        selection.getStyleClass().add("status-bar-text");

        Label device = new Label();
        device.textProperty().bind(Bindings.createStringBinding(
            () -> "设备: " + deviceStatus.getDeviceName(),
            deviceStatus.deviceNameProperty()
        ));
        device.getStyleClass().add("status-bar-text");

        Label dirty = new Label();
        dirty.textProperty().bind(Bindings.createStringBinding(
            () -> "待保存改动: " + studioState.getDirtyCount(),
            studioState.dirtyCountProperty()
        ));
        dirty.getStyleClass().add("status-bar-text");

        Label sync = new Label();
        sync.textProperty().bind(studioState.syncStatusProperty());
        sync.getStyleClass().add("status-bar-text");

        Label lastSync = new Label();
        lastSync.textProperty().bind(studioState.lastSyncSummaryProperty());
        lastSync.getStyleClass().add("status-bar-text");

        HBox spacer = new HBox();
        HBox.setHgrow(spacer, Priority.ALWAYS);

        getChildren().addAll(selection, device, dirty, spacer, sync, lastSync);
    }
}
