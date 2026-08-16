package com.example.ahakey.view;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.BundledGifLibrary;
import com.example.ahakey.service.OledUploadService;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.image.Image;
import javafx.scene.image.ImageView;
import javafx.scene.layout.*;
import javafx.stage.FileChooser;
import javafx.stage.Modality;
import javafx.stage.Stage;
import javafx.stage.Window;

import java.io.File;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/** USB-only editor for the firmware fixed 4x4 GIF layout. */
public final class ScreenAnimationDialog {
    private static final String[] ASSETS = {"默认", "运行中", "等待/错误", "已完成"};

    private ScreenAnimationDialog() {}

    private static final class DialogState {
        final AtomicBoolean busy = new AtomicBoolean();
        final List<Button> operationButtons = new ArrayList<>();
        final List<Job> allJobs = new ArrayList<>();

        void register(Button button) {
            operationButtons.add(button);
        }

        boolean begin() {
            if (!busy.compareAndSet(false, true)) return false;
            Platform.runLater(() -> operationButtons.forEach(button -> button.setDisable(true)));
            return true;
        }

        void finish() {
            busy.set(false);
            Platform.runLater(() -> operationButtons.forEach(button -> button.setDisable(false)));
        }
    }

    private record Job(ModeSlot mode, int asset, Path path, Label status) {}

    public static void show(Window owner, StudioController controller) {
        Stage stage = new Stage();
        if (owner != null) stage.initOwner(owner);
        stage.initModality(Modality.NONE);
        stage.setTitle("屏幕动画");

        DialogState dialogState = new DialogState();
        Label flashInfo = new Label("正在读取设备 Flash 与动画配置…");
        flashInfo.setWrapText(true);
        TabPane profiles = new TabPane();
        for (ModeSlot mode : ModeSlot.values())
            profiles.getTabs().add(profileTab(stage, controller, mode, dialogState));

        Button restoreAll = new Button("恢复全部内置动画");
        dialogState.register(restoreAll);
        restoreAll.setOnAction(event -> {
            if (!confirm("将依次覆盖四个模式的全部 16 个动画分区，是否继续？")) return;
            runJobs(controller, dialogState, new ArrayList<>(dialogState.allJobs), "全部内置动画恢复完成。");
        });

        Label guidance = new Label(
            "每个模式包含 4 个固定分区；仅支持 USB 写入。软件会先读取真实 Flash 容量，"
                + "所有写入严格串行执行。GIF 建议 160×80；默认动画最多 8 帧，其他状态最多 12 帧。"
        );
        guidance.setWrapText(true);
        VBox root = new VBox(10, guidance, flashInfo, restoreAll, profiles);
        root.setPadding(new Insets(16));
        stage.setScene(new Scene(root, 820, 620));
        stage.show();

        refreshDeviceSummary(controller, flashInfo);
    }

    private static Tab profileTab(Stage owner, StudioController controller, ModeSlot mode,
                                  DialogState dialogState) {
        FlowPane cards = new FlowPane(12, 12);
        File[] selected = new File[ASSETS.length];
        Label[] statuses = new Label[ASSETS.length];
        List<Job> modeDefaults = new ArrayList<>();
        for (int asset = 0; asset < ASSETS.length; asset++) {
            VBox card = assetCard(owner, controller, mode, asset, selected, statuses,
                modeDefaults, dialogState);
            cards.getChildren().add(card);
        }

        Button uploadAllSelected = new Button("写入本模式全部当前动画");
        Button restoreMode = new Button("恢复本模式内置动画");
        dialogState.register(uploadAllSelected);
        dialogState.register(restoreMode);
        uploadAllSelected.setOnAction(event -> {
            List<Job> jobs = new ArrayList<>();
            for (int asset = 0; asset < selected.length; asset++) {
                if (selected[asset] != null)
                    jobs.add(new Job(mode, asset, selected[asset].toPath(), statuses[asset]));
            }
            if (jobs.isEmpty()) {
                new Alert(Alert.AlertType.WARNING, "本模式没有可写入的动画。").showAndWait();
                return;
            }
            runJobs(controller, dialogState, jobs, "本模式当前动画写入完成。");
        });
        restoreMode.setOnAction(event -> {
            if (confirm("将覆盖 " + mode.getShortName() + " 的四个动画分区，是否继续？"))
                runJobs(controller, dialogState, new ArrayList<>(modeDefaults), "本模式内置动画恢复完成。");
        });

        ScrollPane scroll = new ScrollPane(cards);
        scroll.setFitToWidth(true);
        VBox content = new VBox(10, new HBox(8, uploadAllSelected, restoreMode), scroll);
        Tab tab = new Tab(mode.getShortName(), content);
        tab.setClosable(false);
        return tab;
    }

