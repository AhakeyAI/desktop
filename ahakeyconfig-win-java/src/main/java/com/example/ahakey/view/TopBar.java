package com.example.ahakey.view;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.service.AgentManager;
import com.example.ahakey.service.VoiceInputManager;
import com.example.ahakey.util.Icons;
import javafx.application.Platform;
import javafx.beans.binding.Bindings;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.Menu;
import javafx.scene.control.MenuBar;
import javafx.scene.control.MenuItem;
import javafx.scene.control.SeparatorMenuItem;
import javafx.scene.control.TextArea;
import javafx.scene.control.ToggleButton;
import javafx.scene.control.ScrollPane;
import javafx.scene.layout.*;
import javafx.scene.paint.Color;
import javafx.scene.text.Text;
import javafx.stage.Stage;
import javafx.scene.Scene;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import javafx.scene.control.Alert;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.io.File;
import javafx.scene.canvas.Canvas;
import javafx.scene.canvas.GraphicsContext;
import javafx.animation.AnimationTimer;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fasterxml.jackson.databind.node.ArrayNode;

public class TopBar extends VBox {
    private final StudioController controller;
    private final DeviceStatus deviceStatus;
    private final StudioState studioState;
    private final AgentManager agentManager;
    private VoiceInputManager voiceInputManager;
    private TextArea logArea;
    
    // 语音相关UI组件
    private Button voiceRecordButton;
    private VoiceStatusLamp voiceStatusLamp;
    private Label voiceStatusLabel;
    private Label voiceResultPreview;
    private volatile boolean isRecording = false;
    private volatile boolean voiceRunning = false;
    private FloatingVoiceNotification floatingNotification;  // 浮动通知窗口

    public TopBar(StudioController controller, DeviceStatus deviceStatus,
                  StudioState studioState, AgentManager agentManager) {
        this.controller = controller;
        this.deviceStatus = deviceStatus;
        this.studioState = studioState;
        this.agentManager = agentManager;
        setSpacing(0);
        setPadding(new Insets(0));
        getStyleClass().add("top-bar");
        initContent();
    }
    
    /**
     * 设置语音输入管理器
     */
    public void setVoiceInputManager(VoiceInputManager voiceInputManager) {
        this.voiceInputManager = voiceInputManager;
        updateVoiceButtonState();
    }

