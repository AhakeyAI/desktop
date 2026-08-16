package com.example.ahakey.view;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.firmware.FirmwareFlasher;
import com.example.ahakey.firmware.WindowsWchIspFlasher;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.update.AssetDownloader;
import com.example.ahakey.update.SemanticVersion;
import com.example.ahakey.update.StableReleaseClient;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.scene.control.Alert;
import javafx.scene.control.Button;
import javafx.scene.control.CheckBox;
import javafx.scene.control.Label;
import javafx.scene.control.ProgressBar;
import javafx.scene.control.TitledPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;
import javafx.stage.FileChooser;
import javafx.stage.Stage;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.Optional;

/** Firmware management and USB-only device factory reset cards. */
public final class DeviceMaintenancePane {
    static final String BUNDLED_FIRMWARE_VERSION = "1.4.0";
    static final String BUNDLED_FIRMWARE_NAME =
        "AhaKey-X1-firmware-" + BUNDLED_FIRMWARE_VERSION + "-ch582.hex";
    private final StudioController controller;
    private final BleManager bleManager;
    private final DeviceStatus deviceStatus;
    private final boolean chinese =
        Locale.getDefault().getLanguage().equalsIgnoreCase("zh");

    public DeviceMaintenancePane(StudioController controller) {
        this.controller = controller;
        this.bleManager = controller.getBleManager();
        this.deviceStatus = controller.getDeviceStatus();
    }

    public VBox create(Stage owner) {
        return new VBox(12, firmwareCard(owner), resetCard(owner));
    }