    private static VBox assetCard(Stage owner, StudioController controller, ModeSlot mode, int asset,
                                  File[] selected, Label[] statuses, List<Job> modeDefaults,
                                  DialogState dialogState) {
        Label title = new Label(ASSETS[asset]);
        title.setStyle("-fx-font-weight:bold;");
        ImageView preview = new ImageView();
        preview.setFitWidth(160);
        preview.setFitHeight(80);
        preview.setPreserveRatio(true);
        Label fileName = new Label("内置动画");
        fileName.setMaxWidth(190);
        Label status = new Label("正在读取设备配置…");
        status.setWrapText(true);
        statuses[asset] = status;

        Path bundled = null;
        try {
            bundled = BundledGifLibrary.extract(mode, asset);
            selected[asset] = bundled.toFile();
            if (BundledGifLibrary.resource(mode, asset) != null)
                preview.setImage(new Image(BundledGifLibrary.resource(mode, asset).toExternalForm(),
                    160, 80, true, true));
        } catch (Exception e) {
            status.setText("内置动画不可用：" + e.getMessage());
        }

        Job defaultJob = bundled == null ? null : new Job(mode, asset, bundled, status);
        if (defaultJob != null) {
            modeDefaults.add(defaultJob);
            dialogState.allJobs.add(defaultJob);
        }

        Button choose = new Button("选择 GIF");
        Button upload = new Button("写入当前动画");
        Button restore = new Button("写入内置动画");
        Button clear = new Button("清空状态");
        dialogState.register(choose);
        dialogState.register(upload);
        dialogState.register(restore);
        dialogState.register(clear);
        upload.setDisable(selected[asset] == null);
        restore.setDisable(defaultJob == null);

        choose.setOnAction(event -> {
            FileChooser picker = new FileChooser();
            picker.setTitle("选择 160×80 GIF");
            picker.getExtensionFilters().add(new FileChooser.ExtensionFilter("GIF 动画", "*.gif"));
            File file = picker.showOpenDialog(owner);
            if (file == null) return;
            selected[asset] = file;
            fileName.setText(file.getName());
            preview.setImage(new Image(file.toURI().toString(), 160, 80, true, true));
            status.setText("已选择本地 GIF，等待写入；设备原配置尚未改变。");
        });
        upload.setOnAction(event -> runJobs(controller, dialogState,
            List.of(new Job(mode, asset, selected[asset].toPath(), status)), "动画写入完成。"));
        restore.setOnAction(event -> {
            if (defaultJob != null)
                runJobs(controller, dialogState, List.of(defaultJob), "内置动画恢复完成。");
        });
        clear.setOnAction(event -> {
            if (!dialogState.begin()) {
                status.setText("已有动画操作正在进行，请等待完成。");
                return;
            }
            OledUploadService.clearAsset(controller.getBleManager(), mode, asset,
                result -> Platform.runLater(() -> {
                    status.setText(result + "；设备当前 0 帧");
                    dialogState.finish();
                }),
                error -> Platform.runLater(() -> {
                    status.setText("清空失败：" + error);
                    dialogState.finish();
                }));
        });

        VBox card = new VBox(7, title, preview, fileName, status,
            new HBox(7, choose, upload), new HBox(7, restore, clear));
        card.setPadding(new Insets(12));
        card.setPrefWidth(370);
        card.setStyle("-fx-background-color:#f4f6f8;-fx-background-radius:10;"
            + "-fx-border-color:#d8dee8;-fx-border-radius:10;");
        refreshAssetState(controller, mode, asset, status);
        return card;
    }

