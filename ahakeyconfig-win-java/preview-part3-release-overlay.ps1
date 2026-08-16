param(
    [string]$BaselineAppDir = (Join-Path $env:ProgramFiles "AhaKeyStudio\app"),
    [string]$OutputRoot = "",
    [switch]$Launch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectDir = $PSScriptRoot
[xml]$pom = Get-Content -LiteralPath (Join-Path $projectDir "pom.xml") -Raw
$previewAppVersion = [string]$pom.project.version
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectDir "target\part3-release-preview"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

$baselineJar = Get-ChildItem -LiteralPath $BaselineAppDir `
    -Filter "ahakey-studio-*.jar" |
    Where-Object { $_.Name -notlike "*preview*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName
$baselineLibDir = Join-Path $BaselineAppDir "lib"
$baselineModelsDir = Join-Path $BaselineAppDir "models"

foreach ($required in @($baselineJar, $baselineLibDir, $baselineModelsDir)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing release baseline path: $required"
    }
}

$git = $null
$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if ($gitCommand) {
    $git = $gitCommand.Source
}
if (-not $git) {
    $bundledGit = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe"
    if (Test-Path -LiteralPath $bundledGit) {
        $git = $bundledGit
    }
}
if (-not $git) {
    throw "Git is required to materialize the release-baseline TopBar source."
}

$jdkCandidates = @()
if ($env:JAVA_HOME) {
    $jdkCandidates += Join-Path $env:JAVA_HOME "bin"
}
$jdkCandidates += Join-Path $env:LOCALAPPDATA "Temp\ahakey-part3-toolchain\jdk-17\bin"

$jdkBin = $jdkCandidates |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ "javac.exe") } |
    Select-Object -First 1
if (-not $jdkBin) {
    throw "JDK 17 is required. Set JAVA_HOME to a JDK 17 installation."
}

$javac = Join-Path $jdkBin "javac.exe"
$javaw = Join-Path (Split-Path -Parent $BaselineAppDir) "runtime\bin\javaw.exe"
if (-not (Test-Path -LiteralPath $javaw)) {
    $javaw = Join-Path $jdkBin "javaw.exe"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$buildDir = Join-Path $OutputRoot $timestamp
$classesDir = Join-Path $buildDir "classes"
$generatedSourceDir = Join-Path $buildDir "generated-source"
$emptySourcePath = Join-Path $buildDir "empty-sourcepath"
New-Item -ItemType Directory -Force -Path $classesDir, $generatedSourceDir, $emptySourcePath | Out-Null

$repoRoot = (& $git -C $projectDir rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
    throw "Unable to resolve repository root."
}

# The installed release TopBar matches this pre-localization source, except that
# the installed FloatingVoiceNotification uses its singleton accessor.
$topBarCommit = "4812844"
$topBarRepoPath = "ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/TopBar.java"
$topBarLines = & $git -C $repoRoot show "$topBarCommit`:$topBarRepoPath"
if ($LASTEXITCODE -ne 0 -or -not $topBarLines) {
    throw "Unable to read release-baseline TopBar source from $topBarCommit."
}
$topBarSource = [string]::Join([Environment]::NewLine, $topBarLines)

function Replace-ExactlyOnce {
    param(
        [string]$Text,
        [string]$OldValue,
        [string]$NewValue,
        [string]$Description
    )
    $count = [regex]::Matches($Text, [regex]::Escape($OldValue)).Count
    if ($count -ne 1) {
        throw "Baseline drift while applying $Description; expected one match, found $count."
    }
    return $Text.Replace($OldValue, $NewValue)
}

$topBarSource = Replace-ExactlyOnce `
    $topBarSource `
    "floatingNotification = new FloatingVoiceNotification();" `
    "floatingNotification = FloatingVoiceNotification.getInstance();" `
    "installed-release voice notification compatibility"

$batteryExpressionPattern =
    '\(\) -> controller\.isEffectivelyConnected\(\) \? deviceStatus\.getBatteryLevel\(\) \+ "%" : "[^"]*"'
if ([regex]::Matches($topBarSource, $batteryExpressionPattern).Count -ne 1) {
    throw "Baseline drift while applying transport-aware battery expression."
}
$topBarSource = [regex]::Replace(
    $topBarSource,
    $batteryExpressionPattern,
    '() -> formatBattery(deviceStatus)'
)
$batteryDependenciesPattern =
    'deviceStatus\.isConnectedProperty\(\),\s*\r?\n(\s*)deviceStatus\.batteryLevelProperty\(\)'
if ([regex]::Matches($topBarSource, $batteryDependenciesPattern).Count -ne 1) {
    throw "Baseline drift while applying transport-aware battery dependencies."
}
$batteryDependenciesReplacement =
    'deviceStatus.isConnectedProperty(),' + [Environment]::NewLine +
    '${1}deviceStatus.batteryLevelProperty(),' + [Environment]::NewLine +
    '${1}deviceStatus.transportProperty()'
$topBarSource = [regex]::Replace(
    $topBarSource,
    $batteryDependenciesPattern,
    $batteryDependenciesReplacement
)

$connectionNew = @"
        connStatus.textProperty().bind(Bindings.createStringBinding(() ->
            "\u8fde\u63a5: " + (this.deviceStatus.isConnected()
                ? "\u5df2\u8fde\u63a5 (" + this.deviceStatus.getTransport() + ")"
                : "\u672a\u8fde\u63a5"),
            this.deviceStatus.isConnectedProperty(),
            this.deviceStatus.transportProperty()
        ));
"@
$connectionPattern =
    '(?s)        connStatus\.textProperty\(\)\.bind\(Bindings\.createStringBinding\(\(\) ->\s*.*?this\.deviceStatus\.isConnectedProperty\(\)\s*\)\);'
if ([regex]::Matches($topBarSource, $connectionPattern).Count -ne 1) {
    throw "Baseline drift while applying transport label."
}
$topBarSource = [regex]::Replace(
    $topBarSource,
    $connectionPattern,
    $connectionNew.TrimEnd()
)

$dialogBatteryNew = @"
        batteryStatus.textProperty().bind(Bindings.createStringBinding(() ->
            "\u7535\u91cf: " + formatBattery(this.deviceStatus),
            this.deviceStatus.isConnectedProperty(),
            this.deviceStatus.batteryLevelProperty(),
            this.deviceStatus.transportProperty()
        ));
"@
$dialogBatteryPattern =
    '(?s)        batteryStatus\.textProperty\(\)\.bind\(Bindings\.createStringBinding\(\(\) ->\s*.*?this\.deviceStatus\.batteryLevelProperty\(\)\s*\)\);'
if ([regex]::Matches($topBarSource, $dialogBatteryPattern).Count -ne 1) {
    throw "Baseline drift while applying dialog battery display."
}
$topBarSource = [regex]::Replace(
    $topBarSource,
    $dialogBatteryPattern,
    $dialogBatteryNew.TrimEnd()
)

$voiceLampMarker = "    private class VoiceStatusLamp extends Canvas {"
$batteryFormatter = @"
    private static String formatBattery(DeviceStatus status) {
        if (!status.isConnected()) {
            return "\u2014";
        }
        if ("USB".equals(status.getTransport())) {
            return "USB \u4f9b\u7535";
        }
        int level = status.getBatteryLevel();
        return level >= 0 && level <= 100 ? level + "%" : "\u8bfb\u53d6\u4e2d";
    }

$voiceLampMarker
"@
$topBarSource = Replace-ExactlyOnce `
    $topBarSource $voiceLampMarker $batteryFormatter.TrimEnd() `
    "battery formatter"

$constructorMarker = "        initContent();"
$constructorReplacement = @"
        initContent();
        Platform.runLater(() -> {
            Stage owner = getScene() != null
                && getScene().getWindow() instanceof Stage
                ? (Stage) getScene().getWindow()
                : null;
            com.example.ahakey.update.AppUpdateCoordinator.onApplicationReady(owner);
            com.example.ahakey.update.FirmwareUpdateNotifier.checkWhenConnected(
                owner, controller.getBleManager(), deviceStatus
            );
        });
"@
$topBarSource = Replace-ExactlyOnce `
    $topBarSource `
    $constructorMarker `
    $constructorReplacement.TrimEnd() `
    "daily non-blocking update check"

$deviceCardMarker = "        deviceCard.getChildren().addAll(deviceTitle, deviceRow1, deviceRow2);"
$deviceCardReplacement = @"
$deviceCardMarker
        VBox standbyCard = new StandbySettingsPane(
            controller.getBleManager(),
            deviceStatus
        ).create(dialog);
        VBox maintenanceCards = new DeviceMaintenancePane(controller).create(dialog);
        VBox supportCard = new SupportPane().create();
"@
$topBarSource = Replace-ExactlyOnce `
    $topBarSource `
    $deviceCardMarker `
    $deviceCardReplacement.TrimEnd() `
    "standby settings card creation"

$contentMarker = "        content.getChildren().addAll(deviceCard, claudeCard, cursorCard, codexCard, kimiCard, logCard, actionButtons);"
$contentReplacement = @"
        content.getChildren().addAll(
            deviceCard,
            standbyCard,
            maintenanceCards,
            supportCard,
            claudeCard,
            cursorCard,
            codexCard,
            kimiCard,
            logCard,
            actionButtons
        );
"@
$topBarSource = Replace-ExactlyOnce `
    $topBarSource `
    $contentMarker `
    $contentReplacement.TrimEnd() `
    "standby settings card placement"

$versionDialogOld = "    private void showVersionDialog() {"
$versionDialogNew = @"
    private void showVersionDialog() {
        com.example.ahakey.update.AppUpdateCoordinator.showAboutAndCheck(
            (Stage) getScene().getWindow()
        );
    }

    private void showLegacyVersionDialog() {
"@
$topBarSource = Replace-ExactlyOnce `
    $topBarSource `
    $versionDialogOld `
    $versionDialogNew.TrimEnd() `
    "manual software update entry"

$generatedTopBar = Join-Path $generatedSourceDir "com\example\ahakey\view\TopBar.java"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $generatedTopBar) | Out-Null
[IO.File]::WriteAllText(
    $generatedTopBar,
    $topBarSource,
    [Text.UTF8Encoding]::new($false)
)

$controllerRepoPath = "ahakeyconfig-win-java/src/main/java/com/example/ahakey/app/StudioController.java"
$controllerLines = & $git -C $repoRoot show "$topBarCommit`:$controllerRepoPath"
if ($LASTEXITCODE -ne 0 -or -not $controllerLines) {
    throw "Unable to read release-baseline StudioController source from $topBarCommit."
}
$controllerSource = [string]::Join("`n", $controllerLines)
$controllerSource = Replace-ExactlyOnce `
    -Text $controllerSource `
    -OldValue 'import com.example.ahakey.util.StudioStore;' `
    -NewValue "import com.example.ahakey.util.StudioStore;`nimport com.example.ahakey.update.SemanticVersion;" `
    -Description "firmware version type"
$controllerSource = Replace-ExactlyOnce `
    -Text $controllerSource `
    -OldValue '    private final com.example.ahakey.service.KimiAhaKeyBridge kimiAhaKeyBridge;' `
    -NewValue "    private final com.example.ahakey.service.KimiAhaKeyBridge kimiAhaKeyBridge;`n    private volatile SemanticVersion lastKnownFirmwareVersion;`n    private volatile SemanticVersion pendingFirmwareVersion;" `
    -Description "firmware workflow state"
$firmwareVersionAccessors = @"
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
"@.TrimEnd().Replace("`r", "")
$controllerSource = Replace-ExactlyOnce `
    -Text $controllerSource `
    -OldValue "    public StudioState getStudioState() {`n        return studioState;`n    }" `
    -NewValue $firmwareVersionAccessors `
    -Description "firmware workflow accessors"
$usbBridgeOld = @"
                if (bleManager.isUsbConnected()) {
                    kimiAhaKeyBridge.start();
                }
"@
$usbBridgeNew = @"
                if (bleManager.isUsbConnected()) {
                    kimiAhaKeyBridge.start();
                } else {
                    kimiAhaKeyBridge.stop();
                }
"@
$controllerSource = Replace-ExactlyOnce `
    $controllerSource `
    $usbBridgeOld.TrimEnd().Replace("`r", "") `
    $usbBridgeNew.TrimEnd().Replace("`r", "") `
    "USB/BLE bridge handoff"
$controllerSource = Replace-ExactlyOnce `
    $controllerSource `
    "                Platform.runLater(() -> deviceStatus.setConnected(false));" `
    "                Platform.runLater(() -> deviceStatus.setConnected(false));`n                kimiAhaKeyBridge.stop();" `
    "USB disconnect bridge release"
$controllerSource = Replace-ExactlyOnce `
    $controllerSource `
    "        deviceStatus.setDeviceName(status.getDeviceName());" `
    "        deviceStatus.setDeviceName(status.getDeviceName());`n        deviceStatus.setTransport(status.getTransport());" `
    "transport status propagation"
$controllerSource = Replace-ExactlyOnce `
    $controllerSource `
    '        int pollPeriod = ModelConfig.getInstance().getStatusPollPeriodSeconds();' `
    '        int pollPeriod = Math.max(1, Math.min(2, ModelConfig.getInstance().getStatusPollPeriodSeconds()));' `
    "1-2 second status polling"
$controllerSource = Replace-ExactlyOnce `
    $controllerSource `
    '            if (!simulateBle && deviceStatus.isConnected()) {' `
    '            if (!simulateBle && bleManager.isTransportSessionActive()) {' `
    "transport-session polling"
$heartbeatPattern = '(?s)\s*long lastUpdate = bleManager\.getLastStatusUpdateTime\(\);.*?bleManager\.disconnect\(\);\s*\}'
if ([regex]::Matches($controllerSource, $heartbeatPattern).Count -ne 1) {
    throw "Baseline drift while removing destructive heartbeat disconnect."
}
$controllerSource = [regex]::Replace($controllerSource, $heartbeatPattern, '')
$commandsOld = '        var commands = DeviceSyncService.commandsForModes(studioState, ModeSlot.values());'
$commandsNew = @"
        boolean includeVoiceKey = false;
        try {
            var capabilities = bleManager.queryDeviceCapabilities();
            includeVoiceKey = capabilities != null
                && capabilities.supports(AhaKeyProtocol.CAP_VOICE_KEY_DUAL_V1);
        } catch (Exception exception) {
            logger.info("Device has no dual voice-key capability; saving ordinary settings");
        }
        var commands = DeviceSyncService.commandsForModes(
            studioState, includeVoiceKey, ModeSlot.values());
"@
$controllerSource = Replace-ExactlyOnce `
    $controllerSource $commandsOld $commandsNew.TrimEnd().Replace("`r", "") `
    "granular voice-key capability save"
$modeSyncPattern = '(?s)\s*ModeSlot deviceMode = ModeSlot\.fromIndex\(status\.getWorkMode\(\)\);\s*if \(deviceMode != studioState\.getSelectedMode\(\)\) \{\s*studioState\.setSelectedMode\(deviceMode\);\s*\}'
if ([regex]::Matches($controllerSource, $modeSyncPattern).Count -ne 1) {
    throw "Baseline drift while protecting the actively edited mode."
}
$controllerSource = [regex]::Replace(
    $controllerSource, $modeSyncPattern,
    "`n        // Polling must not overwrite the mode currently being edited."
)
$generatedController = Join-Path $generatedSourceDir `
    "com\example\ahakey\app\StudioController.java"
New-Item -ItemType Directory -Force `
    -Path (Split-Path -Parent $generatedController) | Out-Null