    private VBox firmwareCard(Stage owner) {
        VBox card = card();
        Label title = title(text("固件管理（CH582）", "Firmware Management (CH582)"));
        Label description = body(text(
            "支持安装包内置固件、ahakey.com 最新固件和本地 .hex。普通更新保留设备数据。",
            "Use bundled, latest ahakey.com, or local .hex firmware. Normal updates preserve device data."
        ));
        Label selected = body(text("尚未选择固件", "No firmware selected"));
        Label status = body(text(
            "烧录前：断开设备，按住最左侧“语音输入键”，再插入 USB。",
            "Before flashing: unplug, hold the leftmost Voice Input key, then connect USB."
        ));
        ProgressBar progress = new ProgressBar(0);
        progress.setMaxWidth(Double.MAX_VALUE);
        progress.setVisible(false);
        progress.setManaged(false);

        CheckBox allowDowngrade = new CheckBox(text(
            "高级选项：我了解风险，允许降级",
            "Advanced: I understand the risk and allow downgrade"
        ));
        CheckBox allowUnknown = new CheckBox(text(
            "我了解本地固件版本未知的风险",
            "I understand the risk of unknown local firmware"
        ));
        allowUnknown.setVisible(false);
        allowUnknown.setManaged(false);

        final Path[] firmware = {null};
        final SemanticVersion[] targetVersion = {null};
        final SemanticVersion[] currentVersion = {
            controller.getLastKnownFirmwareVersion()
        };
        final SemanticVersion[] pendingFlashVersion = {
            controller.getPendingFirmwareVersion()
        };
        final boolean[] unknownVersion = {false};
        final boolean[] environmentReady = {false};
        final TitledPane[] steps = new TitledPane[4];
        final String[] diagnosticReport = {""};

        Button bundled = new Button(text(
            "选择内置 " + BUNDLED_FIRMWARE_VERSION,
            "Bundled " + BUNDLED_FIRMWARE_VERSION
        ));
        Button latest = new Button(text("下载最新固件", "Download Latest"));
        Button local = new Button(text("选择本地 .hex", "Choose Local .hex"));
        Button flash = new Button(text("开始烧录", "Flash Firmware"));
        Button readDeviceVersion = new Button(text("读取设备版本", "Read Device Version"));
        Label detectedVersion = body(text(
            "当前设备固件：尚未读取",
            "Current device firmware: not read"
        ));
        detectedVersion.setWrapText(true);
        if (currentVersion[0] != null) {
            detectedVersion.setText(text(
                "当前设备固件（已缓存）：",
                "Current device firmware (cached): "
            ) + currentVersion[0]);
        }
        flash.getStyleClass().add("button-prominent");
        flash.setDisable(true);
        Label flashRequirement = body("");

        Runnable updateFlashState = () -> {
            String block = flashBlockReason(
                firmware[0] != null,
                targetVersion[0],
                currentVersion[0],
                unknownVersion[0],
                allowUnknown.isSelected(),
                allowDowngrade.isSelected()
            );
            flash.setDisable(!canStartFlash(block, environmentReady[0]));
            flashRequirement.setText(switch (block) {
                case "FIRMWARE_REQUIRED" -> text(
                    "请先在第 2 步选择固件。",
                    "Choose firmware in step 2 first.");
                case "UNKNOWN_CONFIRMATION_REQUIRED" -> text(
                    "本地固件版本未知，需要勾选风险确认。",
                    "Confirm the risk for unknown local firmware.");
                case "CURRENT_VERSION_REQUIRED" -> text(
                    "请先在普通连接模式完成第 1 步版本读取。",
                    "Read the device version in normal mode in step 1 first.");
                case "DOWNGRADE_CONFIRMATION_REQUIRED" -> text(
                    "检测到固件降级，默认禁止。",
                    "Firmware downgrade detected and blocked by default.");
                default -> environmentReady[0] ? text(
                    "条件已满足，可以开始烧录。",
                    "All prerequisites are satisfied; flashing is ready.") : text(
                    "请先完成第 3 步烧录环境检查。",
                    "Complete the flash environment check in step 3.");
            });
            if (block.isEmpty() && environmentReady[0]) {
                expandStep(steps, 3);
            }
        };
        allowUnknown.selectedProperty().addListener((o, a, b) -> updateFlashState.run());
        allowDowngrade.selectedProperty().addListener((o, a, b) -> updateFlashState.run());

        readDeviceVersion.setOnAction(event -> {
            if (!deviceStatus.isConnected()) {
                detectedVersion.setText(text(
                    "当前设备固件：请先正常连接设备",
                    "Current device firmware: connect the device normally first"
                ));
                return;
            }
            readDeviceVersion.setDisable(true);
            detectedVersion.setText(text(
                "当前设备固件：正在读取…",
                "Current device firmware: reading…"
            ));
            daemon("firmware-read-version", () -> {
                try {
                    var caps = bleManager.queryDeviceCapabilities();
                    if (caps == null) {
                        throw new IllegalStateException(text(
                            "设备未返回有效的 0x9F 版本信息",
                            "The device did not return valid 0x9F version information"
                        ));
                    }
                    SemanticVersion version = new SemanticVersion(
                        caps.firmwareMajor(),
                        caps.firmwareMinor(),
                        caps.firmwarePatch()
                    );
                    currentVersion[0] = version;
                    controller.setLastKnownFirmwareVersion(version);
                    String value = text("当前设备固件：", "Current device firmware: ")
                        + version
                        + text("；协议 ", "; protocol ")
                        + caps.protocolMajor() + "." + caps.protocolMinor()
                        + text("；能力位 0x", "; capabilities 0x")
                        + String.format("%08X", caps.capabilityBits());
                    Platform.runLater(() -> {
                        detectedVersion.setText(value);
                        updateFlashState.run();
                        expandStep(steps, 1);
                        SemanticVersion expected = controller.getPendingFirmwareVersion();
                        if (expected == null) {
                            return;
                        }
                        pendingFlashVersion[0] = null;
                        controller.setPendingFirmwareVersion(null);
                        if (expected.equals(version)) {
                            status.setText(text(
                                "固件升级成功，设备当前版本为 ",
                                "Firmware update succeeded; device version is "
                            ) + version);
                            show(owner, Alert.AlertType.INFORMATION,
                                text("固件升级成功", "Firmware Update Succeeded"),
                                text("已从设备读取到目标版本 ", "The device reported target version ")
                                    + expected + "。");
                        } else {
                            status.setText(text(
                                "烧录未生效：目标版本 ",
                                "Flash did not take effect: target "
                            ) + expected + text("，设备仍为 ", ", device still reports ")
                                + version);
                            show(owner, Alert.AlertType.ERROR,
                                text("固件升级未生效", "Firmware Update Did Not Take Effect"),
                                text("目标版本为 ", "Target version is ") + expected
                                    + text("，但设备返回 ", ", but the device reported ")
                                    + version + "。\n\n"
                                    + text(
                                        "请重新进入 ISP 模式后点击“重新烧录”。",
                                        "Re-enter ISP mode and click Flash Firmware again."
                                    ));
                        }
                    });
                } catch (Exception exception) {
                    Platform.runLater(() -> detectedVersion.setText(
                        text("版本读取失败：", "Version read failed: ")
                            + exception.getMessage()
                    ));
                } finally {
                    Platform.runLater(() -> readDeviceVersion.setDisable(false));
                }
            });
        });

        bundled.setOnAction(event -> {
            Path path = bundledFirmwarePath();
            if (!Files.isRegularFile(path)) {
                show(owner, Alert.AlertType.WARNING,
                    text("内置固件尚未生成", "Bundled Firmware Missing"),
                    text("请先执行安全发布构建，将 " + BUNDLED_FIRMWARE_VERSION + " 固件放入安装包。",
                        "Run the safe release build and include firmware "
                            + BUNDLED_FIRMWARE_VERSION + " first."));
                return;
            }
            firmware[0] = path;
            targetVersion[0] = SemanticVersion.parse(BUNDLED_FIRMWARE_VERSION);
            currentVersion[0] = controller.getLastKnownFirmwareVersion();
            unknownVersion[0] = false;
            allowUnknown.setVisible(false);
            allowUnknown.setManaged(false);
            selected.setText(path.getFileName().toString());
            expandStep(steps, 2);
            updateFlashState.run();
        });

        local.setOnAction(event -> {
            FileChooser chooser = new FileChooser();
            chooser.setTitle(text("选择 CH582 固件", "Choose CH582 Firmware"));
            chooser.getExtensionFilters().add(
                new FileChooser.ExtensionFilter("Intel HEX (*.hex)", "*.hex")
            );
            var chosen = chooser.showOpenDialog(owner);
            if (chosen == null) {
                return;
            }
            firmware[0] = chosen.toPath();
            targetVersion[0] = versionFromFilename(chosen.getName()).orElse(null);
            currentVersion[0] = controller.getLastKnownFirmwareVersion();
            unknownVersion[0] = targetVersion[0] == null;
            allowUnknown.setSelected(false);
            allowUnknown.setVisible(unknownVersion[0]);
            allowUnknown.setManaged(unknownVersion[0]);
            selected.setText(chosen.getName());
            expandStep(steps, 2);
            updateFlashState.run();
        });

        latest.setOnAction(event -> {
            setBusy(true, progress, bundled, latest, local, flash);
            status.setText(text(
                "正在读取 ahakey.com 稳定版本…",
                "Checking the ahakey.com stable release…"));
            daemon("firmware-release", () -> {
                try {
                    var release = new StableReleaseClient().fetchLatest()
                        .orElseThrow(() -> new IllegalStateException("尚未发布稳定版本"));
                    var asset = release.ch582Firmware()
                        .orElseThrow(() -> new IllegalStateException("稳定版本中没有 CH582 固件"));
                    Path destination = Path.of(
                        System.getProperty("user.home"), ".ahakey", "downloads",
                        asset.asset().name()
                    );
                    new AssetDownloader().download(
                        asset.asset(),
                        destination,
                        (done, total) -> Platform.runLater(() ->
                            progress.setProgress(total > 0 ? (double) done / total : -1))
                    );
                    Platform.runLater(() -> {
                        firmware[0] = destination;
                        targetVersion[0] = asset.version();
                        currentVersion[0] = controller.getLastKnownFirmwareVersion();
                        unknownVersion[0] = false;
                        allowUnknown.setVisible(false);
                        allowUnknown.setManaged(false);
                        selected.setText(asset.asset().name());
                        expandStep(steps, 2);
                        status.setText(text(
                            "下载完成并通过固件格式检查。",
                            "Downloaded and firmware format validated."));
                        setBusy(false, progress, bundled, latest, local, flash);
                        updateFlashState.run();
                    });
                } catch (Exception exception) {
                    Platform.runLater(() -> {
                        status.setText(text("下载失败：", "Download failed: ") + exception.getMessage());
                        setBusy(false, progress, bundled, latest, local, flash);
                        updateFlashState.run();
                    });
                }
            });
        });

        flash.setOnAction(event -> {
            if (!environmentReady[0]) {
                expandStep(steps, 2);
                updateFlashState.run();
                return;
            }
            if (!isVersionAllowed(
                owner, targetVersion[0], currentVersion[0],
                allowDowngrade.isSelected()
            )) {
                return;
            }
            FirmwareFlasher flasher = new WindowsWchIspFlasher();
            expandStep(steps, 3);
            setBusy(true, progress, bundled, latest, local, flash);
            status.setText(text("正在调用 WCHISP…", "Starting WCHISP…"));
            Path selectedFirmware = firmware[0];
            daemon("firmware-flash", () -> {
                try {
                    FirmwareFlasher.FlashResult result = flasher.flashAndVerify(
                        selectedFirmware,
                        (stage, value, detail) -> Platform.runLater(() -> {
                            progress.setProgress(value);
                            status.setText(detail);
                        })
                    );
                    Platform.runLater(() -> {
                        environmentReady[0] = false;
                        setBusy(false, progress, bundled, latest, local, flash);
                        updateFlashState.run();
                        if (result.success()) {
                            pendingFlashVersion[0] = targetVersion[0];
                            controller.setPendingFirmwareVersion(targetVersion[0]);
                            status.setText(text(
                                "WCHISP 已确认写入成功；请正常重连并读取设备版本。",
                                "WCHISP confirmed the write; reconnect normally and read the device version."
                            ));
                            show(owner, Alert.AlertType.INFORMATION,
                                text("等待设备版本确认", "Waiting for Device Version Confirmation"),
                                text(
                                    "WCHISP 已返回 Finished / Code 0 / Succeed，写入和字节校验完成。"
                                        + "请断开 USB 后正常重新连接，再点击“读取设备版本”。"
                                        + "只有客户端读取到目标版本，才显示升级成功。",
                                    "WCHISP returned Finished / Code 0 / Succeed, confirming the "
                                        + "write and byte verification. "
                                        + "Disconnect USB, reconnect normally, and click Read Device "
                                        + "Version. Success is shown only after the app reads the target version."
                                ));
                        } else {
                            expandStep(steps, 2);
                            show(owner, Alert.AlertType.ERROR,
                                text("固件更新失败", "Firmware Update Failed"),
                                result.detail() + "\n\n" + text(
                                    "请检查步骤后手动点击“重新烧录”。",
                                    "Check the steps, then click Flash Firmware again."
                                ));
                        }
                    });
                } catch (Exception exception) {
                    Platform.runLater(() -> {
                        environmentReady[0] = false;
                        setBusy(false, progress, bundled, latest, local, flash);
                        updateFlashState.run();
                        expandStep(steps, 2);
                        show(owner, Alert.AlertType.ERROR,
                            text("固件更新失败", "Firmware Update Failed"),
                            exception.getMessage());
                    });
                }
            });
        });

        Label ispStatus = body("");
        Button diagnose = new Button(text(
            "检测烧录环境和 ISP", "Check Environment and ISP"));
        Button exportDiagnostic = new Button(text("导出诊断报告", "Export Diagnostic Report"));
        exportDiagnostic.setDisable(true);
        diagnose.setOnAction(event -> {
            environmentReady[0] = false;
            updateFlashState.run();
            diagnose.setDisable(true);
            ispStatus.setText(text("正在检查 WCHISP 工具、配置和 CH582 ISP 设备…",
                "Checking WCHISP tools, configuration, and the CH582 ISP device…"));
            daemon("wchisp-diagnostics", () -> {
                WindowsWchIspFlasher tool = new WindowsWchIspFlasher();
                StringBuilder report = new StringBuilder("AhaKey WCHISP diagnostics\n");
                boolean ready = false;
                try {
                    var environment = tool.diagnoseEnvironment();
                    environment.checks().forEach(line -> report.append(line).append('\n'));
                    if (environment.ready()) {
                        var device = tool.detect();
                        ready = device.bootloaderPresent();
                        report.append(ready
                            ? text("[通过] 已检测到 CH582 ISP 设备\n",
                                "[PASS] CH582 ISP device detected\n")
                            : text("[失败] 未检测到 CH582 ISP 设备\n",
                                "[FAIL] CH582 ISP device not detected\n"));
                        if (device.detail() != null && !device.detail().isBlank()) {
                            report.append(device.detail()).append('\n');
                        }
                    }
                } catch (Exception exception) {
                    report.append("[失败] ").append(exception.getMessage()).append('\n');
                }
                diagnosticReport[0] = report.toString();
                boolean readyResult = ready;
                Platform.runLater(() -> {
                    diagnose.setDisable(false);
                    exportDiagnostic.setDisable(false);
                    ispStatus.setText(diagnosticReport[0]);
                    environmentReady[0] = readyResult;
                    updateFlashState.run();
                });
            });
        });
        exportDiagnostic.setOnAction(event -> {
            FileChooser chooser = new FileChooser();
            chooser.setTitle(text("导出烧录诊断报告", "Export Flash Diagnostics"));
            chooser.setInitialFileName("ahakey-wchisp-diagnostics.txt");
            var file = chooser.showSaveDialog(owner);
            if (file == null) return;
            try {
                Files.writeString(file.toPath(), diagnosticReport[0],
                    java.nio.charset.StandardCharsets.UTF_8);
            } catch (Exception exception) {
                show(owner, Alert.AlertType.ERROR,
                    text("导出失败", "Export Failed"), exception.getMessage());
            }
        });

        HBox sources = new HBox(8, bundled, latest, local);
        HBox version = new HBox(8, readDeviceVersion, detectedVersion);
        HBox.setHgrow(detectedVersion, Priority.ALWAYS);
        steps[0] = step(text("1. 读取设备版本", "1. Read Device Version"), version, true);
        steps[1] = step(text("2. 选择固件", "2. Choose Firmware"),
            new VBox(8, sources, selected, allowUnknown, allowDowngrade), false);
        steps[2] = step(text("3. 进入 ISP 并检测", "3. Enter and Detect ISP"),
            new VBox(8, body(text(
                "断开 USB，按住最左侧“语音输入键”，再插入 USB；随后点击检测。",
                "Disconnect USB, hold the leftmost Voice Input key, reconnect USB, then run detection."
            )), new HBox(8, diagnose, exportDiagnostic), ispStatus), false);
        steps[3] = step(text("4. 烧录、校验并确认版本", "4. Flash, Verify, and Confirm"),
            new VBox(8, flash, flashRequirement, progress, status), false);
        card.getChildren().addAll(
            title, description, steps[0], steps[1], steps[2], steps[3]
        );
        updateFlashState.run();
        return card;
    }

