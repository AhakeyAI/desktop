package com.example.ahakey.view;

import com.example.ahakey.model.StudioPart;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.util.KeyBindingDiffer;
import javafx.application.Platform;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.control.cell.PropertyValueFactory;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;
import javafx.stage.Modality;
import javafx.stage.Stage;
import javafx.stage.Window;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;

/**
 * 同步后验证弹窗:从设备重新读出 16 个键位,跟 StudioState 期望比对,
 * 让用户看到"哪些键位同步成功,哪些没对上"。
 */
public class SyncVerifyDialog {

    private static final Logger logger = LoggerFactory.getLogger(SyncVerifyDialog.class);

    private static Stage findActiveStage() {
        return Window.getWindows().stream()
            .filter(w -> w instanceof Stage)
            .map(w -> (Stage) w)
            .filter(Stage::isShowing)
            .findFirst()
            .orElse(null);
    }

    /**
     * 弹出验证弹窗,后台读取 EEPROM 后填充表格。
     *
     * @param bleManager 用于 readKeyBindingFull
     * @param state      StudioState 期望
     * @param owner      父窗口
     */
    public static void showAndWait(BleManager bleManager,
                                   com.example.ahakey.model.StudioState state,
                                   Stage owner) {
        Stage dialog = new Stage();
        dialog.initModality(Modality.WINDOW_MODAL);
        Stage effectiveOwner = owner != null ? owner : findActiveStage();
        if (effectiveOwner != null) {
            dialog.initOwner(effectiveOwner);
        }
        dialog.setTitle("同步完成 - 验证");
        dialog.setWidth(640);
        dialog.setHeight(420);

        Label titleLabel = new Label("正在重新读取设备验证...");
        titleLabel.getStyleClass().add("sync-dialog-title");

        ProgressIndicator progress = new ProgressIndicator();
        progress.setMaxSize(40, 40);

        HBox topBox = new HBox(10, titleLabel, progress);
        topBox.setAlignment(Pos.CENTER_LEFT);

        // 表格(默认只显示有差异的行)
        ObservableList<KeyBindingDiffer.DiffEntry> allRows = FXCollections.observableArrayList();
        javafx.collections.transformation.FilteredList<KeyBindingDiffer.DiffEntry> rows =
            new javafx.collections.transformation.FilteredList<>(allRows, e -> e.changed());
        TableView<KeyBindingDiffer.DiffEntry> table = new TableView<>(rows);
        table.setPlaceholder(new Label("等待验证..."));
        table.setColumnResizePolicy(TableView.CONSTRAINED_RESIZE_POLICY);

        TableColumn<KeyBindingDiffer.DiffEntry, String> modeCol = new TableColumn<>("模式");
        modeCol.setCellValueFactory(cd -> new javafx.beans.property.SimpleStringProperty(
            cd.getValue().getModeName()));
        modeCol.setPrefWidth(80);

        TableColumn<KeyBindingDiffer.DiffEntry, String> keyCol = new TableColumn<>("键位");
        keyCol.setCellValueFactory(cd -> {
            StudioPart p = cd.getValue().part();
            String label = switch (p) {
                case KEY1 -> "KEY1";
                case KEY2 -> "KEY2";
                case KEY3 -> "KEY3";
                case KEY4 -> "KEY4";
                default -> p.name();
            };
            return new javafx.beans.property.SimpleStringProperty(label);
        });
        keyCol.setPrefWidth(70);

        TableColumn<KeyBindingDiffer.DiffEntry, String> expectedCol = new TableColumn<>("期望值");
        expectedCol.setCellValueFactory(cd -> new javafx.beans.property.SimpleStringProperty(cd.getValue().after()));
        expectedCol.setPrefWidth(220);

        TableColumn<KeyBindingDiffer.DiffEntry, String> actualCol = new TableColumn<>("设备实际");
        actualCol.setCellValueFactory(cd -> new javafx.beans.property.SimpleStringProperty(cd.getValue().before()));
        actualCol.setPrefWidth(220);

        TableColumn<KeyBindingDiffer.DiffEntry, Boolean> okCol = new TableColumn<>("状态");
        okCol.setCellValueFactory(cd -> new javafx.beans.property.SimpleBooleanProperty(!cd.getValue().changed()));
        okCol.setCellFactory(col -> new TableCell<>() {
            @Override
            protected void updateItem(Boolean ok, boolean empty) {
                super.updateItem(ok, empty);
                if (empty || ok == null) {
                    setText(null);
                    setStyle("");
                } else if (ok) {
                    setText("✓ 一致");
                    // 验证一致:用主 UI 调色板的成功绿 #30d158(比 bootstrap 绿轻)
                    getStyleClass().setAll("sync-cell-unchanged");
                } else {
                    setText("✗ 不一致");
                    // 验证不一致:跟 diff 的"变化"保持一致用琥珀 #ff9f0a
                    // (一致性比"错误红"更重要,避免被误读为"程序崩了")
                    getStyleClass().setAll("sync-cell-changed");
                }
            }
        });
        okCol.setPrefWidth(80);

        table.getColumns().addAll(modeCol, keyCol, expectedCol, actualCol, okCol);

        // "显示全部" 复选框(默认只显示有差异的行)
        CheckBox showAllCheck = new CheckBox("显示全部 16 项");
        showAllCheck.setSelected(false);
        showAllCheck.selectedProperty().addListener((obs, oldVal, newVal) -> {
            rows.setPredicate(newVal ? e -> true : KeyBindingDiffer.DiffEntry::changed);
        });
        HBox checkBoxBar = new HBox(showAllCheck);
        checkBoxBar.setAlignment(Pos.CENTER_LEFT);

        Button closeBtn = new Button("关闭");
        closeBtn.getStyleClass().add("button-action");
        closeBtn.setDefaultButton(true);
        closeBtn.setOnAction(e -> dialog.close());
        ButtonBar buttonBar = new ButtonBar();
        buttonBar.getButtons().add(closeBtn);

        Label statusLabel = new Label("");
        statusLabel.getStyleClass().add("sync-dialog-status");

        VBox root = new VBox(12, topBox, checkBoxBar, table, statusLabel, buttonBar);
        root.setPadding(new Insets(14));
        root.getStyleClass().add("sync-dialog-root");
        VBox.setVgrow(table, Priority.ALWAYS);
        Scene scene = new Scene(root);
        scene.getStylesheets().add(SyncVerifyDialog.class.getResource("/style.css").toExternalForm());
        dialog.setScene(scene);

        dialog.setOnShown(e -> {
            new Thread(() -> {
                try {
                    List<AhaKeyResponseParser.FullKeyBinding> bindings = new java.util.ArrayList<>();
                    for (int m = 0; m < 4; m++) {
                        for (int k = 0; k < 4; k++) {
                            AhaKeyResponseParser.FullKeyBinding b = bleManager.readKeyBindingFull(m, k);
                            bindings.add(b);
                        }
                    }
                    List<KeyBindingDiffer.DiffEntry> diffs = KeyBindingDiffer.diff(bindings, state);
                    int mismatched = KeyBindingDiffer.countChanged(diffs);
                    int matched = 16 - mismatched;
                    Platform.runLater(() -> {
                        allRows.setAll(diffs);
                        progress.setVisible(false);
                        if (mismatched == 0) {
                            titleLabel.setText(String.format("✓ 同步成功:16/16 键位完全一致"));
                            titleLabel.getStyleClass().setAll("sync-dialog-title", "sync-dialog-title-success");
                            statusLabel.setText("默认隐藏无变化行,勾选'显示全部'可看完整列表");
                        } else {
                            titleLabel.setText(String.format("⚠ 同步有差异:%d 项一致, %d 项不一致", matched, mismatched));
                            // 标题用琥珀色(#ff9f0a),跟 cell-changed 配色一致
                            titleLabel.getStyleClass().setAll("sync-dialog-title", "sync-dialog-title-warning");
                            statusLabel.setText("可能原因:其他端在同步后修改了设备 EEPROM,或同步过程中断");
                        }
                    });
                } catch (Exception ex) {
                    logger.error("[SyncVerifyDialog] 验证读取失败", ex);
                    Platform.runLater(() -> {
                        progress.setVisible(false);
                        titleLabel.setText("验证失败");
                        // 错误场景才用主 UI 的红 #ff453a,跟"差异"警示色区分
                        titleLabel.getStyleClass().setAll("sync-dialog-title", "sync-dialog-title-error");
                        statusLabel.setText("错误: " + ex.getMessage());
                    });
                }
            }, "sync-verify-reader").start();
        });

        dialog.showAndWait();
    }
}
