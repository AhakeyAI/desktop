package com.example.ahakey.view;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.BleManager;
import javafx.application.Platform;
import javafx.beans.property.BooleanProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Alert;
import javafx.scene.control.Button;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Label;
import javafx.scene.control.ProgressIndicator;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.stage.Stage;
import javafx.animation.PauseTransition;
import javafx.util.Duration;
import javafx.util.StringConverter;

import java.util.List;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicLong;

/** Protocol v2 standby-time card, isolated from all voice/model classes. */
public final class StandbySettingsPane {
    private static final List<Integer> OPTIONS = List.of(0, 5, 10, 15, 30);
    private final BleManager bleManager;
    private final DeviceStatus deviceStatus;
    private final boolean chinese =
        Locale.getDefault().getLanguage().equalsIgnoreCase("zh");

    public StandbySettingsPane(BleManager bleManager, DeviceStatus deviceStatus) {
        this.bleManager = bleManager;
        this.deviceStatus = deviceStatus;
    }

    public VBox create(Stage owner) {
        VBox card = new VBox(10);
        card.getStyleClass().add("dialog-card");
        card.setPadding(new Insets(12));
        Label title = label(text("自动待机时间", "Automatic Standby"), true);
        Label description = label(text(
            "设备无操作达到指定时间后自动待机。支持 USB 或 BLE，保存后会回读校验。",
            "The device enters standby after the selected period. USB and BLE are supported; saves are read back and verified."
        ), false);
        Label current = label(currentText(null), false);
        Label status = label(text(
            "请先通过 USB 或 BLE 连接设备。",
            "Connect the device by USB or BLE first."
        ), false);

        ComboBox<Integer> options = new ComboBox<>();
        options.getItems().setAll(OPTIONS);
        options.setPromptText(text("选择时间", "Select timeout"));
        options.setConverter(new StringConverter<>() {
            @Override public String toString(Integer value) {
                return value == null ? "" : minutes(value);
            }
            @Override public Integer fromString(String value) {
                return null;
            }
        });
        Button save = new Button(text("保存", "Save"));
        save.getStyleClass().add("button-prominent");
        ProgressIndicator progress = new ProgressIndicator();
        progress.setPrefSize(22, 22);

        BooleanProperty supported = new SimpleBooleanProperty(false);
        BooleanProperty busy = new SimpleBooleanProperty(false);
        options.disableProperty().bind(supported.not().or(busy));
        save.disableProperty().bind(
            supported.not().or(busy).or(options.valueProperty().isNull())
        );
        progress.visibleProperty().bind(busy);
        progress.managedProperty().bind(progress.visibleProperty());
        AtomicLong generation = new AtomicLong();

        HBox controls = new HBox(10, options, save, progress);
        controls.setAlignment(Pos.CENTER_LEFT);
        card.getChildren().addAll(title, description, current, controls, status);

        Runnable refresh = () -> refresh(
            owner, options, current, status, supported, busy, generation
        );
        save.setOnAction(event -> save(
            owner, options, current, status, busy, generation
        ));
        var connectionListener = new javafx.beans.value.ChangeListener<Boolean>() {
            @Override public void changed(
                javafx.beans.value.ObservableValue<? extends Boolean> observable,
                Boolean oldValue, Boolean connected
            ) {
                if (connected) {
                    delayedRefresh(refresh);
                } else {
                    generation.incrementAndGet();
                    supported.set(false);
                    busy.set(false);
                    options.getSelectionModel().clearSelection();
                    current.setText(currentText(null));
                    status.setText(text("请先通过 USB 或 BLE 连接设备。",
                        "Connect the device by USB or BLE first."));
                }
            }
        };
        deviceStatus.isConnectedProperty().addListener(connectionListener);
        owner.setOnHidden(event ->
            deviceStatus.isConnectedProperty().removeListener(connectionListener));
        Platform.runLater(() -> delayedRefresh(refresh));
        return card;
    }

    private void delayedRefresh(Runnable refresh) {
        PauseTransition delay = new PauseTransition(Duration.millis(300));
        delay.setOnFinished(event -> refresh.run());
        delay.play();
    }