    private VBox resetCard(Stage owner) {
        VBox card = card();
        Label title = title(text("危险操作：恢复初始化", "Danger: Factory Reset"));
        title.setStyle("-fx-text-fill: #d73a49;");
        Label description = body(text(
            "仅限 USB。将清除 GIF、用户配置、按键配置、待机时间、其他用户数据和蓝牙配对；保留固件版本、设备标识和 MAC。数据不可恢复。",
            "USB only. Erases GIFs, user/key settings, standby, other user data and Bluetooth bonds; preserves firmware, device identity and MAC. This cannot be undone."
        ));
        CheckBox understood = new CheckBox(text(
            "我已了解数据不可恢复",
            "I understand the data cannot be recovered"
        ));
        understood.getStyleClass().add("dialog-dark-check-box");
        Button reset = new Button(text("恢复初始化", "Factory Reset"));
        reset.setStyle("-fx-background-color: #d73a49; -fx-text-fill: white;");
        reset.disableProperty().bind(understood.selectedProperty().not());
        Button reconnect = new Button(text("重新检测 USB", "Detect USB Again"));
        reconnect.setVisible(false);
        reconnect.setManaged(false);
        Label status = body("");

        reconnect.setOnAction(event -> {
            reconnect.setDisable(true);
            status.setText(text("正在重新检测 USB…", "Detecting USB again…"));
            controller.userConnect();
            javafx.animation.PauseTransition delay =
                new javafx.animation.PauseTransition(javafx.util.Duration.seconds(2));
            delay.setOnFinished(done -> {
                reconnect.setDisable(false);
                if (bleManager.isUsbConnected()) {
                    reconnect.setVisible(false);
                    reconnect.setManaged(false);
                    status.setText(text("USB 已重新连接，可读取设备设置。",
                        "USB reconnected; device settings are available."));
                } else {
                    status.setText(text("仍未检测到 USB，请重新拔插后再试。",
                        "USB is still unavailable; reconnect the cable and try again."));
                }
            });
            delay.play();
        });

        reset.setOnAction(event -> {
            if (!bleManager.isUsbConnected()) {
                show(owner, Alert.AlertType.WARNING,
                    text("需要 USB 连接", "USB Required"),
                    text("恢复初始化不能通过 BLE 执行，请连接 USB 数据线。",
                        "Factory reset cannot run over BLE. Connect the USB cable."));
                return;
            }
            Alert confirmation = new Alert(Alert.AlertType.CONFIRMATION);
            confirmation.initOwner(owner);
            confirmation.setTitle(text("确认恢复初始化", "Confirm Factory Reset"));
            confirmation.setHeaderText(text("所有设备用户数据将被永久删除",
                "All device user data will be permanently erased"));
            confirmation.setContentText(text("确认后设备会重启，请保持 USB 连接。",
                "The device will reboot. Keep USB connected."));
            if (confirmation.showAndWait().filter(
                button -> button == javafx.scene.control.ButtonType.OK).isEmpty()) {
                return;
            }
            understood.setSelected(false);
            reconnect.setVisible(false);
            reconnect.setManaged(false);
            status.setText(text("正在发送恢复命令…", "Sending factory-reset command…"));
            daemon("factory-reset", () -> performFactoryReset(
                owner, understood, reconnect, status));
        });

        card.getChildren().addAll(title, description, understood,
            new HBox(8, reset, reconnect), status);
        return card;
    }

