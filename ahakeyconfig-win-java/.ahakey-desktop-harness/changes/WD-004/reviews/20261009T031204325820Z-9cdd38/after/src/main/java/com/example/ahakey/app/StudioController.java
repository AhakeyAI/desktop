package com.example.ahakey.app;

import com.example.ahakey.config.ModelConfig;
import com.example.ahakey.model.*;
import com.example.ahakey.platform.VoiceRelayPlatform;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.service.AgentManager;
import com.example.ahakey.service.AiRuntimeDisplayService;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.service.DeviceSyncService;
import com.example.ahakey.service.HookDispatchServer;
import com.example.ahakey.service.HookInstaller;
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
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 应用总线：连接 Swift 中 `AhaKeyStudioView` + `BLE` + `AgentManager` 的编排逻辑。
 */
public class StudioController {
    private static final Logger logger = LoggerFactory.getLogger(StudioController.class);
    private static final long MODE_SWITCH_STATUS_SETTLE_MS = 1500;
    private final LanguageManager languageManager = LanguageManager.getInstance();
    private final DeviceStatus deviceStatus = new DeviceStatus();
    private final StudioState studioState = new StudioState();
    private final AgentManager agentManager = new AgentManager();
    private final VoiceRelayPlatform voiceRelay = new VoiceRelayPlatform();
    private final BleManager bleManager;
    private final AiRuntimeDisplayService aiRuntimeDisplayService;
    private final HookInstaller aiRuntimeHookInstaller;
    private final boolean simulateBle;
    private final HookDispatchServer hookDispatchServer;
    private final com.example.ahakey.service.KimiAhaKeyBridge kimiAhaKeyBridge;
    private Runnable hookManagerOpener;

    private int lastSyncedRevision = -1;
    
    // 定时轮询设备状态（由于BLE通知不可靠，需要主动查询）
    private ScheduledExecutorService statusPoller;
    private ScheduledFuture<?> pollFuture;
    private volatile boolean firmwareCatalogKeyRequested = false;
    private volatile boolean enterEditingAfterConnect = false;
    private final AtomicBoolean cp4cInputReadbackInProgress = new AtomicBoolean(false);
    private volatile ModeSlot pendingModeSwitchTarget = null;
    private volatile long suppressModeStatusUntilMillis = 0;
    private final AtomicBoolean modeSwitchInProgress = new AtomicBoolean(false);

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
                    if (enterEditingAfterConnect) {
                        enterEditingAfterConnect = false;
                        activateConfigurationEditing();
                    }
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
                firmwareCatalogKeyRequested = false;
                enterEditingAfterConnect = false;
                Platform.runLater(() -> {
                    deviceStatus.setConnected(false);
                    deviceStatus.clearFirmwareIdentity();
                    studioState.setCp4cInputConfigEnabled(false);
                    if (modeSwitchInProgress.getAndSet(false)) {
                        studioState.modeSwitchingProperty().set(false);
                        studioState.syncStatusProperty().set("连接中断，键盘模式未确认");
                    }
                    clearModeSwitchStatusGuard();
                });
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
                enterEditingAfterConnect = false;
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
        aiRuntimeDisplayService = new AiRuntimeDisplayService(bleManager);
        hookDispatchServer = new HookDispatchServer(bleManager, aiRuntimeDisplayService);
        aiRuntimeHookInstaller = new HookInstaller(hookDispatchServer::getActualPort, msg -> logger.info("{}", msg));
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

    public AiRuntimeDisplayService getAiRuntimeDisplayService() {
        return aiRuntimeDisplayService;
    }

    public int getHookDispatchPort() {
        return hookDispatchServer.getActualPort();
    }

    public void setHookManagerOpener(Runnable hookManagerOpener) {
        this.hookManagerOpener = hookManagerOpener;
    }