[IO.File]::WriteAllText(
    $generatedController,
    $controllerSource,
    [Text.UTF8Encoding]::new($false)
)

$appRepoPath = "ahakeyconfig-win-java/src/main/java/com/example/ahakey/App.java"
$appLines = & $git -C $repoRoot show "$topBarCommit`:$appRepoPath"
if ($LASTEXITCODE -ne 0 -or -not $appLines) {
    throw "Unable to read release-baseline App source from $topBarCommit."
}
$appSource = [string]::Join("`n", $appLines)
$dpiBlockPattern = '(?s)        final double\[\] savedSize = \{1280, 820\};.*?        primaryStage\.heightProperty\(\)\.addListener\(posSizeListener\);'
if ([regex]::Matches($appSource, $dpiBlockPattern).Count -ne 1) {
    throw "Baseline drift while applying per-monitor layout refresh."
}
$dpiBlockReplacement = @"
        // Let JavaFX/Windows apply per-monitor scaling. Re-layout after moving
        // screens, but never force dimensions captured on a different DPI.
        primaryStage.setMinWidth(980);
        primaryStage.setMinHeight(640);
        PauseTransition layoutRefresh = new PauseTransition(Duration.millis(150));
        layoutRefresh.setOnFinished(e -> Platform.runLater(() -> {
            root.applyCss();
            root.requestLayout();
        }));
        javafx.beans.value.ChangeListener<Number> posSizeListener = (obs, old, val) -> {
            layoutRefresh.stop();
            layoutRefresh.playFromStart();
        };
        primaryStage.xProperty().addListener(posSizeListener);
        primaryStage.yProperty().addListener(posSizeListener);
        primaryStage.widthProperty().addListener(posSizeListener);
        primaryStage.heightProperty().addListener(posSizeListener);