    private void performFactoryReset(
        Stage owner, CheckBox understood, Button reconnect, Label status
    ) {
        try {
            AhaKeyResponseParser.DeviceCapabilities capabilities =
                bleManager.queryDeviceCapabilities();
            if (capabilities == null
                || !capabilities.supports(AhaKeyProtocol.CAP_FACTORY_RESET_V1)) {
                throw new IllegalStateException("当前固件不支持安全恢复初始化，请先更新固件");
            }
            bleManager.factoryReset();
            Files.deleteIfExists(Path.of(
                System.getProperty("user.home"), ".ahakey", "studio-draft.json"
            ));
            Platform.runLater(() -> {
                controller.getStudioState().loadFromPersisted(
                    com.example.ahakey.util.StudioStore.loadOrDefault()
                );
                understood.setSelected(false);
                reconnect.setVisible(true);
                reconnect.setManaged(true);
                status.setText(text(
                    "设备已接受恢复命令。请重新拔插 USB 后点击“重新检测 USB”；蓝牙配对已清除，需要在 Windows 中删除旧 AhaKey 配对记录后重新配对。",
                    "The reset was accepted. Reconnect USB and click Detect USB Again. Bluetooth bonding was cleared; pair the keyboard again in Windows."
                ));
                show(owner, Alert.AlertType.INFORMATION,
                    text("恢复初始化命令已执行", "Factory Reset Accepted"),
                    text(
                        "客户端不会等待蓝牙自动重连。请重新拔插 USB。\n\n"
                            + BluetoothPairingGuide.WINDOWS_STEPS,
                        "The app will not wait for automatic Bluetooth reconnection. Reconnect USB and pair Bluetooth again."
                    ));
            });
        } catch (Exception exception) {
            Platform.runLater(() -> {
                status.setText(text("恢复失败：", "Reset failed: ") + exception.getMessage());
                show(owner, Alert.AlertType.ERROR,
                    text("恢复初始化失败", "Factory Reset Failed"),
                    exception.getMessage());
            });
        }
    }