    private static void runJobs(StudioController controller, DialogState dialogState,
                                List<Job> jobs, String successMessage) {
        if (!dialogState.begin()) {
            new Alert(Alert.AlertType.WARNING, "已有动画操作正在进行，请等待完成。").showAndWait();
            return;
        }
        Thread worker = new Thread(() -> {
            String failure = null;
            for (Job job : jobs) {
                CountDownLatch done = new CountDownLatch(1);
                AtomicReference<String> error = new AtomicReference<>();
                OledUploadService.uploadAsset(controller.getBleManager(), job.mode(), job.asset(),
                    job.path(), 12,
                    progress -> Platform.runLater(() -> job.status().setText(progress.detail())),
                    result -> {
                        Platform.runLater(() -> job.status().setText(result));
                        done.countDown();
                    },
                    message -> {
                        error.set(message);
                        Platform.runLater(() -> job.status().setText("写入失败：" + message));
                        done.countDown();
                    });
                try {
                    done.await();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    failure = "操作已中断";
                    break;
                }
                if (error.get() != null) {
                    failure = error.get();
                    break;
                }
            }
            String finalFailure = failure;
            Platform.runLater(() -> {
                dialogState.finish();
                if (finalFailure == null)
                    new Alert(Alert.AlertType.INFORMATION, successMessage).showAndWait();
                else
                    new Alert(Alert.AlertType.ERROR, "写入未完成：" + finalFailure).showAndWait();
            });
        }, "oled-dialog-sequence");
        worker.setDaemon(true);
        worker.start();
    }

    private static void refreshDeviceSummary(StudioController controller, Label label) {
        Thread thread = new Thread(() -> {
            String text;
            try {
                var layout = controller.getBleManager().queryGifLayout();
                if (layout == null) text = "设备未返回 Flash 布局。";
                else if (!layout.hasPhysicalFlashDiagnostics())
                    text = "固件仅返回旧版布局，写入前请升级到固件 1.4.3。";
                else text = String.format(
                    "Flash ID 0x%04X；实际容量 %.1f MiB；可用帧槽 %d；规划分区共 %d 个帧槽。",
                    layout.flashId(), layout.flashBytes() / 1048576.0, layout.frameSlots(),
                    AhaKeyProtocol.GIF_TOTAL_PLANNED_FRAMES);
            } catch (Exception e) {
                text = "读取 Flash 布局失败：" + errorMessage(e);
            }
            String result = text;
            Platform.runLater(() -> label.setText(result));
        }, "oled-layout-read");
        thread.setDaemon(true);
        thread.start();
    }

    private static void refreshAssetState(StudioController controller, ModeSlot mode, int asset,
                                          Label status) {
        Thread thread = new Thread(() -> {
            String text;
            try {
                var state = OledUploadService.readAssetState(controller.getBleManager(), mode, asset);
                text = "设备当前：" + state.frameCount() + " 帧，起始帧 " + state.startIndex()
                    + (state.frameCount() > 0 ? "，帧间隔 " + state.frameInterval() + " ms" : "");
            } catch (Exception e) {
                text = "设备配置读取失败：" + errorMessage(e);
            }
            String result = text;
            Platform.runLater(() -> status.setText(result));
        }, "oled-state-read-" + mode.getIndex() + "-" + asset);
        thread.setDaemon(true);
        thread.start();
    }

    private static boolean confirm(String message) {
        return new Alert(Alert.AlertType.CONFIRMATION, message, ButtonType.OK, ButtonType.CANCEL)
            .showAndWait().orElse(ButtonType.CANCEL) == ButtonType.OK;
    }

    private static String errorMessage(Throwable error) {
        return error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
    }
}