"@
$appSource = [regex]::Replace(
    $appSource, $dpiBlockPattern, $dpiBlockReplacement.TrimEnd()
)
$appSource = Replace-ExactlyOnce `
    -Text $appSource `
    -OldValue 'primaryStage.setMinWidth(800);' `
    -NewValue 'primaryStage.setMinWidth(1024);' `
    -Description "minimum window width"
$appSource = Replace-ExactlyOnce `
    -Text $appSource `
    -OldValue 'primaryStage.setMinHeight(600);' `
    -NewValue 'primaryStage.setMinHeight(640);' `
    -Description "minimum window height"
$appSource = Replace-ExactlyOnce `
    -Text $appSource `
    -OldValue 'centerPane.setMinWidth(Region.USE_PREF_SIZE);' `
    -NewValue 'centerPane.setMinWidth(1100);' `
    -Description "fixed workspace geometry"
$appSource = Replace-ExactlyOnce `
    -Text $appSource `
    -OldValue 'centerScroll.setFitToWidth(true);' `
    -NewValue 'centerScroll.setFitToWidth(false);' `
    -Description "horizontal workspace scrolling"
$generatedApp = Join-Path $generatedSourceDir "com\example\ahakey\App.java"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $generatedApp) | Out-Null
[IO.File]::WriteAllText(
    $generatedApp, $appSource, [Text.UTF8Encoding]::new($false)
)

