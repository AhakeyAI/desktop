package com.example.ahakey.view;

import static com.example.ahakey.util.LanguageManager.localize;

import com.example.ahakey.localvoice.LocalVoiceFeature;
import com.example.ahakey.localvoice.LocalVoiceSettings.ChineseScript;
import javafx.beans.binding.Bindings;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Alert;
import javafx.scene.control.Button;
import javafx.scene.control.ButtonBar;
import javafx.scene.control.ButtonType;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Label;
import javafx.scene.control.ProgressBar;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.stage.Window;
import javafx.util.StringConverter;

import java.util.Optional;

/**
 * Settings card that turns the optional local voice feature on or off.
 * Turning it on downloads the speech model and unlocks the voice key's local
 * voice actions, AhaType and the cloud account.
 */
public final class LocalVoicePane {

    private final LocalVoiceFeature feature;

    public LocalVoicePane(LocalVoiceFeature feature) {
        this.feature = feature;
    }

    public VBox create(Window owner) {
        VBox card = new VBox(10);
        card.getStyleClass().add("dialog-card");
        card.setPadding(new Insets(12));

        Label title = label(text(localize("本地语音（可选）"), "Local voice (optional)"), true);
        Label description = label(text(
            localize("开启后会下载离线语音识别模型（约 250 MB），语音键可使用本地语音输入，并可启用 AhaType 云端整理。关闭时不占用磁盘和内存。"),
            "Turning this on downloads an offline speech model (about 250 MB). The voice key can then use local "
                + "voice input and AhaType cloud polishing. While off, nothing is downloaded or loaded."), false);

        Label state = label("", false);
        state.textProperty().bind(Bindings.createStringBinding(this::stateText,
            feature.availableProperty(), feature.enabledProperty(), feature.installedProperty(),
            feature.phaseProperty()));

        Button enable = new Button(text(localize("开启本地语音"), "Turn on"));
        enable.getStyleClass().add("button-prominent");
        enable.setOnAction(event -> feature.enable());

        Button disable = new Button(text(localize("关闭本地语音"), "Turn off"));
        disable.setOnAction(event -> confirmDisable(owner));

        Button cancel = new Button(text(localize("取消下载"), "Cancel download"));
        cancel.setOnAction(event -> feature.cancelDownload());

        Button deleteFiles = new Button(text(localize("删除已下载的模型"), "Delete downloaded model"));
        deleteFiles.setOnAction(event -> feature.disable(true));

        var busy = Bindings.createBooleanBinding(feature::isBusy, feature.phaseProperty());
        enable.visibleProperty().bind(feature.availableProperty().not().and(busy.not()));
        disable.visibleProperty().bind(feature.availableProperty().and(busy.not()));
        cancel.visibleProperty().bind(busy);
        // Lets users reclaim disk space after turning the feature off.
        deleteFiles.visibleProperty().bind(feature.enabledProperty().not()
            .and(feature.installedProperty()).and(busy.not()));
        for (Button button : new Button[] {enable, disable, cancel, deleteFiles}) {
            button.managedProperty().bind(button.visibleProperty());
        }

        ProgressBar progress = new ProgressBar();
        progress.setMaxWidth(Double.MAX_VALUE);
        progress.progressProperty().bind(Bindings.createDoubleBinding(
            () -> feature.phaseProperty().get() == LocalVoiceFeature.Phase.DOWNLOADING
                ? feature.progressProperty().get() : ProgressBar.INDETERMINATE_PROGRESS,
            feature.phaseProperty(), feature.progressProperty()));
        progress.visibleProperty().bind(busy);
        progress.managedProperty().bind(progress.visibleProperty());

        Label message = label("", false);
        message.textProperty().bind(feature.messageProperty());
        message.visibleProperty().bind(message.textProperty().isNotEmpty());
        message.managedProperty().bind(message.visibleProperty());

        ComboBox<ChineseScript> script = new ComboBox<>();
        script.getItems().setAll(ChineseScript.values());
        script.setValue(feature.getChineseScript());
        script.setConverter(new StringConverter<>() {
            @Override public String toString(ChineseScript value) {
                if (value == null) return "";
                return value == ChineseScript.TRADITIONAL
                    ? text(localize("繁体中文"), "Traditional Chinese")
                    : text(localize("简体中文"), "Simplified Chinese");
            }
            @Override public ChineseScript fromString(String value) {
                return null;
            }
        });
        script.setOnAction(event -> feature.setChineseScript(script.getValue()));
        Label scriptLabel = label(text(localize("识别结果输出"), "Output script"), false);
        HBox scriptRow = new HBox(10, scriptLabel, script);
        scriptRow.setAlignment(Pos.CENTER_LEFT);
        scriptRow.visibleProperty().bind(feature.availableProperty());
        scriptRow.managedProperty().bind(scriptRow.visibleProperty());

        HBox buttons = new HBox(10, enable, disable, cancel, deleteFiles);
        buttons.setAlignment(Pos.CENTER_LEFT);
        card.getChildren().addAll(title, description, state, buttons, progress, message, scriptRow);
        return card;
    }

    private String stateText() {
        if (feature.isBusy()) return text(localize("当前状态：正在准备"), "Status: preparing");
        if (feature.isAvailable()) return text(localize("当前状态：已开启"), "Status: on");
        if (feature.enabledProperty().get()) {
            return text(localize("当前状态：模型文件缺失，需要重新下载"), "Status: model files missing");
        }
        return feature.installedProperty().get()
            ? text(localize("当前状态：已关闭（模型仍保留在本机）"), "Status: off (model kept on this PC)")
            : text(localize("当前状态：未开启"), "Status: off");
    }

    private void confirmDisable(Window owner) {
        ButtonType keep = new ButtonType(text(localize("关闭，保留模型"), "Turn off, keep model"),
            ButtonBar.ButtonData.OK_DONE);
        ButtonType delete = new ButtonType(text(localize("关闭并删除模型"), "Turn off and delete"),
            ButtonBar.ButtonData.OTHER);
        Alert alert = new Alert(Alert.AlertType.CONFIRMATION,
            text(localize("关闭后，语音键的本地语音动作和 AhaType 将不可用。保留模型可以在下次开启时免去重新下载。"),
                "Local voice actions and AhaType stop working. Keeping the model avoids downloading it again."),
            keep, delete, ButtonType.CANCEL);
        if (owner != null) alert.initOwner(owner);
        alert.setTitle(text(localize("关闭本地语音"), "Turn off local voice"));
        alert.setHeaderText(null);
        Optional<ButtonType> choice = alert.showAndWait();
        if (choice.isEmpty() || choice.get() == ButtonType.CANCEL) return;
        feature.disable(choice.get() == delete);
    }

    private static Label label(String value, boolean title) {
        Label label = new Label(value);
        label.getStyleClass().add(title ? "dialog-card-title" : "dialog-text");
        label.setWrapText(true);
        return label;
    }

    private static String text(String zh, String en) {
        var language = com.example.ahakey.util.LanguageManager.getInstance();
        return language.usesLocalizedLiterals() ? zh : en;
    }
}
