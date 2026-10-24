package com.example.ahakey.view;

import javafx.application.Platform;
import javafx.geometry.Pos;
import javafx.scene.Scene;
import javafx.scene.canvas.Canvas;
import javafx.scene.canvas.GraphicsContext;
import javafx.scene.control.Label;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.scene.paint.Color;
import javafx.scene.text.Font;
import javafx.scene.text.Text;
import javafx.stage.Stage;
import javafx.stage.StageStyle;

/**
 * 浮动语音通知窗口
 * 微信风格浮窗：白色圆角气泡 + 波形动画 + 绿色主题
 */
public class FloatingVoiceNotification {

    private Stage stage;
    private Canvas waveform;         // 波形动画
    private Text statusText;         // 状态文字
    private Label transcriptLabel;   // 实时转写文字
    private AnimationTimer pulseTimer;
    private boolean isTimerRunning = false;
    private double angle = 0;
    private String currentStatus = "idle";

    /** 状态配置 */
    private static class StatusConfig {
        String text;
        Color accentColor;
        boolean pulse;
        StatusConfig(String text, Color accentColor, boolean pulse) {
            this.text = text;
            this.accentColor = accentColor;
            this.pulse = pulse;
        }
    }

    public FloatingVoiceNotification() {
        init();
    }

    private void init() {
        stage = new Stage();
        stage.initStyle(StageStyle.TRANSPARENT);
        stage.setAlwaysOnTop(true);
        stage.setResizable(false);
        stage.initModality(javafx.stage.Modality.NONE);
        stage.initOwner(null);

        // 主容器：白色圆角气泡，带阴影
        VBox root = new VBox(10);
        root.setAlignment(Pos.CENTER);
        root.setStyle(
            "-fx-background-color: rgba(255, 255, 255, 0.96);" +
            "-fx-padding: 14 20;" +
            "-fx-background-radius: 14;" +
            "-fx-border-radius: 14;" +
            "-fx-border-color: rgba(0, 0, 0, 0.06);" +
            "-fx-border-width: 1;" +
            "-fx-effect: dropshadow(gaussian, rgba(0, 0, 0, 0.12), 20, 0.15, 0, 6);"
        );
        root.setFocusTraversable(false);
        root.setMouseTransparent(true);
        root.setPrefWidth(280); // 固定宽度，居中状态不随文字长度变化

        // 状态行：波形动画 + 状态文字
        HBox statusRow = new HBox(10);
        statusRow.setAlignment(Pos.CENTER);
        statusRow.setMouseTransparent(true);

        // 波形动画画布
        waveform = new Canvas(48, 24);
        waveform.setMouseTransparent(true);

        // 状态文字
        statusText = new Text();
        statusText.setFont(Font.font("Microsoft YaHei", 15));
        statusText.setFill(Color.rgb(29, 29, 31));

        statusRow.getChildren().addAll(waveform, statusText);

        // 实时转写文字
        transcriptLabel = new Label();
        transcriptLabel.setFont(Font.font("Microsoft YaHei", 13));
        transcriptLabel.setTextFill(Color.rgb(100, 110, 125));
        transcriptLabel.setWrapText(true);
        transcriptLabel.setMaxWidth(246); // 280px - 14px左padding - 20px右padding
        transcriptLabel.setMouseTransparent(true);
        transcriptLabel.setVisible(false);
        transcriptLabel.setAlignment(Pos.CENTER);

        root.getChildren().addAll(transcriptLabel, statusRow);

        // 场景
        Scene scene = new Scene(root);
        scene.setFill(Color.TRANSPARENT);
        scene.getRoot().setFocusTraversable(false);
        stage.setScene(scene);

        // 启动脉冲动画
        startPulseAnimation();
    }

    /**
     * 更新状态
     */
    public void updateStatus(String status, String message) {
        Platform.runLater(() -> {
            currentStatus = status;
            StatusConfig config = getStatusConfig(status, message);
            statusText.setText(config.text);
            drawWaveform(config.accentColor, config.pulse);
            stage.sizeToScene();
            if (!"idle".equals(status) && !"stopped".equals(status) && !"ready".equals(status)) {
                show();
            } else {
                if (transcriptLabel != null) {
                    transcriptLabel.setText("");
                    transcriptLabel.setVisible(false);
                }
                hide();
            }
        });
    }

    /**
     * 更新实时转写文字
     */
    public void updateTranscript(String text) {
        Platform.runLater(() -> {
            if (transcriptLabel == null) return;
            if (text == null || text.isEmpty()) {
                transcriptLabel.setText("");
                transcriptLabel.setVisible(false);
            } else {
                transcriptLabel.setText(text);
                transcriptLabel.setVisible(true);
            }
            stage.sizeToScene();
            show();
        });
    }

