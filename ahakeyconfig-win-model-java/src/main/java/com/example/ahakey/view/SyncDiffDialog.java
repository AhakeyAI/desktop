package com.example.ahakey.view;

import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.util.KeyBindingDiffer;
import javafx.beans.property.SimpleStringProperty;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
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

/**
 * 保存前预览弹窗:不读取设备硬件配置,直接列出 StudioState 中本次要保存的
 * 16 个键位数据,让用户确认后再由调用方写入设备。
 */
public class SyncDiffDialog {

    public enum UserChoice {
        CONFIRM,    // 用户确认保存
        CANCEL      // 用户取消
    }

    /** 保存预览行:单个键位本次要写入设备的数据 */
    public record SaveRow(String modeName, String keyName, String value) {
    }

    private static Stage findActiveStage() {
        return Window.getWindows().stream()
            .filter(w -> w instanceof Stage)
            .map(w -> (Stage) w)
            .filter(Stage::isShowing)
            .findFirst()
            .orElse(null);
    }

    /**
     * 弹出保存预览弹窗。
     * <p>纯本地数据,不读取设备:直接把 StudioState 里 4 mode × 4 key 共 16 个
     * 键位配置列成表格展示,用户点"保存到设备"后由调用方写入。
     *
     * @param state 本地 StudioState(本次要保存的数据)
     * @param owner 父窗口
     * @return UserChoice 枚举,标识用户决定
     */
    public static UserChoice showSavePreview(StudioState state, Stage owner) {
        Stage dialog = new Stage();
        dialog.initModality(Modality.WINDOW_MODAL);
        Stage effectiveOwner = owner != null ? owner : findActiveStage();
        if (effectiveOwner != null) {
            dialog.initOwner(effectiveOwner);
        }
        dialog.setTitle("保存配置到设备");
        dialog.setWidth(560);
        dialog.setHeight(420);

        // 顶部标题
        Label titleLabel = new Label("即将保存以下配置到设备");
        titleLabel.getStyleClass().add("sync-dialog-title");

        // 从 StudioState 直接生成 16 行数据(不读硬件)
        ObservableList<SaveRow> rows = FXCollections.observableArrayList();
        StudioPart[] parts = {StudioPart.KEY1, StudioPart.KEY2, StudioPart.KEY3, StudioPart.KEY4};
        for (int m = 0; m < 4; m++) {
            ModeSlot mode = ModeSlot.fromIndex(m);
            for (int k = 0; k < 4; k++) {
                KeyConfig key = state.getKeyConfig(mode, parts[k]);
                rows.add(new SaveRow(
                    mode.getShortName(),
                    parts[k].name(),
                    KeyBindingDiffer.formatKeyConfig(key)
                ));
            }
        }

        TableView<SaveRow> table = new TableView<>(rows);
        table.setPlaceholder(new Label("无配置数据"));
        table.setColumnResizePolicy(TableView.CONSTRAINED_RESIZE_POLICY);

        TableColumn<SaveRow, String> modeCol = new TableColumn<>("模式");
        modeCol.setCellValueFactory(cd -> new SimpleStringProperty(cd.getValue().modeName()));
        modeCol.setPrefWidth(80);

        TableColumn<SaveRow, String> keyCol = new TableColumn<>("键位");
        keyCol.setCellValueFactory(cd -> new SimpleStringProperty(cd.getValue().keyName()));
        keyCol.setPrefWidth(70);

        TableColumn<SaveRow, String> valueCol = new TableColumn<>("本次保存数据");
        valueCol.setCellValueFactory(cd -> new SimpleStringProperty(cd.getValue().value()));
        valueCol.setPrefWidth(360);

        table.getColumns().addAll(modeCol, keyCol, valueCol);

        Label statusLabel = new Label(String.format("共 %d 个键位配置,确认后将写入设备。", rows.size()));
        statusLabel.getStyleClass().add("sync-dialog-status");

        // 底部按钮 — 用主 UI 的样式(取消 = .button-action 灰白,确认 = .button-prominent 蓝)
        Button cancelBtn = new Button("取消");
        cancelBtn.getStyleClass().add("button-action");
        cancelBtn.setCancelButton(true);
        Button confirmBtn = new Button("保存到设备");
        confirmBtn.getStyleClass().add("button-prominent");
        confirmBtn.setDefaultButton(true);

        ButtonBar buttonBar = new ButtonBar();
        buttonBar.getButtons().addAll(cancelBtn, confirmBtn);

        VBox root = new VBox(12, titleLabel, table, statusLabel, buttonBar);
        root.setPadding(new Insets(14));
        root.getStyleClass().add("sync-dialog-root");
        VBox.setVgrow(table, Priority.ALWAYS);
        Scene scene = new Scene(root);
        // 加载主 UI 的 style.css,让 TableView / Button 等组件继承主 UI 配色
        scene.getStylesheets().add(SyncDiffDialog.class.getResource("/style.css").toExternalForm());
        dialog.setScene(scene);

        // 用户选择
        UserChoice[] result = {UserChoice.CANCEL};
        confirmBtn.setOnAction(e -> {
            result[0] = UserChoice.CONFIRM;
            dialog.close();
        });
        cancelBtn.setOnAction(e -> {
            result[0] = UserChoice.CANCEL;
            dialog.close();
        });

        dialog.showAndWait();
        return result[0];
    }
}