$canvasRepoPath = "ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/CanvasPane.java"
$canvasLines = & $git -C $repoRoot show "$topBarCommit`:$canvasRepoPath"
if ($LASTEXITCODE -ne 0 -or -not $canvasLines) {
    throw "Unable to read release-baseline CanvasPane source from $topBarCommit."
}
$canvasSource = [string]::Join("`n", $canvasLines)
$canvasSource = Replace-ExactlyOnce `
    -Text $canvasSource `
    -OldValue '        setMinWidth(420);' `
    -NewValue "        setMinWidth(600);`n        setPrefWidth(680);" `
    -Description "fixed keyboard preview width"
$generatedCanvas = Join-Path $generatedSourceDir "com\example\ahakey\view\CanvasPane.java"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $generatedCanvas) | Out-Null
[IO.File]::WriteAllText(
    $generatedCanvas, $canvasSource, [Text.UTF8Encoding]::new($false)
)

$deviceStatusRepoPath = "ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/DeviceStatus.java"
$deviceStatusLines = & $git -C $repoRoot show "$topBarCommit`:$deviceStatusRepoPath"
if ($LASTEXITCODE -ne 0 -or -not $deviceStatusLines) {
    throw "Unable to read release-baseline DeviceStatus source from $topBarCommit."
}
$deviceStatusSource = [string]::Join("`n", $deviceStatusLines)
$deviceStatusSource = Replace-ExactlyOnce `
    $deviceStatusSource `
    '    private final IntegerProperty switchState = new SimpleIntegerProperty(-1);' `
    "    private final IntegerProperty switchState = new SimpleIntegerProperty(-1);`n    private final StringProperty transport = new SimpleStringProperty(`"NONE`");" `
    "transport property"
$deviceStatusSource = Replace-ExactlyOnce `
    $deviceStatusSource `
    '    public String getDeviceName() { return deviceName.get(); }' `
    "    public String getDeviceName() { return deviceName.get(); }`n    public String getTransport() { return transport.get(); }" `
    "transport getter"
$deviceStatusSource = Replace-ExactlyOnce `
    $deviceStatusSource `
    '    public StringProperty deviceNameProperty() { return deviceName; }' `
    "    public StringProperty deviceNameProperty() { return deviceName; }`n    public StringProperty transportProperty() { return transport; }" `
    "transport observable"
$deviceStatusSource = Replace-ExactlyOnce `
    $deviceStatusSource `
    '    public void setDeviceName(String value) { deviceName.set(value); }' `
    "    public void setDeviceName(String value) { deviceName.set(value); }`n    public void setTransport(String value) { transport.set(value == null || value.isBlank() ? `"NONE`" : value); }" `
    "transport setter"
$generatedDeviceStatus = Join-Path $generatedSourceDir `
    "com\example\ahakey\model\DeviceStatus.java"
New-Item -ItemType Directory -Force `
    -Path (Split-Path -Parent $generatedDeviceStatus) | Out-Null
[IO.File]::WriteAllText(
    $generatedDeviceStatus,
    $deviceStatusSource,
    [Text.UTF8Encoding]::new($false)
)

# Materialize the installed-release InspectorPane and apply only the dual
# voice-key UI change. This avoids importing unrelated localization classes
# from the current development tree into the release overlay.
$inspectorRepoPath = "ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/InspectorPane.java"
$inspectorLines = & $git -C $repoRoot show "$topBarCommit`:$inspectorRepoPath"
if ($LASTEXITCODE -ne 0 -or -not $inspectorLines) {
    throw "Unable to read release-baseline InspectorPane source from $topBarCommit."
}
$inspectorSource = [string]::Join("`n", $inspectorLines)
$oldKey1Block = @"
            KeyConfig key1 = studioState.getKeyConfig(StudioPart.KEY1);
            if (key1.getVoicePreset() != com.example.ahakey.model.VoicePreset.CUSTOM) {
                key1.setVoicePreset(com.example.ahakey.model.VoicePreset.CUSTOM);
            }
            body.getChildren().add(createKeyBindingGroup(part));
            body.getChildren().add(createSimulateKeyGroup(part));
            body.getChildren().add(createDescriptionGroup(part));
"@
$newKey1Block = @"
            body.getChildren().add(createDualVoiceKeyGroup());
"@
$oldKey1BlockValue = $oldKey1Block.TrimEnd().Replace("`r", "")
$newKey1BlockValue = $newKey1Block.TrimEnd().Replace("`r", "")
$inspectorSource = Replace-ExactlyOnce $inspectorSource $oldKey1BlockValue $newKey1BlockValue "dual voice-key inspector entry"

$simulateMarker = "    private VBox createSimulateKeyGroup(StudioPart part) {"
$dualVoiceEditor = @"
    private VBox createDualVoiceKeyGroup() {
        return createGroupBox("\u8bed\u97f3\u952e\uff1a\u77ed\u6309 / \u957f\u6309", () -> {
            VBox box = new VBox(16);
            Label hint = new Label(
                "\u5168\u5c40\u914d\u7f6e\uff0c\u6240\u6709\u6a21\u5f0f\u5171\u7528\u3002"
                    + "\u77ed\u6309\u4f1a\u70b9\u51fb\u4e00\u6b21\u5feb\u6377\u952e\uff1b"
                    + "\u6309\u4f4f\u8d85\u8fc7 350ms \u540e\uff0c"
                    + "\u957f\u6309\u5feb\u6377\u952e\u4f1a\u4fdd\u6301\u6309\u4e0b\uff0c"
                    + "\u677e\u5f00\u8bed\u97f3\u952e\u65f6\u91ca\u653e\u3002"
                    + "\u4efb\u4e00\u5217\u8868\u6e05\u7a7a\u5373\u53ef\u7981\u7528\u5bf9\u5e94\u52a8\u4f5c\u3002"
            );
            hint.setWrapText(true);
            hint.getStyleClass().add("warning-note");
            Label shortLabel = new Label("\u77ed\u6309\u5feb\u6377\u952e\uff08\u9ed8\u8ba4\uff1aRight Alt\uff0c\u7528\u4e8e Typeless\uff09");
            shortLabel.getStyleClass().add("field-label");
            Label longLabel = new Label("\u957f\u6309\u5feb\u6377\u952e\uff08\u9ed8\u8ba4\uff1aLeft Ctrl + Left Win\uff0c\u7528\u4e8e\u5fae\u4fe1\u8bed\u97f3\u8f93\u5165\uff09");
            longLabel.getStyleClass().add("field-label");
            box.getChildren().addAll(
                hint,
                shortLabel,
                createShortcutEditor(studioState.getVoiceKeyShort(), StudioPart.KEY1),
                longLabel,
                createShortcutEditor(studioState.getVoiceKeyLong(), StudioPart.KEY1)
            );
            return box;
        });
    }

$simulateMarker
"@
$dualVoiceEditorValue = $dualVoiceEditor.TrimEnd().Replace("`r", "")
$inspectorSource = Replace-ExactlyOnce $inspectorSource $simulateMarker $dualVoiceEditorValue "dual voice-key editors"

$shortcutOld = @"
    private VBox createShortcutEditor(StudioPart part) {
        VBox box = new VBox(12);
        KeyConfig key = studioState.getKeyConfig(part);
"@
$shortcutNew = @"
    private VBox createShortcutEditor(StudioPart part) {
        return createShortcutEditor(studioState.getKeyConfig(part), part);
    }

    private VBox createShortcutEditor(KeyConfig key, StudioPart dirtyPart) {
        VBox box = new VBox(12);
"@
$shortcutOldValue = $shortcutOld.TrimEnd().Replace("`r", "")
$shortcutNewValue = $shortcutNew.TrimEnd().Replace("`r", "")
$inspectorSource = Replace-ExactlyOnce $inspectorSource $shortcutOldValue $shortcutNewValue "shortcut editor reuse"
$inspectorSource = Replace-ExactlyOnce $inspectorSource `
    "                    studioState.markDirty(part);`n                }`n                rebuild();" `
    "                    studioState.markDirty(dirtyPart);`n                }`n                rebuild();" `
    "shortcut add dirty tracking"
$inspectorSource = Replace-ExactlyOnce $inspectorSource `
    "                studioState.markDirty(part);`n                rebuild();`n            }`n        });`n`n        keyListView" `
    "                studioState.markDirty(dirtyPart);`n                rebuild();`n            }`n        });`n`n        keyListView" `
    "shortcut delete dirty tracking"