    private void initContent() {
        Text titleIcon = Icons.keyboard("20");
        Label titleLabel = new Label("AhaKey Studio");
        titleLabel.getStyleClass().add("title");
        HBox titleBox = new HBox(8);
        titleBox.getChildren().addAll(titleIcon, titleLabel);

        HBox infoPills = new HBox(10);
        infoPills.getChildren().addAll(
            new InfoPill(
                Bindings.createStringBinding(
                    () -> controller.isEffectivelyConnected() ? "已连接"
                        : (deviceStatus.isScanning() ? "扫描中" : "未连接"),
                    deviceStatus.isConnectedProperty(),
                    deviceStatus.isScanningProperty()
                ),
                deviceStatus.deviceNameProperty(),
                Bindings.createObjectBinding(
                    () -> controller.isEffectivelyConnected() ? AccentColor.GREEN : AccentColor.ORANGE,
                    deviceStatus.isConnectedProperty()
                )
            ),
            new InfoPill(
                Bindings.createStringBinding(() -> "电量"),
                Bindings.createStringBinding(
                    () -> controller.isEffectivelyConnected() ? deviceStatus.getBatteryLevel() + "%" : "—",
                    deviceStatus.isConnectedProperty(),
                    deviceStatus.batteryLevelProperty()
                ),
                Bindings.createObjectBinding(() -> AccentColor.BLUE)
            ),
            new InfoPill(
                Bindings.createStringBinding(() -> "拨杆"),
                Bindings.createStringBinding(deviceStatus::getSwitchTitle, deviceStatus.switchStateProperty()),
                Bindings.createObjectBinding(
                    () -> deviceStatus.isAutoApproval() ? AccentColor.MINT : AccentColor.INDIGO,
                    deviceStatus.switchStateProperty()
                )
            )
        );

        // 操作按钮
        Button connectButton = new Button();
        connectButton.getStyleClass().add("button-connect");
        connectButton.textProperty().bind(Bindings.createStringBinding(
            () -> deviceStatus.isConnected() ? "断开连接" : "连接设备",
            deviceStatus.isConnectedProperty()
        ));
        // 连接状态变化时切换按钮样式
        deviceStatus.isConnectedProperty().addListener((obs, oldVal, newVal) -> {
            connectButton.getStyleClass().removeAll("button-connect", "button-disconnect");
            connectButton.getStyleClass().add(newVal ? "button-disconnect" : "button-connect");
        });
        connectButton.setOnAction(event -> {
            if (deviceStatus.isConnected()) {
                controller.userDisconnect();
            } else {
                controller.userConnect();
            }
        });

        // BLE 驱动按钮
        Button bleButton = new Button("BLE驱动");
        bleButton.getStyleClass().add("button-ble");
        bleButton.setOnAction(event -> handleBleButtonClick());

        ToggleButton ahaTypeToggle = new ToggleButton();
        ahaTypeToggle.getStyleClass().add("toggle-button");
        ahaTypeToggle.textProperty().bind(Bindings.createStringBinding(
            () -> studioState.ahaTypeEnabledProperty().get() ? "AhaType" : "AhaType",
            studioState.ahaTypeEnabledProperty()
        ));
        ahaTypeToggle.selectedProperty().bindBidirectional(studioState.ahaTypeEnabledProperty());
        ahaTypeToggle.selectedProperty().addListener((obs, oldValue, newValue) -> studioState.toggleAhaType(newValue));

        // 语音启动按钮
        voiceRecordButton = new Button("启动语音输入");
        voiceRecordButton.getStyleClass().add("button-voice");
        voiceRecordButton.setOnAction(event -> toggleVoiceService());
        
        // 语音状态指示灯
        voiceStatusLamp = new VoiceStatusLamp();
        
        // 语音状态标签
        voiceStatusLabel = new Label("语音未启动");
        voiceStatusLabel.getStyleClass().add("voice-status");
        
        // 语音识别结果预览
        voiceResultPreview = new Label("");
        voiceResultPreview.getStyleClass().add("voice-preview");
        
        // 语音控制区域
        VBox voiceControlBox = new VBox(4);
        HBox voiceButtonRow = new HBox(8);
        voiceButtonRow.getChildren().addAll(voiceRecordButton, voiceStatusLamp, voiceStatusLabel);
        voiceControlBox.getChildren().addAll(voiceButtonRow, voiceResultPreview);

        VBox ahaTypeStatus = createStatusBox(
            studioState.ahaTypeEnabledProperty(),
            Bindings.createStringBinding(
                () -> studioState.ahaTypeEnabledProperty().get() ? "AhaType 开启" : "AhaType 关闭",
                studioState.ahaTypeEnabledProperty()
            ),
            studioState.ahaTypeStatusProperty()
        );

        // 检查本地模型是否启用
        boolean modelEnabled = com.example.ahakey.config.ModelConfig.getInstance().isEnabled();

        VBox configStatus = createStatusBox(
            Bindings.createBooleanBinding(agentManager::isEditingConfiguration, agentManager.bluetoothOwnerProperty()),
            Bindings.createStringBinding(
                () -> agentManager.isEditingConfiguration() ? "编辑配置中" : "键盘控制中",
                agentManager.bluetoothOwnerProperty()
            ),
            Bindings.createStringBinding(
                () -> agentManager.isEditingConfiguration()
                    ? "正在编辑配置"
                    : "键盘正常运行中",
                agentManager.bluetoothOwnerProperty()
            )
        );

        Button configModeButton = new Button();
        configModeButton.getStyleClass().add("button-prominent");
        configModeButton.textProperty().bind(Bindings.createStringBinding(controller::configurationModeButtonTitle,
            studioState.syncingProperty(),
            agentManager.bluetoothOwnerProperty()));
        configModeButton.disableProperty().bind(Bindings.createBooleanBinding(
            () -> studioState.syncingProperty().get() || agentManager.operationInProgressProperty().get(),
            studioState.syncingProperty(),
            agentManager.operationInProgressProperty()
        ));
        configModeButton.setOnAction(event -> controller.handleConfigurationModeButton());

        Menu moreMenu = new Menu("更多");
        Text moreIcon = Icons.moreHorizontal("16");
        moreMenu.setGraphic(moreIcon);

        MenuItem restoreDefaults = new MenuItem("恢复当前模式默认值");
        restoreDefaults.setOnAction(event -> studioState.restoreCurrentModeDefaults());
        MenuItem reconnect = new MenuItem("重新连接设备");
        reconnect.setOnAction(event -> {
            controller.userDisconnect();
            controller.userConnect();
        });
        MenuItem clearOled = new MenuItem("清空 OLED 预览");
        clearOled.setOnAction(event -> studioState.clearOledPreview());
        SeparatorMenuItem divider1 = new SeparatorMenuItem();
        MenuItem deviceInfo = new MenuItem("设备信息 · Hooks…");
        deviceInfo.setOnAction(event -> showDeviceInfoDialog());
        MenuItem cloudAccount = new MenuItem("云端账号 · AhaType…");
        SeparatorMenuItem divider2 = new SeparatorMenuItem();
        MenuItem refresh = new MenuItem("刷新 AhaType 状态");
        refresh.setOnAction(event -> studioState.toggleAhaType(studioState.ahaTypeEnabledProperty().get()));

        // 条件添加 AhaType 相关菜单项
        if (modelEnabled) {
            moreMenu.getItems().addAll(
                restoreDefaults,
                reconnect,
                clearOled,
                divider1,
                deviceInfo,
                cloudAccount,
                divider2,
                refresh
            );
        } else {
            // 模型禁用时，隐藏 AhaType 相关菜单
            moreMenu.getItems().addAll(
                restoreDefaults,
                reconnect,
                clearOled,
                divider1,
                deviceInfo
            );
        }

        MenuBar menuBar = new MenuBar(moreMenu);
        menuBar.setUseSystemMenuBar(false);
        menuBar.getStyleClass().add("toolbar-menu");

        // 将操作按钮放入统一的 HBox
        HBox actionButtons = new HBox(4);
        actionButtons.setAlignment(Pos.CENTER_LEFT);
        actionButtons.getChildren().addAll(connectButton, bleButton);

        // 状态信息与操作按钮之间的固定间距
        Region spacer = new Region();
        spacer.setMinWidth(12);
        spacer.setPrefWidth(16);
        spacer.setMaxWidth(40);

        // 主行 HBox：所有控件在一行，不会换行
        HBox mainRow = new HBox(10);
        mainRow.setAlignment(Pos.CENTER_LEFT);
        mainRow.setPadding(new Insets(6, 16, 6, 16));
        mainRow.setMinWidth(Region.USE_PREF_SIZE); // 保持首选宽度，不缩小
        mainRow.getChildren().addAll(titleBox, infoPills, spacer, actionButtons);
        if (modelEnabled) {
            mainRow.getChildren().addAll(ahaTypeToggle, ahaTypeStatus, voiceControlBox);
        } else {
            // 隐藏语音相关控件
            voiceRecordButton.setVisible(false);
            voiceRecordButton.setManaged(false);
            voiceStatusLamp.setVisible(false);
            voiceStatusLamp.setManaged(false);
            voiceStatusLabel.setVisible(false);
            voiceStatusLabel.setManaged(false);
            voiceResultPreview.setVisible(false);
            voiceResultPreview.setManaged(false);
        }
        mainRow.getChildren().addAll(configStatus, configModeButton, menuBar);

        // 右侧弹性 spacer：把编辑配置/菜单推到最右
        Region rightSpacer = new Region();
        HBox.setHgrow(rightSpacer, Priority.ALWAYS);
        mainRow.getChildren().add(
            mainRow.getChildren().size() - 3, rightSpacer  // 插到 configStatus 前面
        );

        // 包裹在水平 ScrollPane 中：宽屏时不显示滚动条，分屏窄时可水平滚动
        ScrollPane scrollWrapper = new ScrollPane(mainRow);
        scrollWrapper.setFitToWidth(true);
        scrollWrapper.setFitToHeight(true);
        scrollWrapper.setHbarPolicy(ScrollPane.ScrollBarPolicy.AS_NEEDED);
        scrollWrapper.setVbarPolicy(ScrollPane.ScrollBarPolicy.NEVER);
        scrollWrapper.setPannable(false);
        scrollWrapper.setStyle("-fx-background: transparent; -fx-background-color: transparent;");
        // 让 ScrollPane 内容背景透明
        mainRow.setStyle("-fx-background-color: transparent;");

        getChildren().add(scrollWrapper);
    }
    
    /**
     * 处理 BLE 驱动按钮点击
     * - 如果 BLE_tcp_driver.exe 已运行，弹窗提示
     * - 否则启动同级目录下的 BLE_tcp_driver.exe
     */
    private void handleBleButtonClick() {
        if (isBleDriverRunning()) {
            if (isBleBridgeReachable()) {
                Alert alert = new Alert(Alert.AlertType.INFORMATION);
                alert.setTitle("BLE 驱动");
                alert.setHeaderText(null);
                alert.setContentText("BLE 驱动已打开");
                alert.showAndWait();
            } else {
                stopBleDriverProcess();
                launchBleDriver();
            }
        } else {
            // 启动 BLE 驱动
            launchBleDriver();
        }
    }

    private boolean isBleBridgeReachable() {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress("127.0.0.1", 9000), 800);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private void stopBleDriverProcess() {
        try {
            new ProcessBuilder("taskkill", "/F", "/IM", "BLE_tcp_driver.exe").redirectErrorStream(true).start().waitFor();
            Thread.sleep(300);
        } catch (Exception ignored) {
        }
    }
    