    private boolean isVersionAllowed(
        Stage owner, SemanticVersion target, SemanticVersion cachedCurrent,
        boolean allowDowngrade
    ) {
        if (target == null) {
            return true;
        }
        // Step 4 runs while the keyboard is in ISP mode, where normal 0x9F
        // queries are unavailable. Only use the version captured in step 1.
        SemanticVersion current = cachedCurrent;
        if (current == null && !allowDowngrade) {
            show(owner, Alert.AlertType.WARNING,
                text("无法验证固件版本", "Cannot Verify Firmware Version"),
                text(
                    "请先在正常模式连接设备后选择固件；或在高级选项中确认风险后继续。",
                    "Connect the device in normal mode before choosing firmware, or explicitly accept the advanced risk."
                ));
            return false;
        }
        if (current != null && target.compareTo(current) < 0 && !allowDowngrade) {
            show(owner, Alert.AlertType.WARNING,
                text("已阻止固件降级", "Firmware Downgrade Blocked"),
                text("当前版本 ", "Current version ") + current
                    + text("，目标版本 ", ", target version ") + target
                    + text("。如确需降级，请勾选高级风险选项。",
                        ". Enable the advanced risk option to continue."));
            return false;
        }
        return true;
    }

    static String flashBlockReason(
        boolean firmwareSelected,
        SemanticVersion target,
        SemanticVersion current,
        boolean unknownVersion,
        boolean allowUnknown,
        boolean allowDowngrade
    ) {
        if (!firmwareSelected) {
            return "FIRMWARE_REQUIRED";
        }
        if (unknownVersion && !allowUnknown) {
            return "UNKNOWN_CONFIRMATION_REQUIRED";
        }
        if (target != null && current == null && !allowDowngrade) {
            return "CURRENT_VERSION_REQUIRED";
        }
        if (target != null && current != null
            && target.compareTo(current) < 0 && !allowDowngrade) {
            return "DOWNGRADE_CONFIRMATION_REQUIRED";
        }
        return "";
    }