$generatedInspector = Join-Path $generatedSourceDir "com\example\ahakey\view\InspectorPane.java"
[IO.File]::WriteAllText(
    $generatedInspector,
    $inspectorSource,
    [Text.UTF8Encoding]::new($false)
)

# Feature releases use the current controller/inspector/top-bar sources while
# continuing to preserve the installed, known-good speech recognizer classes.
# FloatingVoiceNotification is the only release-baseline API compatibility
# adjustment required by the installed application shell.
$currentController = Get-Content -LiteralPath (Join-Path $projectDir `
    "src\main\java\com\example\ahakey\app\StudioController.java") -Raw -Encoding UTF8
$currentInspector = Get-Content -LiteralPath (Join-Path $projectDir `
    "src\main\java\com\example\ahakey\view\InspectorPane.java") -Raw -Encoding UTF8
$currentTopBar = Get-Content -LiteralPath (Join-Path $projectDir `
    "src\main\java\com\example\ahakey\view\TopBar.java") -Raw -Encoding UTF8
$currentTopBar = Replace-ExactlyOnce `
    $currentTopBar `
    "floatingNotification = new FloatingVoiceNotification();" `
    "floatingNotification = FloatingVoiceNotification.getInstance();" `
    "installed-release voice notification compatibility"
[IO.File]::WriteAllText($generatedController, $currentController, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($generatedInspector, $currentInspector, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($generatedTopBar, $currentTopBar, [Text.UTF8Encoding]::new($false))

$storeRepoPath = "ahakeyconfig-win-java/src/main/java/com/example/ahakey/util/StudioStore.java"
$storeLines = & $git -C $repoRoot show "$topBarCommit`:$storeRepoPath"
if ($LASTEXITCODE -ne 0 -or -not $storeLines) {
    throw "Unable to read release-baseline StudioStore source from $topBarCommit."
}
$storeSource = [string]::Join("`n", $storeLines)
$storeMarker = "            defaults.lightBrightness = savedDraft.lightBrightness;"
$storeReplacement = @"
$storeMarker
            if (savedDraft.voiceKeyShortHid != null) {
                defaults.voiceKeyShortHid = savedDraft.voiceKeyShortHid;
            }
            if (savedDraft.voiceKeyLongHid != null) {
                defaults.voiceKeyLongHid = savedDraft.voiceKeyLongHid;
            }
"@
$storeReplacementValue = $storeReplacement.TrimEnd().Replace("`r", "")
$storeSource = Replace-ExactlyOnce $storeSource $storeMarker $storeReplacementValue "voice-key draft migration"
$generatedStore = Join-Path $generatedSourceDir "com\example\ahakey\util\StudioStore.java"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $generatedStore) | Out-Null
[IO.File]::WriteAllText(
    $generatedStore,
    $storeSource,
    [Text.UTF8Encoding]::new($false)
)

