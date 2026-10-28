package com.example.ahakey.view;

import static com.example.ahakey.util.LanguageManager.text;

import static com.example.ahakey.util.LanguageManager.localize;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.service.AgentManager;
import com.example.ahakey.service.HookInstaller;
import com.example.ahakey.service.BleBridgeProcessOwner;
import com.example.ahakey.service.BleDriverLocator;
import com.example.ahakey.localvoice.LocalVoiceFeature;
import com.example.ahakey.service.VoiceInputManager;
import com.example.ahakey.util.Icons;
import com.example.ahakey.util.LanguageManager;
import com.example.ahakey.util.FirstRunState;
import javafx.animation.PauseTransition;
import javafx.animation.KeyFrame;
import javafx.animation.Timeline;
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
import java.nio.file.Path;
import java.nio.file.Paths;
import java.io.File;
import javafx.scene.canvas.Canvas;
import javafx.scene.canvas.GraphicsContext;
import javafx.animation.AnimationTimer;
import javafx.util.Duration;

public class TopBar extends VBox {
    private final StudioController controller;
    private final DeviceStatus deviceStatus;
    private final StudioState studioState;
    private final AgentManager agentManager;
    private VoiceInputManager voiceInputManager;
    private TextArea logArea;
    private final HookInstaller hookInstaller;
    private final LanguageManager languageManager;
    private MenuItem languageMenuItem;
    