    /**
     * 检查 BLE_tcp_driver.exe 是否正在运行
     */
    private boolean isBleDriverRunning() {
        try {
            ProcessBuilder pb = new ProcessBuilder("tasklist", "/FI", "IMAGENAME eq BLE_tcp_driver.exe", "/NH");
            pb.redirectErrorStream(true);
            Process p = pb.start();
            
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.toLowerCase().contains("ble_tcp_driver.exe")) {
                        return true;
                    }
                }
            }
            p.waitFor();
        } catch (Exception e) {
            // 检查失败，假定未运行
        }
        return false;
    }
    
    /**
     * 启动同级目录下的 BLE_tcp_driver.exe
     */
    private void launchBleDriver() {
        try {
            // 获取应用所在目录
            String appDir = System.getProperty("user.dir");
            
            // 尝试从 JAR 所在目录获取（打包后的情况）
            try {
                Path jarPath = Paths.get(getClass().getProtectionDomain().getCodeSource().getLocation().toURI());
                if (jarPath.toString().endsWith(".jar")) {
                    appDir = jarPath.getParent().toString();
                }
            } catch (Exception ignored) {}
            
            File bleExe = null;
            File appDirFile = new File(appDir);
            
            // 依次查找多个可能的位置
            File[] candidates = {
                new File(appDir, "BLE_tcp_driver.exe"),                                  // JAR 同级目录 (app/)
                appDirFile.getParentFile() != null 
                    ? new File(appDirFile.getParentFile(), "BLE_tcp_driver.exe") : null, // 父目录（jpackage 结构）
                new File(System.getProperty("user.dir"), "BLE_tcp_driver.exe"),          // user.dir
                new File(appDir, "app/BLE_tcp_driver.exe")                               // app 子目录
            };
            
            for (File candidate : candidates) {
                if (candidate != null && candidate.exists()) {
                    bleExe = candidate;
                    break;
                }
            }
            
            if (bleExe != null) {
                final File finalBleExe = bleExe;
                ProcessBuilder pb = new ProcessBuilder(finalBleExe.getAbsolutePath());
                pb.directory(finalBleExe.getParentFile());
                pb.start();
                
                // 短暂延迟后再次检查，给用户反馈
                new Thread(() -> {
                    try {
                        Thread.sleep(1000);
                        Platform.runLater(() -> {
                            if (isBleDriverRunning()) {
                                // 启动成功，无需额外提示
                            } else {
                                showAlert("BLE 驱动", "BLE 驱动启动失败，请手动运行: " + finalBleExe.getAbsolutePath());
                            }
                        });
                    } catch (Exception ignored) {}
                }).start();
            } else {
                showAlert("BLE 驱动", "未找到 BLE_tcp_driver.exe\n已尝试以下位置:\n" 
                    + new File(appDir, "BLE_tcp_driver.exe").getAbsolutePath() + "\n"
                    + (appDirFile.getParentFile() != null ? new File(appDirFile.getParentFile(), "BLE_tcp_driver.exe").getAbsolutePath() : "") + "\n"
                    + new File(System.getProperty("user.dir"), "BLE_tcp_driver.exe").getAbsolutePath());
            }
        } catch (Exception e) {
            showAlert("BLE 驱动", "启动失败: " + e.getMessage());
        }
    }
    
    /**
     * 显示警告弹窗
     */
    private void showAlert(String title, String content) {
        Alert alert = new Alert(Alert.AlertType.WARNING);
        alert.setTitle(title);
        alert.setHeaderText(null);
        alert.setContentText(content);
        alert.showAndWait();
    }
    
    /**
     * 切换语音服务状态（启动/停止）
     */
    private void toggleVoiceService() {
        if (voiceInputManager == null) {
            setVoiceStatus("error", "语音服务未初始化");
            return;
        }
        
        if (voiceRunning) {
            stopVoiceService();
        } else {
            startVoiceService();
        }
    }
    
    /**
     * 启动语音服务
     */
    private void startVoiceService() {
        voiceRunning = true;
        updateVoiceButtonState();
        setVoiceStatus("starting", "语音启动中");
        
        // 创建浮动通知窗口
        if (floatingNotification == null) {
            floatingNotification = new FloatingVoiceNotification();
        }
        
        // 设置状态回调（同时更新UI和浮动通知）
        voiceInputManager.setStatusCallback(status -> {
            // 状态格式: "code:message"
            String[] parts = status.split(":", 2);
            String code = parts[0];
            String message = parts.length > 1 ? parts[1] : code;
            
            Platform.runLater(() -> {
                // 更新 TopBar 状态
                setVoiceStatus(code, message);
                
                // 更新浮动通知
                if (floatingNotification != null) {
                    floatingNotification.updateStatus(code, message);
                }
            });
        });
        
        // 启动语音输入管理器
        voiceInputManager.startVoiceInput(result -> {
            Platform.runLater(() -> {
                voiceResultPreview.setText(result);
            });
        }, partialResult -> {
            Platform.runLater(() -> {
                voiceResultPreview.setText(partialResult);
            });
        });
    }
    
    /**
     * 停止语音服务
     */
    private void stopVoiceService() {
        voiceRunning = false;
        updateVoiceButtonState();
        setVoiceStatus("stopping", "语音关闭中");
        
        // 关闭浮动通知窗口
        if (floatingNotification != null) {
            floatingNotification.close();
            floatingNotification = null;
        }
        
        if (voiceInputManager != null) {
            voiceInputManager.stopVoiceInput();
        }
        
        // 延迟更新状态
        new Thread(() -> {
            try {
                Thread.sleep(500);
                Platform.runLater(() -> {
                    setVoiceStatus("stopped", "语音未启动");
                    voiceResultPreview.setText("");
                });
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }).start();
    }
    
    /**
     * 设置语音状态
     */
    private void setVoiceStatus(String status, String text) {
        if (voiceStatusLamp != null) {
            voiceStatusLamp.setStatus(status);
        }
        
        if (voiceStatusLabel != null) {
            voiceStatusLabel.setText(text);
            
            // 根据状态设置颜色
            String color = switch (status) {
                case "stopped", "idle" -> "#A7AFBA";           // 空闲状态 - 灰色
                case "starting", "stopping", "processing", "recognizing" -> "#F5A623";  // 处理/识别中 - 橙色
                case "recording" -> "#E74C3C";                 // 录音中 - 红色
                case "ready" -> "#2ECC71";                     // 就绪 - 绿色
                default -> "#E74C3C"; // error
            };
            voiceStatusLabel.setStyle("-fx-text-fill: " + color + ";");
        }
    }
    
    /**
     * 更新语音按钮状态
     */
    private void updateVoiceButtonState() {
        if (voiceRecordButton == null) return;
        
        if (voiceInputManager == null || !voiceInputManager.isEnabled()) {
            voiceRecordButton.setDisable(true);
            voiceRecordButton.setText("启动语音输入 (不可用)");
            setVoiceStatus("error", "语音服务未加载");
            return;
        }
        
        voiceRecordButton.setDisable(false);
        
        if (voiceRunning) {
            voiceRecordButton.getStyleClass().add("voice-recording");
            voiceRecordButton.setText("停止语音输入");
        } else {
            voiceRecordButton.getStyleClass().remove("voice-recording");
            voiceRecordButton.setText("启动语音输入");
        }
    }

    private VBox createStatusBox(
        javafx.beans.value.ObservableValue<Boolean> isPositive,
        javafx.beans.value.ObservableValue<String> title,
        javafx.beans.value.ObservableValue<String> detail
    ) {
        VBox box = new VBox(1);
        box.getStyleClass().add("status-box");

        HBox row = new HBox(8);
        Label dot = new Label();
        dot.getStyleClass().add("status-dot");
        dot.styleProperty().bind(Bindings.createStringBinding(
            () -> "-fx-background-color: " + (isPositive.getValue() ? "#30d158" : "#0a84ff") + ";",
            isPositive
        ));

        VBox text = new VBox(1);
        Label titleLabel = new Label();
        titleLabel.textProperty().bind(title);
        titleLabel.getStyleClass().add("status-label");

        Label detailLabel = new Label();
        detailLabel.textProperty().bind(detail);
        detailLabel.getStyleClass().add("status-detail");

        text.getChildren().addAll(titleLabel, detailLabel);
        row.getChildren().addAll(dot, text);
        box.getChildren().add(row);
        return box;
    }

    private void showDeviceInfoDialog() {
        Stage dialog = new Stage();
        dialog.initOwner(getScene().getWindow());
        dialog.setTitle("Hook 安装 & 分发工具");
        dialog.setWidth(550);
        dialog.setHeight(650);

        ScrollPane scrollPane = new ScrollPane();
        scrollPane.setFitToWidth(true);

        VBox content = new VBox(12);
        content.setPadding(new Insets(12));

        // 设备信息摘要
        VBox deviceCard = new VBox(8);
        deviceCard.getStyleClass().add("dialog-card");
        deviceCard.setPadding(new Insets(12));

        Label deviceTitle = new Label("设备信息");
        deviceTitle.getStyleClass().add("dialog-card-title");

        HBox deviceRow1 = new HBox(16);
        Label connStatus = new Label();
        connStatus.getStyleClass().add("dialog-text");
        connStatus.textProperty().bind(Bindings.createStringBinding(() ->
            "连接: " + (this.deviceStatus.isConnected() ? "已连接" : "未连接"),
            this.deviceStatus.isConnectedProperty()
        ));
        Label batteryStatus = new Label();
        batteryStatus.getStyleClass().add("dialog-text");
        batteryStatus.textProperty().bind(Bindings.createStringBinding(() ->
            "电量: " + this.deviceStatus.getBatteryLevel() + "%",
            this.deviceStatus.batteryLevelProperty()
        ));
        deviceRow1.getChildren().addAll(connStatus, batteryStatus);

        HBox deviceRow2 = new HBox(16);
        Label deviceName = new Label("设备名: " + (this.deviceStatus.getDeviceName() != null ? this.deviceStatus.getDeviceName() : "—"));
        deviceName.getStyleClass().add("dialog-text");
        Label switchState = new Label();
        switchState.getStyleClass().add("dialog-text");
        switchState.textProperty().bind(Bindings.createStringBinding(() ->
            "拨杆: " + this.deviceStatus.getSwitchTitle(),
            this.deviceStatus.switchStateProperty()
        ));
        deviceRow2.getChildren().addAll(deviceName, switchState);

        deviceCard.getChildren().addAll(deviceTitle, deviceRow1, deviceRow2);

        // 日志区域（提前创建以记录检测过程）
        logArea = new TextArea();
        logArea.getStyleClass().add("dialog-log-area");
        logArea.setEditable(false);
        logArea.setPrefHeight(150);
        logArea.setWrapText(true);
        logArea.setText("[系统] Hook 安装工具已启动\n");
        
        // 输出用户目录信息
        String homeDir = System.getProperty("user.home");
        addLog("[系统] 用户目录: " + homeDir);
        addLog("[系统] 操作系统: " + System.getProperty("os.name"));
        addLog("[系统] Java 版本: " + System.getProperty("java.version"));
        addLog("");

        // 检测并记录各 Hook 状态
        String[] hookNames = {"Claude", "Cursor", "Codex", "Kimi"};
        boolean[] hookInstalled = new boolean[4];
        
        for (int i = 0; i < hookNames.length; i++) {
            String name = hookNames[i];
            Path path = getHookConfigPath(name);
            File file = path.toFile();
            
            // 使用完整的检查逻辑
            boolean installed = isHookInstalled(name);
            
            // 添加详细调试信息
            addLog("[检测] === " + name + " Hook ===");
            addLog("[检测] 检查路径: " + path);
            addLog("[检测] 文件存在: " + file.exists());
            
            if (file.exists()) {
                try {
                    String fileContent = new String(java.nio.file.Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
                    addLog("[检测] 文件大小: " + fileContent.length() + " 字符");
                    
                    if ("Claude".equals(name)) {
                        addLog("[检测] 包含 hooks: " + fileContent.contains("\"hooks\""));
                        addLog("[检测] 包含 SessionStart: " + fileContent.contains("SessionStart"));
                    } else if ("Cursor".equals(name)) {
                        addLog("[检测] 包含 hooks: " + fileContent.contains("\"hooks\""));
                        addLog("[检测] 包含 sessionStart: " + fileContent.contains("sessionStart"));
                    } else if ("Codex".equals(name)) {
                        String home = System.getProperty("user.home");
                        Path sidecar = Paths.get(home, ".codex", CODEX_SIDECAR_NAME);
                        addLog("[检测] sidecar 存在: " + sidecar.toFile().exists());
                        addLog("[检测] hooks.json 内容长度: " + fileContent.length());
                    } else if ("Kimi".equals(name)) {
                        addLog("[检测] 包含 BEGIN 标记: " + fileContent.contains(KIMI_HOOK_BLOCK_START));
                        addLog("[检测] 包含 END 标记: " + fileContent.contains(KIMI_HOOK_BLOCK_END));
                    }
                } catch (Exception e) {
                    addLog("[检测] 读取文件失败: " + e.getMessage());
                }
            }
            
            hookInstalled[i] = installed;
            addLog("[检测] 最终状态: " + (installed ? "已安装" : "未安装"));
            addLog("");
        }

        // Hook 安装卡片
        VBox claudeCard = createHookCard("Claude", hookInstalled[0]);
        VBox cursorCard = createHookCard("Cursor", hookInstalled[1]);
        VBox codexCard = createHookCard("Codex", hookInstalled[2]);
        VBox kimiCard = createHookCard("Kimi", hookInstalled[3]);

        // 日志卡片
        VBox logCard = new VBox(8);
        logCard.getStyleClass().add("dialog-card");
        logCard.setPadding(new Insets(12));

        Label logTitle = new Label("日志");
        logTitle.getStyleClass().add("dialog-log-title");
        logCard.getChildren().addAll(logTitle, logArea);

        // 操作按钮
        HBox actionButtons = new HBox(10);
        Button connectBtn = new Button("连接设备");
        connectBtn.getStyleClass().add("button-connect");
        connectBtn.disableProperty().bind(this.deviceStatus.isConnectedProperty());
        connectBtn.setOnAction(event -> controller.userConnect());

        Button disconnectBtn = new Button("断开连接");
        disconnectBtn.getStyleClass().add("button-disconnect");
        disconnectBtn.disableProperty().bind(this.deviceStatus.isConnectedProperty().not());
        disconnectBtn.setOnAction(event -> controller.userDisconnect());

        Button clearLogBtn = new Button("清空日志");
        clearLogBtn.setOnAction(event -> logArea.setText("[系统] 日志已清空\n"));

        Button closeBtn = new Button("关闭");
        closeBtn.setOnAction(event -> dialog.close());

        actionButtons.getChildren().addAll(connectBtn, disconnectBtn, clearLogBtn, closeBtn);
        actionButtons.setAlignment(Pos.CENTER_RIGHT);

        content.getChildren().addAll(deviceCard, claudeCard, cursorCard, codexCard, kimiCard, logCard, actionButtons);
        scrollPane.setContent(content);

        Scene scene = new Scene(scrollPane);
        scene.getStylesheets().add(getClass().getResource("/style.css").toExternalForm());
        dialog.setScene(scene);
        dialog.showAndWait();
    }

    private VBox createHookCard(String hookName, boolean isInstalled) {
        VBox card = new VBox(8);
        card.getStyleClass().add("dialog-card");
        card.setPadding(new Insets(12));

        HBox titleRow = new HBox();
        Label title = new Label(hookName + " Hook");
        title.getStyleClass().add("dialog-card-title");
        Region spacer1 = new Region();
        HBox.setHgrow(spacer1, Priority.ALWAYS);
        titleRow.getChildren().addAll(title, spacer1);

        HBox statusRow = new HBox(8);
        Label statusLabel = new Label("安装状态:");
        statusLabel.getStyleClass().add("dialog-status-label");

        Label statusValue = new Label(isInstalled ? "已安装" : "未安装");
        if (isInstalled) {
            statusValue.getStyleClass().add("dialog-status-installed");
        } else {
            statusValue.getStyleClass().add("dialog-status-uninstalled");
        }

        Region spacer2 = new Region();
        HBox.setHgrow(spacer2, Priority.ALWAYS);

        Button installBtn = new Button("安装");
        installBtn.getStyleClass().add("button-install");
        installBtn.setOnAction(event -> {
            installHook(hookName);
            statusValue.setText("已安装");
            statusValue.getStyleClass().remove("dialog-status-uninstalled");
            statusValue.getStyleClass().add("dialog-status-installed");
        });

        Button uninstallBtn = new Button("卸载");
        uninstallBtn.getStyleClass().add("button-uninstall");
        uninstallBtn.setOnAction(event -> {
            uninstallHook(hookName);
            statusValue.setText("未安装");
            statusValue.getStyleClass().remove("dialog-status-installed");
            statusValue.getStyleClass().add("dialog-status-uninstalled");
        });

        statusRow.getChildren().addAll(statusLabel, statusValue, spacer2, installBtn, uninstallBtn);

        card.getChildren().addAll(titleRow, statusRow);
        return card;
    }

    // ==================== Hook 管理（与 Python 版完全对齐） ====================

    private static final ObjectMapper HOOK_MAPPER = new ObjectMapper();
    private static final int HOOK_DISPATCH_PORT = 8765;
    private static final String CODEX_SIDECAR_NAME = ".ahakey_codex_hooks_v1";
    private static final String CODEX_HOOK_BLOCK_START = "# BEGIN AhaKey Codex Hooks";
    private static final String CODEX_HOOK_BLOCK_END = "# END AhaKey Codex Hooks";
    private static final String KIMI_HOOK_BLOCK_START = "# BEGIN AhaKey Kimi Hooks";
    private static final String KIMI_HOOK_BLOCK_END = "# END AhaKey Kimi Hooks";

    // Claude: 9 个事件（与 Python HOOK_EVENTS 完全一致）
    private static final String[][] CLAUDE_EVENTS = {
        {"SessionStart", "10"}, {"SessionEnd", "10"}, {"PreToolUse", "10"},
        {"PostToolUse", "10"}, {"PermissionRequest", "60"}, {"Notification", "10"},
        {"TaskCompleted", "10"}, {"Stop", "10"}, {"UserPromptSubmit", "10"}
    };
    // Cursor: 5 个事件（与 Python CURSOR_HOOK_EVENTS 完全一致）
    private static final String[][] CURSOR_EVENTS = {
        {"sessionStart", "10"}, {"sessionEnd", "10"}, {"preToolUse", "10"},
        {"postToolUse", "10"}, {"stop", "10"}
    };
    // Codex: 6 个事件（与 Python CODEX_HOOK_EVENTS 完全一致）
    private static final String[][] CODEX_EVENTS = {
        {"SessionStart", "CodexSessionStart", "10"}, {"PostToolUse", "CodexPostToolUse", "10"},
        {"PreToolUse", "CodexPreToolUse", "20"}, {"PermissionRequest", "CodexPermissionRequest", "20"},
        {"UserPromptSubmit", "CodexUserPromptSubmit", "10"}, {"Stop", "CodexStop", "10"}
    };
    // Kimi: 7 个事件（与 Python kimi_hooks.KIMI_HOOK_ENTRIES 完全一致）
    private static final String[][] KIMI_EVENTS = {
        {"Notification", "KimiNotification", "10"}, {"SessionStart", "KimiSessionStart", "10"},
        {"SessionEnd", "KimiSessionEnd", "10"}, {"PreToolUse", "KimiPreToolUse", "20"},
        {"PostToolUse", "KimiPostToolUse", "10"}, {"UserPromptSubmit", "KimiUserPromptSubmit", "10"},
        {"Stop", "KimiStop", "10"}
    };

    private static final String HOOK_SCRIPT_NAME = "ahakey-hook.ps1";

    private Path getHookScriptPath() {
        String home = System.getProperty("user.home");
        return Paths.get(home, ".ahakey", "hooks", HOOK_SCRIPT_NAME);
    }

    private String buildHookCommand(String agentEvent) {
        Path scriptPath = getHookScriptPath();
        String ps = scriptPath.toString().replace("\\", "/");
        return "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + ps + "\" " + agentEvent;
    }

    /**
     * 生成 hook 分发 PowerShell 脚本（~/.ahakey/hooks/ahakey-hook.ps1）。
     * 该脚本接收事件名参数，通过 TCP 发送到 Java HookDispatchServer，后者映射为 BLE 状态码。
     */
    private void generateHookScript() {
        Path scriptPath = getHookScriptPath();
        try {
            java.nio.file.Files.createDirectories(scriptPath.getParent());
            String content =
                "# AhaKey Hook Dispatcher - Auto-generated, do not edit\n" +
                "# Receives hook event name as argument, dispatches to AhaKey Studio via TCP.\n" +
                "# Compatible with Claude Code, Codex, Kimi, and Cursor hooks.\n" +
                "param([Parameter(Position=0)][string]$EventName)\n" +
                "try {\n" +
                "    if ([Console]::IsInputRedirected) { $null = [Console]::In.ReadToEnd() }\n" +
                "} catch { }\n" +
                "try {\n" +
                "    $tcp = New-Object System.Net.Sockets.TcpClient\n" +
                "    $tcp.Connect('127.0.0.1', " + HOOK_DISPATCH_PORT + ")\n" +
                "    $writer = New-Object System.IO.StreamWriter($tcp.GetStream())\n" +
                "    $writer.WriteLine($EventName)\n" +
                "    $writer.Flush()\n" +
                "    $reader = New-Object System.IO.StreamReader($tcp.GetStream())\n" +
                "    $response = $reader.ReadLine()\n" +
                "    $tcp.Close()\n" +
                "} catch {\n" +
                "    $response = $null\n" +
                "}\n" +
                "# Codex lifecycle hooks must output exactly {} (Codex validates JSON schema)\n" +
                "if ($EventName -match '^Codex' -and $EventName -ne 'CodexPermissionRequest') {\n" +
                "    [Console]::WriteLine('{}')\n" +
                "    exit 0\n" +
                "}\n" +
                "# Codex PermissionRequest: output hookSpecificOutput in Codex format\n" +
                "if ($EventName -eq 'CodexPermissionRequest') {\n" +
                "    $isAuto = $response -match '\"autoApproved\"\\s*:\\s*true'\n" +
                "    if ($isAuto) {\n" +
                "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
                "    } else {\n" +
                "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\"}}')\n" +
                "    }\n" +
                "    exit 0\n" +
                "}\n" +
                "# Claude / Kimi / Cursor: pass through server response\n" +
                "if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{\"ok\":true}') }\n" +
                "exit 0\n";
            java.nio.file.Files.write(scriptPath, content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            addLog("[安装] 生成分发脚本: " + scriptPath);
        } catch (Exception e) {
            addLog("[警告] 生成分发脚本失败: " + e.getMessage());
        }
    }

    private String tomlEscape(String s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private Path getHookConfigPath(String hookName) {
        String home = System.getProperty("user.home");
        switch (hookName) {
            case "Claude": return Paths.get(home, ".claude", "settings.json");
            case "Cursor": return Paths.get(home, ".cursor", "hooks.json");
            case "Codex": return Paths.get(home, ".codex", "hooks.json");
            case "Kimi": return Paths.get(home, ".kimi", "config.toml");
            default: return Paths.get(home, "." + hookName.toLowerCase(), "config.json");
        }
    }

    private boolean isHookInstalled(String hookName) {
        switch (hookName) {
            case "Claude": return checkClaudeHookInstalled(getHookConfigPath("Claude"));
            case "Cursor": return checkCursorHookInstalled(getHookConfigPath("Cursor"));
            case "Codex": return checkCodexHookInstalled();
            case "Kimi": return checkKimiHookInstalled(getHookConfigPath("Kimi"));
            default: return false;
        }
    }

    private boolean checkClaudeHookInstalled(Path path) {
        if (!path.toFile().exists()) return false;
        try {
            String c = new String(java.nio.file.Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
            return c.contains("\"hooks\"") && c.contains("SessionStart");
        } catch (Exception e) { addLog("[错误] 读取 Claude 配置: " + e.getMessage()); return false; }
    }

    private boolean checkCursorHookInstalled(Path path) {
        if (!path.toFile().exists()) return false;
        try {
            String c = new String(java.nio.file.Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
            return c.contains("\"hooks\"") && c.contains("sessionStart");
        } catch (Exception e) { addLog("[错误] 读取 Cursor 配置: " + e.getMessage()); return false; }
    }

    private boolean checkCodexHookInstalled() {
        String home = System.getProperty("user.home");
        return Paths.get(home, ".codex", CODEX_SIDECAR_NAME).toFile().exists();
    }

    private boolean checkKimiHookInstalled(Path path) {
        if (!path.toFile().exists()) return false;
        try {
            String c = new String(java.nio.file.Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
            return c.contains(KIMI_HOOK_BLOCK_START) && c.contains(KIMI_HOOK_BLOCK_END);
        } catch (Exception e) { addLog("[错误] 读取 Kimi 配置: " + e.getMessage()); return false; }
    }

    private void installHook(String hookName) {
        addLog("[安装] 开始安装 " + hookName + " Hook...");
        // 先生成分发脚本（所有平台共用）
        generateHookScript();
        switch (hookName) {
            case "Claude": installClaudeHooks(); break;
            case "Cursor": installCursorHooks(); break;
            case "Codex": installCodexHooks(); break;
            case "Kimi": installKimiHooks(); break;
            default: addLog("[错误] 未知 Hook 类型: " + hookName);
        }
    }

    private void uninstallHook(String hookName) {
        addLog("[卸载] 开始卸载 " + hookName + " Hook...");
        switch (hookName) {
            case "Claude": uninstallClaudeHooks(); break;
            case "Cursor": uninstallCursorHooks(); break;
            case "Codex": uninstallCodexHooks(); break;
            case "Kimi": uninstallKimiHooks(); break;
            default: addLog("[错误] 未知 Hook 类型: " + hookName);
        }
    }

    // ---- Claude: ~/.claude/settings.json（9 个事件） ----
    private void installClaudeHooks() {
        Path path = getHookConfigPath("Claude");
        try {
            java.nio.file.Files.createDirectories(path.getParent());
            backupFile(path);
            ObjectNode settings = loadJsonSettings(path);
            ObjectNode hooks = HOOK_MAPPER.createObjectNode();
            for (String[] ev : CLAUDE_EVENTS) {
                ObjectNode cmd = HOOK_MAPPER.createObjectNode();
                cmd.put("type", "command");
                cmd.put("command", buildHookCommand(ev[0]));
                cmd.put("timeout", Integer.parseInt(ev[1]));
                ArrayNode inner = HOOK_MAPPER.createArrayNode();
                inner.add(cmd);
                ObjectNode wrapper = HOOK_MAPPER.createObjectNode();
                wrapper.put("matcher", "");
                wrapper.set("hooks", inner);
                ArrayNode outer = HOOK_MAPPER.createArrayNode();
                outer.add(wrapper);
                hooks.set(ev[0], outer);
            }
            settings.set("hooks", hooks);
            HOOK_MAPPER.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
            addLog("[成功] 已注册 " + CLAUDE_EVENTS.length + " 个 Claude hook 事件");
            addLog("[成功] 配置文件: " + path);
        } catch (Exception e) { addLog("[错误] Claude 安装失败: " + e.getMessage()); }
    }

    private void uninstallClaudeHooks() {
        Path path = getHookConfigPath("Claude");
        try {
            if (!path.toFile().exists()) { addLog("[信息] 配置文件不存在"); return; }
            ObjectNode settings = loadJsonSettings(path);
            if (settings.has("hooks")) {
                settings.remove("hooks");
                HOOK_MAPPER.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
                addLog("[成功] 已从 Claude 配置中移除 hooks");
            } else { addLog("[信息] 配置中不存在 hooks"); }
        } catch (Exception e) { addLog("[错误] Claude 卸载失败: " + e.getMessage()); }
    }

    // ---- Cursor: ~/.cursor/hooks.json（5 个事件） ----
    private void installCursorHooks() {
        Path path = getHookConfigPath("Cursor");
        try {
            java.nio.file.Files.createDirectories(path.getParent());
            backupFile(path);
            ObjectNode settings = loadJsonSettings(path);
            ObjectNode existingHooks = settings.has("hooks") ? (ObjectNode) settings.get("hooks") : HOOK_MAPPER.createObjectNode();
            for (String[] ev : CURSOR_EVENTS) {
                ObjectNode entry = HOOK_MAPPER.createObjectNode();
                entry.put("command", buildHookCommand(ev[0]));
                entry.put("timeout", Integer.parseInt(ev[1]));
                ArrayNode arr = HOOK_MAPPER.createArrayNode();
                arr.add(entry);
                existingHooks.set(ev[0], arr);
            }
            settings.set("hooks", existingHooks);
            settings.put("version", 1);
            HOOK_MAPPER.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
            addLog("[成功] 已注册 " + CURSOR_EVENTS.length + " 个 Cursor hook 事件");
            addLog("[成功] 配置文件: " + path);
        } catch (Exception e) { addLog("[错误] Cursor 安装失败: " + e.getMessage()); }
    }

    private void uninstallCursorHooks() {
        Path path = getHookConfigPath("Cursor");
        try {
            if (!path.toFile().exists()) { addLog("[信息] 配置文件不存在"); return; }
            ObjectNode settings = loadJsonSettings(path);
            if (settings.has("hooks")) {
                settings.remove("hooks");
                HOOK_MAPPER.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), settings);
                addLog("[成功] 已从 Cursor 配置中移除 hooks");
            } else { addLog("[信息] 配置中不存在 hooks"); }
        } catch (Exception e) { addLog("[错误] Cursor 卸载失败: " + e.getMessage()); }
    }

    // ---- Codex: ~/.codex/hooks.json + config.toml + sidecar（6 个事件） ----
    private void installCodexHooks() {
        String home = System.getProperty("user.home");
        Path hooksJson = Paths.get(home, ".codex", "hooks.json");
        Path configToml = Paths.get(home, ".codex", "config.toml");
        Path sidecar = Paths.get(home, ".codex", CODEX_SIDECAR_NAME);
        try {
            java.nio.file.Files.createDirectories(hooksJson.getParent());
            backupFile(hooksJson);
            // 构建 hooks.json（与 Python build_codex_hooks_json 完全一致）
            ObjectNode hooks = HOOK_MAPPER.createObjectNode();
            for (String[] ev : CODEX_EVENTS) {
                ObjectNode cmd = HOOK_MAPPER.createObjectNode();
                cmd.put("type", "command");
                cmd.put("command", buildHookCommand(ev[1]));
                cmd.put("timeout", Integer.parseInt(ev[2]));
                ArrayNode innerArr = HOOK_MAPPER.createArrayNode();
                innerArr.add(cmd);
                ObjectNode entry = HOOK_MAPPER.createObjectNode();
                if ("SessionStart".equals(ev[0])) {
                    entry.put("matcher", "startup|resume|clear");
                } else if ("UserPromptSubmit".equals(ev[0]) || "Stop".equals(ev[0])) {
                    // no matcher
                } else {
                    entry.put("matcher", "*");
                }
                entry.set("hooks", innerArr);
                ArrayNode outerArr = HOOK_MAPPER.createArrayNode();
                outerArr.add(entry);
                hooks.set(ev[0], outerArr);
            }
            ObjectNode root = HOOK_MAPPER.createObjectNode();
            root.set("hooks", hooks);
            HOOK_MAPPER.writerWithDefaultPrettyPrinter().writeValue(hooksJson.toFile(), root);
            addLog("[成功] 已写入 " + hooksJson);
            // 写入 sidecar 管理标记
            java.nio.file.Files.write(sidecar, java.time.LocalDateTime.now().toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
            // 更新 config.toml：确保 [features] hooks = true
            backupFile(configToml);
            String toml = configToml.toFile().exists()
                ? new String(java.nio.file.Files.readAllBytes(configToml), java.nio.charset.StandardCharsets.UTF_8)
                : "";
            toml = removeCodexHookBlock(toml);
            toml = ensureCodexHooksFeature(toml);
            if (!toml.contains("AhaKey：生命周期 hooks")) {
                toml = toml.trim() + "\n\n# AhaKey：生命周期 hooks 由 hook_install 写入 ~/.codex/hooks.json\n";
            }
            java.nio.file.Files.write(configToml, toml.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            addLog("[成功] 已更新 " + configToml + "（[features].hooks = true）");
            addLog("[成功] 已注册 " + CODEX_EVENTS.length + " 个 Codex hook 事件");
        } catch (Exception e) { addLog("[错误] Codex 安装失败: " + e.getMessage()); }
    }

    private void uninstallCodexHooks() {
        String home = System.getProperty("user.home");
        Path hooksJson = Paths.get(home, ".codex", "hooks.json");
        Path configToml = Paths.get(home, ".codex", "config.toml");
        Path sidecar = Paths.get(home, ".codex", CODEX_SIDECAR_NAME);
        try {
            if (sidecar.toFile().exists()) {
                java.nio.file.Files.delete(sidecar);
                if (hooksJson.toFile().exists()) {
                    java.nio.file.Files.delete(hooksJson);
                    addLog("[成功] 已删除 " + hooksJson + "（由 AhaKey 安装器写入）");
                }
            }
            if (configToml.toFile().exists()) {
                String toml = new String(java.nio.file.Files.readAllBytes(configToml), java.nio.charset.StandardCharsets.UTF_8);
                if (toml.contains(CODEX_HOOK_BLOCK_START)) {
                    toml = removeCodexHookBlock(toml);
                    java.nio.file.Files.write(configToml, toml.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                    addLog("[成功] 已从 config.toml 移除内联 AhaKey Codex 块");
                }
            }
            addLog("[成功] Codex Hook 卸载完成");
        } catch (Exception e) { addLog("[错误] Codex 卸载失败: " + e.getMessage()); }
    }

    // ---- Kimi: ~/.kimi/config.toml（7 个事件，TOML [[hooks]] 块） ----
    private void installKimiHooks() {
        Path path = getHookConfigPath("Kimi");
        try {
            java.nio.file.Files.createDirectories(path.getParent());
            backupFile(path);
            String existing = path.toFile().exists()
                ? new String(java.nio.file.Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8)
                : "";
            String cleaned = removeKimiHookBlock(existing).trim();
            String hookBlock = buildKimiHookBlock();
            String result = (cleaned.isEmpty() ? "" : cleaned + "\n\n") + hookBlock + "\n";
            java.nio.file.Files.write(path, result.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            addLog("[成功] 已注册 " + KIMI_EVENTS.length + " 个 Kimi hook 事件");
            addLog("[成功] 配置文件: " + path);
        } catch (Exception e) { addLog("[错误] Kimi 安装失败: " + e.getMessage()); }
    }

    private void uninstallKimiHooks() {
        Path path = getHookConfigPath("Kimi");
        try {
            if (!path.toFile().exists()) { addLog("[信息] 配置文件不存在"); return; }
            String content = new String(java.nio.file.Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
            String cleaned = removeKimiHookBlock(content);
            if (!cleaned.equals(content)) {
                java.nio.file.Files.write(path, cleaned.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                addLog("[成功] Hook 块已从配置文件中删除");
            } else { addLog("[警告] 未找到 AhaKey Hook 块"); }
        } catch (Exception e) { addLog("[错误] Kimi 卸载失败: " + e.getMessage()); }
    }

    // ---- 配置构建辅助方法 ----
    private String buildKimiHookBlock() {
        StringBuilder sb = new StringBuilder();
        sb.append(KIMI_HOOK_BLOCK_START).append("\n");
        sb.append("# Managed by AhaKey. Kimi CLI hooks run this installer with Kimi* event names.\n");
        sb.append("# Re-run Install Kimi Hooks after upgrading kimi-cli so the dial-control patch is restored.\n");
        for (String[] ev : KIMI_EVENTS) {
            sb.append("\n[[hooks]]\n");
            sb.append("event = \"").append(ev[0]).append("\"\n");
            sb.append("matcher = \"\"\n");
            sb.append("command = \"").append(tomlEscape(buildHookCommand(ev[1]))).append("\"\n");
            sb.append("timeout = ").append(ev[2]).append("\n");
        }
        sb.append("\n").append(KIMI_HOOK_BLOCK_END).append("\n");
        return sb.toString();
    }

    private String removeKimiHookBlock(String content) {
        return removeBlock(content, KIMI_HOOK_BLOCK_START, KIMI_HOOK_BLOCK_END);
    }

    private String removeCodexHookBlock(String content) {
        return removeBlock(content, CODEX_HOOK_BLOCK_START, CODEX_HOOK_BLOCK_END);
    }

    private String removeBlock(String content, String startMarker, String endMarker) {
        String result = content;
        while (true) {
            int start = result.indexOf(startMarker);
            if (start == -1) break;
            int end = result.indexOf(endMarker, start);
            if (end == -1) break;
            String before = result.substring(0, start);
            String after = result.substring(end + endMarker.length());
            result = before + after;
        }
        while (result.contains("\n\n\n")) result = result.replace("\n\n\n", "\n\n");
        return result.trim().isEmpty() ? "" : result.trim() + "\n";
    }

    private String ensureCodexHooksFeature(String config) {
        String[] lines = config.split("\n");
        int featuresStart = -1;
        for (int i = 0; i < lines.length; i++) {
            if (lines[i].trim().equals("[features]")) { featuresStart = i; break; }
        }
        if (featuresStart == -1) {
            String base = config.trim();
            return (base.isEmpty() ? "" : base + "\n\n") + "[features]\nhooks = true\n";
        }
        int sectionEnd = lines.length;
        for (int i = featuresStart + 1; i < lines.length; i++) {
            String t = lines[i].trim();
            if (t.startsWith("[") && t.endsWith("]")) { sectionEnd = i; break; }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i <= featuresStart; i++) sb.append(lines[i]).append("\n");
        sb.append("hooks = true\n");
        for (int i = featuresStart + 1; i < sectionEnd; i++) {
            String t = lines[i].trim();
            if (t.startsWith("hooks") && t.contains("=")) continue;
            if (t.startsWith("codex_hooks")) continue;
            sb.append(lines[i]).append("\n");
        }
        for (int i = sectionEnd; i < lines.length; i++) sb.append(lines[i]).append("\n");
        return sb.toString();
    }

    private ObjectNode loadJsonSettings(Path path) {
        try {
            if (path.toFile().exists()) {
                return (ObjectNode) HOOK_MAPPER.readTree(path.toFile());
            }
        } catch (Exception e) { addLog("[警告] 解析配置失败，将使用空配置: " + e.getMessage()); }
        return HOOK_MAPPER.createObjectNode();
    }

    private void backupFile(Path path) {
        if (!path.toFile().exists()) return;
        try {
            String ts = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
            Path backup = path.resolveSibling(path.getFileName().toString() + ".bak." + ts);
            java.nio.file.Files.copy(path, backup);
            addLog("[备份] " + backup.getFileName());
        } catch (Exception e) { addLog("[警告] 备份失败: " + e.getMessage()); }
    }

    private void addLog(String message) {
        if (logArea != null) {
            String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss"));
            logArea.appendText("[" + timestamp + "] " + message + "\n");
            logArea.setScrollTop(Double.MAX_VALUE);
        }
    }
    
    /**
     * 语音状态指示灯组件
     */
    private class VoiceStatusLamp extends Canvas {
        private String status = "stopped";
        private double angle = 0;
        private AnimationTimer timer;
        private boolean isTimerRunning = false;
        
        public VoiceStatusLamp() {
            super(16, 16);
            timer = new AnimationTimer() {
                @Override
                public void handle(long now) {
                    angle = (angle + 30) % 360;
                    draw();
                }
            };
        }
        
        public void setStatus(String status) {
            this.status = status != null ? status : "stopped";
            if (status.equals("starting") || status.equals("stopping") || status.equals("processing")) {
                if (!isTimerRunning) {
                    timer.start();
                    isTimerRunning = true;
                }
            } else {
                timer.stop();
                isTimerRunning = false;
                angle = 0;
            }
            draw();
        }
        
        private void draw() {
            GraphicsContext gc = getGraphicsContext2D();
            gc.clearRect(0, 0, getWidth(), getHeight());
            
            if (status.equals("stopped")) {
                // 灰色空心圆
                gc.setStroke(javafx.scene.paint.Color.web("#8A9099"));
                gc.setLineWidth(1.6);
                gc.strokeOval(2.0, 2.0, getWidth() - 4, getHeight() - 4);
            } else if (status.equals("starting") || status.equals("stopping") || status.equals("processing")) {
                // 旋转动画
                gc.setStroke(javafx.scene.paint.Color.web("#5C6470"));
                gc.setLineWidth(1.6);
                gc.strokeOval(2.0, 2.0, getWidth() - 4, getHeight() - 4);
                
                gc.setStroke(javafx.scene.paint.Color.web("#F5A623"));
                gc.setLineWidth(2.2);
                gc.setLineCap(javafx.scene.shape.StrokeLineCap.ROUND);
                
                double startAngle = -angle * Math.PI / 180;
                double arcLength = -120 * Math.PI / 180;
                gc.strokeArc(2.0, 2.0, getWidth() - 4, getHeight() - 4, startAngle, arcLength, javafx.scene.shape.ArcType.OPEN);
            } else if (status.equals("ready")) {
                // 绿色实心圆
                gc.setFill(javafx.scene.paint.Color.web("#2ECC71"));
                gc.fillOval(2.0, 2.0, getWidth() - 4, getHeight() - 4);
            } else {
                // 红色实心圆（error）
                gc.setFill(javafx.scene.paint.Color.web("#E74C3C"));
                gc.fillOval(2.0, 2.0, getWidth() - 4, getHeight() - 4);
            }
        }
    }
}