    /**
     * 获取状态配置
     */
    private StatusConfig getStatusConfig(String status, String message) {
        Color wechatGreen = Color.rgb(7, 193, 96);
        Color wechatOrange = Color.rgb(255, 150, 0);
        Color wechatRed = Color.rgb(255, 80, 80);
        Color wechatGray = Color.rgb(180, 185, 195);
        return switch (status) {
            case "recording"   -> new StatusConfig("语音输入中", wechatGreen, true);
            case "recognizing" -> new StatusConfig("识别中", wechatOrange, true);
            case "processing"  -> new StatusConfig("处理中", wechatOrange, true);
            case "ready"       -> new StatusConfig("语音就绪", wechatGreen, false);
            case "starting"    -> new StatusConfig("启动中", wechatOrange, true);
            default -> new StatusConfig(message != null ? message : "空闲", wechatGray, false);
        };
    }

    /**
     * 绘制微信风格波形动画
     * 3 条竖条，高度随 pulse 状态变化
     */
    private void drawWaveform(Color accent, boolean pulse) {
        GraphicsContext gc = waveform.getGraphicsContext2D();
        gc.clearRect(0, 0, waveform.getWidth(), waveform.getHeight());

        double cx = waveform.getWidth() / 2;
        double cy = waveform.getHeight() / 2;
        double barWidth = 4;
        double gap = 5;
        double totalWidth = 3 * barWidth + 2 * gap;
        double startX = cx - totalWidth / 2;

        // 脉冲时，波形高度随角度变化；静止时固定高度
        double[] heights;
        if (pulse) {
            double phase = Math.sin(angle * Math.PI / 180);
            heights = new double[]{
                6 + Math.abs(Math.sin(angle * Math.PI / 180)) * 10,
                6 + Math.abs(Math.sin((angle + 60) * Math.PI / 180)) * 10,
                6 + Math.abs(Math.sin((angle + 120) * Math.PI / 180)) * 10
            };
        } else {
            heights = new double[]{6, 6, 6};
        }

        // 绘制圆角竖条
        for (int i = 0; i < 3; i++) {
            double x = startX + i * (barWidth + gap);
            double h = heights[i];
            double y = cy - h / 2;
            gc.setFill(accent);
            gc.setGlobalAlpha(0.9);
            gc.fillRoundRect(x, y, barWidth, h, 2, 2);
        }
        gc.setGlobalAlpha(1.0);
    }

    /**
     * 启动脉冲动画
     */
    private void startPulseAnimation() {
        pulseTimer = new AnimationTimer() {
            @Override
            public void handle(long now) {
                if (!isTimerRunning) return;
                angle = (angle + 5) % 360;
                if ("recording".equals(currentStatus) || "recognizing".equals(currentStatus) ||
                    "processing".equals(currentStatus) || "starting".equals(currentStatus)) {
                    Platform.runLater(() -> {
                        StatusConfig config = getStatusConfig(currentStatus, statusText.getText());
                        drawWaveform(config.accentColor, config.pulse);
                    });
                }
            }
        };
        isTimerRunning = true;
        pulseTimer.start();
    }

    /**
     * 显示窗口
     */
    public void show() {
        Platform.runLater(() -> {
            if (!stage.isShowing()) {
                try {
                    com.sun.jna.platform.win32.WinDef.HWND foregroundWindow =
                        com.sun.jna.platform.win32.User32.INSTANCE.GetForegroundWindow();
                    stage.show();
                    if (foregroundWindow != null) {
                        com.sun.jna.platform.win32.User32.INSTANCE.SetForegroundWindow(foregroundWindow);
                    }
                } catch (Exception e) {
                    stage.show();
                }
                Platform.runLater(() -> {
                    double screenWidth = javafx.stage.Screen.getPrimary().getBounds().getWidth();
                    double screenHeight = javafx.stage.Screen.getPrimary().getBounds().getHeight();
                    stage.setX((screenWidth - stage.getWidth()) / 2);
                    stage.setY(screenHeight - 100);
                });
            }
        });
    }

    /**
     * 隐藏窗口
     */
    public void hide() {
        Platform.runLater(() -> {
            if (stage.isShowing()) {
                stage.hide();
            }
        });
    }

    /**
     * 关闭窗口
     */
    public void close() {
        isTimerRunning = false;
        if (pulseTimer != null) {
            pulseTimer.stop();
        }
        if (stage != null) {
            stage.close();
        }
    }

    /**
     * 动画计时器（兼容JavaFX）
     */
    private abstract class AnimationTimer {
        public abstract void handle(long now);
        public void start() {
            FloatingVoiceNotification.this.isTimerRunning = true;
            new Thread(() -> {
                while (FloatingVoiceNotification.this.isTimerRunning) {
                    handle(System.currentTimeMillis());
                    try { Thread.sleep(16); } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }).start();
        }
        public void stop() {
            FloatingVoiceNotification.this.isTimerRunning = false;
        }
    }
}