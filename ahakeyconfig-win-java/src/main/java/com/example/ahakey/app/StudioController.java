package com.example.ahakey.app;

import com.example.ahakey.config.ModelConfig;
import com.example.ahakey.model.*;
import com.example.ahakey.platform.VoiceRelayPlatform;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.AgentManager;
import com.example.ahakey.service.ApprovalService;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.service.DeviceSyncService;
import com.example.ahakey.service.HookDispatchServer;
import com.example.ahakey.service.OledUploadService;
import com.example.ahakey.service.GifUploadRules;
import com.example.ahakey.service.GifSelectionHistory;
import com.example.ahakey.service.LightOperationCoordinator;
import com.example.ahakey.service.TaskActivityService;
import com.example.ahakey.util.OLEDFrameEncoder;
import com.example.ahakey.util.StudioStore;
import com.example.ahakey.util.LanguageManager;
import com.example.ahakey.update.SemanticVersion;
import javafx.application.Platform;
import javafx.stage.FileChooser;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.prefs.Preferences;

/**
 * 应用总线：连接 Swift 中 `AhaKeyStudioView` + `BLE` + `AgentManager` 的编排逻辑。
 */
public class StudioController {
    private static final Logger logger = LoggerFactory.getLogger(StudioController.class);
    private final LanguageManager languageManager = LanguageManager.getInstance();
    private final DeviceStatus deviceStatus = new DeviceStatus();
    private final StudioState studioState = new StudioState();
    private final AgentManager agentManager = new AgentManager();
    private final VoiceRelayPlatform voiceRelay = new VoiceRelayPlatform();
    private final BleManager bleManager;
    private final boolean simulateBle;
    private final HookDispatchServer hookDispatchServer;
    private final TaskActivityService taskActivityService;
    private final ApprovalService approvalService;
    private final Preferences preferences = Preferences.userNodeForPackage(StudioController.class);
    private final com.example.ahakey.service.KimiAhaKeyBridge kimiAhaKeyBridge;
    private volatile SemanticVersion lastKnownFirmwareVersion;
    private volatile SemanticVersion pendingFirmwareVersion;
    private final WorkModeSynchronizer workModeSynchronizer =
        new WorkModeSynchronizer(deviceStatus, studioState);
    private final StatusRefreshScheduler statusRefreshScheduler =
        new StatusRefreshScheduler();
    private volatile boolean manuallyDisconnected;
    private volatile String lastConnectionError;
    /** Only one manual approval alert may be active; concurrent requests fail closed. */
    private final java.util.concurrent.locks.ReentrantLock approvalDialogLock =
        new java.util.concurrent.locks.ReentrantLock(true);

    private int lastSyncedRevision = -1;
    
    // 定时轮询设备状态（由于BLE通知不可靠，需要主动查询）
    private ScheduledExecutorService statusPoller;
    private ScheduledFuture<?> pollFuture;