    // 语音相关UI组件
    private Button voiceRecordButton;
    private VoiceStatusLamp voiceStatusLamp;
    private Label voiceStatusLabel;
    private Label voiceResultPreview;
    private volatile boolean isRecording = false;
    private volatile boolean voiceRunning = false;
    /** Mirrors voiceRunning for UI bindings. */
    private final javafx.beans.property.BooleanProperty voiceRunningProperty =
        new javafx.beans.property.SimpleBooleanProperty(false);
    private ToggleButton ahaTypeSwitch;
    /** Voice input starts once the model is loaded. */
    private boolean startVoiceWhenReady;
    /** Set only when the user turned the switch on: then also turn on cloud refinement. */
    private boolean enableCloudWhenReady;
    /** Last voice service error, shown under "AhaType 开启". */
    private final javafx.beans.property.StringProperty voiceErrorProperty =
        new javafx.beans.property.SimpleStringProperty("");
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
        this.languageManager = LanguageManager.getInstance();
        setSpacing(0);
        setPadding(new Insets(0));
        getStyleClass().add("top-bar");
        initContent();
        setupLanguageChangeListener();
        Platform.runLater(() -> {
            Stage owner = getScene() != null
                && getScene().getWindow() instanceof Stage
                ? (Stage) getScene().getWindow()
                : null;
            com.example.ahakey.update.AppUpdateCoordinator.onApplicationReady(owner);
            com.example.ahakey.update.FirmwareUpdateNotifier.checkWhenConnected(
                owner, controller.getBleManager(), deviceStatus
            );
            PauseTransition onboardingDelay = new PauseTransition(Duration.seconds(1.2));
            onboardingDelay.setOnFinished(event ->
                Platform.runLater(() -> showHookOnboardingIfNeeded(owner)));
            onboardingDelay.play();
        });
    }

    private void showHookOnboardingIfNeeded(Stage owner) {
        if (!System.getProperty("os.name", "").toLowerCase().contains("win")
            || !FirstRunState.shouldShowHookOnboarding()) {
            return;
        }
        if (isHookInstalled("Claude") || isHookInstalled("Cursor")
            || isHookInstalled("Codex") || isHookInstalled("Kimi")) {
            FirstRunState.markHookOnboardingShown();
            return;
        }

        ButtonType openManager = new ButtonType(localize("打开 Hook 管理"));
        ButtonType later = new ButtonType(localize("稍后设置"));
        Alert alert = new Alert(Alert.AlertType.INFORMATION,
            localize("AhaKey Studio 尚未安装 AI 软件的 Hook 组件。未安装 Hook 时，键盘配置和语音功能仍可使用，")
                + localize("但 Claude、Cursor、Codex、Kimi 等 AI 联动状态与审批功能不可用。\n\n")
                + localize("安装 Hook 后，请在对应 AI 软件中同意 Hook/钩子权限，并完全退出后重新启动该 Agent。"),
            openManager, later);
        if (owner != null) alert.initOwner(owner);
        alert.setTitle(localize("首次使用：安装 AI Hook 组件"));
        alert.setHeaderText(localize("需要 AI 联动功能时，请先安装对应 Hook"));
        Optional<ButtonType> selected = alert.showAndWait();
        FirstRunState.markHookOnboardingShown();
        if (selected.filter(openManager::equals).isPresent()) {
            showDeviceInfoDialog();
        }
    }
    
    /**
     * 设置语音输入管理器
     */
    public void setVoiceInputManager(VoiceInputManager voiceInputManager) {
        if (voiceInputManager == null && voiceRunning) {
            // Local voice was turned off in settings while the service ran.
            stopVoiceService();
        }
        this.voiceInputManager = voiceInputManager;
        updateVoiceButtonState();
        // There is no start button: voice input runs whenever local voice is
        // available, whether it was turned on here, in settings, or at startup.
        if (LocalVoiceFeature.getInstance().isAvailable()) {
            startVoiceWhenReady = false;
            if (voiceInputManager == null) {
                setVoiceStatus("error", text("aha.master.start-failed"));
                return;
            }
            if (!voiceRunning) startVoiceService();
            if (enableCloudWhenReady) {
                enableCloudWhenReady = false;
                enableCloudRefinementIfPossible();
            }
        }
    }

    private boolean isAhaTypeMasterOn() {
        LocalVoiceFeature feature = LocalVoiceFeature.getInstance();
        LocalVoiceFeature.Phase phase = feature.phaseProperty().get();
        return feature.enabledProperty().get()
            || phase == LocalVoiceFeature.Phase.CHECKING
            || phase == LocalVoiceFeature.Phase.DOWNLOADING
            || phase == LocalVoiceFeature.Phase.INSTALLING;
    }

    /** Second line under "AhaType 开启/关闭": what the switch is doing right now. */
    private String ahaTypeMasterDetail() {
        LocalVoiceFeature feature = LocalVoiceFeature.getInstance();
        LocalVoiceFeature.Phase phase = feature.phaseProperty().get();
        if (phase == LocalVoiceFeature.Phase.FAILED) return feature.messageProperty().get();
        if (!isAhaTypeMasterOn()) return text("aha.master.off-detail");
        if (!feature.isAvailable()) {
            String message = feature.messageProperty().get();
            return message == null || message.isBlank() ? text("aha.master.preparing") : message;
        }
        String error = voiceErrorProperty.get();
        if (error != null && !error.isBlank()) return error;
        String voice = text(voiceRunning ? "aha.master.voice-running" : "aha.master.voice-ready");
        return voice + " · " + text(studioState.ahaTypeEnabledProperty().get()
            ? "aha.master.cloud-on" : "aha.master.cloud-off");
    }

    private void turnAhaTypeOn() {
        LocalVoiceFeature feature = LocalVoiceFeature.getInstance();
        if (feature.isBusy()) return;
        if (!feature.installedProperty().get() && !confirmLocalVoiceDownload()) {
            return;
        }
        voiceErrorProperty.set("");
        startVoiceWhenReady = true;
        enableCloudWhenReady = true;
        feature.enable();
        if (feature.isAvailable() && voiceInputManager != null) {
            // Already installed and loaded (e.g. turned on again in the same session).
            startVoiceWhenReady = false;
            enableCloudWhenReady = false;
            if (!voiceRunning) startVoiceService();
            enableCloudRefinementIfPossible();
        }
    }

    private void turnAhaTypeOff() {
        startVoiceWhenReady = false;
        enableCloudWhenReady = false;
        voiceErrorProperty.set("");
        if (voiceRunning) stopVoiceService();
        studioState.toggleAhaType(false);
        LocalVoiceFeature.getInstance().disable(false);
    }

    private void enableCloudRefinementIfPossible() {
        boolean changed = studioState.toggleAhaType(true);
        if (shouldOpenCloudAccountOnAhaTypeToggle(
            true, changed, studioState.shouldOpenAhaTypeAccountForEnable())) {
            showCloudAccountDialog();
        }
    }

    /** Explains local voice before the first download; nothing is downloaded without consent. */
    private boolean confirmLocalVoiceDownload() {
        Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
        if (getScene() != null) alert.initOwner(getScene().getWindow());
        alert.setTitle(text("aha.download.title"));
        alert.setHeaderText(text("aha.download.header"));
        Label body = new Label(text("aha.download.body"));
        body.setWrapText(true);
        body.setMaxWidth(440);
        alert.getDialogPane().setContent(body);
        ButtonType download = new ButtonType(text("aha.download.confirm"),
            javafx.scene.control.ButtonBar.ButtonData.OK_DONE);
        ButtonType cancel = new ButtonType(text("aha.download.cancel"),
            javafx.scene.control.ButtonBar.ButtonData.CANCEL_CLOSE);
        alert.getButtonTypes().setAll(download, cancel);
        return alert.showAndWait().filter(download::equals).isPresent();
    }

    /** Like {@link #createStatusBox} but with the switch right after the title text. */
    private VBox createSwitchStatusBox(
        ToggleButton toggle,
        javafx.beans.value.ObservableValue<Boolean> isPositive,
        javafx.beans.value.ObservableValue<String> title,
        javafx.beans.value.ObservableValue<String> detail
    ) {
        VBox box = createStatusBox(isPositive, title, detail);
        // createStatusBox: box > row(dot, text) > text(title, detail)
        HBox row = (HBox) box.getChildren().get(0);
        VBox textColumn = (VBox) row.getChildren().get(1);
        Label titleLabel = (Label) textColumn.getChildren().get(0);
        textColumn.getChildren().remove(titleLabel);
        HBox titleLine = new HBox(10, titleLabel, toggle);
        titleLine.setAlignment(Pos.CENTER_LEFT);
        textColumn.getChildren().add(0, titleLine);
        return box;
    }

    /** Small on/off switch drawn with CSS (track + knob). */
    private static ToggleButton createSwitch() {
        Region knob = new Region();
        knob.getStyleClass().add("aha-switch-knob");
        StackPane track = new StackPane(knob);
        track.getStyleClass().add("aha-switch-track");
        ToggleButton toggle = new ToggleButton();
        toggle.getStyleClass().setAll("aha-switch");
        toggle.setGraphic(track);
        toggle.setAccessibleText("AhaType");
        return toggle;
    }

    private void initContent() {
        Text titleIcon = Icons.keyboard("20");
        Label titleLabel = new Label("AhaKey Studio");
        titleLabel.getStyleClass().add("title");
        HBox titleBox = new HBox(8);
        titleBox.getChildren().addAll(titleIcon, titleLabel);

        // 连接状态块兼作 BLE 驱动入口：点击打开/置前驱动，长按 5 秒停止（原 BLE 驱动按钮）。
        InfoPill connectionPill = new InfoPill(
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
                () -> connectionAccent(controller.isEffectivelyConnected(), deviceStatus.isScanning()),
                deviceStatus.isConnectedProperty(),
                deviceStatus.isScanningProperty()
            )
        );
        connectionPill.getStyleClass().add("info-pill-clickable");
        Tooltip.install(connectionPill, new Tooltip(text("status.ble-driver-hint")));
        connectionPill.setAccessibleRole(javafx.scene.AccessibleRole.BUTTON);
        connectionPill.setAccessibleText(languageManager.getString("button.ble-driver"));
        setupBleButtonLongPress(connectionPill);

        HBox infoPills = new HBox(10);
        infoPills.getChildren().addAll(
            connectionPill,
            new InfoPill(
                Bindings.createStringBinding(() -> languageManager.getString("status.battery")),
                Bindings.createStringBinding(
                    () -> formatBattery(deviceStatus),
                    deviceStatus.isConnectedProperty(),
                    deviceStatus.batteryLevelProperty(),
                    deviceStatus.transportProperty()
                ),
                Bindings.createObjectBinding(
                    () -> batteryAccent(deviceStatus.isConnected(), deviceStatus.getTransport(),
                        deviceStatus.getBatteryLevel()),
                    deviceStatus.isConnectedProperty(),
                    deviceStatus.batteryLevelProperty(),
                    deviceStatus.transportProperty()
                )
            ),
            new InfoPill(
                Bindings.createStringBinding(() -> languageManager.getString("status.switch")),
                Bindings.createStringBinding(deviceStatus::getSwitchTitle,
                    deviceStatus.switchStateProperty(), deviceStatus.isConnectedProperty()),
                Bindings.createObjectBinding(
                    () -> !deviceStatus.isConnected() ? AccentColor.GRAY
                        : deviceStatus.isAutoApproval() ? AccentColor.MINT : AccentColor.INDIGO,
                    deviceStatus.switchStateProperty(),
                    deviceStatus.isConnectedProperty()
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

        // AhaType 总开关：开=启用本地语音（首次需确认下载）并开启云端整理；
        // 关=隐藏语音控件、关闭云端整理，模型保留。
        LocalVoiceFeature localVoice = LocalVoiceFeature.getInstance();
        ahaTypeSwitch = createSwitch();
        ahaTypeSwitch.setSelected(isAhaTypeMasterOn());
        Runnable syncSwitch = () -> ahaTypeSwitch.setSelected(isAhaTypeMasterOn());
        localVoice.enabledProperty().addListener((obs, oldValue, newValue) -> syncSwitch.run());
        localVoice.phaseProperty().addListener((obs, oldValue, newValue) -> syncSwitch.run());
        ahaTypeSwitch.setOnAction(event -> {
            if (ahaTypeSwitch.isSelected()) {
                turnAhaTypeOn();
            } else {
                turnAhaTypeOff();
            }
            syncSwitch.run();
        });

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

        javafx.beans.binding.BooleanBinding masterOn = Bindings.createBooleanBinding(
            this::isAhaTypeMasterOn, localVoice.enabledProperty(), localVoice.phaseProperty());
        VBox ahaTypeStatus = createSwitchStatusBox(
            ahaTypeSwitch,
            localVoice.availableProperty(),
            Bindings.createStringBinding(
                () -> text(masterOn.get() ? "aha.master.on" : "aha.master.off"),
                masterOn
            ),
            Bindings.createStringBinding(
                this::ahaTypeMasterDetail,
                masterOn, localVoice.availableProperty(), localVoice.phaseProperty(),
                localVoice.messageProperty(), studioState.ahaTypeEnabledProperty(),
                studioState.ahaTypeStatusProperty(), voiceRunningProperty, voiceErrorProperty
            )
        );

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

        // 编辑配置 / 保存配置按钮在右侧编辑区每个模块的标题行（InspectorPane），顶栏只显示状态。

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
        MenuItem screenAnimations = new MenuItem(localize("屏幕动画"));
        screenAnimations.setOnAction(event -> ScreenAnimationDialog.show(getScene() == null ? null : getScene().getWindow(), controller));
        SeparatorMenuItem divider1 = new SeparatorMenuItem();
        MenuItem deviceInfo = new MenuItem(languageManager.getString("menu.device-info"));
        deviceInfo.setOnAction(event -> showDeviceInfoDialog());
        MenuItem versionInfo = new MenuItem(languageManager.getString("menu.version-info"));
        versionInfo.setOnAction(event -> showVersionDialog());
        
        languageMenuItem = new MenuItem(languageManager.getLanguageToggleText());
        languageMenuItem.setOnAction(event -> toggleLanguage());
        
        MenuItem exitApp = new MenuItem(languageManager.getString("menu.exit"));
        exitApp.setOnAction(event -> exitApplication());
        
        MenuItem cloudAccount = new MenuItem(languageManager.getString("menu.cloud-account"));
        cloudAccount.setOnAction(event -> showCloudAccountDialog());

        // 云端账号只服务于 AhaType，而 AhaType 依赖本地语音：未开启本地语音时隐藏。
        cloudAccount.visibleProperty().bind(LocalVoiceFeature.getInstance().availableProperty());
        // 菜单顺序以轻量版为准：轻量版原有的菜单项在前，新增功能放在分隔线之后。
        SeparatorMenuItem divider2 = new SeparatorMenuItem();
        moreMenu.getItems().addAll(
            restoreDefaults,
            reconnect,
            clearOled,
            divider1,
            deviceInfo,
            cloudAccount,
            divider2,
            screenAnimations,
            versionInfo,
            languageMenuItem,
            exitApp
        );

        MenuBar menuBar = new MenuBar(moreMenu);
        menuBar.setUseSystemMenuBar(false);
        menuBar.getStyleClass().add("toolbar-menu");

        // 将操作按钮放入统一的 HBox
        HBox actionButtons = new HBox(4);
        actionButtons.setAlignment(Pos.CENTER_LEFT);
        actionButtons.getChildren().addAll(connectButton);

        // 布局以轻量版为准：所有控件在一行。AhaType 和语音控件位于 BLE 驱动之后，
        // 只有在设置中开启本地语音后才显示，默认形态与轻量版完全一致。
        // 导航栏只保留 AhaType 状态和总开关；语音输入随开关自动启动/停止，
        // 运行状态和错误显示在 AhaType 第二行。
        HBox ahaTypeControls = new HBox(ahaTypeStatus);
        ahaTypeControls.setAlignment(Pos.CENTER_LEFT);
        voiceResultPreview.setMaxWidth(260);

        // 状态信息与操作按钮之间的固定间距
        Region spacer = new Region();
        spacer.setMinWidth(12);
        spacer.setPrefWidth(16);
        spacer.setMaxWidth(40);

        // 右侧弹性 spacer：把编辑配置/菜单推到最右
        Region rightSpacer = new Region();
        HBox.setHgrow(rightSpacer, Priority.ALWAYS);

        // 主行 HBox：所有控件在一行，不会换行
        HBox mainRow = new HBox(10);
        mainRow.setAlignment(Pos.CENTER_LEFT);
        mainRow.setPadding(new Insets(6, 16, 6, 16));
        mainRow.setMinWidth(Region.USE_PREF_SIZE); // 保持首选宽度，不缩小
        mainRow.getChildren().addAll(titleBox, infoPills, spacer, actionButtons,
            ahaTypeControls, rightSpacer, configStatus, menuBar);

        // 包裹在水平 ScrollPane 中：宽屏时不显示滚动条，分屏窄时可水平滚动
        ScrollPane scrollWrapper = new ScrollPane(mainRow);
        scrollWrapper.setFitToWidth(true);
        scrollWrapper.setFitToHeight(true);
        scrollWrapper.setHbarPolicy(ScrollPane.ScrollBarPolicy.AS_NEEDED);
        scrollWrapper.setVbarPolicy(ScrollPane.ScrollBarPolicy.NEVER);
        scrollWrapper.setPannable(false);
        scrollWrapper.setStyle("-fx-background: transparent; -fx-background-color: transparent;");
        mainRow.setStyle("-fx-background-color: transparent;");

        getChildren().add(scrollWrapper);
        updateVoiceButtonState();
    }
    
    /** BLE bridge process/window lifecycle is owned by BleBridgeProcessOwner. */
    private volatile boolean bleButtonProcessing = false;
    private volatile long lastBleButtonClickTime = 0;
    private static final long BLE_BUTTON_CLICK_DELAY_MS = 2000;
    private static final int BLE_BRIDGE_PORT = 9000;
    private static final long BLE_BRIDGE_READY_TIMEOUT_MS = 5000;
    
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
                BleDriverLocator.Resolution resolution = BleDriverLocator.resolve();
                Path executable = resolution.selected().orElse(null);
                if (executable == null) {
                    Platform.runLater(() -> showAlert(
                        languageManager.getString("dialog.ble-driver-title"),
                        resolution.diagnosticMessage()));
                    return;
                }

                // Adopt an exact path match before starting anything. This makes the
                // second click a pure foreground operation and avoids a second 9000
                // listener. It also adopts a manually started bridge for shutdown.
                if (BleBridgeProcessOwner.activateOrAdopt(executable)) return;
                launchBleDriver(executable);
            } finally {
                bleButtonProcessing = false;
            }
        }, "ble-button-handler").start();
    }

    /**
     * 设置 BLE 按钮长按功能。长按只停止当前精确匹配且已拥有/收养的实例，
     * 不再按进程名全局 taskkill。
     */
    private void setupBleButtonLongPress(javafx.scene.Node bleButton) {
        bleButton.setOnMousePressed(event -> {
            bleButtonPressed = true;
            bleLongPressTriggered = false;
            
            bleLongPressThread = new Thread(() -> {
                try {
                    Thread.sleep(5000);
                    if (bleButtonPressed && !bleLongPressTriggered) {
                        bleLongPressTriggered = true;
                        stopManagedBleDriver();
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
    
    private void stopManagedBleDriver() {
        new Thread(() -> {
            BleDriverLocator.Resolution resolution = BleDriverLocator.resolve();
            Path executable = resolution.selected().orElse(null);
            if (executable == null
                || (!BleBridgeProcessOwner.activateOrAdopt(executable)
                    && !BleBridgeProcessOwner.findExactPid(executable).isPresent())) {
                Platform.runLater(() -> showAlert(
                    languageManager.getString("dialog.ble-driver-title"),
                    executable == null
                        ? resolution.diagnosticMessage()
                        : languageManager.getString("dialog.ble-no-process")));
                return;
            }
            boolean stopped = BleBridgeProcessOwner.stopOwned();
            Platform.runLater(() -> {
                String message = stopped
                    ? languageManager.getString("dialog.ble-kill-success")
                    : languageManager.getString("dialog.ble-kill-fail").replace("%d", "1");
                showAlert(languageManager.getString("dialog.ble-driver-title"), message);
            });
        }, "ble-driver-stop").start();
    }

    private void launchBleDriver(Path executable) {
        try {
            ProcessBuilder builder = new ProcessBuilder(executable.toString(), "--show",
                "--language=" + languageManager.getCurrentLanguage());
            builder.directory(executable.getParent().toFile());
            builder.redirectOutput(ProcessBuilder.Redirect.INHERIT);
            builder.redirectError(ProcessBuilder.Redirect.INHERIT);
            Process process = builder.start();
            BleBridgeProcessOwner.register(process, executable);

            new Thread(() -> {
                try {
                    if (!BleBridgeProcessOwner.waitForTcpPort(
                        "127.0.0.1", BLE_BRIDGE_PORT, BLE_BRIDGE_READY_TIMEOUT_MS)) {
                        BleBridgeProcessOwner.stopOwned();
                        Platform.runLater(() -> showAlert(
                            languageManager.getString("dialog.ble-driver-title"),
                            String.format(languageManager.getString("dialog.ble-start-fail"),
                                executable + localize(" (TCP 9000 未在 5 秒内就绪)"))));
                        return;
                    }
                    // Bounded foreground retry; the bridge owns BLE discovery.
                    for (int i = 0; i < 30 && process.isAlive(); i++) {
                        if (BleBridgeProcessOwner.activateOwnedWindow()) return;
                        Thread.sleep(100);
                    }
                    if (!process.isAlive()) {
                        Platform.runLater(() -> showAlert(
                            languageManager.getString("dialog.ble-driver-title"),
                            String.format(languageManager.getString("dialog.ble-start-fail"), executable)));
                    }
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                }
            }, "ble-driver-foreground").start();
        } catch (Exception exception) {
            Platform.runLater(() -> showAlert(
                languageManager.getString("dialog.ble-driver-title"),
                String.format(languageManager.getString("dialog.ble-start-fail"),
                    executable + ": " + exception.getMessage())));
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
        voiceRunningProperty.set(true);
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
                if ("stopped".equalsIgnoreCase(code)) {
                    studioState.refreshAhaTypeState();
                }
                
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
        // startVoiceInput() deliberately returns void and can fail closed
        // when the model was not initialized.  Do not advertise a local
        // executor until the manager confirms it is actually activated;
        // otherwise an AhaKey long press would be swallowed as a silent no-op.
        boolean activated = voiceInputManager.isActivated();
        controller.getVoiceRelay().setAhaKeyVoiceAvailable(activated);
        if (!activated) {
            setVoiceStatus("error", localize("本地语音不可用；长按不会执行其他语音动作。"));
        }
    }
    
    /**
     * 停止语音服务
     */
    private void stopVoiceService() {
        voiceRunning = false;
        voiceRunningProperty.set(false);
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
        controller.getVoiceRelay().setAhaKeyVoiceAvailable(false);
        
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
        boolean known = switch (status) {
            case "stopped", "idle", "starting", "stopping", "processing", "recognizing",
                 "recording", "ready" -> true;
            default -> false;
        };
        voiceErrorProperty.set(known ? "" : (text == null ? "" : text));
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
        if (!voiceRunning) {
            // The service may have just finished loading after local voice was
            // turned on; replace the earlier "not loaded" error.
            setVoiceStatus("stopped", languageManager.getString("voice.status.stopped"));
        }
        
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
        detailLabel.visibleProperty().bind(detailLabel.textProperty().isNotEmpty());
        detailLabel.managedProperty().bind(detailLabel.visibleProperty());

        text.getChildren().addAll(titleLabel, detailLabel);
        row.getChildren().addAll(dot, text);
        box.getChildren().add(row);
        return box;
    }

    private void showDeviceInfoDialog() {
        Stage dialog = new Stage();
        dialog.initOwner(getScene().getWindow());
        dialog.setTitle(languageManager.getString("dialog.hook-title"));
        dialog.setWidth(550);
        dialog.setHeight(760);

        ScrollPane scrollPane = new ScrollPane();
        scrollPane.setFitToWidth(true);

        VBox content = new VBox(12);
        content.setPadding(new Insets(12));

        // 设备信息摘要
        VBox deviceCard = new VBox(8);
        deviceCard.getStyleClass().add("dialog-card");
        deviceCard.setPadding(new Insets(12));

        Label deviceTitle = new Label(languageManager.getString("dialog.device-info"));
        deviceTitle.getStyleClass().add("dialog-card-title");

        HBox deviceRow1 = new HBox(16);
        Label connStatus = new Label();
        connStatus.getStyleClass().add("dialog-text");
        connStatus.textProperty().bind(Bindings.createStringBinding(() ->
            languageManager.getString("dialog.connection") + ": " +
                (this.deviceStatus.isConnected()
                    ? languageManager.getString("status.connected") + " (" + this.deviceStatus.getTransport() + ")"
                    : languageManager.getString("status.disconnected")),
            this.deviceStatus.isConnectedProperty(),
            this.deviceStatus.transportProperty()
        ));
        Label batteryStatus = new Label();
        batteryStatus.getStyleClass().add("dialog-text");
        batteryStatus.textProperty().bind(Bindings.createStringBinding(() ->
            languageManager.getString("status.battery") + ": " + formatBattery(this.deviceStatus),
            this.deviceStatus.isConnectedProperty(),
            this.deviceStatus.batteryLevelProperty(),
            this.deviceStatus.transportProperty()
        ));
        deviceRow1.getChildren().addAll(connStatus, batteryStatus);

        HBox deviceRow2 = new HBox(16);
        Label deviceName = new Label(languageManager.getString("dialog.device-name") + ": " + this.deviceStatus.getDisplayDeviceName());
        deviceName.getStyleClass().add("dialog-text");
        Label switchState = new Label();
        switchState.getStyleClass().add("dialog-text");
        switchState.textProperty().bind(Bindings.createStringBinding(() ->
            languageManager.getString("status.switch") + ": " + this.deviceStatus.getSwitchTitle(),
            this.deviceStatus.switchStateProperty(),
            this.deviceStatus.isConnectedProperty()
        ));
        deviceRow2.getChildren().addAll(deviceName, switchState);

        deviceCard.getChildren().addAll(deviceTitle, deviceRow1, deviceRow2);
        VBox standbyCard = new StandbySettingsPane(
            controller.getBleManager(),
            deviceStatus
        ).create(dialog);
        VBox localVoiceCard = new LocalVoicePane(LocalVoiceFeature.getInstance()).create(dialog);
        VBox maintenanceCards = new DeviceMaintenancePane(controller).create(dialog);
        VBox pairingGuideCard = BluetoothPairingGuide.createCard();
        VBox supportCard = new SupportPane().create();

        // 日志区域（提前创建以记录检测过程）
        logArea = new TextArea();
        logArea.getStyleClass().add("dialog-log-area");
        logArea.setEditable(false);
        logArea.setPrefHeight(150);
        logArea.setWrapText(true);
        logArea.setText(text("hooks.log.started"));
        
        String homeDir = System.getProperty("user.home");
        addLog(text("hooks.log.home") + homeDir);
        addLog(text("hooks.log.os") + System.getProperty("os.name"));
        addLog(text("hooks.log.java") + System.getProperty("java.version"));
        addLog("");

        // Hook 安装卡片：配置、分发服务和最近活动是相互独立的状态。
        HookCardControls claudeCard = createHookCard("Claude");
        HookCardControls cursorCard = createHookCard("Cursor");
        HookCardControls codexCard = createHookCard("Codex");
        HookCardControls kimiCard = createHookCard("Kimi");

        // 日志卡片
        VBox logCard = new VBox(8);
        logCard.getStyleClass().add("dialog-card");
        logCard.setPadding(new Insets(12));

        Label logTitle = new Label(languageManager.getString("dialog.log"));
        logTitle.getStyleClass().add("dialog-log-title");
        logCard.getChildren().addAll(logTitle, logArea);

        // 操作按钮
        HBox actionButtons = new HBox(10);
        Button connectBtn = new Button(languageManager.getString("button.connect"));
        connectBtn.getStyleClass().add("button-connect");
        connectBtn.disableProperty().bind(this.deviceStatus.isConnectedProperty());
        connectBtn.setOnAction(event -> controller.userConnect());

        Button disconnectBtn = new Button(languageManager.getString("button.disconnect"));
        disconnectBtn.getStyleClass().add("button-disconnect");
        disconnectBtn.disableProperty().bind(this.deviceStatus.isConnectedProperty().not());
        disconnectBtn.setOnAction(event -> controller.userDisconnect());

        Button clearLogBtn = new Button(languageManager.getString("dialog.clear-log"));
        clearLogBtn.setOnAction(event -> logArea.setText(text("hooks.log.cleared")));

        Button closeBtn = new Button(languageManager.getString("dialog.close"));
        closeBtn.setOnAction(event -> dialog.close());

        actionButtons.getChildren().addAll(connectBtn, disconnectBtn, clearLogBtn, closeBtn);
        actionButtons.setAlignment(Pos.CENTER_RIGHT);

        // 顺序以轻量版为准：设备信息 → Hook → 日志 → 操作按钮；新增的设置放在其后。
        Label moreSettingsTitle = new Label(localize("更多设置"));
        moreSettingsTitle.getStyleClass().add("dialog-card-title");
        moreSettingsTitle.setPadding(new Insets(8, 0, 0, 4));
        content.getChildren().addAll(
            deviceCard,
            claudeCard.root(),
            cursorCard.root(),
            codexCard.root(),
            kimiCard.root(),
            logCard,
            actionButtons,
            moreSettingsTitle,
            localVoiceCard,
            standbyCard,
            maintenanceCards,
            pairingGuideCard,
            supportCard
        );
        scrollPane.setContent(content);

        Scene scene = new Scene(scrollPane);
        scene.getStylesheets().add(getClass().getResource("/style.css").toExternalForm());
        dialog.setScene(scene);
        
        // 先显示对话框，然后在后台线程中进行 Hook 检测
        dialog.show();
        
        // 在后台线程中检测 Hook 状态
        new Thread(() -> {
            String[] hookNames = {"Claude", "Cursor", "Codex", "Kimi"};
            HookCardControls[] hookCards = {claudeCard, cursorCard, codexCard, kimiCard};
            
            for (int i = 0; i < hookNames.length; i++) {
                String name = hookNames[i];
                Path path = hookInstaller.getHookConfigPath(name);
                File file = path.toFile();
                
                HookInstaller.ConfigurationInspection inspection =
                    hookInstaller.inspectInstallation(name);
                
                String detectionPrefix = languageManager.getString("hook.detection");
                addLog(detectionPrefix + " === " + name + " Hook ===");
                addLog(detectionPrefix + " " + languageManager.getString("hook.check-path") + ": " + path);
                addLog(detectionPrefix + " " + languageManager.getString("hook.file-exists") + ": " + file.exists());
                
                if (file.exists()) {
                    try {
                        String fileContent = new String(java.nio.file.Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
                        addLog(detectionPrefix + " " + languageManager.getString("hook.file-size") + ": " + fileContent.length() + " chars");
                        
                        if ("Claude".equals(name)) {
                            addLog(detectionPrefix + " " + languageManager.getString("hook.contains") + " hooks: " + fileContent.contains("\"hooks\""));
                            addLog(detectionPrefix + " " + languageManager.getString("hook.contains") + " SessionStart: " + fileContent.contains("SessionStart"));
                        } else if ("Cursor".equals(name)) {
                            addLog(detectionPrefix + " " + languageManager.getString("hook.contains") + " hooks: " + fileContent.contains("\"hooks\""));
                            addLog(detectionPrefix + " " + languageManager.getString("hook.contains") + " sessionStart: " + fileContent.contains("sessionStart"));
                        } else if ("Codex".equals(name)) {
                            String home = System.getProperty("user.home");
                            Path sidecar = Paths.get(home, ".codex", HookInstaller.CODEX_SIDECAR_NAME);
                            addLog(detectionPrefix + " sidecar " + languageManager.getString("hook.file-exists") + ": " + sidecar.toFile().exists());
                            addLog(detectionPrefix + " hooks.json content length: " + fileContent.length());
                        } else if ("Kimi".equals(name)) {
                            addLog(detectionPrefix + " " + languageManager.getString("hook.contains") + " BEGIN marker: " + fileContent.contains(HookInstaller.KIMI_HOOK_BLOCK_START));
                            addLog(detectionPrefix + " " + languageManager.getString("hook.contains") + " END marker: " + fileContent.contains(HookInstaller.KIMI_HOOK_BLOCK_END));
                        }
                    } catch (Exception e) {
                        addLog(detectionPrefix + " " + languageManager.getString("hook.read-failed") + ": " + e.getMessage());
                    }
                }
                
                addLog(detectionPrefix + " " + languageManager.getString("hook.final-status") + ": " + inspection.status());
                if ("Codex".equals(name)) {
                    addLog("CODEX_HOOK_CONFIGURED="
                        + (inspection.configured() ? "YES" : "NO"));
                }
                addLog("");
                
                // 更新卡片状态
                int finalI = i;
                HookInstaller.ConfigurationInspection finalInspection = inspection;
                Platform.runLater(() -> updateHookCardStatus(
                    hookCards[finalI], name, finalInspection));
            }
        }, "hook-detection").start();

        Timeline hookRuntimeRefresh = new Timeline(new KeyFrame(
            Duration.seconds(1), event -> {
                refreshHookRuntime(claudeCard, "Claude");
                refreshHookRuntime(cursorCard, "Cursor");
                refreshHookRuntime(codexCard, "Codex");
                refreshHookRuntime(kimiCard, "Kimi");
            }));
        hookRuntimeRefresh.setCycleCount(Timeline.INDEFINITE);
        hookRuntimeRefresh.play();
        dialog.setOnHidden(event -> hookRuntimeRefresh.stop());
    }

    private void showCloudAccountDialog() {
        Stage owner = getScene() != null && getScene().getWindow() instanceof Stage stage ? stage : null;
        new CloudAccountDialog(owner, com.example.ahakey.service.CloudAccountManager.getInstance(),
            studioState::refreshAhaTypeState).show();
    }

    static boolean shouldOpenCloudAccountOnAhaTypeToggle(
            boolean requestedEnable, boolean changed, boolean loginRequired) {
        return requestedEnable && !changed && loginRequired;
    }

    private record HookCardControls(
        VBox root, Label installation, Label configured, Label enabledTrusted,
        Label server, Label recent,
        Button install, Button uninstall
    ) {}

    private void updateHookCardStatus(
        HookCardControls card, String hookName,
        HookInstaller.ConfigurationInspection inspection
    ) {
        HookInstaller.ConfigurationStatus status = inspection.status();
        card.installation().setText(languageManager.getString(status.messageKey()));
        card.installation().getStyleClass().removeAll(
            "dialog-status-installed", "dialog-status-uninstalled");
        card.installation().getStyleClass().add(
            status == HookInstaller.ConfigurationStatus.INSTALLED
                ? "dialog-status-installed" : "dialog-status-uninstalled");
        if (status == HookInstaller.ConfigurationStatus.CHECKING) {
            card.configured().setText(languageManager.getString("hook.checking"));
            card.enabledTrusted().setText(languageManager.getString("hook.checking"));
        } else {
            card.configured().setText(yesNo(inspection.configured()));
            card.enabledTrusted().setText(yesNo(inspection.enabledOrTrusted()));
        }
        card.install().setDisable(status == HookInstaller.ConfigurationStatus.INSTALLED);
        card.uninstall().setDisable(status == HookInstaller.ConfigurationStatus.NOT_INSTALLED
            || status == HookInstaller.ConfigurationStatus.CHECKING);
        refreshHookRuntime(card, hookName);
    }

    private HookCardControls createHookCard(String hookName) {
        VBox card = new VBox(8);
        card.getStyleClass().add("dialog-card");
        card.setPadding(new Insets(12));

        HBox titleRow = new HBox();
        Label title = new Label(hookName + " Hook");
        title.getStyleClass().add("dialog-card-title");
        Region spacer1 = new Region();
        HBox.setHgrow(spacer1, Priority.ALWAYS);
        titleRow.getChildren().addAll(title, spacer1);

        Label statusValue = new Label(languageManager.getString("hook.checking"));
        Label configuredValue = new Label(languageManager.getString("hook.checking"));
        Label enabledTrustedValue = new Label(languageManager.getString("hook.checking"));
        Label serverValue = new Label(languageManager.getString("hook.server-offline"));
        Label recentValue = new Label(languageManager.getString("hook.recent-none"));

        Button installBtn = new Button(languageManager.getString("button.install"));
        installBtn.getStyleClass().add("button-install");

        Button uninstallBtn = new Button(languageManager.getString("button.uninstall"));
        uninstallBtn.getStyleClass().add("button-uninstall");
        HBox actions = new HBox(8, installBtn, uninstallBtn);
        card.getChildren().addAll(titleRow,
            statusRow("hook.installation-status", statusValue),
            statusRow("hook.configured", configuredValue),
            statusRow("hook.enabled-trusted", enabledTrustedValue),
            statusRow("hook.server-status", serverValue),
            statusRow("hook.recent-activity", recentValue), actions);
        HookCardControls controls = new HookCardControls(card, statusValue,
            configuredValue, enabledTrustedValue, serverValue, recentValue,
            installBtn, uninstallBtn);
        installBtn.setOnAction(event -> {
            installHook(hookName);
            updateHookCardStatus(controls, hookName,
                hookInstaller.inspectInstallation(hookName));
        });
        uninstallBtn.setOnAction(event -> {
            uninstallHook(hookName);
            updateHookCardStatus(controls, hookName,
                hookInstaller.inspectInstallation(hookName));
        });
        updateHookCardStatus(controls, hookName, new HookInstaller.ConfigurationInspection(
            HookInstaller.ConfigurationStatus.CHECKING, false, false));
        return controls;
    }

    private HBox statusRow(String labelKey, Label value) {
        Label label = new Label(languageManager.getString(labelKey) + ":");
        label.getStyleClass().add("dialog-status-label");
        return new HBox(8, label, value);
    }

    private String yesNo(boolean value) {
        return languageManager.getString(value ? "hook.yes" : "hook.no");
    }

    private void refreshHookRuntime(HookCardControls card, String hookName) {
        boolean active = controller.isHookDispatchServerRunning();
        card.server().setText(languageManager.getString(
            active ? "hook.server-online" : "hook.server-offline"));
        long lastRequest = controller.getLastHookRequestTimeMillis(hookName);
        card.recent().setText(formatRecentHookActivity(lastRequest));
    }

    private String formatRecentHookActivity(long timestampMillis) {
        if (timestampMillis <= 0) return languageManager.getString("hook.recent-none");
        long seconds = Math.max(0L,
            (System.currentTimeMillis() - timestampMillis) / 1_000L);
        if (seconds < 10) return languageManager.getString("hook.recent-just-now");
        return seconds + "s";
    }

    // ==================== Hook 管理（委托给 HookInstaller） ====================

    private boolean isHookInstalled(String hookName) {
        return hookInstaller.isInstalled(hookName);
    }

    private boolean installHook(String hookName) {
        boolean installed = hookInstaller.install(hookName);
        Alert result = new Alert(installed
            ? Alert.AlertType.INFORMATION : Alert.AlertType.ERROR);
        if (getScene() != null && getScene().getWindow() != null) {
            result.initOwner(getScene().getWindow());
        }
        result.setTitle(installed ? localize("Hook 安装完成") : localize("Hook 安装失败"));
        result.setHeaderText(null);
        result.setContentText(installed
            ? hookName + localize(" Hook 已安装。请在 ") + hookName
                + localize(" 中同意 Hook/钩子权限，然后完全退出并重新启动该 Agent。")
            : hookName + localize(" Hook 未能完成安装，请查看本窗口底部日志后重试。"));
        result.showAndWait();
        return installed;
    }

    private boolean uninstallHook(String hookName) {
        addLog(localize("[卸载] 开始卸载 ") + hookName + " Hook...");
        boolean removed = hookInstaller.uninstall(hookName);
        if (!removed) {
            Alert result = new Alert(Alert.AlertType.ERROR);
            if (getScene() != null && getScene().getWindow() != null) {
                result.initOwner(getScene().getWindow());
            }
            result.setTitle(localize("Hook 卸载失败"));
            result.setHeaderText(null);
            result.setContentText(
                hookName + localize(" Hook 卸载后仍可检测到，请查看本窗口底部日志。"));
            result.showAndWait();
        }
        return removed;
    }

    private void addLog(String message) {
        if (logArea != null) {
            String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss"));
            logArea.appendText("[" + timestamp + "] " + message + "\n");
            logArea.setScrollTop(Double.MAX_VALUE);
        }
    }
    
    private void showVersionDialog() {
        com.example.ahakey.update.AppUpdateCoordinator.showAboutAndCheck(
            (Stage) getScene().getWindow()
        );
    }
    
    private String getVersion() {
        String version = System.getProperty("app.version");
        if (version == null || version.isEmpty()) {
            version = "unknown";
        }
        return version;
    }
    
    private void toggleLanguage() {
        var choices = java.util.List.of("Русский", "English", "中文", "한국어");
        String selected = switch (languageManager.getCurrentLanguage()) {
            case "ru" -> "Русский";
            case "zh" -> "中文";
            case "ko" -> "한국어";
            default -> "English";
        };
        var chooser = new javafx.scene.control.ChoiceDialog<String>(selected, choices);
        chooser.initOwner(getScene().getWindow());
        chooser.setTitle(languageManager.getString("language.select"));
        chooser.setHeaderText(languageManager.getString("language.restart"));
        chooser.setContentText("Language / Язык / 语言 / 언어:");
        var choice = chooser.showAndWait();
        if (choice.isEmpty()) return;
        String newLang = switch (choice.get()) {
            case "Русский" -> "ru";
            case "中文" -> "zh";
            case "한국어" -> "ko";
            default -> "en";
        };
        if (newLang.equals(languageManager.getCurrentLanguage())) return;
        languageManager.switchLanguage(newLang);
        
        Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
        alert.setTitle(languageManager.getString("language-change-title"));
        alert.setHeaderText(null);
        alert.setContentText(languageManager.getString(switch (newLang) {
            case "ru" -> "language-change-russian";
            case "zh" -> "language-change-chinese";
            case "ko" -> "language-change-korean";
            default -> "language-change-english";
        }));
        
        ButtonType exitBtn = new ButtonType(languageManager.getString("dialog.exit-now"));
        ButtonType laterBtn = new ButtonType(languageManager.getString("dialog.exit-later"));
        
        alert.getButtonTypes().setAll(exitBtn, laterBtn);
        
        Optional<ButtonType> result = alert.showAndWait();
        if (result.isPresent() && result.get() == exitBtn) {
            exitApplication();
        }
    }
    
    private void exitApplication() {
        com.example.ahakey.app.ApplicationLifecycle.requestExit();
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

    /** Dot colour of the connection block: green connected, orange scanning, red disconnected. */
    static AccentColor connectionAccent(boolean connected, boolean scanning) {
        if (connected) return AccentColor.GREEN;
        return scanning ? AccentColor.ORANGE : AccentColor.RED;
    }

    /** Dot colour of the battery block: grey unknown, green USB or above 50 %, orange to 20 %, red below. */
    static AccentColor batteryAccent(boolean connected, String transport, int level) {
        if (!connected) return AccentColor.GRAY;
        if ("USB".equals(transport)) return AccentColor.GREEN;
        if (level < 0 || level > 100) return AccentColor.GRAY;
        if (level > 50) return AccentColor.GREEN;
        return level > 20 ? AccentColor.ORANGE : AccentColor.RED;
    }

    private static String formatBattery(DeviceStatus status) {
        if (!status.isConnected()) {
            return "—";
        }
        if ("USB".equals(status.getTransport())) {
            return localize("USB 供电");
        }
        int level = status.getBatteryLevel();
        return level >= 0 && level <= 100 ? level + "%" : localize("读取中");
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
