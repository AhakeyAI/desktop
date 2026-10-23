package com.example.ahakey.view;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.service.AgentManager;
import com.example.ahakey.service.HookDispatchServer;
import com.example.ahakey.service.HookInstaller;
import com.example.ahakey.service.VoiceInputManager;
import com.example.ahakey.util.Icons;
import com.example.ahakey.util.LanguageManager;
import javafx.application.Platform;
import javafx.beans.binding.Bindings;
import javafx.beans.property.BooleanProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Label;
import javafx.scene.control.Menu;
import javafx.scene.control.MenuBar;
import javafx.scene.control.MenuItem;
import javafx.scene.control.SeparatorMenuItem;
import javafx.scene.control.TextArea;
import javafx.scene.control.ToggleButton;
import javafx.scene.control.Tooltip;
import javafx.scene.control.ScrollPane;
import javafx.scene.layout.*;
import javafx.scene.paint.Color;
import javafx.scene.text.Text;
import javafx.stage.Stage;
import javafx.scene.Scene;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import javafx.scene.control.Alert;
import javafx.scene.control.ButtonType;
import java.util.Optional;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.io.File;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import javafx.scene.canvas.Canvas;
import javafx.scene.canvas.GraphicsContext;
import javafx.animation.AnimationTimer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class TopBar extends VBox {
    private static final Logger logger = LoggerFactory.getLogger(TopBar.class);
    private final StudioController controller;
    private final DeviceStatus deviceStatus;
    private final StudioState studioState;
    private final AgentManager agentManager;
    private VoiceInputManager voiceInputManager;
    private TextArea logArea;
    private final HookInstaller hookInstaller;
    private final LanguageManager languageManager;
    private MenuItem languageMenuItem;
    private boolean hookUpdateSummaryShown;
    
    // 语音相关UI组件
    private Button voiceRecordButton;
    private VoiceStatusLamp voiceStatusLamp;
    private Label voiceStatusLabel;
    private Label voiceResultPreview;
    private volatile boolean isRecording = false;
    private volatile boolean voiceRunning = false;
    private FloatingVoiceNotification floatingNotification;  // 浮动通知窗口
    
    // BLE按钮长按相关
    private volatile boolean bleButtonPressed = false;
    private volatile boolean bleLongPressTriggered = false;
    private Thread bleLongPressThread;

    public TopBar(StudioController controller, DeviceStatus deviceStatus,
                  StudioState studioState, AgentManager agentManager) {
        this.controller = controller;
        this.deviceStatus = deviceStatus;
        this.studioState = studioState;
        this.agentManager = agentManager;
        this.hookInstaller = new HookInstaller(
            () -> controller.getHookDispatchPort(), this::addLog);
        this.controller.setHookManagerOpener(this::showDeviceInfoDialog);
        this.languageManager = LanguageManager.getInstance();
        setSpacing(0);
        setPadding(new Insets(0));
        getStyleClass().add("top-bar");
        initContent();
        setupLanguageChangeListener();
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
                    () -> controller.isEffectivelyConnected() ? languageManager.getString("status.connected")
                        : (deviceStatus.isScanning() ? languageManager.getString("status.scanning") : languageManager.getString("status.disconnected")),
                    deviceStatus.isConnectedProperty(),
                    deviceStatus.isScanningProperty()
                ),
                Bindings.createStringBinding(
                    () -> controller.isEffectivelyConnected() ? deviceStatus.getDeviceName() : languageManager.getString("status.waiting-device"),
                    deviceStatus.isConnectedProperty(),
                    deviceStatus.deviceNameProperty()
                ),
                Bindings.createObjectBinding(
                    () -> controller.isEffectivelyConnected() ? AccentColor.GREEN : AccentColor.ORANGE,
                    deviceStatus.isConnectedProperty()
                )
            ),
            new InfoPill(
                Bindings.createStringBinding(() -> languageManager.getString("status.battery")),
                Bindings.createStringBinding(
                    () -> controller.isEffectivelyConnected() ? deviceStatus.getBatteryLevel() + "%" : "—",
                    deviceStatus.isConnectedProperty(),
                    deviceStatus.batteryLevelProperty()
                ),
                Bindings.createObjectBinding(() -> AccentColor.BLUE)
            ),
            new InfoPill(
                Bindings.createStringBinding(() -> languageManager.getString("status.switch")),
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
            () -> deviceStatus.isConnected() ? languageManager.getString("button.disconnect") : languageManager.getString("button.connect"),
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
        Button bleButton = new Button(languageManager.getString("button.ble-driver"));
        bleButton.getStyleClass().add("button-ble");
        setupBleButtonLongPress(bleButton);

        ToggleButton ahaTypeToggle = new ToggleButton();
        ahaTypeToggle.getStyleClass().add("toggle-button");
        ahaTypeToggle.textProperty().bind(Bindings.createStringBinding(
            () -> studioState.ahaTypeEnabledProperty().get() ? "AhaType" : "AhaType",
            studioState.ahaTypeEnabledProperty()
        ));
        ahaTypeToggle.selectedProperty().bindBidirectional(studioState.ahaTypeEnabledProperty());
        ahaTypeToggle.selectedProperty().addListener((obs, oldValue, newValue) -> studioState.toggleAhaType(newValue));

        // 语音启动按钮
        voiceRecordButton = new Button(languageManager.getString("button.start-voice"));
        voiceRecordButton.getStyleClass().add("button-voice");
        voiceRecordButton.setOnAction(event -> toggleVoiceService());
        
        // 语音状态指示灯
        voiceStatusLamp = new VoiceStatusLamp();
        
        // 语音状态标签
        voiceStatusLabel = new Label(languageManager.getString("voice.status.stopped"));
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
                () -> studioState.ahaTypeEnabledProperty().get() ? languageManager.getString("aha-type.enabled") : languageManager.getString("aha-type.disabled"),
                studioState.ahaTypeEnabledProperty()
            ),
            studioState.ahaTypeStatusProperty()
        );

        // 检查本地模型是否启用
        boolean modelEnabled = com.example.ahakey.config.ModelConfig.getInstance().isEnabled();

        VBox configStatus = createStatusBox(
            Bindings.createBooleanBinding(agentManager::isEditingConfiguration, agentManager.bluetoothOwnerProperty()),
            Bindings.createStringBinding(
                () -> agentManager.isEditingConfiguration() ? languageManager.getString("config.status.editing") : languageManager.getString("config.status.keyboard-control"),
                agentManager.bluetoothOwnerProperty()
            ),
            Bindings.createStringBinding(
                () -> agentManager.isEditingConfiguration()
                    ? languageManager.getString("config.status.editing-detail")
                    : languageManager.getString("config.status.keyboard-detail"),
                agentManager.bluetoothOwnerProperty()
            )
        );

        Button configModeButton = new Button();
        configModeButton.getStyleClass().add("button-prominent");
        configModeButton.textProperty().bind(Bindings.createStringBinding(controller::configurationModeButtonTitle,
            studioState.syncingProperty(),
            agentManager.bluetoothOwnerProperty()));
        configModeButton.disableProperty().bind(Bindings.createBooleanBinding(
            () -> studioState.syncingProperty().get()
                || agentManager.operationInProgressProperty().get()
                || (agentManager.isEditingConfiguration() && !controller.canWriteToDevice()),
            studioState.syncingProperty(),
            agentManager.operationInProgressProperty(),
            agentManager.bluetoothOwnerProperty(),
            deviceStatus.isConnectedProperty()
        ));
        configModeButton.setTooltip(new Tooltip("连接键盘后可保存/应用"));
        configModeButton.setOnAction(event -> controller.handleConfigurationModeButton());

        Menu moreMenu = new Menu(languageManager.getString("menu.more"));
        Text moreIcon = Icons.moreHorizontal("16");
        moreMenu.setGraphic(moreIcon);

        MenuItem restoreDefaults = new MenuItem(languageManager.getString("menu.restore-defaults"));
        restoreDefaults.setOnAction(event -> studioState.restoreCurrentModeDefaults());
        MenuItem reconnect = new MenuItem(languageManager.getString("menu.reconnect"));
        reconnect.setOnAction(event -> {
            controller.userDisconnect();
            controller.userConnect();
        });
        MenuItem clearOled = new MenuItem(languageManager.getString("menu.clear-oled"));
        clearOled.setOnAction(event -> studioState.clearOledPreview());
        SeparatorMenuItem divider1 = new SeparatorMenuItem();
        MenuItem deviceInfo = new MenuItem("Hook 管理");
        deviceInfo.setOnAction(event -> showDeviceInfoDialog());
        MenuItem versionInfo = new MenuItem(languageManager.getString("menu.version-info"));
        versionInfo.setOnAction(event -> showVersionDialog());
        
        languageMenuItem = new MenuItem(languageManager.getLanguageToggleText());
        languageMenuItem.setOnAction(event -> toggleLanguage());
        
        MenuItem exitApp = new MenuItem(languageManager.getString("menu.exit"));
        exitApp.setOnAction(event -> exitApplication());
        
        MenuItem cloudAccount = new MenuItem(languageManager.getString("menu.cloud-account"));
        SeparatorMenuItem divider2 = new SeparatorMenuItem();
        MenuItem refresh = new MenuItem(languageManager.getString("menu.refresh-ahatype"));
        refresh.setOnAction(event -> studioState.toggleAhaType(studioState.ahaTypeEnabledProperty().get()));

        // 条件添加 AhaType 相关菜单项
        if (modelEnabled) {
            moreMenu.getItems().addAll(
                restoreDefaults,
                reconnect,
                clearOled,
                divider1,
                deviceInfo,
                versionInfo,
                languageMenuItem,
                exitApp,
                cloudAccount,
                divider2,
                refresh
            );
        } else {
            moreMenu.getItems().addAll(
                restoreDefaults,
                reconnect,
                clearOled,
                divider1,
                deviceInfo,
                versionInfo,
                languageMenuItem,
                exitApp
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
    private volatile boolean bleButtonProcessing = false;
    private volatile long lastBleButtonClickTime = 0;
    private static final long BLE_BUTTON_CLICK_DELAY_MS = 2000;
    
    private void handleBleButtonClick() {
        long now = System.currentTimeMillis();
        
        if (now - lastBleButtonClickTime < BLE_BUTTON_CLICK_DELAY_MS) {
            return;
        }
        
        if (bleButtonProcessing) {
            return;
        }
        
        lastBleButtonClickTime = now;
        bleButtonProcessing = true;
        
        new Thread(() -> {
            try {
                boolean running = isBleDriverRunning();
                
                if (!running) {
                    launchBleDriver();
                    return;
                }
                
                boolean reachable = isBleBridgeReachable();
                
                if (reachable) {
                    Platform.runLater(() -> {
                        Alert alert = new Alert(Alert.AlertType.INFORMATION);
                        alert.setTitle(languageManager.getString("dialog.ble-driver-title"));
                        alert.setHeaderText(null);
                        alert.setContentText(languageManager.getString("dialog.ble-running"));
                        alert.showAndWait();
                    });
                } else {
                    Thread.sleep(1500);
                    reachable = isBleBridgeReachable();
                    
                    if (!reachable) {
                        stopBleDriverProcess();
                        Thread.sleep(500);
                        launchBleDriver();
                    }
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } finally {
                bleButtonProcessing = false;
            }
        }, "ble-button-handler").start();
    }

    /**
     * 设置 BLE 按钮长按功能
     * 长按5秒：强制关闭所有 BLE_tcp_driver 进程（包括挂起的）
     * 短按：正常的 BLE 驱动启动/重启逻辑
     */
    private void setupBleButtonLongPress(Button bleButton) {
        bleButton.setOnMousePressed(event -> {
            bleButtonPressed = true;
            bleLongPressTriggered = false;
            
            bleLongPressThread = new Thread(() -> {
                try {
                    Thread.sleep(5000);
                    if (bleButtonPressed && !bleLongPressTriggered) {
                        bleLongPressTriggered = true;
                        Platform.runLater(() -> {
                            forceKillAllBleProcesses();
                        });
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }, "ble-longpress");
            bleLongPressThread.start();
        });
        
        bleButton.setOnMouseReleased(event -> {
            bleButtonPressed = false;
            if (bleLongPressThread != null) {
                bleLongPressThread.interrupt();
                bleLongPressThread = null;
            }
            
            if (!bleLongPressTriggered) {
                handleBleButtonClick();
            }
        });
        
        bleButton.setOnMouseExited(event -> {
            if (bleButtonPressed) {
                bleButtonPressed = false;
                if (bleLongPressThread != null) {
                    bleLongPressThread.interrupt();
                    bleLongPressThread = null;
                }
            }
        });
    }
    
    /**
     * 强制杀死所有 BLE_tcp_driver 进程（包括挂起的）
     */
    private void forceKillAllBleProcesses() {
        new Thread(() -> {
            int initialCount = countBleProcesses();
            if (initialCount == 0) {
                Platform.runLater(() -> showAlert(languageManager.getString("dialog.ble-driver-title"), languageManager.getString("dialog.ble-no-process")));
                return;
            }
            
            boolean success = killProcessesWithMultipleMethods();
            
            try { Thread.sleep(1000); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            
            int remainingCount = countBleProcesses();
            
            Platform.runLater(() -> {
                if (remainingCount == 0) {
                    Alert alert = new Alert(Alert.AlertType.INFORMATION);
                    alert.setTitle(languageManager.getString("dialog.ble-driver-title"));
                    alert.setHeaderText(null);
                    alert.setContentText(languageManager.getString("dialog.ble-kill-success"));
                    alert.showAndWait();
                } else {
                    Alert alert = new Alert(Alert.AlertType.WARNING);
                    alert.setTitle(languageManager.getString("dialog.ble-driver-title"));
                    alert.setHeaderText(null);
                    alert.setContentText(String.format(languageManager.getString("dialog.ble-kill-fail"), remainingCount));
                    alert.showAndWait();
                }
            });
        }, "ble-kill").start();
    }
    
    private boolean killProcessesWithMultipleMethods() {
        boolean success = false;
        
        success = sendShutdownCommand();
        
        if (!success) {
            success |= executeKillCommand("taskkill", "/F", "/IM", "BLE_tcp_driver.exe");
        }
        
        if (!success) {
            success |= executeKillCommand("taskkill", "/F", "/T", "/IM", "BLE_tcp_driver.exe");
        }
        
        if (!success) {
            success |= executeKillCommand("powershell", "-Command", "Stop-Process -Name BLE_tcp_driver -Force -ErrorAction SilentlyContinue");
        }
        
        if (!success) {
            success |= executeKillCommand("powershell", "-Command", "Get-Process -Name BLE_tcp_driver -ErrorAction SilentlyContinue | Stop-Process -Force");
        }
        
        if (!success) {
            success |= executeKillCommand("wmic", "process", "where", "name='BLE_tcp_driver.exe'", "call", "terminate");
        }
        
        if (!success) {
            success |= executeKillCommand("powershell", "-Command", "Get-WmiObject Win32_Process -Filter \"Name='BLE_tcp_driver.exe'\" | ForEach-Object { $_.Terminate() }");
        }
        
        if (!success) {
            success |= executeKillCommand("powershell", "-Command", "$pids = (Get-CimInstance Win32_Process -Filter 'Name=''BLE_tcp_driver.exe''').ProcessId; if($pids) { taskkill /F /PID $pids -ErrorAction SilentlyContinue }");
        }
        
        if (!success) {
            success |= executeKillCommand("powershell", "-Command", "Get-CimInstance Win32_Process -Filter 'Name=''BLE_tcp_driver.exe''' | Invoke-CimMethod -MethodName Terminate");
        }
        
        if (!success) {
            success |= killProcessByPidList();
        }
        
        return success;
    }
    
    private boolean killProcessByPidList() {
        try {
            ProcessBuilder pb = new ProcessBuilder("tasklist", "/FI", "IMAGENAME eq BLE_tcp_driver.exe", "/NH", "/FO", "CSV");
            pb.redirectErrorStream(true);
            Process p = pb.start();
            
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.toLowerCase().contains("ble_tcp_driver.exe")) {
                        String[] parts = line.split(",");
                        if (parts.length >= 2) {
                            String pidStr = parts[1].replace("\"", "").trim();
                            try {
                                int pid = Integer.parseInt(pidStr);
                                new ProcessBuilder("taskkill", "/F", "/PID", String.valueOf(pid)).redirectErrorStream(true).start().waitFor();
                            } catch (NumberFormatException e) {
                                // ignore
                            }
                        }
                    }
                }
            }
            p.waitFor();
            
            Thread.sleep(500);
            return countBleProcesses() == 0;
        } catch (Exception e) {
            return false;
        }
    }
    
    private boolean sendShutdownCommand() {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress("127.0.0.1", 9000), 1000);
            
            byte[] shutdownPacket = new byte[3];
            shutdownPacket[0] = 0x05;
            shutdownPacket[1] = 0x00;
            shutdownPacket[2] = 0x00;
            
            socket.getOutputStream().write(shutdownPacket);
            socket.getOutputStream().flush();
            
            Thread.sleep(500);
            
            return countBleProcesses() == 0;
        } catch (Exception e) {
            return false;
        }
    }
    
    private boolean executeKillCommand(String... command) {
        try {
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(true);
            pb.directory(new File(System.getProperty("user.dir")));
            Process p = pb.start();
            int exitCode = p.waitFor();
            
            try (java.io.BufferedReader reader = new java.io.BufferedReader(
                    new java.io.InputStreamReader(p.getInputStream()))) {
                StringBuilder output = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                }
            }
            
            Thread.sleep(300);
            
            return countBleProcesses() == 0;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 统计 BLE_tcp_driver 进程数量
     */
    private int countBleProcesses() {
        int count = 0;
        try {
            ProcessBuilder pb = new ProcessBuilder("tasklist", "/FI", "IMAGENAME eq BLE_tcp_driver.exe", "/NH");
            pb.redirectErrorStream(true);
            Process p = pb.start();
            
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.toLowerCase().contains("ble_tcp_driver.exe")) {
                        count++;
                    }
                }
            }
            p.waitFor();
        } catch (Exception e) {
            // 统计失败，返回0
        }
        return count;
    }

    private boolean isBleBridgeReachable() {
        int maxRetries = 3;
        int delayMs = 300;
        
        for (int i = 0; i < maxRetries; i++) {
            try (Socket socket = new Socket()) {
                socket.connect(new InetSocketAddress("127.0.0.1", 9000), 500);
                return true;
            } catch (Exception e) {
                if (i < maxRetries - 1) {
                    try {
                        Thread.sleep(delayMs);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
        }
        return false;
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
                
                pb.redirectOutput(ProcessBuilder.Redirect.INHERIT);
                pb.redirectError(ProcessBuilder.Redirect.INHERIT);
                
                Process process = pb.start();
                
                new Thread(() -> {
                    try {
                        int exitCode = process.waitFor();
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    }
                }, "ble-driver-monitor").start();
                
                new Thread(() -> {
                    try {
                        Thread.sleep(1000);
                        Platform.runLater(() -> {
                            if (isBleDriverRunning()) {
                            } else {
                                showAlert(languageManager.getString("dialog.ble-driver-title"), String.format(languageManager.getString("dialog.ble-start-fail"), finalBleExe.getAbsolutePath()));
                            }
                        });
                    } catch (Exception ignored) {}
                }).start();
            } else {
                showAlert(languageManager.getString("dialog.ble-driver-title"), languageManager.getString("dialog.ble-not-found") + "\n" 
                    + new File(appDir, "BLE_tcp_driver.exe").getAbsolutePath() + "\n"
                    + (appDirFile.getParentFile() != null ? new File(appDirFile.getParentFile(), "BLE_tcp_driver.exe").getAbsolutePath() : "") + "\n"
                    + new File(System.getProperty("user.dir"), "BLE_tcp_driver.exe").getAbsolutePath());
            }
        } catch (Exception e) {
            showAlert(languageManager.getString("dialog.ble-driver-title"), languageManager.getString("dialog.ble-start-fail").replace("%s", "") + e.getMessage());
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
            setVoiceStatus("error", languageManager.getString("voice.status.voice-service-unavailable"));
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
        setVoiceStatus("starting", languageManager.getString("voice.status.starting"));
        
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
        setVoiceStatus("stopping", languageManager.getString("voice.status.stopping"));
        
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
                    setVoiceStatus("stopped", languageManager.getString("voice.status.stopped"));
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
            voiceRecordButton.setText(languageManager.getString("button.voice-unavailable"));
            setVoiceStatus("error", languageManager.getString("voice.status.voice-service-unavailable"));
            return;
        }
        
        voiceRecordButton.setDisable(false);
        
        if (voiceRunning) {
            voiceRecordButton.getStyleClass().add("voice-recording");
            voiceRecordButton.setText(languageManager.getString("button.stop-voice"));
        } else {
            voiceRecordButton.getStyleClass().remove("voice-recording");
            voiceRecordButton.setText(languageManager.getString("button.start-voice"));
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
        dialog.setTitle("AhaKey Hook 管理");
        dialog.setWidth(560);
        dialog.setHeight(620);

        ScrollPane scrollPane = new ScrollPane();
        scrollPane.setFitToWidth(true);

        VBox content = new VBox(12);
        content.setPadding(new Insets(12));
        Map<String, VBox> cards = new LinkedHashMap<>();
        Map<String, HookInstaller.HookStatus> statuses = new LinkedHashMap<>();
        Map<String, Button> actionButtons = new LinkedHashMap<>();
        BooleanProperty hookDialogBusy = new SimpleBooleanProperty(false);
        VBox list = new VBox(10);
        for (String name : List.of("Claude", "Cursor", "Codex", "Kimi")) {
            VBox card = createHookManagerCard(
                name,
                HookInstaller.HookStatus.DETECTING,
                statuses,
                actionButtons,
                hookDialogBusy,
                null
            );
            cards.put(name, card);
            list.getChildren().add(card);
        }

        Button refresh = new Button("重新检测");
        refresh.setGraphic(Icons.refresh("14"));
        refresh.disableProperty().bind(hookDialogBusy);
        Runnable[] rescan = new Runnable[1];
        rescan[0] = () -> {
            hookDialogBusy.set(true);
            actionButtons.clear();
            for (Map.Entry<String, VBox> entry : cards.entrySet()) {
                updateHookManagerCard(
                    entry.getValue(),
                    entry.getKey(),
                    HookInstaller.HookStatus.DETECTING,
                    statuses,
                    actionButtons,
                    hookDialogBusy,
                    rescan[0]
                );
            }
            Thread thread = new Thread(() -> {
                Map<String, HookInstaller.HookStatus> scanned = new LinkedHashMap<>();
                for (String name : cards.keySet()) {
                    scanned.put(name, hookInstaller.getHookStatus(name));
                }
                Platform.runLater(() -> {
                    statuses.clear();
                    statuses.putAll(scanned);
                    actionButtons.clear();
                    for (Map.Entry<String, HookInstaller.HookStatus> entry : scanned.entrySet()) {
                        updateHookManagerCard(
                            cards.get(entry.getKey()),
                            entry.getKey(),
                            entry.getValue(),
                            statuses,
                            actionButtons,
                            hookDialogBusy,
                            rescan[0]
                        );
                    }
                    hookDialogBusy.set(false);
                    List<String> outdated = scanned.entrySet().stream()
                        .filter(entry -> entry.getValue() == HookInstaller.HookStatus.OUTDATED)
                        .map(Map.Entry::getKey)
                        .toList();
                    if (!outdated.isEmpty() && !hookUpdateSummaryShown) {
                        hookUpdateSummaryShown = true;
                        showHookUpdateSummary(outdated, rescan[0]);
                    }
                });
            }, "hook-manager-scan");
            thread.setDaemon(true);
            thread.start();
        };
        refresh.setOnAction(event -> rescan[0].run());

        Label note1 = hookNote("安装或更新时，AhaKey 只会添加/替换自己的 Hook，不会删除你原本配置的其他 Hook。");
        Label note2 = hookNote("当前多任务灯光支持 Codex / Cursor。");
        HBox bottom = new HBox(10);
        bottom.setAlignment(Pos.CENTER_RIGHT);
        Button closeBtn = new Button("关闭");
        closeBtn.setOnAction(event -> dialog.close());
        bottom.getChildren().addAll(refresh, closeBtn);

        content.getChildren().addAll(list, note1, note2, bottom);
        scrollPane.setContent(content);

        Scene scene = new Scene(scrollPane);
        scene.getStylesheets().add(getClass().getResource("/style.css").toExternalForm());
        dialog.setScene(scene);
        dialog.show();
        rescan[0].run();
    }

    private Label hookNote(String text) {
        Label label = new Label(text);
        label.getStyleClass().add("group-note");
        label.setWrapText(true);
        return label;
    }

    private VBox createHookManagerCard(
        String hookName,
        HookInstaller.HookStatus status,
        Map<String, HookInstaller.HookStatus> statuses,
        Map<String, Button> actionButtons,
        BooleanProperty hookDialogBusy,
        Runnable rescan
    ) {
        VBox card = new VBox(8);
        card.getStyleClass().add("dialog-card");
        card.setPadding(new Insets(12));
        updateHookManagerCard(card, hookName, status, statuses, actionButtons, hookDialogBusy, rescan);
        return card;
    }

    private void updateHookManagerCard(
        VBox card,
        String hookName,
        HookInstaller.HookStatus status,
        Map<String, HookInstaller.HookStatus> statuses,
        Map<String, Button> actionButtons,
        BooleanProperty hookDialogBusy,
        Runnable rescan
    ) {
        card.getChildren().clear();
        statuses.put(hookName, status);
        if (actionButtons != null) {
            actionButtons.remove(hookName);
        }

        HBox titleRow = new HBox(8);
        titleRow.setAlignment(Pos.CENTER_LEFT);
        Label title = new Label(hookName);
        title.getStyleClass().add("dialog-card-title");
        Region spacer = new Region();
        HBox.setHgrow(spacer, Priority.ALWAYS);
        Label statusLabel = new Label(hookStatusText(status));
        statusLabel.getStyleClass().add(status == HookInstaller.HookStatus.LATEST ? "dialog-status-installed" : "dialog-status-uninstalled");
        titleRow.getChildren().addAll(title, spacer, statusLabel);

        Label description = hookNote(hookDescription(status));
        Button action = new Button(hookActionText(status));
        boolean canWrite = status == HookInstaller.HookStatus.NOT_INSTALLED || status == HookInstaller.HookStatus.OUTDATED;
        if (hookDialogBusy == null) {
            action.setDisable(!canWrite);
        } else {
            action.disableProperty().bind(Bindings.createBooleanBinding(
                () -> hookDialogBusy.get() || !canWrite,
                hookDialogBusy
            ));
        }
        if (actionButtons != null) {
            actionButtons.put(hookName, action);
        }
        if (canWrite) {
            action.getStyleClass().add("button-install");
            action.setOnAction(event -> runSingleHookWrite(hookName, status, action, actionButtons, hookDialogBusy, rescan));
        }

        card.getChildren().addAll(titleRow, description, action);
    }

    private void runSingleHookWrite(
        String hookName,
        HookInstaller.HookStatus status,
        Button action,
        Map<String, Button> actionButtons,
        BooleanProperty hookDialogBusy,
        Runnable rescan
    ) {
        if (hookDialogBusy != null && hookDialogBusy.get()) {
            return;
        }
        if (hookDialogBusy != null) {
            hookDialogBusy.set(true);
        }
        if (actionButtons != null) {
            actionButtons.values().forEach(button -> button.setMouseTransparent(true));
        }
        action.setText(status == HookInstaller.HookStatus.NOT_INSTALLED ? "安装中" : "更新中");
        Thread thread = new Thread(() -> {
            HookInstaller.HookWriteResult result = hookInstaller.installOrUpdate(hookName);
            Platform.runLater(() -> {
                if (actionButtons != null) {
                    actionButtons.values().forEach(button -> button.setMouseTransparent(false));
                }
                if (result.success()) {
                    if (rescan != null) {
                        rescan.run();
                    } else if (hookDialogBusy != null) {
                        hookDialogBusy.set(false);
                    }
                } else {
                    Alert alert = new Alert(Alert.AlertType.ERROR);
                    alert.initOwner(getScene() == null ? null : getScene().getWindow());
                    alert.setTitle("AhaKey Hook 管理");
                    alert.setHeaderText(null);
                    alert.setContentText(result.reason() + "，请联系管理员");
                    alert.showAndWait();
                    if (rescan != null) {
                        rescan.run();
                    } else if (hookDialogBusy != null) {
                        hookDialogBusy.set(false);
                    }
                }
            });
        }, "hook-manager-write-" + hookName);
        thread.setDaemon(true);
        thread.start();
    }

    private void showHookUpdateSummary(List<String> outdated, Runnable rescan) {
        javafx.scene.control.Dialog<Void> dialog = new javafx.scene.control.Dialog<>();
        dialog.initOwner(getScene() == null ? null : getScene().getWindow());
        dialog.setTitle("AhaKey Hook 管理");
        ButtonType update = new ButtonType("一键更新");
        ButtonType cancel = new ButtonType("取消", javafx.scene.control.ButtonBar.ButtonData.CANCEL_CLOSE);
        dialog.getDialogPane().getButtonTypes().setAll(update, cancel);
        Label message = hookNote("以下工具需要更新 Hook：" + String.join("、", outdated)
            + "\n更新会先备份原 Hook 文件，并且只替换 AhaKey Hook。");
        dialog.getDialogPane().setContent(message);
        Button updateButton = (Button) dialog.getDialogPane().lookupButton(update);
        Button cancelButton = (Button) dialog.getDialogPane().lookupButton(cancel);
        updateButton.addEventFilter(javafx.event.ActionEvent.ACTION, event -> {
            event.consume();
            updateButton.setDisable(true);
            cancelButton.setDisable(true);
            Thread thread = new Thread(() -> {
                List<String> failed = new ArrayList<>();
                for (String name : outdated) {
                    String currentName = name;
                    Platform.runLater(() -> message.setText("正在更新：" + currentName));
                    HookInstaller.HookWriteResult result = hookInstaller.installOrUpdate(currentName);
                    if (!result.success()) {
                        failed.add(currentName + "：" + result.reason());
                    }
                }
                Platform.runLater(() -> {
                    if (failed.isEmpty()) {
                        dialog.close();
                        if (rescan != null) {
                            rescan.run();
                        }
                    } else {
                        message.setText("以下工具更新失败：\n" + String.join("\n", failed));
                        ButtonType know = new ButtonType("知道了", javafx.scene.control.ButtonBar.ButtonData.OK_DONE);
                        dialog.getDialogPane().getButtonTypes().setAll(know);
                        Button knowButton = (Button) dialog.getDialogPane().lookupButton(know);
                        knowButton.addEventFilter(javafx.event.ActionEvent.ACTION, e -> {
                            if (rescan != null) {
                                rescan.run();
                            }
                        });
                    }
                });
            }, "hook-manager-update-all");
            thread.setDaemon(true);
            thread.start();
        });
        dialog.show();
    }

    private String hookStatusText(HookInstaller.HookStatus status) {
        return switch (status) {
            case DETECTING -> "检测中";
            case APP_NOT_FOUND -> "未检测到应用";
            case NOT_INSTALLED -> "未安装";
            case OUTDATED -> "待更新";
            case LATEST -> "最新";
            case ERROR -> "异常";
        };
    }

    private String hookActionText(HookInstaller.HookStatus status) {
        return switch (status) {
            case APP_NOT_FOUND -> "不可安装";
            case NOT_INSTALLED -> "安装 Hook";
            case OUTDATED -> "更新 Hook";
            case LATEST -> "已是最新";
            case ERROR -> "异常";
            case DETECTING -> "检测中";
        };
    }

    private String hookDescription(HookInstaller.HookStatus status) {
        return switch (status) {
            case APP_NOT_FOUND -> "未检测到对应应用，暂不可安装 Hook";
            case NOT_INSTALLED -> "未安装 Hook，安装后可支持 AhaKey 功能";
            case OUTDATED -> "当前 Hook 需要更新，更新后可支持多任务灯光状态，并优化 Cursor 权限流程";
            case LATEST -> "已是最新版，支持多任务灯光状态";
            case ERROR -> "检测异常，请联系管理员";
            case DETECTING -> "正在检测 Hook 状态";
        };
    }

    private SleepWaitTimeControl createSleepWaitTimeControl() {
        VBox box = new VBox(6);

        Label title = new Label(languageManager.getString("sleep-wait-time.title"));
        title.getStyleClass().add("dialog-text");

        ComboBox<SleepWaitTimeOption> options = new ComboBox<>();
        options.getItems().addAll(
            new SleepWaitTimeOption(0, languageManager.getString("sleep-wait-time.never")),
            new SleepWaitTimeOption(30, languageManager.getString("sleep-wait-time.30")),
            new SleepWaitTimeOption(60, languageManager.getString("sleep-wait-time.60")),
            new SleepWaitTimeOption(120, languageManager.getString("sleep-wait-time.120"))
        );
        options.setPrefWidth(140);

        Label status = new Label();
        status.getStyleClass().add("dialog-text");
        status.setWrapText(true);
        AtomicInteger readSerial = new AtomicInteger();

        Label description = new Label(languageManager.getString("sleep-wait-time.description"));
        description.getStyleClass().add("dialog-text");
        description.setWrapText(true);

        Button saveButton = new Button(languageManager.getString("sleep-wait-time.save"));
        BooleanProperty busy = new SimpleBooleanProperty(false);
        options.disableProperty().bind(Bindings.createBooleanBinding(
            () -> !controller.isEffectivelyConnected() || busy.get(),
            this.deviceStatus.isConnectedProperty(),
            busy
        ));
        saveButton.disableProperty().bind(Bindings.createBooleanBinding(
            () -> !controller.isEffectivelyConnected() || busy.get() || options.getSelectionModel().getSelectedItem() == null,
            this.deviceStatus.isConnectedProperty(),
            busy,
            options.getSelectionModel().selectedItemProperty()
        ));

        HBox row = new HBox(8);
        row.setAlignment(Pos.CENTER_LEFT);
        row.getChildren().addAll(title, options, saveButton);

        saveButton.setOnAction(event -> saveSleepWaitTime(options, status, busy));
        loadSleepWaitTime(options, status, busy, readSerial);

        box.getChildren().addAll(row, description, status);
        return new SleepWaitTimeControl(box, () -> loadSleepWaitTime(options, status, busy, readSerial));
    }

    private void loadSleepWaitTime(ComboBox<SleepWaitTimeOption> options, Label status, BooleanProperty busy, AtomicInteger readSerialSource) {
        if (!controller.isEffectivelyConnected()) {
            status.setText(languageManager.getString("sleep-wait-time.not-connected"));
            return;
        }
        int readSerial = readSerialSource.incrementAndGet();
        logger.info("Sleep wait time UI read started: serial={}", readSerial);
        busy.set(true);
        status.setText(languageManager.getString("sleep-wait-time.reading"));
        Thread timeoutThread = new Thread(() -> {
            try {
                Thread.sleep(10_000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            Platform.runLater(() -> {
                if (readSerialSource.get() == readSerial && busy.get()) {
                    readSerialSource.incrementAndGet();
                    logger.warn("Sleep wait time UI read timed out: serial={}", readSerial);
                    options.getSelectionModel().clearSelection();
                    status.setText(languageManager.getString("sleep-wait-time.read-timeout"));
                    busy.set(false);
                }
            });
        }, "sleep-wait-time-read-timeout");
        timeoutThread.setDaemon(true);
        timeoutThread.start();

        Thread thread = new Thread(() -> {
            try {
                int minutes = controller.getBleManager().readSleepWaitTimeMinutes();
                Platform.runLater(() -> {
                    if (readSerialSource.get() != readSerial) {
                        logger.info("Sleep wait time UI update ignored for stale read: serial={}, current={}", readSerial, readSerialSource.get());
                        return;
                    }
                    try {
                        SleepWaitTimeOption option = findSleepWaitTimeOption(options, minutes);
                        if (option == null) {
                            options.getSelectionModel().clearSelection();
                            status.setText(languageManager.getString("sleep-wait-time.invalid-current"));
                            logger.warn("Sleep wait time UI read returned unsupported value: serial={}, minutes={}", readSerial, minutes);
                        } else {
                            options.getSelectionModel().select(option);
                            status.setText(formatSleepWaitTimeStatus("sleep-wait-time.current", option.label()));
                            logger.info("Sleep wait time UI updated: serial={}, minutes={}, label={}", readSerial, minutes, option.label());
                        }
                    } finally {
                        busy.set(false);
                    }
                });
            } catch (Exception e) {
                Platform.runLater(() -> {
                    if (readSerialSource.get() != readSerial) {
                        logger.info("Sleep wait time UI failure ignored for stale read: serial={}, current={}", readSerial, readSerialSource.get());
                        return;
                    }
                    status.setText(languageManager.getString("sleep-wait-time.read-failed") + e.getMessage());
                    logger.warn("Sleep wait time UI read failed: serial={}", readSerial, e);
                    busy.set(false);
                });
            }
        }, "sleep-wait-time-read");
        thread.setDaemon(true);
        thread.start();
    }

    private void saveSleepWaitTime(ComboBox<SleepWaitTimeOption> options, Label status, BooleanProperty busy) {
        SleepWaitTimeOption selected = options.getSelectionModel().getSelectedItem();
        if (selected == null) {
            return;
        }
        if (!controller.isEffectivelyConnected()) {
            status.setText(languageManager.getString("sleep-wait-time.not-connected"));
            return;
        }
        busy.set(true);
        status.setText(languageManager.getString("sleep-wait-time.saving"));
        Thread thread = new Thread(() -> {
            try {
                int readback = controller.getBleManager().setSleepWaitTimeMinutesAndVerify(selected.minutes());
                Platform.runLater(() -> {
                    SleepWaitTimeOption option = findSleepWaitTimeOption(options, readback);
                    if (option != null) {
                        options.getSelectionModel().select(option);
                        status.setText(formatSleepWaitTimeStatus("sleep-wait-time.saved", option.label()));
                    } else {
                        status.setText(languageManager.getString("sleep-wait-time.invalid-current"));
                    }
                });
            } catch (Exception e) {
                Platform.runLater(() -> status.setText(languageManager.getString("sleep-wait-time.save-failed") + e.getMessage()));
            } finally {
                Platform.runLater(() -> busy.set(false));
            }
        }, "sleep-wait-time-save");
        thread.setDaemon(true);
        thread.start();
    }

    private SleepWaitTimeOption findSleepWaitTimeOption(ComboBox<SleepWaitTimeOption> options, int minutes) {
        for (SleepWaitTimeOption option : options.getItems()) {
            if (option.minutes() == minutes) {
                return option;
            }
        }
        return null;
    }

    private String formatSleepWaitTimeStatus(String key, String label) {
        String pattern = languageManager.getString(key);
        if (pattern == null || pattern.isBlank()) {
            return label;
        }
        if (pattern.contains("%s")) {
            return String.format(pattern, label);
        }
        return pattern + label;
    }

    private record SleepWaitTimeOption(int minutes, String label) {
        @Override
        public String toString() {
            return label;
        }
    }

    private record SleepWaitTimeControl(VBox node, Runnable refreshAction) {
        void refresh() {
            refreshAction.run();
        }
    }
    
    private void updateHookCardStatus(VBox card, String hookName, boolean isInstalled) {
        for (var child : card.getChildren()) {
            if (child instanceof Button button) {
                if (isInstalled) {
                    button.setText(languageManager.getString("hook.uninstall"));
                    button.getStyleClass().remove("button-install");
                    button.getStyleClass().add("button-uninstall");
                    button.setOnAction(event -> uninstallHook(hookName));
                } else {
                    button.setText(languageManager.getString("hook.install"));
                    button.getStyleClass().remove("button-uninstall");
                    button.getStyleClass().add("button-install");
                    button.setOnAction(event -> installHook(hookName));
                }
                break;
            }
        }
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
        Label statusLabel = new Label(languageManager.getString("hook.installation-status") + ":");
        statusLabel.getStyleClass().add("dialog-status-label");

        Label statusValue = new Label(isInstalled ? languageManager.getString("hook.installed") : languageManager.getString("hook.not-installed"));
        if (isInstalled) {
            statusValue.getStyleClass().add("dialog-status-installed");
        } else {
            statusValue.getStyleClass().add("dialog-status-uninstalled");
        }

        Region spacer2 = new Region();
        HBox.setHgrow(spacer2, Priority.ALWAYS);

        Button installBtn = new Button(languageManager.getString("button.install"));
        installBtn.getStyleClass().add("button-install");
        installBtn.setOnAction(event -> {
            installHook(hookName);
            statusValue.setText(languageManager.getString("hook.installed"));
            statusValue.getStyleClass().remove("dialog-status-uninstalled");
            statusValue.getStyleClass().add("dialog-status-installed");
        });

        Button uninstallBtn = new Button(languageManager.getString("button.uninstall"));
        uninstallBtn.getStyleClass().add("button-uninstall");
        uninstallBtn.setOnAction(event -> {
            uninstallHook(hookName);
            statusValue.setText(languageManager.getString("hook.not-installed"));
            statusValue.getStyleClass().remove("dialog-status-installed");
            statusValue.getStyleClass().add("dialog-status-uninstalled");
        });

        statusRow.getChildren().addAll(statusLabel, statusValue, spacer2, installBtn, uninstallBtn);

        card.getChildren().addAll(titleRow, statusRow);
        return card;
    }

    // ==================== Hook 管理（委托给 HookInstaller） ====================

    private boolean isHookInstalled(String hookName) {
        return hookInstaller.isInstalled(hookName);
    }

    private void installHook(String hookName) {
        hookInstaller.install(hookName);
    }

    private void uninstallHook(String hookName) {
        addLog("[卸载] 开始卸载 " + hookName + " Hook...");
        hookInstaller.uninstall(hookName);
    }

    private void addLog(String message) {
        if (logArea != null) {
            String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss"));
            logArea.appendText("[" + timestamp + "] " + message + "\n");
            logArea.setScrollTop(Double.MAX_VALUE);
        }
    }
    
    private void showVersionDialog() {
        Alert alert = new Alert(Alert.AlertType.INFORMATION);
        alert.setTitle(languageManager.getString("dialog.version-title"));
        alert.setHeaderText(null);
        
        String version = getVersion();
        alert.setContentText(String.format(languageManager.getString("dialog.version-content"), version));
        
        alert.showAndWait();
    }
    
    private String getVersion() {
        String version = System.getProperty("app.version");
        if (version == null || version.isEmpty()) {
            Package pkg = TopBar.class.getPackage();
            version = pkg != null ? pkg.getImplementationVersion() : null;
        }
        if (version == null || version.isEmpty()) {
            version = "1.0.0";
        }
        return version;
    }
    
    private void toggleLanguage() {
        String newLang = languageManager.isChinese() ? "en" : "zh";
        languageManager.switchLanguage(newLang);
        
        Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
        alert.setTitle(languageManager.getString("language-change-title"));
        alert.setHeaderText(null);
        alert.setContentText(languageManager.isChinese() 
            ? languageManager.getString("language-change-chinese") 
            : languageManager.getString("language-change-english"));
        
        ButtonType exitBtn = new ButtonType(languageManager.getString("dialog.exit-now"));
        ButtonType laterBtn = new ButtonType(languageManager.getString("dialog.exit-later"));
        
        alert.getButtonTypes().setAll(exitBtn, laterBtn);
        
        Optional<ButtonType> result = alert.showAndWait();
        if (result.isPresent() && result.get() == exitBtn) {
            exitApplication();
        }
    }
    
    private void exitApplication() {
        Platform.exit();
        System.exit(0);
    }
    
    private void setupLanguageChangeListener() {
        LanguageManager.LanguageChangeNotifier.addListener(() -> {
            Platform.runLater(() -> {
                if (languageMenuItem != null) {
                    languageMenuItem.setText(languageManager.getLanguageToggleText());
                }
            });
        });
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