$libJars = Get-ChildItem -LiteralPath $baselineLibDir -Filter "*.jar" |
    ForEach-Object FullName
$classPath = [string]::Join(";", @($baselineJar) + $libJars)

$sources = @(
    $generatedApp,
    (Join-Path $projectDir "src\main\java\com\example\ahakey\protocol\AhaKeyProtocol.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\protocol\AhaKeyResponseParser.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\model\DeviceStatus.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\model\VoicePreset.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\model\StudioState.java"),
    $generatedStore,
    (Join-Path $projectDir "src\main\java\com\example\ahakey\service\BleManager.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\service\UsbHidTransport.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\service\DeviceSyncService.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\service\HookInstaller.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\service\HookDispatchServer.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\service\TaskActivityService.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\service\OledUploadService.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\service\BundledGifLibrary.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\platform\VoiceRelayPlatform.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\platform\windows\WindowsVoiceRelayService.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\util\FirstRunState.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\util\LanguageManager.java"),
    $generatedController,
    $generatedCanvas,
    $generatedInspector,
    (Join-Path $projectDir "src\main\java\com\example\ahakey\view\StandbySettingsPane.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\view\DeviceMaintenancePane.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\view\SupportPane.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\view\BluetoothPairingGuide.java"),
    (Join-Path $projectDir "src\main\java\com\example\ahakey\view\ScreenAnimationDialog.java"),
    $generatedTopBar
)
$sources += Get-ChildItem `
    -LiteralPath (Join-Path $projectDir "src\main\java\com\example\ahakey\firmware") `
    -Filter "*.java" |
    ForEach-Object FullName
$sources += Get-ChildItem `
    -LiteralPath (Join-Path $projectDir "src\main\java\com\example\ahakey\update") `
    -Filter "*.java" |
    ForEach-Object FullName

& $javac `
    --release 17 `
    -encoding UTF-8 `
    -sourcepath $emptySourcePath `
    -cp $classPath `
    -d $classesDir `
    @sources
if ($LASTEXITCODE -ne 0) {
    throw "Release-baseline overlay compilation failed."
}

$previewJar = Join-Path $buildDir "ahakey-studio-1.0.0-part3-preview.jar"
Copy-Item -LiteralPath $baselineJar -Destination $previewJar

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$allowedEntryPattern = "^(com/example/ahakey/App.*\.class|com/example/ahakey/protocol/AhaKeyProtocol\.class|com/example/ahakey/protocol/AhaKeyResponseParser.*\.class|com/example/ahakey/model/(DeviceStatus|VoicePreset|StudioState).*\.class|com/example/ahakey/app/StudioController.*\.class|com/example/ahakey/util/(StudioStore|FirstRunState|LanguageManager).*\.class|com/example/ahakey/service/(BleManager|UsbHidTransport|DeviceSyncService|HookInstaller|HookDispatchServer|TaskActivityService|OledUploadService|BundledGifLibrary).*\.class|com/example/ahakey/platform/VoiceRelayPlatform\.class|com/example/ahakey/platform/windows/WindowsVoiceRelayService.*\.class|com/example/ahakey/view/(TopBar|CanvasPane|InspectorPane|StandbySettingsPane|DeviceMaintenancePane|SupportPane|BluetoothPairingGuide|ScreenAnimationDialog).*\.class|com/example/ahakey/firmware/.*\.class|com/example/ahakey/update/.*\.class|default-gifs/(claude|cursor|codex|mode4)/(default|running|waiting-error|completed)\.gif|fxml/CanvasLayout\.fxml|images/support-service-qr\.png|messages_(zh|en)\.properties|style\.css)$"

