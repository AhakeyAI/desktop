package com.example.ahakey.view;

import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.canvas.Canvas;
import javafx.scene.canvas.GraphicsContext;
import javafx.scene.layout.HBox;
import javafx.scene.paint.Color;
import javafx.scene.text.Font;
import javafx.scene.text.Text;
import javafx.stage.Stage;
import javafx.stage.StageStyle;

/**
 * 浮动语音通知窗口（Ubuntu/Linux 版本）
 * 在桌面上显示语音状态提示，始终在最顶层
 */
public class FloatingVoiceNotification {
    
    private Stage stage;
    private Canvas indicator;
    private Text statusText;
    private AnimationTimer pulseTimer;
    private boolean isTimerRunning = false;
    private double angle = 0;
    private String currentStatus = "idle";
    
    /**
     * 状态配置
     */
    private static class StatusConfig {
        String text;
        Color indicatorColor;
        boolean pulse;
        
        StatusConfig(String text, Color indicatorColor, boolean pulse) {
            this.text = text;
            this.indicatorColor = indicatorColor;
            this.pulse = pulse;
        }
    }
    
    public FloatingVoiceNotification() {
        init();
    }
    
    private void init() {
        // 创建主窗口
        stage = new Stage();
        stage.initStyle(StageStyle.TRANSPARENT);
        stage.setAlwaysOnTop(true);
        stage.setResizable(false);
        // 设置为非模态，不阻塞其他窗口
        stage.initModality(javafx.stage.Modality.NONE);
        // 设置无所有者窗口
        stage.initOwner(null);
        
        // 创建内容区域
        HBox content = new HBox(12);
        content.setStyle("-fx-background-color: rgba(0, 0, 0, 0.85); -fx-padding: 12 16; -fx-border-radius: 8; -fx-background-radius: 8;");
        // 设置根节点不接收焦点
        content.setFocusTraversable(false);
        // 设置鼠标透明，点击会穿透到下面的窗口
        content.setMouseTransparent(true);
        
        // 创建指示灯
        indicator = new Canvas(16, 16);
        
        // 创建状态文字
        statusText = new Text();
        statusText.setFont(Font.font("Noto Sans CJK SC", 14));
        statusText.setFill(Color.WHITE);
        
        content.getChildren().addAll(indicator, statusText);
        
        // 创建场景
        Scene scene = new Scene(content);
        scene.setFill(Color.TRANSPARENT);
        // 场景不接收鼠标事件，不获取焦点
        scene.getRoot().setFocusTraversable(false);
        // 场景鼠标透明
        scene.setFill(javafx.scene.paint.Color.TRANSPARENT);
        
        stage.setScene(scene);
        
        // 启动脉冲动画
        startPulseAnimation();
    }
    
    /**
     * 更新状态
     * @param status 状态码
     * @param message 状态消息
     */
    public void updateStatus(String status, String message) {
        Platform.runLater(() -> {
            currentStatus = status;
            
            StatusConfig config = getStatusConfig(status, message);
            statusText.setText(config.text);
            
            // 更新指示灯颜色
            drawIndicator(config.indicatorColor, config.pulse);
            
            // 调整窗口大小
            stage.sizeToScene();
            
            // 如果不是空闲状态，显示窗口
            if (!"idle".equals(status) && !"stopped".equals(status) && !"ready".equals(status)) {
                show();
            } else {
                hide();
            }
        });
    }
    
    /**
     * 获取状态配置
     */
    private StatusConfig getStatusConfig(String status, String message) {
        return switch (status) {
            case "recording" -> new StatusConfig("语音输入中", Color.rgb(231, 76, 60), true);   // 红色
            case "recognizing" -> new StatusConfig("识别中", Color.rgb(245, 166, 35), true);     // 橙色
            case "processing" -> new StatusConfig("处理中", Color.rgb(245, 166, 35), true);     // 橙色
            case "ready" -> new StatusConfig("语音就绪", Color.rgb(46, 204, 113), false);       // 绿色
            case "starting" -> new StatusConfig("启动中", Color.rgb(245, 166, 35), true);       // 橙色
            default -> new StatusConfig(message != null ? message : "空闲", Color.rgb(167, 175, 186), false); // 灰色
        };
    }
    
    /**
     * 绘制指示灯
     */
    private void drawIndicator(Color color, boolean pulse) {
        GraphicsContext gc = indicator.getGraphicsContext2D();
        gc.clearRect(0, 0, indicator.getWidth(), indicator.getHeight());
        
        double centerX = indicator.getWidth() / 2;
        double centerY = indicator.getHeight() / 2;
        double radius = 6;
        
        // 绘制外圈光晕（脉冲效果）
        if (pulse) {
            double alpha = 0.3 + Math.sin(angle * Math.PI / 180) * 0.2;
            gc.setFill(new Color(color.getRed(), color.getGreen(), color.getBlue(), alpha));
            gc.fillOval(centerX - radius - 4, centerY - radius - 4, radius * 2 + 8, radius * 2 + 8);
        }
        
        // 绘制指示灯
        gc.setFill(color);
        gc.fillOval(centerX - radius, centerY - radius, radius * 2, radius * 2);
        
        // 绘制高光
        gc.setFill(Color.WHITE);
        gc.setGlobalAlpha(0.4);
        gc.fillOval(centerX - radius * 0.4, centerY - radius * 0.4, radius * 0.8, radius * 0.8);
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
                
                // 只在需要脉冲效果的状态时更新
                if ("recording".equals(currentStatus) || "recognizing".equals(currentStatus) || 
                    "processing".equals(currentStatus) || "starting".equals(currentStatus)) {
                    Platform.runLater(() -> {
                        StatusConfig config = getStatusConfig(currentStatus, statusText.getText());
                        drawIndicator(config.indicatorColor, config.pulse);
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
                // 计算位置：屏幕底部中间偏上
                double screenWidth = javafx.stage.Screen.getPrimary().getBounds().getWidth();
                double screenHeight = javafx.stage.Screen.getPrimary().getBounds().getHeight();
                stage.setX((screenWidth - stage.getWidth()) / 2);
                stage.setY(screenHeight - 100);
                
                // 显示窗口
                stage.show();
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
                    try {
                        Thread.sleep(16); // ~60fps
                    } catch (InterruptedException e) {
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