    static boolean canStartFlash(String blockReason, boolean ispReady) {
        return blockReason != null && blockReason.isEmpty() && ispReady;
    }

    private SemanticVersion readCurrentVersion() {
        if (!deviceStatus.isConnected()) return null;
        try {
            var caps = bleManager.queryDeviceCapabilities();
            return caps == null ? null : new SemanticVersion(
                caps.firmwareMajor(), caps.firmwareMinor(), caps.firmwarePatch()
            );
        } catch (Exception ignored) {
            return null;
        }
    }

    private Path bundledFirmwarePath() {
        return bundledFirmwarePath(
            System.getProperty("jpackage.app-path", ""),
            Path.of("firmware", BUNDLED_FIRMWARE_NAME)
                .toAbsolutePath()
        );
    }

    static Path bundledFirmwarePath(String appPath, Path developmentFallback) {
        if (!appPath.isBlank()) {
            Path parent = Path.of(appPath).toAbsolutePath().getParent();
            if (parent != null) {
                Path packaged = parent.resolve("app").resolve("firmware")
                    .resolve(BUNDLED_FIRMWARE_NAME);
                if (Files.isRegularFile(packaged)) {
                    return packaged;
                }
                return parent.resolve("firmware")
                    .resolve(BUNDLED_FIRMWARE_NAME);
            }
        }
        return developmentFallback.toAbsolutePath();
    }

