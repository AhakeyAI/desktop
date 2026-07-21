package com.example.ahakey.app;

import com.example.ahakey.config.ModelConfig;
import com.example.ahakey.model.*;
import com.example.ahakey.platform.VoiceRelayPlatform;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.AgentManager;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.service.DeviceSyncService;
import com.example.ahakey.service.HookDispatchServer;
import com.example.ahakey.service.OledUploadService;
import com.example.ahakey.util.OLEDFrameEncoder;
import com.example.ahakey.util.StudioStore;
import com.example.ahakey.util.LanguageManager;
import javafx.application.Platform;
import javafx.stage.FileChooser;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Path;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

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
    private final com.example.ahakey.service.KimiAhaKeyBridge kimiAhaKeyBridge;

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
                if (bleManager.isUsbConnected()) {
                    kimiAhaKeyBridge.start();
                }
                // 启动定时轮询（BLE通知不可靠，需要主动查询）
                startStatusPolling();
            }

            @Override
            public void onDisconnected() {
                Platform.runLater(() -> deviceStatus.setConnected(false));
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
        hookDispatchServer = new HookDispatchServer(bleManager);
        hookDispatchServer.setApprovalCallback(this::showApprovalDialog);
        hookDispatchServer.start();

        // KimiAhaKeyBridge 在设备连接后按连接类型决定是否启动（见 onConnected）
        kimiAhaKeyBridge = new com.example.ahakey.service.KimiAhaKeyBridge(bleManager);
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

    public AgentManager getAgentManager() {
        return agentManager;
    }

    public int getHookDispatchPort() {
        return hookDispatchServer.getActualPort();
    }

    public boolean isEffectivelyConnected() {
        return deviceStatus.isConnected();
    }

    public boolean hasUnsyncedChanges() {
        return studioState.getRevision() != lastSyncedRevision || studioState.getDirtyCount() > 0;
    }

    public void shutdown() {
        voiceRelay.stop();
        stopStatusPolling();
        hookDispatchServer.stop();
        kimiAhaKeyBridge.stop();
        if (!simulateBle) {
            bleManager.disconnect();
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
        int pollPeriod = ModelConfig.getInstance().getStatusPollPeriodSeconds();
        logger.info("设备状态轮询周期: {}秒", pollPeriod);
        pollFuture = statusPoller.scheduleAtFixedRate(() -> {
            if (!simulateBle && deviceStatus.isConnected()) {
                try {
                    bleManager.queryStatus();
                    // 检查心跳超时：超过15秒没有收到状态更新，认为设备已断开
                    long lastUpdate = bleManager.getLastStatusUpdateTime();
                    if (lastUpdate > 0 && System.currentTimeMillis() - lastUpdate > 15000) {
                        logger.warn("设备心跳超时，断开连接");
                        bleManager.disconnect();
                    }
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

    public void userConnect() {
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
    }

    public void userDisconnect() {
        bleManager.disconnect();
    }

    public void selectKeyboardMode(ModeSlot mode) {
        studioState.setSelectedMode(mode);
        if (!simulateBle && deviceStatus.isConnected()) {
            bleManager.setWorkMode(mode.getIndex());
        }
    }

    public void enterEditingConfiguration() {
        agentManager.setBluetoothOwner(AgentManager.BluetoothOwner.AHAKEY_STUDIO);
        studioState.syncStatusProperty().set("已进入编辑配置模式。");
        refreshVoiceRoutes();
        if (!deviceStatus.isConnected() && !simulateBle) {
            userConnect();
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
            studioState.syncStatusProperty().set("设备未连接，请先连接键盘。");
            userConnect();
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
            studioState.clearDirtyAfterSync();
            lastSyncedRevision = studioState.getRevision();
            studioState.syncStatusProperty().set("模拟模式：已标记为保存。");
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

        var commands = DeviceSyncService.commandsForModes(studioState, ModeSlot.values());
        studioState.syncingProperty().set(true);
        studioState.syncStatusProperty().set("正在通过 " + transport + " 写入设备配置...");
        studioState.syncStatusProperty().set("正在写入设备配置...");
        studioState.syncStatusProperty().set("Saving via " + transport + "...");
        int syncRevision = studioState.getRevision();
        new Thread(() -> {
            try {
                Thread.sleep(45000);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
            if (studioState.syncingProperty().get() && studioState.getRevision() == syncRevision) {
                Platform.runLater(() -> {
                    studioState.syncingProperty().set(false);
                    studioState.syncStatusProperty().set("保存超时，请重新连接键盘后再保存。");
                });
            }
        }, "device-sync-watchdog").start();
        DeviceSyncService.writeSequentially(
            bleManager,
            commands,
            () -> Platform.runLater(() -> {
                studioState.clearDirtyAfterSync();
                lastSyncedRevision = studioState.getRevision();
                studioState.syncingProperty().set(false);
                studioState.syncStatusProperty().set("已保存配置。");
                bleManager.queryStatus();
                if (returnToAgentWhenDone) {
                    returnToKeyboardControl();
                }
            }),
            () -> Platform.runLater(() -> studioState.syncingProperty().set(false)),
            msg -> Platform.runLater(() -> studioState.syncStatusProperty().set(msg))
        );
    }
    public void previewLightOnDevice() {
        LightBarPreviewState preview = studioState.getLightBarPreview();
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("请先连接设备再预览灯效。");
            return;
        }
        // 使用 IDE 状态码发送（适配当前固件，固件根据 claude_state 映射灯效）
        IDEState ideState = preview.getIdeState();
        if (!simulateBle) {
            bleManager.updateState((byte) ideState.getCode());
        }
        studioState.syncStatusProperty().set(
            "已发送灯效预览：" + preview.getTitle() + " → " + ideState.getFullLabel()
        );
    }

    public void previewLightEffectOnDevice(LightEffectStyle effect) {
        if (effect == null) {
            return;
        }
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("请先连接键盘，再测试灯效。");
            return;
        }
        if (!simulateBle) {
            bleManager.setLightEffect(effect.getCode());
        }
        studioState.syncStatusProperty().set("已发送灯效测试：" + effect.getTitle());
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
        new Thread(() -> {
            bleManager.setLightBrightness(brightness);
            bleManager.setLightEffect(LightEffectStyle.RAINBOW_MOVE.getCode());
            Platform.runLater(() -> studioState.syncStatusProperty().set("已发送灯光亮度：" + brightness));
        }, "brightness-test").start();
    }
    public void syncCurrentModeLightConfig() {
        ModeSlot mode = studioState.getSelectedMode();
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("请先连接键盘，再保存当前模式灯效。");
            return;
        }
        if (!simulateBle) {
            bleManager.setAiLightConfig(mode.getIndex(), studioState.getAiLightEffectBytes(mode));
            bleManager.setLightBrightness(studioState.getLightBrightness());
        }
        studioState.syncStatusProperty().set("已保存 " + mode.getTitle() + " 的 AI 状态灯效和亮度。");
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
        if (!javafx.application.Platform.isFxApplicationThread()) {
            java.util.concurrent.CountDownLatch latch = new java.util.concurrent.CountDownLatch(1);
            final boolean[] result = {false};
            javafx.application.Platform.runLater(() -> {
                result[0] = showApprovalDialog(platform, eventName);
                latch.countDown();
            });
            try { latch.await(30, java.util.concurrent.TimeUnit.SECONDS); } catch (InterruptedException e) { }
            return result[0];
        }
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.CONFIRMATION);
        alert.setTitle(languageManager.getString("dialog.confirm-title"));
        alert.setHeaderText(null);
        alert.setContentText(String.format(languageManager.getString("dialog.confirm-content"), 
            platform, eventName));
        
        javafx.scene.control.ButtonType okButton = new javafx.scene.control.ButtonType(languageManager.getString("dialog.allow"));
        javafx.scene.control.ButtonType cancelButton = new javafx.scene.control.ButtonType(languageManager.getString("dialog.deny"));
        alert.getButtonTypes().setAll(okButton, cancelButton);
        
        java.util.Optional<javafx.scene.control.ButtonType> result = alert.showAndWait();
        return result.isPresent() && result.get() == okButton;
    }

    private int validateLocalOledAsset(Path path, boolean isStaticImage) throws Exception {
        OLEDFrameEncoder.validateGifSourceFileSize(path);
        if (isStaticImage) {
            return 1;
        }
        int count = OLEDFrameEncoder.frameCount(path);
        int limit = localSafeGifFrameLimit();
        if (count <= 0) {
            throw new IllegalStateException(languageManager.getString("dialog.gif-no-frames"));
        }
        if (count > limit) {
            throw new IllegalStateException(
                String.format(languageManager.getString("dialog.gif-too-many-frames"), count, limit)
            );
        }
        return count;
    }

    public void selectOledGif(javafx.stage.Window owner) {
        FileChooser chooser = new FileChooser();
        chooser.setTitle(languageManager.getString("dialog.select-gif"));
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter(languageManager.getString("dialog.filter-gif"), "*.gif"));
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter(languageManager.getString("dialog.filter-png"), "*.png"));
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter(languageManager.getString("dialog.filter-jpg"), "*.jpg", "*.jpeg"));
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter(languageManager.getString("dialog.filter-all"), "*.gif", "*.png", "*.jpg", "*.jpeg"));
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
            int count = validateLocalOledAsset(path, isStaticImage);
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

    public void previewOledOnDevice() {
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("设备未连接，请先连接键盘。");
            userConnect();
            return;
        }
        OledModeDraft draft = studioState.getOledDraft();
        String path = draft.getLocalAssetPath();
        if (path == null || path.isBlank()) {
            studioState.syncStatusProperty().set("请先选择 GIF。");
            return;
        }
        if (simulateBle) {
            studioState.syncStatusProperty().set("（模拟）OLED 预览已跳过。");
            return;
        }
        OledUploadService.previewGif(
            bleManager,
            Path.of(path),
            draft.getFramesPerSecond(),
            msg -> Platform.runLater(() -> studioState.syncStatusProperty().set(msg)),
            err -> Platform.runLater(() -> {
                studioState.syncStatusProperty().set("OLED 预览失败：" + err);
                showOledWarning("OLED 预览失败", err);
            })
        );
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
                draft.getFramesPerSecond(),
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
        deviceStatus.setWorkMode(status.getWorkMode());
        deviceStatus.setSwitchState(status.getSwitchState());
        ModeSlot deviceMode = ModeSlot.fromIndex(status.getWorkMode());
        if (deviceMode != studioState.getSelectedMode()) {
            studioState.setSelectedMode(deviceMode);
        }
    }

    private void persistDraft() {
        StudioStore.save(studioState.toPersisted());
    }
}