    public void setAiRuntimeDisplayMode(AiRuntimeDisplayMode mode) {
        aiRuntimeDisplayService.setDisplayMode(mode);
        if (mode == AiRuntimeDisplayMode.MULTI && isAiRuntimeHookLatest()
            && !simulateBle && deviceStatus.isConnected() && aiRuntimeDisplayService.isDeviceSupported()) {
            new Thread(() -> {
                try {
                    aiRuntimeDisplayService.applyToKeyboard();
                } catch (Exception e) {
                    logger.warn("Auto apply MULTI runtime snapshot failed: {}", e.getMessage());
                }
            }, "ai-runtime-mode-auto-apply").start();
        }
        studioState.syncStatusProperty().set("AI 运行展示已切换为：" + mode.getTitle());
    }

    private boolean isAiRuntimeHookLatest() {
        return aiRuntimeHookInstaller.getHookStatus("Codex") == HookInstaller.HookStatus.LATEST
            && aiRuntimeHookInstaller.getHookStatus("Cursor") == HookInstaller.HookStatus.LATEST;
    }

    public HookInstaller.HookStatus getAiRuntimeHookStatus(String platform) {
        return aiRuntimeHookInstaller.getHookStatus(platform);
    }

    public void openHookManager() {
        if (hookManagerOpener != null) {
            hookManagerOpener.run();
        }
    }

