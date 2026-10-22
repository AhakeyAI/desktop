package com.example.ahakey.view;

import static com.example.ahakey.util.LanguageManager.localize;

import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.VoicePreset;
import com.example.ahakey.platform.voice.VoiceActionRouter;
import javafx.beans.property.SimpleStringProperty;
import javafx.collections.FXCollections;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.ButtonBar;
import javafx.scene.control.Label;
import javafx.scene.control.TableColumn;
import javafx.scene.control.TableView;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;
import javafx.stage.Modality;
import javafx.stage.Stage;
import javafx.stage.Window;

import java.util.ArrayList;
import java.util.List;

/**
 * Shows the 16 key bindings (4 modes × K1–K4) that are about to be written to
 * the keyboard and lets the user confirm or cancel. Nothing is read from the
 * device: the current firmware protocol has no key binding read command.
 *
 * <p>Ported from the full client's {@code SyncDiffDialog.showSavePreview}.
 */
public final class SavePreviewDialog {

    private SavePreviewDialog() {
    }

    /** One key binding that will be written. */
    public record Row(String mode, String key, String value) {
    }

    private static final StudioPart[] KEYS = {
        StudioPart.KEY1, StudioPart.KEY2, StudioPart.KEY3, StudioPart.KEY4
    };

    /** Rows in mode order, then K1..K4; pure so it can be tested without JavaFX. */
    public static List<Row> rows(StudioState state) {
        List<Row> rows = new ArrayList<>();
        for (ModeSlot mode : ModeSlot.values()) {
            for (StudioPart part : KEYS) {
                KeyConfig key = state.getKeyConfig(mode, part);
                rows.add(new Row(mode.getShortName(), part.name().replace("KEY", "K"), describe(key)));
            }
        }
        return rows;
    }

    /** Human-readable binding: macro steps, preset, or shortcut, plus its label. */
    static String describe(KeyConfig key) {
        if (key == null) return localize("未设置");
        String binding;
        if (key.usesMacro()) {
            binding = localize("宏：") + key.formatMacroPreview();
        } else if (key.getVoicePreset() != VoicePreset.CUSTOM) {
            binding = key.getDisplaySummary();
        } else if (key.getHidCode() == 0) {
            binding = localize("未设置");
        } else {
            binding = VoiceActionRouter.formatShortcut(key.getHidCode());
        }
        String description = key.getDescription();
        return description == null || description.isBlank() ? binding : binding + "  ·  " + description;
    }

    /** @return true when the user confirmed the save */
    public static boolean confirm(StudioState state, Window owner) {
        Stage dialog = new Stage();
        dialog.initModality(Modality.WINDOW_MODAL);
        Window effectiveOwner = owner != null ? owner : activeWindow();
        if (effectiveOwner != null) dialog.initOwner(effectiveOwner);
        dialog.setTitle(localize("保存配置到设备"));
        dialog.setWidth(600);
        dialog.setHeight(480);

        Label title = new Label(localize("即将把以下按键配置写入键盘"));
        title.getStyleClass().add("dialog-card-title");

        TableView<Row> table = new TableView<>(FXCollections.observableArrayList(rows(state)));
        table.setColumnResizePolicy(TableView.CONSTRAINED_RESIZE_POLICY);
        TableColumn<Row, String> mode = new TableColumn<>(localize("模式"));
        mode.setCellValueFactory(cell -> new SimpleStringProperty(cell.getValue().mode()));
        mode.setPrefWidth(80);
        TableColumn<Row, String> key = new TableColumn<>(localize("键位"));
        key.setCellValueFactory(cell -> new SimpleStringProperty(cell.getValue().key()));
        key.setPrefWidth(60);
        TableColumn<Row, String> value = new TableColumn<>(localize("本次写入"));
        value.setCellValueFactory(cell -> new SimpleStringProperty(cell.getValue().value()));
        value.setPrefWidth(400);
        table.getColumns().add(mode);
        table.getColumns().add(key);
        table.getColumns().add(value);

        Label note = new Label(localize(
            "灯效、亮度和屏幕文字也会一并写入。K1 的短按 / 长按动作只保存在电脑上，不写入键盘。"));
        note.setWrapText(true);
        note.getStyleClass().add("hint-text");

        Button cancel = new Button(localize("取消"));
        cancel.setCancelButton(true);
        Button save = new Button(localize("保存到设备"));
        save.getStyleClass().add("button-prominent");
        save.setDefaultButton(true);
        ButtonBar buttons = new ButtonBar();
        buttons.getButtons().addAll(cancel, save);

        VBox root = new VBox(12, title, table, note, buttons);
        root.setPadding(new Insets(14));
        VBox.setVgrow(table, Priority.ALWAYS);
        Scene scene = new Scene(root);
        var css = SavePreviewDialog.class.getResource("/style.css");
        if (css != null) scene.getStylesheets().add(css.toExternalForm());
        dialog.setScene(scene);

        boolean[] confirmed = {false};
        save.setOnAction(event -> {
            confirmed[0] = true;
            dialog.close();
        });
        cancel.setOnAction(event -> dialog.close());
        dialog.showAndWait();
        return confirmed[0];
    }

    private static Window activeWindow() {
        return Window.getWindows().stream().filter(Window::isFocused).findFirst()
            .orElse(Window.getWindows().stream().filter(Window::isShowing).findFirst().orElse(null));
    }
}