    public StudioController() {
        String sim = System.getenv("AHAKEY_STUDIO_SIMULATE_BLE");
        simulateBle = sim != null && (sim.equals("1") || sim.equalsIgnoreCase("true"));
        studioState.loadFromPersisted(StudioStore.loadOrDefault());
        lastSyncedRevision = studioState.getRevision();

        bleManager = BleManager.fromEnvironment(new BleManager.BleCallback() {
            @Override
            public void onConnected() {
                logger.info("收到设备连接通知");
                Platform.runLater(() -> {
                    DeviceStatus status = bleManager.getCachedStatus();
                    applyBleStatus(status);
                });
                // 有线（USB HID）连接时启动 Kimi AhaKey 桥接（无线模式下 9000 端口已由 BLE-TCP bridge 占用）
                if (bleManager.isUsbConnected()
                    && !bleManager.isBleBridgeSessionActive()) {
                    kimiAhaKeyBridge.start();
                } else {
                    kimiAhaKeyBridge.stop();
                }
                // 启动定时轮询（BLE通知不可靠，需要主动查询）
                startStatusPolling();
            }

            @Override
            public void onDisconnected() {
                workModeSynchronizer.invalidateSession();
                Platform.runLater(() -> deviceStatus.setConnected(false));
                kimiAhaKeyBridge.stop();
                // 停止定时轮询
                stopStatusPolling();
            }

            @Override
            public void onStatusReceived(DeviceStatus status) {
                Platform.runLater(() -> {
                    applyBleStatus(status);
                    // 不再强制同步设备工作模式到UI选择，让用户自由选择要编辑的模式
                });
            }

            @Override
            public void onError(String message) {
                if (isTransientConnectionError(message)) {
                    lastConnectionError = message;
                }
                Platform.runLater(() -> studioState.syncStatusProperty().set(message));
            }
        });

        voiceRelay.configure(() -> studioState, deviceStatus::getWorkMode);
        refreshVoiceRoutes();
        voiceRelay.start();

        Runnable onDraftChange = () -> {
            persistDraft();
            refreshVoiceRoutes();
        };
        studioState.revisionProperty().addListener((o, a, b) -> onDraftChange.run());
        studioState.selectedModeProperty().addListener((o, a, b) -> onDraftChange.run());

        // 启动 Hook 分发服务器（接收 Codex/Claude/Cursor/Kimi hook 事件 → BLE 状态码）
        taskActivityService = new TaskActivityService(bleManager);
        approvalService = new ApprovalService(bleManager);
        hookDispatchServer = new HookDispatchServer(
            bleManager, taskActivityService, approvalService, HookDispatchServer.DEFAULT_PORT);
        taskActivityService.setDisplayModeListener(result -> Platform.runLater(() -> {
            if (result.status() != TaskActivityService.DisplayModeStatus.OFFLINE_PENDING) {
                preferences.putBoolean("task.display.multi", result.confirmedMultiMode());
            }
            studioState.syncStatusProperty().set(result.message());
        }));
        taskActivityService.setMultiMode(preferences.getBoolean("task.display.multi", false));
        hookDispatchServer.setApprovalCallback(this::showApprovalDialog);
        hookDispatchServer.start();

        bleManager.setModeChangeListener(mode ->
            Platform.runLater(() -> applyReportedWorkMode(mode)));
        bleManager.setTransportSessionInvalidationListener(
            workModeSynchronizer::invalidateSession);

        // KimiAhaKeyBridge 在设备连接后按连接类型决定是否启动（见 onConnected）
        kimiAhaKeyBridge = new com.example.ahakey.service.KimiAhaKeyBridge(approvalService);
    }

    public BleManager getBleManager() {
        return bleManager;
    }

    public VoiceRelayPlatform getVoiceRelay() {
        return voiceRelay;
    }

    public DeviceStatus getDeviceStatus() {
        return deviceStatus;
    }

    public StudioState getStudioState() {
        return studioState;
    }

    public SemanticVersion getLastKnownFirmwareVersion() {
        return lastKnownFirmwareVersion;
    }

    public void setLastKnownFirmwareVersion(SemanticVersion version) {
        lastKnownFirmwareVersion = version;
    }

    public SemanticVersion getPendingFirmwareVersion() {
        return pendingFirmwareVersion;
    }

    public void setPendingFirmwareVersion(SemanticVersion version) {
        pendingFirmwareVersion = version;
    }

    public AgentManager getAgentManager() {
        return agentManager;
    }

    public int getHookDispatchPort() {
        return hookDispatchServer.getActualPort();
    }

    public TaskActivityService getTaskActivityService() { return taskActivityService; }

    public boolean isMultiTaskDisplay() { return taskActivityService.isMultiMode(); }

    public void setMultiTaskDisplay(boolean enabled) {
        taskActivityService.setMultiMode(enabled);
        studioState.syncStatusProperty().set(deviceStatus.isConnected()
            ? "正在等待设备确认任务显示模式…"
            : "任务显示模式仅在本地修改，待设备重连后同步。");
    }

    public boolean isEffectivelyConnected() {
        return deviceStatus.isConnected();
    }

    public boolean hasUnsyncedChanges() {
        return studioState.getRevision() != lastSyncedRevision || studioState.getDirtyCount() > 0;
    }

    public void shutdown() {
        voiceRelay.releaseAllSimulatedKeys();
        voiceRelay.stop();
        stopStatusPolling();
        statusRefreshScheduler.shutdown();
        hookDispatchServer.stop();
        kimiAhaKeyBridge.stop();
        if (!simulateBle) {
            bleManager.shutdown();
        }
    }
    