    private void refresh(
        Stage owner, ComboBox<Integer> options, Label current, Label status,
        BooleanProperty supported, BooleanProperty busy, AtomicLong generation
    ) {
        long request = generation.incrementAndGet();
        if (!deviceStatus.isConnected()) {
            supported.set(false);
            status.setText(text("请先连接设备。", "Connect the device first."));
            return;
        }
        supported.set(false);
        busy.set(true);
        status.setText(text("正在读取设备设置…", "Reading device setting…"));
        daemon("standby-read", () -> {
            try {
                var capabilities = bleManager.queryDeviceCapabilities();
                if (capabilities == null || capabilities.protocolMajor() < 2
                    || !capabilities.supports(AhaKeyProtocol.CAP_STANDBY_TIMEOUT_V2)) {
                    throw new IllegalStateException(text(
                        "当前固件不支持安全待机协议，请先更新固件。",
                        "Firmware update required for safe standby settings."
                    ));
                }
                int value = bleManager.readStandbyTimeoutMinutes();
                Platform.runLater(() -> {
                    if (!owner.isShowing() || generation.get() != request) return;
                    options.setValue(OPTIONS.contains(value) ? value : null);
                    current.setText(currentText(value));
                    supported.set(true);
                    busy.set(false);
                    status.setText(text("已通过 ", "Connected over ")
                        + (bleManager.isUsbConnected() ? "USB" : "BLE")
                        + text(" 读取成功。", "."));
                });
            } catch (Exception exception) {
                Platform.runLater(() -> {
                    if (!owner.isShowing() || generation.get() != request) return;
                    busy.set(false);
                    supported.set(false);
                    status.setText(text("读取失败：", "Read failed: ")
                        + exception.getMessage());
                });
            }
        });
    }

    private void save(
        Stage owner, ComboBox<Integer> options, Label current, Label status,
        BooleanProperty busy, AtomicLong generation
    ) {
        Integer requested = options.getValue();
        if (requested == null) return;
        long request = generation.get();
        busy.set(true);
        status.setText(text(
            "正在设置、保存并回读校验，请勿断开设备…",
            "Setting, saving, and verifying. Do not disconnect…"
        ));
        daemon("standby-save", () -> {
            try {
                int verified = bleManager.setSaveAndVerifyStandbyTimeoutMinutes(requested);
                Platform.runLater(() -> {
                    if (!owner.isShowing() || generation.get() != request) return;
                    options.setValue(verified);
                    current.setText(currentText(verified));
                    busy.set(false);
                    status.setText(text("已保存并验证：", "Saved and verified: ")
                        + minutes(verified));
                });
            } catch (Exception exception) {
                Platform.runLater(() -> {
                    if (!owner.isShowing() || generation.get() != request) return;
                    busy.set(false);
                    String message = text("保存失败：", "Save failed: ")
                        + exception.getMessage();
                    status.setText(message);
                    Alert alert = new Alert(Alert.AlertType.WARNING);
                    alert.initOwner(owner);
                    alert.setTitle(text("待机时间设置失败", "Standby Setting Failed"));
                    alert.setHeaderText(null);
                    alert.setContentText(message);
                    alert.showAndWait();
                });
            }
        });
    }

    private Label label(String value, boolean title) {
        Label label = new Label(value);
        label.getStyleClass().add(title ? "dialog-card-title" : "dialog-text");
        label.setWrapText(true);
        return label;
    }

    private String currentText(Integer value) {
        return value == null
            ? text("当前设置：—", "Current setting: —")
            : text("当前设置：", "Current setting: ") + minutes(value);
    }

    private String minutes(int value) {
        if (value == 0) return text("永不关机", "Never power off");
        return chinese ? value + " 分钟" : value + " minutes";
    }

    private String text(String zh, String en) {
        return chinese ? zh : en;
    }

    private void daemon(String name, Runnable task) {
        Thread thread = new Thread(task, name);
        thread.setDaemon(true);
        thread.start();
    }
}