$zip = [IO.Compression.ZipFile]::Open(
    $previewJar,
    [IO.Compression.ZipArchiveMode]::Update
)
try {
    foreach ($classFile in Get-ChildItem -LiteralPath $classesDir -Recurse -Filter "*.class") {
        $entryName = $classFile.FullName.Substring($classesDir.Length + 1).Replace("\", "/")
        if ($entryName -notmatch $allowedEntryPattern) {
            throw "Compiler produced a class outside the overlay allowlist: $entryName"
        }
        $existing = $zip.GetEntry($entryName)
        if ($existing) {
            $existing.Delete()
        }
        $entry = $zip.CreateEntry(
            $entryName,
            [IO.Compression.CompressionLevel]::Optimal
        )
        $input = [IO.File]::OpenRead($classFile.FullName)
        $output = $entry.Open()
        try {
            $input.CopyTo($output)
        } finally {
            $output.Dispose()
            $input.Dispose()
        }
    }

    $supportQr = Join-Path $projectDir `
        "src\main\resources\images\support-service-qr.png"
    if (-not (Test-Path -LiteralPath $supportQr)) {
        throw "Bundled support QR code is missing: $supportQr"
    }
    $supportQrEntryName = "images/support-service-qr.png"
    $existingSupportQr = $zip.GetEntry($supportQrEntryName)
    if ($existingSupportQr) {
        $existingSupportQr.Delete()
    }
    $supportQrEntry = $zip.CreateEntry(
        $supportQrEntryName,
        [IO.Compression.CompressionLevel]::Optimal
    )
    $supportQrInput = [IO.File]::OpenRead($supportQr)
    $supportQrOutput = $supportQrEntry.Open()
    try {
        $supportQrInput.CopyTo($supportQrOutput)
    } finally {
        $supportQrOutput.Dispose()
        $supportQrInput.Dispose()
    }

    $bundledGifRoot = Join-Path $projectDir "src\main\resources\default-gifs"
    $bundledGifFiles = if (Test-Path -LiteralPath $bundledGifRoot -PathType Container) {
        @(Get-ChildItem -LiteralPath $bundledGifRoot -Recurse -File -Filter "*.gif")
    } else {
        @()
    }
    if ($bundledGifFiles.Count -ne 16) {
        throw "Expected 16 bundled GIF assets, found $($bundledGifFiles.Count): $bundledGifRoot"
    }
    foreach ($bundledGifFile in $bundledGifFiles) {
        $relativeGifPath = $bundledGifFile.FullName.Substring(
            $bundledGifRoot.Length + 1
        ).Replace("\", "/")
        $bundledGifEntryName = "default-gifs/$relativeGifPath"
        $existingBundledGif = $zip.GetEntry($bundledGifEntryName)
        if ($existingBundledGif) {
            $existingBundledGif.Delete()
        }
        $bundledGifEntry = $zip.CreateEntry(
            $bundledGifEntryName,
            [IO.Compression.CompressionLevel]::Optimal
        )
        $bundledGifInput = [IO.File]::OpenRead($bundledGifFile.FullName)
        $bundledGifOutput = $bundledGifEntry.Open()
        try {
            $bundledGifInput.CopyTo($bundledGifOutput)
        } finally {
            $bundledGifOutput.Dispose()
            $bundledGifInput.Dispose()
        }
    }

    $canvasLayout = Join-Path $projectDir "src\main\resources\fxml\CanvasLayout.fxml"
    if (-not (Test-Path -LiteralPath $canvasLayout)) {
        throw "Canvas layout resource is missing: $canvasLayout"
    }
    $canvasLayoutEntryName = "fxml/CanvasLayout.fxml"
    $existingCanvasLayout = $zip.GetEntry($canvasLayoutEntryName)
    if ($existingCanvasLayout) {
        $existingCanvasLayout.Delete()
    }
    $canvasLayoutEntry = $zip.CreateEntry(
        $canvasLayoutEntryName,
        [IO.Compression.CompressionLevel]::Optimal
    )
    $canvasLayoutInput = [IO.File]::OpenRead($canvasLayout)
    $canvasLayoutOutput = $canvasLayoutEntry.Open()
    try {
        $canvasLayoutInput.CopyTo($canvasLayoutOutput)
    } finally {
        $canvasLayoutOutput.Dispose()
        $canvasLayoutInput.Dispose()
    }

    $styleSheet = Join-Path $projectDir "src\main\resources\style.css"
    if (-not (Test-Path -LiteralPath $styleSheet)) {
        throw "Application stylesheet is missing: $styleSheet"
    }
    $styleSheetEntryName = "style.css"
    $existingStyleSheet = $zip.GetEntry($styleSheetEntryName)
    if ($existingStyleSheet) {
        $existingStyleSheet.Delete()
    }
    $styleSheetEntry = $zip.CreateEntry(
        $styleSheetEntryName,
        [IO.Compression.CompressionLevel]::Optimal
    )
    $styleSheetInput = [IO.File]::OpenRead($styleSheet)
    $styleSheetOutput = $styleSheetEntry.Open()
    try {
        $styleSheetInput.CopyTo($styleSheetOutput)
    } finally {
        $styleSheetOutput.Dispose()
        $styleSheetInput.Dispose()
    }

    foreach ($messageFileName in @("messages_zh.properties", "messages_en.properties")) {
        $messageFile = Join-Path $projectDir "src\main\resources\$messageFileName"
        if (-not (Test-Path -LiteralPath $messageFile -PathType Leaf)) {
            throw "Language resource is missing: $messageFile"
        }
        $existingMessage = $zip.GetEntry($messageFileName)
        if ($existingMessage) {
            $existingMessage.Delete()
        }
        $messageEntry = $zip.CreateEntry(
            $messageFileName,
            [IO.Compression.CompressionLevel]::Optimal
        )
        $messageInput = [IO.File]::OpenRead($messageFile)
        $messageOutput = $messageEntry.Open()
        try {
            $messageInput.CopyTo($messageOutput)
        } finally {
            $messageOutput.Dispose()
            $messageInput.Dispose()
        }
    }
} finally {
    $zip.Dispose()
}

function Get-ZipEntryHashes {
    param([string]$Path)
    $result = @{}
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.EndsWith("/")) {
                continue
            }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $hash = [BitConverter]::ToString(
                    $sha.ComputeHash($stream)
                ).Replace("-", "").ToLowerInvariant()
                $result[$entry.FullName] = $hash
            } finally {
                $sha.Dispose()
                $stream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
    return $result
}

$baselineHashes = Get-ZipEntryHashes $baselineJar
$previewHashes = Get-ZipEntryHashes $previewJar
$allEntries = @($baselineHashes.Keys + $previewHashes.Keys | Sort-Object -Unique)
$changedEntries = @()
$unexpectedEntries = @()

foreach ($entryName in $allEntries) {
    $before = $baselineHashes[$entryName]
    $after = $previewHashes[$entryName]
    if ($before -ne $after) {
        $changedEntries += $entryName
        if ($entryName -notmatch $allowedEntryPattern) {
            $unexpectedEntries += $entryName
        }
    }
}

if ($unexpectedEntries.Count -gt 0) {
    throw "Overlay changed protected release entries: $($unexpectedEntries -join ', ')"
}

$protectedEntries = @(
    "com/example/ahakey/service/VoiceInputManager.class",
    "com/example/ahakey/service/VoiceInputManager`$Consumer.class",
    "com/example/ahakey/service/VoiceInputManager`$VoiceStatus.class",
    "com/example/ahakey/service/SpeechService.class",
    "com/example/ahakey/service/SpeechService`$Consumer.class",
    "com/example/ahakey/config/ModelConfig.class",
    "model_config.properties"
)
foreach ($entryName in $protectedEntries) {
    if (-not $baselineHashes.ContainsKey($entryName)) {
        throw "Protected baseline entry is missing: $entryName"
    }
    if ($baselineHashes[$entryName] -ne $previewHashes[$entryName]) {
        throw "Protected voice/model entry changed: $entryName"
    }
}

if ($previewHashes.ContainsKey("models/model_q8.onnx")) {
    throw "The overlay unexpectedly contains models/model_q8.onnx."
}

Write-Output "OVERLAY_VALIDATION=OK"
Write-Output "Baseline JAR: $baselineJar"
Write-Output "Preview JAR:  $previewJar"
Write-Output "Changed entries:"
$changedEntries | ForEach-Object { Write-Output "  $_" }
Write-Output "Protected voice/model classes and model_config.properties are byte-identical."

if ($Launch) {
    if (-not (Test-Path -LiteralPath $javaw)) {
        throw "Unable to locate javaw.exe for preview launch."
    }
    $instanceClient = [Net.Sockets.TcpClient]::new()
    try {
        $instanceAttempt = $instanceClient.BeginConnect("127.0.0.1", 48765, $null, $null)
        $instanceRunning = $instanceAttempt.AsyncWaitHandle.WaitOne(300)
        if ($instanceRunning) {
            $instanceClient.EndConnect($instanceAttempt)
            throw "AhaKey Studio is already running. Close it from the system tray before launching the Part 3 preview."
        }
    } catch [Net.Sockets.SocketException] {
        $instanceRunning = $false
    } finally {
        $instanceClient.Dispose()
    }
    $previewClassPath = "$previewJar;$baselineLibDir\*"
    $previewWchIsp = Join-Path $BaselineAppDir `
        "tools\wchisp\WCHISPTool_CH57x-59x.exe"
    if (-not (Test-Path -LiteralPath $previewWchIsp)) {
        throw "Bundled WCHISP executable is missing: $previewWchIsp"
    }
    $arguments = @(
        "--add-opens=javafx.graphics/com.sun.javafx.application=ALL-UNNAMED",
        "--add-opens=javafx.controls/com.sun.javafx.scene.control=ALL-UNNAMED",
        "--add-opens=javafx.fxml/com.sun.javafx.fxml=ALL-UNNAMED",
        "-Dapp.version=$previewAppVersion",
        "-Dahakey.wchisp.path=`"$previewWchIsp`"",
        "-cp",
        "`"$previewClassPath`"",
        "com.example.ahakey.App"
    )
    Start-Process `
        -FilePath $javaw `
        -ArgumentList $arguments `
        -WorkingDirectory $BaselineAppDir `
        -WindowStyle Hidden
    Write-Output "Preview launched from the installed app working directory."
}