    public void applyAiRuntimeToKeyboard(javafx.stage.Window owner) {
        boolean applyingMulti = aiRuntimeDisplayService.getDisplayMode() == AiRuntimeDisplayMode.MULTI;
        HookInstaller.HookStatus codexStatus = applyingMulti ? aiRuntimeHookInstaller.getHookStatus("Codex") : HookInstaller.HookStatus.LATEST;
        HookInstaller.HookStatus cursorStatus = applyingMulti ? aiRuntimeHookInstaller.getHookStatus("Cursor") : HookInstaller.HookStatus.LATEST;
        if (applyingMulti && (codexStatus != HookInstaller.HookStatus.LATEST || cursorStatus != HookInstaller.HookStatus.LATEST)) {
            javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.CONFIRMATION);
            alert.initOwner(owner);
            alert.setTitle("AhaKey Hook 管理");
            alert.setHeaderText(null);
            alert.setContentText("多任务灯光需要先在 Hook 管理中安装或更新 Codex / Cursor Hook。");
            javafx.scene.control.ButtonType update = new javafx.scene.control.ButtonType("去 Hook 管理");
            javafx.scene.control.ButtonType cancel = new javafx.scene.control.ButtonType("取消", javafx.scene.control.ButtonBar.ButtonData.CANCEL_CLOSE);
            alert.getButtonTypes().setAll(update, cancel);
            java.util.Optional<javafx.scene.control.ButtonType> result = alert.showAndWait();
            if (result.isPresent() && result.get() == update) {
                if (hookManagerOpener != null) {
                    hookManagerOpener.run();
                }
            }
            return;
        }
        if (applyingMulti) {
            AiRuntimeDisplayService.ApplyPlan plan = aiRuntimeDisplayService.prepareApply(
                codexStatus == HookInstaller.HookStatus.LATEST,
                cursorStatus == HookInstaller.HookStatus.LATEST
            );
            if (plan.usableCount() == 0) {
                javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.WARNING);
                alert.initOwner(owner);
                alert.setTitle("任务槽不可用");
                alert.setHeaderText(null);
                alert.setContentText("当前没有可应用到键盘的任务槽。请检查 Hook 状态或重新选择会话。");
                alert.showAndWait();
                return;
            }
            if (!plan.unavailableSlots().isEmpty()) {
                StringBuilder message = new StringBuilder("以下任务槽当前不可用，将不会显示到键盘：");
                for (AiRuntimeDisplayService.UnavailableSlot slot : plan.unavailableSlots()) {
                    message.append("\n槽位 ").append(slot.slotIndex() + 1).append("：").append(slot.reason());
                }
                javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.INFORMATION);
                alert.initOwner(owner);
                alert.setTitle("任务槽不可用");
                alert.setHeaderText(null);
                alert.setContentText(message.toString());
                alert.getButtonTypes().setAll(new javafx.scene.control.ButtonType("知道了"));
                alert.showAndWait();
            }
        }
        if (!simulateBle && !deviceStatus.isConnected()) {
            studioState.syncStatusProperty().set("已保存本地槽位；连接键盘后可应用。");
            return;
        }
        if (!simulateBle && !aiRuntimeDisplayService.isDeviceSupported()) {
            studioState.syncStatusProperty().set("当前固件不支持 WS3 CP1 多任务运行展示，已保留本地绑定。");
            return;
        }
        if (simulateBle) {
            aiRuntimeDisplayService.markDraftApplied(
                codexStatus == HookInstaller.HookStatus.LATEST,
                cursorStatus == HookInstaller.HookStatus.LATEST
            );
            studioState.syncStatusProperty().set("模拟模式：已标记为应用到键盘。");
            return;
        }
        new Thread(() -> {
            try {
                aiRuntimeDisplayService.applyToKeyboard(
                    codexStatus == HookInstaller.HookStatus.LATEST,
                    cursorStatus == HookInstaller.HookStatus.LATEST
                );
                Platform.runLater(() -> studioState.syncStatusProperty().set("已应用到键盘。"));
            } catch (Exception e) {
                Platform.runLater(() -> studioState.syncStatusProperty().set("应用到键盘失败：" + e.getMessage()));
            }
        }, "ai-runtime-apply").start();
    }

    public boolean isEffectivelyConnected() {
        return deviceStatus.isConnected();
    }

    public boolean canWriteToDevice() {
        return simulateBle || deviceStatus.isConnected();
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
        firmwareCatalogKeyRequested = false;
        deviceStatus.clearFirmwareIdentity();
        bleManager.clearCachedFirmwareIdentity();
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
        enterEditingAfterConnect = false;
        bleManager.disconnect();
    }

    public void refreshDeviceInfoDetails() {
        clearDeviceInfoDetailsForRefresh();
        readFirmwareCatalogKeyForDeviceInfo();
        refreshDeviceStatusSnapshot();
    }

    public void clearDeviceInfoDetailsForRefresh() {
        firmwareCatalogKeyRequested = false;
        deviceStatus.clearFirmwareIdentity();
        bleManager.clearCachedFirmwareIdentity();
    }

    public void readFirmwareCatalogKeyForDeviceInfo() {
        if (!simulateBle && deviceStatus.isConnected()) {
            firmwareCatalogKeyRequested = true;
            try {
                String catalogKey = bleManager.readFirmwareCatalogKey();
                handleFirmwareCatalogKey(catalogKey);
            } catch (Exception e) {
                logger.info("Firmware catalog key read skipped/fallback: {}", e.getMessage());
            }
        }
    }

    public void refreshDeviceStatusSnapshot() {
        if (!simulateBle && deviceStatus.isConnected()) {
            bleManager.queryStatusAndWait(1000);
        }
    }

    public void selectKeyboardMode(ModeSlot mode) {
        if (mode == null) {
            return;
        }
        if (studioState.modeSwitchingProperty().get()) {
            studioState.syncStatusProperty().set("正在确认键盘模式，请稍候。");
            return;
        }
        if (simulateBle) {
            studioState.setSelectedMode(mode);
            studioState.syncStatusProperty().set("模拟模式：已切换到 " + mode.getTitle() + "。");
            return;
        }
        if (!deviceStatus.isConnected()) {
            studioState.setSelectedMode(mode);
            studioState.syncStatusProperty().set("离线浏览 " + mode.getTitle() + "，本地草稿已保留；连接键盘后可切换/保存。");
            return;
        }
        ModeSlot previousMode = studioState.getSelectedMode();
        if (previousMode == mode) {
            studioState.syncStatusProperty().set("键盘已在 " + mode.getTitle() + "。");
            return;
        }
        if (!modeSwitchInProgress.compareAndSet(false, true)) {
            studioState.syncStatusProperty().set("正在确认键盘模式，请稍候。");
            return;
        }
        studioState.modeSwitchingProperty().set(true);
        pendingModeSwitchTarget = mode;
        suppressModeStatusUntilMillis = 0;
        studioState.setSelectedMode(mode);
        studioState.syncStatusProperty().set("正在切换到 " + mode.getTitle() + "...");
        Thread thread = new Thread(() -> {
            try {
                int confirmedIndex = bleManager.setWorkModeAndVerify(mode.getIndex());
                ModeSlot confirmedMode = ModeSlot.fromIndex(confirmedIndex);
                Platform.runLater(() -> {
                    deviceStatus.setWorkMode(confirmedIndex);
                    studioState.setSelectedMode(confirmedMode);
                    studioState.syncStatusProperty().set("已切换到 " + confirmedMode.getTitle() + "。");
                    pendingModeSwitchTarget = confirmedMode;
                    suppressModeStatusUntilMillis = System.currentTimeMillis() + MODE_SWITCH_STATUS_SETTLE_MS;
                    studioState.modeSwitchingProperty().set(false);
                    modeSwitchInProgress.set(false);
                });
            } catch (Exception e) {
                logger.warn("Mode switch failed: target={}, previous={}, reason={}", mode, previousMode, e.getMessage());
                Platform.runLater(() -> {
                    ModeSlot authoritative = ModeSlot.fromIndex(deviceStatus.getWorkMode());
                    DeviceStatus cached = bleManager.getCachedStatus();
                    if (cached != null && cached.isConnected()) {
                        authoritative = ModeSlot.fromIndex(cached.getWorkMode());
                        deviceStatus.setWorkMode(cached.getWorkMode());
                    }
                    studioState.setSelectedMode(authoritative);
                    if (!deviceStatus.isConnected() || !bleManager.isConnected()) {
                        studioState.syncStatusProperty().set("连接中断，键盘模式未确认");
                    } else {
                        studioState.syncStatusProperty().set("未切换到 " + mode.getTitle() + "，键盘仍在 " + authoritative.getTitle() + "，请重试");
                    }
                    clearModeSwitchStatusGuard();
                    studioState.modeSwitchingProperty().set(false);
                    modeSwitchInProgress.set(false);
                });
            }
        }, "mode-switch-confirm");
        thread.setDaemon(true);
        thread.start();
    }

    public void enterEditingConfiguration() {
        if (!deviceStatus.isConnected() && !simulateBle) {
            enterEditingAfterConnect = true;
            studioState.syncStatusProperty().set("正在连接键盘以进入编辑配置...");
            userConnect();
            return;
        }
        activateConfigurationEditing();
    }

    private void activateConfigurationEditing() {
        agentManager.setBluetoothOwner(AgentManager.BluetoothOwner.AHAKEY_STUDIO);
        studioState.syncStatusProperty().set("已进入编辑配置模式。");
        refreshVoiceRoutes();
    }

    public void finishEditingConfiguration() {
        if (!hasUnsyncedChanges()) {
            returnToKeyboardControl();
            return;
        }
        if (deviceStatus.isConnected() || simulateBle) {
            syncAllModes(true);
        } else {
            studioState.syncStatusProperty().set("连接键盘后可保存/应用");
        }
    }

    public void returnToKeyboardControl() {
        agentManager.setBluetoothOwner(AgentManager.BluetoothOwner.KEYBOARD_DEVICE);
        studioState.syncStatusProperty().set("已交还控制权给键盘设备，连接保持。");
        // 保持 BLE 连接不断开，避免用户需要重新连接
    }

    public void syncAllModes(boolean returnToAgentWhenDone) {
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("连接键盘后可保存/应用");
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
                if (studioState.isCp4cInputConfigEnabled()) {
                    verifyCp4cInputSave(returnToAgentWhenDone);
                } else {
                    studioState.clearDirtyAfterSync();
                    lastSyncedRevision = studioState.getRevision();
                    studioState.syncingProperty().set(false);
                    studioState.syncStatusProperty().set("已保存配置。");
                    bleManager.queryStatus();
                    if (returnToAgentWhenDone) {
                        returnToKeyboardControl();
                    }
                }
            }),
            () -> Platform.runLater(() -> studioState.syncingProperty().set(false)),
            msg -> Platform.runLater(() -> studioState.syncStatusProperty().set(msg))
        );
    }
    public void previewLightOnDevice() {
        LightBarPreviewState preview = studioState.getLightBarPreview();
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("连接键盘后可测试/保存");
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
            studioState.syncStatusProperty().set("连接键盘后可测试/保存");
            return;
        }
        if (!simulateBle) {
            bleManager.setLightEffect(effect.getCode());
        }
        studioState.syncStatusProperty().set("已发送灯效测试：" + effect.getTitle());
    }

    public void sendLightBrightnessToDevice() {
        if (!deviceStatus.isConnected() && !simulateBle) {
            studioState.syncStatusProperty().set("连接键盘后可测试/保存");
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
            studioState.syncStatusProperty().set("连接键盘后可保存/应用");
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
            studioState.syncStatusProperty().set("连接键盘后可保存/应用");
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
            studioState.syncStatusProperty().set("连接键盘后可保存/应用");
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
        deviceStatus.setFirmwareMain(status.getFirmwareMain());
        deviceStatus.setFirmwareSub(status.getFirmwareSub());
        deviceStatus.setFirmwareCatalogKey(status.getFirmwareCatalogKey());
        deviceStatus.setSwitchState(status.getSwitchState());
        requestFirmwareCatalogKeyAfterConnect();
        ModeSlot deviceMode = ModeSlot.fromIndex(status.getWorkMode());
        ModeSlot previousMode = studioState.getSelectedMode();
        boolean suppressModeStatus = status.isConnected() && shouldSuppressModeStatus(deviceMode);
        if (!suppressModeStatus) {
            deviceStatus.setWorkMode(status.getWorkMode());
        }
        if (status.isConnected() && deviceMode != previousMode && !suppressModeStatus) {
            studioState.setSelectedMode(deviceMode);
            clearModeSwitchStatusGuard();
            if (studioState.hasUnsavedDraft(previousMode)) {
                studioState.syncStatusProperty().set("键盘已切到 " + deviceMode.getTitle() + "，" + previousMode.getTitle() + " 的未保存草稿已保留");
            } else {
                studioState.syncStatusProperty().set("键盘已切到 " + deviceMode.getTitle() + "。");
            }
        }
    }

    private boolean shouldSuppressModeStatus(ModeSlot deviceMode) {
        ModeSlot target = pendingModeSwitchTarget;
        if (target == null) {
            return false;
        }
        if (deviceMode == target) {
            if (!modeSwitchInProgress.get() && System.currentTimeMillis() >= suppressModeStatusUntilMillis) {
                clearModeSwitchStatusGuard();
            }
            return false;
        }
        long now = System.currentTimeMillis();
        return modeSwitchInProgress.get() || now < suppressModeStatusUntilMillis;
    }

    private void clearModeSwitchStatusGuard() {
        pendingModeSwitchTarget = null;
        suppressModeStatusUntilMillis = 0;
    }

    private void requestFirmwareCatalogKeyAfterConnect() {
        if (!deviceStatus.isConnected() || firmwareCatalogKeyRequested || !deviceStatus.getFirmwareCatalogKey().isBlank()) {
            return;
        }
        firmwareCatalogKeyRequested = true;
        new Thread(() -> {
            try {
                String catalogKey = bleManager.readFirmwareCatalogKey();
                handleFirmwareCatalogKey(catalogKey);
            } catch (Exception e) {
                logger.info("Firmware catalog key read skipped/fallback: {}", e.getMessage());
                Platform.runLater(() -> studioState.setCp4cInputConfigEnabled(false));
            }
        }, "firmware-catalog-key-connect-read").start();
    }

    private void handleFirmwareCatalogKey(String catalogKey) {
        if (!AhaKeyProtocol.isCp4cCatalogKey(catalogKey)) {
            Platform.runLater(() -> studioState.setCp4cInputConfigEnabled(false));
            return;
        }
        Platform.runLater(() -> {
            studioState.setCp4cInputConfigEnabled(true);
            studioState.setInputReadbackStatus("已识别 CP4C 固件，正在读取输入配置...");
        });
        aiRuntimeDisplayService.onDeviceReady();
        if (aiRuntimeDisplayService.getDisplayMode() == AiRuntimeDisplayMode.MULTI && isAiRuntimeHookLatest()) {
            new Thread(() -> {
                try {
                    aiRuntimeDisplayService.applyToKeyboard();
                } catch (Exception e) {
                    logger.warn("Apply MULTI runtime snapshot after firmware identity failed: {}", e.getMessage());
                }
            }, "ai-runtime-connect-snapshot").start();
        }
        startCp4cInputReadback(catalogKey);
    }

    private void startCp4cInputReadback(String catalogKey) {
        if (!cp4cInputReadbackInProgress.compareAndSet(false, true)) {
            return;
        }
        new Thread(() -> {
            try {
                Platform.runLater(() -> studioState.setInputReadbackInProgress(true));
                AhaKeyResponseParser.SideSwitchConfig sideSwitch = bleManager.readSideSwitchConfig();
                Platform.runLater(() -> {
                    studioState.applySideSwitchReadback(sideSwitch);
                    studioState.setInputFailureStatus("");
                    studioState.setInputReadbackStatus("已读取侧拨配置，正在读取当前模式普通键...");
                });

                ModeSlot currentMode = ModeSlot.fromIndex(deviceStatus.getWorkMode());
                boolean ordinaryReadbackComplete = readCp4cModeKeys(catalogKey, currentMode);
                for (ModeSlot mode : ModeSlot.values()) {
                    if (mode != currentMode) {
                        ordinaryReadbackComplete &= readCp4cModeKeys(catalogKey, mode);
                    }
                }
                boolean finalOrdinaryReadbackComplete = ordinaryReadbackComplete;
                Platform.runLater(() -> {
                    studioState.setInputReadbackInProgress(false);
                    if (!finalOrdinaryReadbackComplete) {
                        studioState.setInputReadbackStatus("已读取侧拨配置，部分普通键未完整读回。");
                        studioState.setInputFailureStatus("部分普通键配置读取失败；相关键位保持未确认状态。");
                        return;
                    }
                    studioState.setInputFailureStatus("");
                    studioState.setInputReadbackStatus("已读取 CP4C 输入配置。");
                });
            } catch (Exception e) {
                logCp4cInputIssue(catalogKey, "0x97/0x87", -1, -1, "connect-readback", e.getMessage());
                Platform.runLater(() -> {
                    studioState.setInputReadbackInProgress(false);
                    studioState.setInputFailureStatus("输入配置读取失败：" + e.getMessage());
                    studioState.syncStatusProperty().set("输入配置读取失败，旧草稿已保留。");
                });
            } finally {
                cp4cInputReadbackInProgress.set(false);
            }
        }, "cp4c-input-readback").start();
    }

    private boolean readCp4cModeKeys(String catalogKey, ModeSlot mode) {
        boolean complete = true;
        for (StudioPart part : new StudioPart[]{StudioPart.KEY1, StudioPart.KEY2, StudioPart.KEY3, StudioPart.KEY4}) {
            int keyIndex = StudioState.keyIndexFor(part);
            try {
                AhaKeyResponseParser.OrdinaryKeyReadback readback = bleManager.readOrdinaryKeyConfig(mode.getIndex(), keyIndex);
                Platform.runLater(() -> studioState.applyOrdinaryKeyReadback(readback));
            } catch (Exception e) {
                logCp4cInputIssue(catalogKey, "0x87", mode.getIndex(), keyIndex, "connect-readback", e.getMessage());
                complete = false;
            }
        }
        if (complete) {
            Platform.runLater(() -> studioState.markInputModeRead(mode));
        }
        return complete;
    }

    private void verifyCp4cInputSave(boolean returnToAgentWhenDone) {
        new Thread(() -> {
            String catalogKey = deviceStatus.getFirmwareCatalogKey();
            try {
                Platform.runLater(() -> studioState.syncStatusProperty().set("正在回读确认 CP4C 输入配置..."));
                if (studioState.isDirty(StudioPart.TOGGLE_SWITCH)) {
                    bleManager.writeSideSwitchConfig(studioState.getSideSwitchConfig());
                }
                verifyCp4cSideSwitch(catalogKey);
                verifyCp4cOrdinaryKeys(catalogKey);
                Platform.runLater(() -> {
                    studioState.clearDirtyAfterSync();
                    lastSyncedRevision = studioState.getRevision();
                    studioState.syncingProperty().set(false);
                    studioState.setInputFailureStatus("");
                    studioState.syncStatusProperty().set("已保存配置，并完成 CP4C 输入回读确认。");
                    bleManager.queryStatus();
                    if (returnToAgentWhenDone) {
                        returnToKeyboardControl();
                    }
                });
            } catch (Exception e) {
                Platform.runLater(() -> {
                    studioState.syncingProperty().set(false);
                    studioState.setInputFailureStatus("保存后回读确认失败：" + e.getMessage());
                    studioState.syncStatusProperty().set("保存未确认：" + e.getMessage() + "。未确认草稿已保留。");
                });
            }
        }, "cp4c-input-save-verify").start();
    }

    private void verifyCp4cSideSwitch(String catalogKey) throws Exception {
        AhaKeyResponseParser.SideSwitchConfig expected = studioState.getSideSwitchConfig();
        AhaKeyResponseParser.SideSwitchConfig actual;
        try {
            actual = bleManager.readSideSwitchConfig();
        } catch (Exception e) {
            logCp4cInputIssue(catalogKey, "0x97", -1, -1, "save-readback", e.getMessage());
            throw e;
        }
        if (!sideSwitchConfigMatches(expected, actual)) {
            logCp4cInputIssue(catalogKey, "0x97", -1, -1, "save-compare", "side switch mismatch");
            throw new IllegalStateException("侧拨配置回读不匹配");
        }
        Platform.runLater(() -> studioState.applySideSwitchReadback(actual));
    }

    private void verifyCp4cOrdinaryKeys(String catalogKey) throws Exception {
        for (ModeSlot mode : ModeSlot.values()) {
            for (StudioPart part : new StudioPart[]{StudioPart.KEY1, StudioPart.KEY2, StudioPart.KEY3, StudioPart.KEY4}) {
                int keyIndex = StudioState.keyIndexFor(part);
                AhaKeyResponseParser.OrdinaryKeyReadback readback;
                try {
                    readback = bleManager.readOrdinaryKeyConfig(mode.getIndex(), keyIndex);
                } catch (Exception e) {
                    logCp4cInputIssue(catalogKey, "0x87", mode.getIndex(), keyIndex, "save-readback", e.getMessage());
                    throw e;
                }
                if (!DeviceSyncService.matchesReadback(studioState.getKeyConfig(mode, part), readback)) {
                    logCp4cInputIssue(catalogKey, "0x87", mode.getIndex(), keyIndex, "save-compare", "ordinary key mismatch");
                    throw new IllegalStateException(mode.getTitle() + " " + part.getTitle() + " 回读不匹配");
                }
                Platform.runLater(() -> studioState.applyOrdinaryKeyReadback(readback));
            }
            Platform.runLater(() -> studioState.markInputModeRead(mode));
        }
    }

    private boolean sideSwitchConfigMatches(AhaKeyResponseParser.SideSwitchConfig expected, AhaKeyResponseParser.SideSwitchConfig actual) {
        return sideSwitchPositionMatches(expected.up(), actual.up())
            && sideSwitchPositionMatches(expected.down(), actual.down());
    }

    private boolean sideSwitchPositionMatches(
        AhaKeyResponseParser.SideSwitchPositionConfig expected,
        AhaKeyResponseParser.SideSwitchPositionConfig actual
    ) {
        return expected.binding() == actual.binding()
            && java.util.Arrays.equals(expected.actionPayload(), actual.actionPayload());
    }

    private void logCp4cInputIssue(String catalogKey, String cmd, int mode, int keyIndex, String phase, String reason) {
        logger.warn("CP4C_INPUT_FAILURE catalogKey={} cmd={} mode={} keyIndex={} phase={} reason={}",
            catalogKey, cmd, mode, keyIndex, phase, reason);
    }

    private void persistDraft() {
        StudioStore.save(studioState.toPersisted());
    }
}