    private void startStatusPolling() {
        stopStatusPolling(); // 先停止之前的轮询
        statusPoller = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "status-poller");
            t.setDaemon(true);
            return t;
        });
        // 从配置文件读取轮询周期，默认3秒
        int pollPeriod = Math.max(1, Math.min(2,
            ModelConfig.getInstance().getStatusPollPeriodSeconds()));
        logger.info("设备状态轮询周期: {}秒", pollPeriod);
        pollFuture = statusPoller.scheduleAtFixedRate(() -> {
            if (!simulateBle && !bleManager.isScanning()
                && bleManager.isTransportSessionActive()) {
                try {
                    bleManager.queryStatus();
                } catch (Exception e) {
                    logger.warn("轮询设备状态失败: {}", e.getMessage());
                }
            }
        }, 2, pollPeriod, TimeUnit.SECONDS); // 延迟2秒后开始，按配置周期执行
    }
    
    private void stopStatusPolling() {
        if (pollFuture != null) {
            pollFuture.cancel(true);
            pollFuture = null;
        }
        if (statusPoller != null) {
            statusPoller.shutdown();
            statusPoller = null;
        }
    }

    private void clearResolvedConnectionError() {
        String connectionError = lastConnectionError;
        if (connectionError == null) {
            return;
        }
        if (connectionError.equals(studioState.syncStatusProperty().get())) {
            studioState.syncStatusProperty().set("设备已通过 BLE 连接。");
        }
        lastConnectionError = null;
    }

    private static boolean isTransientConnectionError(String message) {
        if (message == null) {
            return false;
        }
        return message.contains("BLE bridge") || message.contains("BLE 桥");
    }

    public void userConnect() {
        manuallyDisconnected = false;
        logger.info("用户请求连接 - simulateBle: {}", simulateBle);
        if (simulateBle) {
            logger.info("使用模拟模式，直接设置为已连接");
            deviceStatus.setConnected(true);
            deviceStatus.setScanning(false);
            deviceStatus.setBatteryLevel(84);
            deviceStatus.setDeviceName("AhaKey Keyboard (模拟)");
            return;
        }
        logger.info("使用真实BLE连接");
        deviceStatus.setScanning(true);
        bleManager.connect();
        // Poll the transport while it is connecting. A physical keyboard is
        // shown as connected only after it returns an actual protocol frame.
        startStatusPolling();
    }

    public void userDisconnect() {
        manuallyDisconnected = true;
        voiceRelay.releaseAllSimulatedKeys();
        bleManager.disconnect();
    }

    public boolean isManuallyDisconnected() {
        return manuallyDisconnected;
    }

    public void selectKeyboardMode(ModeSlot mode) {
        WorkModeSynchronizer.SelectionResult result = workModeSynchronizer.selectUserMode(
            mode,
            !simulateBle && deviceStatus.isConnected(),
            () -> bleManager.setWorkMode(mode.getIndex())
        );
        switch (result) {
            case OFFLINE_UI_ONLY -> studioState.syncStatusProperty().set(
                "已选择 " + mode.getTitle() + "（仅本地编辑，尚未同步到设备）。");
            case SENT_PENDING -> studioState.syncStatusProperty().set(
                "模式命令已发送，等待设备确认。");
            case SEND_FAILED -> studioState.syncStatusProperty().set(
                "模式发送失败，已回滚到设备上次确认的模式。");
        }
    }

    public void enterEditingConfiguration() {
        agentManager.setBluetoothOwner(AgentManager.BluetoothOwner.AHAKEY_STUDIO);
        studioState.syncStatusProperty().set("已进入编辑配置模式。");
        refreshVoiceRoutes();
        if (!deviceStatus.isConnected() && !simulateBle && !manuallyDisconnected) {
            userConnect();
        } else if (!deviceStatus.isConnected() && manuallyDisconnected) {
            studioState.syncStatusProperty().set(
                "已手动断开设备；编辑内容仅保存在本地，点击“连接设备”后才能写入键盘。");
        }
    }

    public void finishEditingConfiguration() {
        if (!hasUnsyncedChanges()) {
            returnToKeyboardControl();
            return;
        }
        if (deviceStatus.isConnected() || simulateBle) {
            syncAllModes(true);
        } else {
            studioState.syncStatusProperty().set(
                "设备已断开；配置仍保存在本地，请连接设备后再写入键盘。");
            if (!manuallyDisconnected) {
                userConnect();
            }
        }
    }

    public void returnToKeyboardControl() {
        agentManager.setBluetoothOwner(AgentManager.BluetoothOwner.KEYBOARD_DEVICE);
        studioState.syncStatusProperty().set("已交还控制权给键盘设备，连接保持。");
        // 保持 BLE 连接不断开，避免用户需要重新连接
    }

    public void syncAllModes(boolean returnToAgentWhenDone) {
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("设备未连接，当前只保存本地草稿。");
            return;
        }
        if (simulateBle) {
            int syncRevision = studioState.getRevision();
            StudioState.DirtySnapshot dirtySnapshot =
                studioState.captureDirtySnapshot();
            studioState.clearDirtyAfterSync(dirtySnapshot);
            lastSyncedRevision = syncRevision;
            studioState.syncStatusProperty().set(studioState.getRevision() == syncRevision
                ? "模拟模式：已标记为保存。"
                : "模拟模式：已保存先前快照，后续修改仍待保存。");
            if (returnToAgentWhenDone) {
                returnToKeyboardControl();
            }
            return;
        }

        String transport;
        try {
            transport = bleManager.selectPreferredTransport();
        } catch (Exception e) {
            studioState.syncStatusProperty().set("连接不可用，请重新连接键盘后再保存。");
            return;
        }

        boolean includeVoiceKey = false;
        try {
            var capabilities = bleManager.requireStabilizedDeviceContract();
            includeVoiceKey = capabilities.supports(AhaKeyProtocol.CAP_VOICE_KEY_DUAL_V1);
        } catch (Exception exception) {
            logger.warn("设备未满足稳定版能力合同，已阻止配置写入: {}",
                exception.getMessage());
            studioState.syncStatusProperty().set(
                "设备能力合同不兼容，无法安全保存配置：" + exception.getMessage());
            return;
        }
        int syncRevision = studioState.getRevision();
        StudioState.DirtySnapshot dirtySnapshot = studioState.captureDirtySnapshot();
        var commands = List.copyOf(DeviceSyncService.commandsForModes(
            studioState, includeVoiceKey, ModeSlot.values()));
        studioState.syncingProperty().set(true);
        studioState.syncStatusProperty().set("正在通过 " + transport + " 写入设备配置...");
        studioState.syncStatusProperty().set("正在写入设备配置...");
        studioState.syncStatusProperty().set("Saving via " + transport + "...");
        DeviceSyncService.SyncHandle syncHandle = DeviceSyncService.writeSequentially(
            bleManager,
            commands,
            () -> Platform.runLater(() -> {
                studioState.clearDirtyAfterSync(dirtySnapshot);
                lastSyncedRevision = syncRevision;
                studioState.syncingProperty().set(false);
                studioState.syncStatusProperty().set(
                    studioState.getRevision() == syncRevision
                        ? "已保存配置。"
                        : "设备已保存先前快照，后续修改仍待保存。");
                statusRefreshScheduler.submit(bleManager::queryStatus);
                if (returnToAgentWhenDone) {
                    returnToKeyboardControl();
                }
            }),
            () -> Platform.runLater(() -> studioState.syncingProperty().set(false)),
            msg -> Platform.runLater(() -> studioState.syncStatusProperty().set(msg))
        );
        Thread watchdog = new Thread(() -> {
            try {
                Thread.sleep(45000);
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                return;
            }
            if (syncHandle.isRunning() && studioState.syncingProperty().get()) {
                syncHandle.cancel();
                Platform.runLater(() -> studioState.syncStatusProperty().set(
                    "保存超时，已请求取消；在后台事务实际退出前将阻止冲突写入。"));
            }
        }, "device-sync-watchdog");
        watchdog.setDaemon(true);
        watchdog.start();
    }
    public void previewLightOnDevice() {
        LightBarPreviewState preview = studioState.getLightBarPreview();
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("请先连接设备再预览灯效。");
            return;
        }
        // 使用 IDE 状态码发送（适配当前固件，固件根据 claude_state 映射灯效）
        IDEState ideState = preview.getIdeState();
        String success = "已发送灯效预览：" + preview.getTitle() + " → "
            + ideState.getFullLabel();
        if (simulateBle) {
            studioState.syncStatusProperty().set(success);
            return;
        }
        runLightOperation("light-preview", () -> LightOperationCoordinator.execute(
            success,
            LightOperationCoordinator.step("灯效预览写入",
                () -> bleManager.updateStateOrThrow((byte) ideState.getCode()))));
    }

    public void previewLightEffectOnDevice(LightEffectStyle effect) {
        if (effect == null) {
            return;
        }
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("请先连接键盘，再测试灯效。");
            return;
        }
        String success = "已发送灯效测试：" + effect.getTitle();
        if (simulateBle) {
            studioState.syncStatusProperty().set(success);
            return;
        }
        runLightOperation("light-effect-preview", () -> LightOperationCoordinator.execute(
            success,
            LightOperationCoordinator.step("灯效写入",
                () -> bleManager.setLightEffect(effect.getCode()))));
    }

    public void sendLightBrightnessToDevice() {
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("请先连接键盘，再测试灯光亮度。");
            return;
        }
        int brightness = studioState.getLightBrightness();
        studioState.syncStatusProperty().set("正在测试灯光亮度：" + brightness);
        if (simulateBle) {
            studioState.syncStatusProperty().set("已发送灯光亮度：" + brightness);
            return;
        }
        runLightOperation("brightness-test", () -> LightOperationCoordinator.execute(
                "已发送灯光亮度：" + brightness,
                LightOperationCoordinator.step("亮度写入",
                    () -> bleManager.setLightBrightness(brightness)),
                LightOperationCoordinator.step("灯效写入",
                    () -> bleManager.setLightEffect(LightEffectStyle.RAINBOW_MOVE.getCode()))));
    }
    public void syncCurrentModeLightConfig() {
        ModeSlot mode = studioState.getSelectedMode();
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("请先连接键盘，再保存当前模式灯效。");
            return;
        }
        String success = "已保存 " + mode.getTitle() + " 的 AI 状态灯效和亮度。";
        if (simulateBle) {
            studioState.syncStatusProperty().set(success);
            return;
        }
        runLightOperation("light-mode-sync", () -> LightOperationCoordinator.execute(
            success,
            LightOperationCoordinator.step("AI 状态灯效配置写入",
                () -> bleManager.setAiLightConfig(
                    mode.getIndex(), studioState.getAiLightEffectBytes(mode))),
            LightOperationCoordinator.step("亮度写入",
                () -> bleManager.setLightBrightness(studioState.getLightBrightness()))));
    }

    private void runLightOperation(
        String threadName,
        java.util.function.Supplier<LightOperationCoordinator.Result> operation
    ) {
        Thread worker = new Thread(() -> {
            LightOperationCoordinator.Result result = operation.get();
            Platform.runLater(() -> studioState.syncStatusProperty().set(result.message()));
        }, threadName);
        worker.setDaemon(true);
        worker.start();
    }

    public void updateSwitchState(int state) {
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("请先连接设备再修改拨杆状态。");
            return;
        }
        // 先更新本地状态
        deviceStatus.setSwitchState(state);
        // 发送到设备
        if (!simulateBle) {
            bleManager.updateState((byte) state);
        }
        studioState.syncStatusProperty().set(
            "拨杆状态已更新为: " + deviceStatus.getSwitchTitle()
        );
    }

    private boolean isStaticOledImage(String lowerPath) {
        return lowerPath.endsWith(".png") || lowerPath.endsWith(".jpg") || lowerPath.endsWith(".jpeg");
    }

    private boolean isGifImage(String lowerPath) {
        return lowerPath.endsWith(".gif");
    }

    private int localSafeGifFrameLimit() {
        return OledUploadService.perModeCapacity(Math.min(
            OledUploadService.fallbackTotalFrameSlots(),
            AhaKeyProtocol.OLED_MAX_FRAMES
        ));
    }

    private void showOledWarning(String title, String message) {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.WARNING);
        alert.setTitle(title);
        alert.setHeaderText(null);
        alert.setContentText(message);
        alert.showAndWait();
    }

    /**
     * 显示手动批准确认对话框
     * @param platform 平台名称（如 Cursor、Kimi 等）
     * @param eventName 事件名称
     * @return true 表示用户确认，false 表示用户拒绝
     */
    private boolean showApprovalDialog(String platform, String eventName) {
        if (!approvalDialogLock.tryLock()) {
            logger.warn("Manual approval already active; denying concurrent request from {}", platform);
            return false;
        }
        try {
        if (!javafx.application.Platform.isFxApplicationThread()) {
            java.util.concurrent.CountDownLatch latch = new java.util.concurrent.CountDownLatch(1);
            ManualApprovalGate gate = new ManualApprovalGate();
            java.util.concurrent.atomic.AtomicReference<javafx.scene.control.Alert> alertRef =
                new java.util.concurrent.atomic.AtomicReference<>();
            javafx.application.Platform.runLater(() -> {
                if (gate.isCompleted()) return;
                javafx.scene.control.Alert alert = createApprovalAlert(platform, eventName);
                alertRef.set(alert);
                java.util.Optional<javafx.scene.control.ButtonType> selected = alert.showAndWait();
                javafx.scene.control.ButtonType allowButton = alert.getButtonTypes().get(0);
                gate.complete(selected.isPresent() && selected.get() == allowButton);
                latch.countDown();
            });
            try {
                if (!latch.await(15, java.util.concurrent.TimeUnit.SECONDS)) {
                    gate.timeout();
                    closeApprovalAlert(alertRef);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                gate.cancel();
                closeApprovalAlert(alertRef);
            }
            return gate.isAllowed();
        }
        ManualApprovalGate gate = new ManualApprovalGate();
        javafx.scene.control.Alert alert = createApprovalAlert(platform, eventName);
        javafx.animation.PauseTransition timeout =
            new javafx.animation.PauseTransition(javafx.util.Duration.seconds(15));
        timeout.setOnFinished(event -> {
            if (gate.timeout() && alert.isShowing()) alert.close();
        });
        timeout.play();
        java.util.Optional<javafx.scene.control.ButtonType> result = alert.showAndWait();
        timeout.stop();
        javafx.scene.control.ButtonType allowButton = alert.getButtonTypes().get(0);
        gate.complete(result.isPresent() && result.get() == allowButton);
        return gate.isAllowed();
        } finally {
            approvalDialogLock.unlock();
        }
    }

    private void closeApprovalAlert(
        java.util.concurrent.atomic.AtomicReference<javafx.scene.control.Alert> alertRef
    ) {
        javafx.application.Platform.runLater(() -> {
            javafx.scene.control.Alert alert = alertRef.get();
            if (alert != null && alert.isShowing()) alert.close();
        });
    }

    private javafx.scene.control.Alert createApprovalAlert(
        String platform, String eventName
    ) {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(
            javafx.scene.control.Alert.AlertType.CONFIRMATION);
        alert.setTitle(languageManager.getString("dialog.confirm-title"));
        alert.setHeaderText(null);
        alert.setContentText(String.format(languageManager.getString("dialog.confirm-content"), 
            platform, eventName));
        
        javafx.scene.control.ButtonType okButton = new javafx.scene.control.ButtonType(languageManager.getString("dialog.allow"));
        javafx.scene.control.ButtonType cancelButton = new javafx.scene.control.ButtonType(languageManager.getString("dialog.deny"));
        alert.getButtonTypes().setAll(okButton, cancelButton);
        return alert;
    }

    private int validateLocalOledAsset(Path path, boolean isStaticImage) throws Exception {
        if (isStaticImage) {
            OLEDFrameEncoder.validateGifSourceFileSize(path);
            return 1;
        }
        GifUploadRules.Preflight preflight = OLEDFrameEncoder.preflight(path, 0);
        return Math.min(preflight.sourceFrames(), preflight.targetFrameLimit());
    }

    public void selectOledGif(javafx.stage.Window owner) {
        FileChooser chooser = new FileChooser();
        chooser.setTitle(languageManager.getString("dialog.select-gif"));
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter(languageManager.getString("dialog.filter-gif"), "*.gif"));
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter(languageManager.getString("dialog.filter-png"), "*.png"));
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter(languageManager.getString("dialog.filter-jpg"), "*.jpg", "*.jpeg"));
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter(languageManager.getString("dialog.filter-all"), "*.gif", "*.png", "*.jpg", "*.jpeg"));
        java.io.File last = GifSelectionHistory.initialLocation();
        if (last != null) {
            java.io.File directory = last.isDirectory() ? last : last.getParentFile();
            if (directory != null && directory.isDirectory()) chooser.setInitialDirectory(directory);
            if (last.isFile()) chooser.setInitialFileName(last.getName());
        }
        var file = chooser.showOpenDialog(owner);
        if (file == null) {
            return;
        }
        try {
            Path path = file.toPath();
            String fileName = file.getName().toLowerCase();
            boolean isStaticImage = isStaticOledImage(fileName);
            if (!isStaticImage && !isGifImage(fileName)) {
                throw new IllegalStateException("只支持 GIF、PNG、JPG、JPEG 文件。");
            }
            if (!isStaticImage) {
                GifUploadRules.Preflight preflight = OLEDFrameEncoder.preflight(path, 0);
                if (preflight.needsOptimization()) {
                    javafx.scene.control.Alert confirmation = new javafx.scene.control.Alert(
                        javafx.scene.control.Alert.AlertType.CONFIRMATION,
                        String.format("GIF 将自动优化为 %d×%d、最多 %d 帧，并尽量保持原始总时长。是否继续？",
                            GifUploadRules.WIDTH, GifUploadRules.HEIGHT,
                            preflight.targetFrameLimit()),
                        javafx.scene.control.ButtonType.OK,
                        javafx.scene.control.ButtonType.CANCEL);
                    if (confirmation.showAndWait().orElse(javafx.scene.control.ButtonType.CANCEL)
                        != javafx.scene.control.ButtonType.OK) return;
                }
            }
            int count = validateLocalOledAsset(path, isStaticImage);
            GifSelectionHistory.remember(path);
            studioState.applyOledGifSelection(path.toString(), count);
            studioState.syncStatusProperty().set(
                isStaticImage
                    ? "已选择 " + studioState.getSelectedMode().getTitle() + " 的图片，连接键盘后可上传。"
                    : "已选择 " + studioState.getSelectedMode().getTitle() + " 的 GIF（" + count + " 帧），连接键盘后可上传。"
            );
        } catch (Exception e) {
            String message = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
            studioState.syncStatusProperty().set("GIF / 图片导入失败：" + message);
            showOledWarning("GIF / 图片不适合上传", message);
        }
    }

    public void uploadCurrentOledToDevice() {
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("设备未连接，请先连接键盘。");
            userConnect();
            return;
        }
        OledModeDraft draft = studioState.getOledDraft();
        String path = draft.getLocalAssetPath();
        if (path == null || path.isBlank()) {
            studioState.syncStatusProperty().set("请先选择 GIF 或图片。");
            return;
        }
        if (simulateBle) {
            studioState.syncStatusProperty().set("（模拟）OLED 上传已跳过。");
            return;
        }

        ModeSlot mode = studioState.getSelectedMode();
        Path imagePath = Path.of(path);
        String lowerPath = path.toLowerCase();
        boolean isStaticImage = isStaticOledImage(lowerPath);
        if (!isStaticImage && !isGifImage(lowerPath)) {
            String message = "只支持 GIF、PNG、JPG、JPEG 文件。";
            studioState.syncStatusProperty().set(message);
            showOledWarning("无法上传 OLED GIF / 图片", message);
            return;
        }
        try {
            int frameCount = validateLocalOledAsset(imagePath, isStaticImage);
            if (frameCount != draft.getFrameCount()) {
                studioState.applyOledGifSelection(path, frameCount);
            }
        } catch (Exception e) {
            String message = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
            studioState.syncStatusProperty().set("OLED 上传已取消：" + message);
            showOledWarning("无法上传 OLED GIF / 图片", message);
            return;
        }

        logger.info("[OLED上传] 当前选择模式: {} (索引: {}){}", mode.getShortName(), mode.getIndex(),
            isStaticImage ? ", 类型: 静态图片" : ", 类型: GIF动图");

        javafx.stage.Stage progressStage = new javafx.stage.Stage();
        progressStage.initModality(javafx.stage.Modality.APPLICATION_MODAL);
        progressStage.setTitle(isStaticImage ? "上传 OLED 图片" : "上传 OLED GIF");
        progressStage.setResizable(false);

        javafx.scene.layout.VBox dialogContent = new javafx.scene.layout.VBox(12);
        dialogContent.setPadding(new javafx.geometry.Insets(16));

        javafx.scene.control.Label titleLabel = new javafx.scene.control.Label(
            isStaticImage ? "正在上传 OLED 图片..." : "正在上传 OLED GIF..."
        );
        titleLabel.getStyleClass().add("dialog-title");

        javafx.scene.control.ProgressBar progressBar = new javafx.scene.control.ProgressBar(0);
        progressBar.setPrefWidth(300);

        javafx.scene.control.Label detailLabel = new javafx.scene.control.Label("准备数据...");
        detailLabel.getStyleClass().add("dialog-detail");

        dialogContent.getChildren().addAll(titleLabel, progressBar, detailLabel);

        javafx.scene.Scene dialogScene = new javafx.scene.Scene(dialogContent);
        dialogScene.getStylesheets().add(getClass().getResource("/style.css").toExternalForm());
        progressStage.setScene(dialogScene);
        progressStage.show();

        studioState.uploadingOledProperty().set(true);

        Runnable clearUploading = () -> {
            progressStage.close();
            studioState.uploadingOledProperty().set(false);
        };

        if (isStaticImage) {
            OledUploadService.uploadStaticImage(
                bleManager,
                mode,
                imagePath,
                progress -> Platform.runLater(() -> {
                    double progressValue = progress.totalFrames() > 0 ? (double) progress.completedFrames() / progress.totalFrames() : 0;
                    progressBar.setProgress(progressValue);
                    detailLabel.setText(progress.detail());
                    studioState.oledUploadDetailProperty().set(progress.detail());
                }),
                msg -> Platform.runLater(() -> {
                    clearUploading.run();
                    draft.setStatusLine("上传完成");
                    draft.setCaptionLine(mode.getTitle() + " - 静态图片");
                    studioState.setOledSummary("上传完成");
                    studioState.setOledCaption(mode.getTitle() + " - 静态图片");
                    studioState.syncStatusProperty().set(msg);
                }),
                err -> Platform.runLater(() -> {
                    clearUploading.run();
                    studioState.syncStatusProperty().set(mode.getTitle() + " OLED 上传失败：" + err);
                    showOledWarning("OLED 上传失败", err);
                })
            );
        } else {
            OledUploadService.uploadGif(
                bleManager,
                mode,
                imagePath,
                0,
                progress -> Platform.runLater(() -> {
                    double progressValue = progress.totalFrames() > 0 ? (double) progress.completedFrames() / progress.totalFrames() : 0;
                    progressBar.setProgress(progressValue);
                    detailLabel.setText(progress.detail());
                    studioState.oledUploadDetailProperty().set(progress.detail());
                }),
                msg -> Platform.runLater(() -> {
                    clearUploading.run();
                    draft.setStatusLine("上传完成");
                    draft.setCaptionLine(mode.getTitle() + " - " + draft.getFrameCount() + " 帧");
                    studioState.setOledSummary("上传完成");
                    studioState.setOledCaption(mode.getTitle() + " - " + draft.getFrameCount() + " 帧");
                    studioState.syncStatusProperty().set(msg);
                }),
                err -> Platform.runLater(() -> {
                    clearUploading.run();
                    studioState.syncStatusProperty().set(mode.getTitle() + " OLED 上传失败：" + err);
                    showOledWarning("OLED 上传失败", err);
                })
            );
        }
    }
    public void applyVoicePreset(VoicePreset preset) {
        var key = studioState.getKeyConfig(StudioPart.KEY1);
        key.setVoicePreset(preset);
        if (preset.locksShortcut()) {
            if (preset == VoicePreset.MACOS_NATIVE) {
                // macOS 原生语音始终使用 F18
                key.setHidCode(com.example.ahakey.model.HIDUsage.F18);
            } else if (studioState.getSelectedMode() == ModeSlot.MODE1) {
                key.setHidCode(com.example.ahakey.model.HIDUsage.F17);
            } else {
                key.setHidCode(com.example.ahakey.model.HIDUsage.F18);
            }
        }
        studioState.markDirty(StudioPart.KEY1);
        refreshVoiceRoutes();
    }

    public String configurationModeButtonTitle() {
        if (studioState.syncingProperty().get()) {
            return languageManager.getString("button.save-progress");
        }
        if (agentManager.isEditingConfiguration()) {
            return languageManager.getString("button.save-config");
        }
        return languageManager.getString("button.edit-config");
    }

    public void handleConfigurationModeButton() {
        if (agentManager.isEditingConfiguration()) {
            finishEditingConfiguration();
        } else {
            enterEditingConfiguration();
        }
    }

    private void refreshVoiceRoutes() {
        voiceRelay.updateRoutes(studioState);
    }

    private void applyBleStatus(DeviceStatus status) {
        logger.info("应用BLE状态 - 电量: {}, 工作模式: {}, 拨杆状态: {}", 
            status.getBatteryLevel(), 
            status.getWorkMode(), 
            status.getSwitchState());
        deviceStatus.setConnected(status.isConnected());
        deviceStatus.setScanning(false);
        deviceStatus.setBatteryLevel(status.getBatteryLevel());
        deviceStatus.setDeviceName(status.getDeviceName());
        deviceStatus.setTransport(status.getTransport());
        deviceStatus.setSwitchState(status.getSwitchState());
        deviceStatus.setConnectionReadinessKnown(status.isConnectionReadinessKnown());
        deviceStatus.setBleLinkConnected(status.isBleLinkConnected());
        deviceStatus.setHidInputReady(status.isHidInputReady());
        deviceStatus.setUsbConfigReady(status.isUsbConfigReady());
        if (status.isConnected()) {
            clearResolvedConnectionError();
        }
        applyReportedWorkMode(status.getWorkMode());
    }

    private void applyReportedWorkMode(int reportedMode) {
        WorkModeSynchronizer.Action action =
            workModeSynchronizer.applyDeviceReport(reportedMode);
        if (action == WorkModeSynchronizer.Action.IGNORE_STALE) {
            logger.debug("忽略尚未确认的延迟模式状态: reported={}", reportedMode);
        } else if (action == WorkModeSynchronizer.Action.APPLY_DEVICE) {
            logger.info("设备模式状态已同步到上位机: {}", reportedMode);
        }
    }

    private void persistDraft() {
        if (!StudioStore.save(studioState.toPersisted())) {
            studioState.syncStatusProperty().set("本地配置保存失败；设备配置未受影响，请检查磁盘权限。");
        }
    }
}