    private Optional<SemanticVersion> versionFromFilename(String filename) {
        String lower = filename.toLowerCase(Locale.ROOT);
        String prefix = "ahakey-x1-firmware-";
        String suffix = "-ch582.hex";
        if (!lower.startsWith(prefix) || !lower.endsWith(suffix)) {
            return Optional.empty();
        }
        try {
            return Optional.of(SemanticVersion.parse(
                filename.substring(prefix.length(), filename.length() - suffix.length())
            ));
        } catch (IllegalArgumentException ignored) {
            return Optional.empty();
        }
    }

    private VBox card() {
        VBox card = new VBox(9);
        card.getStyleClass().add("dialog-card");
        card.setPadding(new Insets(12));
        return card;
    }

    private TitledPane step(String title, javafx.scene.Node content, boolean expanded) {
        TitledPane pane = new TitledPane(title, content);
        pane.getStyleClass().add("maintenance-step");
        pane.setExpanded(expanded);
        pane.setAnimated(false);
        return pane;
    }

    private void expandStep(TitledPane[] steps, int selected) {
        if (steps[selected] == null) return;
        for (int index = 0; index < steps.length; index++) {
            if (steps[index] != null) steps[index].setExpanded(index == selected);
        }
    }

    private Label title(String text) {
        Label label = new Label(text);
        label.getStyleClass().add("dialog-card-title");
        return label;
    }

    private Label body(String text) {
        Label label = new Label(text);
        label.getStyleClass().add("dialog-text");
        label.setWrapText(true);
        return label;
    }

    private void setBusy(
        boolean busy, ProgressBar progress, Button... buttons
    ) {
        progress.setVisible(busy);
        progress.setManaged(busy);
        if (busy) {
            progress.setProgress(-1);
        }
        for (Button button : buttons) {
            button.setDisable(busy);
        }
    }

    private void show(Stage owner, Alert.AlertType type, String title, String detail) {
        Alert alert = new Alert(type);
        alert.initOwner(owner);
        alert.setTitle(title);
        alert.setHeaderText(null);
        alert.setContentText(detail);
        alert.showAndWait();
    }

    private void daemon(String name, Runnable task) {
        Thread thread = new Thread(task, name);
        thread.setDaemon(true);
        thread.start();
    }

    private String text(String zh, String en) {
        return chinese ? zh : en;
    }
}
