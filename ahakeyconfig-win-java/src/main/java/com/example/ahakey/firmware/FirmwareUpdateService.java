package com.example.ahakey.firmware;

import com.example.ahakey.service.BleManager;
import com.example.ahakey.update.SemanticVersion;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Single-owner firmware update orchestration.  UI code observes structured
 * events and never touches WCHISP process details, config slots or workspaces.
 */
public final class FirmwareUpdateService implements AutoCloseable {
    private static final Duration ISP_TIMEOUT = Duration.ofSeconds(20);
    private static final Duration UID_TIMEOUT = Duration.ofSeconds(20);
    private static final Duration FLASH_TIMEOUT = Duration.ofMinutes(5);
    private static final Duration RECONNECT_TIMEOUT = Duration.ofSeconds(30);
    /** Explicit development-only escape hatch for hardware without a chip identity API. */
    public static final String DEV_ALLOW_UNKNOWN_CHIP_PROPERTY =
        "ahakey.dev.allow-isp-flash-with-unknown-chip";

    private final RuntimeLocator runtimeProvider;
    /** Non-null only for the production official-tool orchestration path. */
    private final OfficialWchIspAdapter officialAdapter;
    private final IspDeviceProbe ispProbe;
    private final ChipMatched chipMatched;
    private final boolean allowUnknownChip;
    private final WchIspRunner runner;
    private final FirmwarePostVerifier postVerifier;
    private final FirmwareUpdateDiagnostics diagnostics;
    private final Path workspaceParent;
    private final ExecutorService executor;
    private final AtomicReference<FirmwareOperationHandle> active = new AtomicReference<>();
    private final AtomicBoolean shuttingDown = new AtomicBoolean();
    private final CopyOnWriteArrayList<java.util.function.Consumer<FirmwareUpdateStatus>> listeners =
        new CopyOnWriteArrayList<>();
    private final Object admissionMonitor = new Object();
    private final AtomicBoolean diagnosticActive = new AtomicBoolean();
    private final ConcurrentHashMap<UUID, PreparedFlashSession> preparedSessions =
        new ConcurrentHashMap<>();

    public FirmwareUpdateService(BleManager manager) {
        this(new InstalledRuntimeLocator(),
            manager == null ? null : new FirmwarePostVerifier(manager),
            new FirmwareUpdateDiagnostics(), Path.of(System.getProperty("java.io.tmpdir")));
    }

    private FirmwareUpdateService(RuntimeLocator runtimeLocator,
                                  FirmwarePostVerifier postVerifier,
                                  FirmwareUpdateDiagnostics diagnostics,
                                  Path workspaceParent) {
        this(new DefaultOfficialWchIspAdapter(runtimeLocator, IspDeviceProbe.windowsDefault(),
                null), runtimeLocator, postVerifier, diagnostics, workspaceParent);
    }

    /**
     * Production/test seam for the official WCHISP adapter.  The adapter is
     * deliberately injected so tests can prove the command boundary without
     * copying CONFIG files or invoking a UID query.
     */
    FirmwareUpdateService(OfficialWchIspAdapter officialAdapter,
                          RuntimeLocator runtimeProvider,
                          FirmwarePostVerifier postVerifier,
                          FirmwareUpdateDiagnostics diagnostics,
                          Path workspaceParent) {
        this.officialAdapter = officialAdapter == null ? new DefaultOfficialWchIspAdapter() : officialAdapter;
        this.runtimeProvider = runtimeProvider == null ? new InstalledRuntimeLocator() : runtimeProvider;
        this.ispProbe = IspDeviceProbe.windowsDefault();
        this.chipMatched = ChipMatched.unknown();
        this.allowUnknownChip = false;
        this.runner = new WchIspRunner();
        this.postVerifier = postVerifier;
        this.diagnostics = diagnostics == null ? new FirmwareUpdateDiagnostics() : diagnostics;
        this.workspaceParent = workspaceParent == null
            ? Path.of(System.getProperty("java.io.tmpdir")) : workspaceParent;
        this.executor = newExecutor();
    }

    /** Legacy seam retained for existing unit tests; Studio never uses it. */
    public FirmwareUpdateService(RuntimeProvider runtimeProvider,
                                 IspDeviceProbe ispProbe,
                                 WchIspRunner runner,
                                 FirmwarePostVerifier postVerifier,
                                 FirmwareUpdateDiagnostics diagnostics,
                                 Path workspaceParent) {
        this(runtimeProvider, ispProbe, runner, postVerifier, diagnostics, workspaceParent,
            ChipMatched.unknown(), developmentUnknownChipAllowed());
    }

    /** Legacy workspace/parser seam retained for compatibility tests only. */
    FirmwareUpdateService(RuntimeProvider runtimeProvider,
                          IspDeviceProbe ispProbe,
                          WchIspRunner runner,
                          FirmwarePostVerifier postVerifier,
                          FirmwareUpdateDiagnostics diagnostics,
                          Path workspaceParent,
                          ChipMatched chipMatched,
                          boolean allowUnknownChip) {
        this.officialAdapter = null;
        this.runtimeProvider = runtimeProvider == null ? new WchIspRuntimeProvider() : runtimeProvider;
        this.ispProbe = ispProbe == null ? IspDeviceProbe.windowsDefault() : ispProbe;
        this.chipMatched = chipMatched == null ? ChipMatched.unknown() : chipMatched;
        this.allowUnknownChip = allowUnknownChip;
        this.runner = runner == null ? new WchIspRunner() : runner;
        this.postVerifier = postVerifier;
        this.diagnostics = diagnostics == null ? new FirmwareUpdateDiagnostics() : diagnostics;
        this.workspaceParent = workspaceParent == null
            ? Path.of(System.getProperty("java.io.tmpdir")) : workspaceParent;
        this.executor = newExecutor();
    }

    private static ExecutorService newExecutor() {
        return Executors.newSingleThreadExecutor(task -> {
            Thread thread = new Thread(task, "firmware-update");
            thread.setDaemon(true);
            return thread;
        });
    }

    private static boolean developmentUnknownChipAllowed() {
        // jpackage sets app-path for release images.  The override is never
        // honored from a packaged application, keeping release fail-closed.
        boolean packaged = !System.getProperty("jpackage.app-path", "").isBlank();
        return !packaged && Boolean.parseBoolean(
            System.getProperty(DEV_ALLOW_UNKNOWN_CHIP_PROPERTY, "false"));
    }

    public void addListener(java.util.function.Consumer<FirmwareUpdateStatus> listener) {
        if (listener != null) listeners.add(listener);
    }

    public void removeListener(java.util.function.Consumer<FirmwareUpdateStatus> listener) {
        listeners.remove(listener);
    }

    /** Admission is atomic; a second caller receives structured BUSY. */
    public OperationStart start(FirmwareUpdateRequest request) {
        if (request == null) {
            return OperationStart.rejected(FirmwareUpdateError.INTERNAL_ERROR, "请求为空");
        }
        synchronized (admissionMonitor) {
            if (shuttingDown.get()) {
                return OperationStart.rejected(FirmwareUpdateError.CANCELLED, "应用正在退出");
            }
            if (diagnosticActive.get()) return OperationStart.busy();
            UUID operationId = UUID.randomUUID();
            AtomicBoolean cancelled = new AtomicBoolean();
            FirmwareOperationHandle handle = new FirmwareOperationHandle(operationId, () -> cancelled.set(true));
            if (!active.compareAndSet(null, handle)) {
                return OperationStart.busy();
            }
            CompletableFuture.runAsync(() -> runOperation(handle, request, cancelled), executor);
            return OperationStart.accepted(handle);
        }
    }

    /** Convenience for callers that only need the handle; null means BUSY. */
    public FirmwareOperationHandle submit(FirmwareUpdateRequest request) {
        OperationStart start = start(request);
        return start.accepted() ? start.handle() : null;
    }

    /** Performs runtime and HEX checks without starting an ISP operation. */
    public PreflightResult preflight(FirmwareUpdateRequest request) {
        if (request == null) return PreflightResult.failure(FirmwareUpdateError.INTERNAL_ERROR, "请求为空");
        try {
            if (!Files.isRegularFile(request.firmwareHex())) {
                return PreflightResult.failure(FirmwareUpdateError.HEX_INVALID, "固件 HEX 文件不存在");
            }
            if (request.targetVersion() == null && !request.allowUnknownVersion()) {
                return PreflightResult.failure(FirmwareUpdateError.UNKNOWN_VERSION_CONFIRMATION_REQUIRED,
                    "本地固件版本未知，需要显式风险确认");
            }
            if (request.targetVersion() != null && request.currentVersion() == null
                && !request.allowDowngrade()) {
                return PreflightResult.failure(FirmwareUpdateError.CURRENT_VERSION_REQUIRED,
                    "无法确认当前设备版本，需要先读取版本或显式确认风险");
            }
            if (request.targetVersion() != null && request.currentVersion() != null
                && request.targetVersion().compareTo(request.currentVersion()) < 0
                && !request.allowDowngrade()) {
                return PreflightResult.failure(FirmwareUpdateError.DOWNGRADE_CONFIRMATION_REQUIRED,
                    "固件降级默认禁止，需要显式风险确认");
            }
            IntelHexValidator.validate(request.firmwareHex());
            RuntimeBundle runtime = runtimeProvider.resolve();
            return new PreflightResult(true, null, "运行环境和 HEX 校验通过", runtime);
        } catch (IllegalArgumentException | IOException failure) {
            String message = failure.getMessage() == null ? "" : failure.getMessage().toLowerCase();
            FirmwareUpdateError error = message.contains("runtime")
                ? (message.contains("not found")
                    ? FirmwareUpdateError.RUNTIME_NOT_FOUND : FirmwareUpdateError.RUNTIME_INVALID)
                : FirmwareUpdateError.HEX_INVALID;
            return PreflightResult.failure(error, failure.getMessage());
        } catch (Exception failure) {
            return PreflightResult.failure(FirmwareUpdateError.RUNTIME_INVALID, failure.getMessage());
        }
    }

    /**
     * Prepares the official-tool launch before the user is asked to enter ISP.
     * No vendor process is started by this method.
     */
    public PreparationResult prepareFlash(FirmwareUpdateRequest request) {
        if (request == null) {
            return PreparationResult.failure(FirmwareUpdateError.INTERNAL_ERROR, "请求为空");
        }
        synchronized (admissionMonitor) {
            if (shuttingDown.get()) {
                return PreparationResult.failure(FirmwareUpdateError.CANCELLED, "应用正在退出");
            }
            if (active.get() != null || diagnosticActive.get()) return PreparationResult.busy();
        }
        if (officialAdapter == null) {
            return PreparationResult.failure(FirmwareUpdateError.INTERNAL_ERROR,
                "当前兼容路径不支持预备官方 WCHISP 会话");
        }
        UUID operationId = UUID.randomUUID();
        Path diagnosticDirectory = null;
        try {
            diagnosticDirectory = diagnostics.begin(operationId, request);
            initializeDiagnosticFiles(diagnosticDirectory);
            PreflightResult preflight = preflight(request);
            if (!preflight.success()) {
                diagnostics.write(diagnosticDirectory, "preparation-error.txt", preflight.detail());
                return PreparationResult.failure(preflight.error(), preflight.detail(), diagnosticDirectory);
            }
            writeRuntimeEvidence(diagnosticDirectory, preflight.runtime());
            PreparedFlashSession session = officialAdapter.prepareFlash(
                request.firmwareHex(), operationId, diagnosticDirectory, preflight.runtime());
            if (session == null) {
                return PreparationResult.failure(FirmwareUpdateError.INTERNAL_ERROR,
                    "官方适配器未提供预备烧录会话", diagnosticDirectory);
            }
            writePreparedSessionEvidence(diagnosticDirectory, session);
            preparedSessions.put(session.operationId(), session);
            return PreparationResult.success(
                new PreparedFirmwareOperation(request, session, diagnosticDirectory));
        } catch (Exception failure) {
            String detail = failure.getMessage() == null ? failure.toString() : failure.getMessage();
            if (diagnosticDirectory != null) diagnostics.write(diagnosticDirectory, "preparation-error.txt", detail);
            return PreparationResult.failure(classify(failure), detail, diagnosticDirectory);
        }
    }

    /**
     * Starts an already prepared operation.  The click path only arms the
     * session and launches the prepared command; it does not repeat preflight,
     * runtime resolution, CONFIG generation, or workspace creation.
     */
    public OperationStart startPrepared(PreparedFirmwareOperation prepared) {
        if (prepared == null || prepared.session() == null) {
            return OperationStart.rejected(FirmwareUpdateError.INTERNAL_ERROR, "预备烧录会话缺失");
        }
        PreparedFlashSession session = prepared.session();
        if (session.state() != PreparedFlashSession.State.ARMED) {
            return OperationStart.rejected(FirmwareUpdateError.ISP_NOT_PRESENT,
                "请先检测到当前 ISP 设备后再开始烧录");
        }
        synchronized (admissionMonitor) {
            if (shuttingDown.get()) {
                return OperationStart.rejected(FirmwareUpdateError.CANCELLED, "应用正在退出");
            }
            if (diagnosticActive.get()) return OperationStart.busy();
            AtomicBoolean cancelled = new AtomicBoolean();
            FirmwareOperationHandle handle = new FirmwareOperationHandle(
                session.operationId(), () -> {
                    cancelled.set(true);
                    session.cancel();
                });
            if (!active.compareAndSet(null, handle)) return OperationStart.busy();
            Instant flashClickTime = Instant.now();
            CompletableFuture.runAsync(
                () -> runPreparedOfficialOperation(handle, prepared, cancelled, flashClickTime), executor);
            return OperationStart.accepted(handle);
        }
    }

    /** Non-destructive environment/ISP report used by the maintenance UI. */
    public DiagnosticResult diagnose() {
        return diagnose(null);
    }

    /**
     * Runs the operation-local fast probe.  When a prepared session is
     * supplied, runtime resolution and command/config preparation are reused.
     */
    public DiagnosticResult diagnose(PreparedFirmwareOperation prepared) {
        synchronized (admissionMonitor) {
            if (shuttingDown.get()) return DiagnosticResult.failure(FirmwareUpdateError.CANCELLED, "应用正在退出");
            if (active.get() != null || !diagnosticActive.compareAndSet(false, true)) {
                return DiagnosticResult.failure(FirmwareUpdateError.BUSY, "固件操作正在执行");
            }
        }
        if (officialAdapter != null) {
            return diagnoseWithOfficialAdapter(prepared);
        }
        UUID operationId = UUID.randomUUID();
        Path diagnosticDirectory = null;
        RuntimeBundle runtime = null;
        boolean present = false;
        WchIspRunner.WchIspProcessResult processResult = null;
        ChipMatched.ChipMatchResult chip = null;
        boolean chipGateAllowed = false;
        try {
            diagnosticDirectory = diagnostics.beginDiagnostic(operationId);
            initializeDiagnosticFiles(diagnosticDirectory);
            runtime = runtimeProvider.resolve();
            writeRuntimeEvidence(diagnosticDirectory, runtime);
            present = ispProbe.isPresent();
            if (!present) {
                String detail = diagnosticDetail(operationId, diagnosticDirectory, runtime,
                    false, null, false, null, null, "未检测到 CH582 ISP 设备");
                writeDiagnosticResult(diagnosticDirectory, null, detail, null);
                return new DiagnosticResult(true, false, false, runtime, detail, null,
                    operationId, diagnosticDirectory, null, null, false, false);
            }
            chip = inspectChip();
            chipGateAllowed = chipGateAllowed(chip);
            writeChipEvidence(diagnosticDirectory, chip, chipGateAllowed);
            if (!chipGateAllowed) {
                FirmwareUpdateError chipError = chip.mismatch()
                    ? FirmwareUpdateError.CHIP_MISMATCH : FirmwareUpdateError.CHIP_UNKNOWN;
                String detail = diagnosticDetail(operationId, diagnosticDirectory, runtime,
                    true, chip, chipGateAllowed, null, null, chip.detail());
                writeDiagnosticResult(diagnosticDirectory, null, detail, chipError);
                return new DiagnosticResult(true, true, false, runtime, detail, chipError,
                    operationId, diagnosticDirectory, null, chip, false, false);
            }
            try (WchIspWorkspace workspace = WchIspWorkspace.create(workspaceParent, operationId)) {
                WchIspWorkspace.PreparedWorkspace detect = workspace.prepareForDetect(runtime);
                WchIspRunner.WchIspCommand command = new WchIspRunner.WchIspCommand(
                    detect.executable(), workspace.toolDirectory(),
                    List.of("-c", detect.configIni().toString(), "-u", "get"), UID_TIMEOUT,
                    operationId);
                diagnostics.write(diagnosticDirectory, "command.txt", commandText(command));
                WchIspResultParser.UidQueryResult uid;
                String uidWarning = "";
                try {
                    processResult = runner.run(command, WchIspRunner.CancellationToken.NONE);
                    saveProcess(diagnosticDirectory, "uid", command, processResult);
                    uid = WchIspResultParser.parseUid(processResult);
                    if (!uid.success()) uidWarning = uid.detail();
                } catch (Exception failure) {
                    uid = null;
                    uidWarning = failure.getMessage() == null ? failure.toString() : failure.getMessage();
                }
                String detail = diagnosticDetail(operationId, diagnosticDirectory, runtime,
                    true, chip, chipGateAllowed, uid, processResult, uidWarning);
                if (!uidWarning.isBlank()) {
                    diagnostics.write(diagnosticDirectory, "uid-warning.txt", uidWarning);
                }
                writeDiagnosticResult(diagnosticDirectory, processResult, detail, null);
                return new DiagnosticResult(true, true, uid != null && uid.success(), runtime, detail,
                    null, operationId, diagnosticDirectory, processResult, chip, chipGateAllowed, false);
            }
        } catch (Exception failure) {
            String detail = diagnosticDetail(operationId, diagnosticDirectory, runtime,
                present, chip, chipGateAllowed, null, processResult,
                failure.getMessage() == null ? failure.toString() : failure.getMessage());
            FirmwareUpdateError error = failure instanceof IOException
                ? (String.valueOf(failure.getMessage()).toLowerCase().contains("not found")
                    ? FirmwareUpdateError.RUNTIME_NOT_FOUND : FirmwareUpdateError.RUNTIME_INVALID)
                : FirmwareUpdateError.INTERNAL_ERROR;
            writeDiagnosticResult(diagnosticDirectory, processResult, detail, error);
            return new DiagnosticResult(runtime != null, present, false, runtime, detail, error,
                operationId, diagnosticDirectory, processResult, chip, chipGateAllowed, false);
        } finally {
            diagnosticActive.set(false);
        }
    }

    /**
     * Official-tool detection intentionally does not run {@code -u get}.
     * Detection is a user initiated, one-shot presence check; UID is optional
     * evidence supplied by the vendor control process and never a flash gate.
     */
    private DiagnosticResult diagnoseWithOfficialAdapter(PreparedFirmwareOperation prepared) {
        UUID operationId = prepared == null ? UUID.randomUUID() : prepared.session().operationId();
        Path diagnosticDirectory = prepared == null ? null : prepared.diagnosticDirectory();
        RuntimeBundle runtime = prepared == null ? null : prepared.session().runtime();
        try {
            if (diagnosticDirectory == null) {
                diagnosticDirectory = diagnostics.beginDiagnostic(operationId);
                initializeDiagnosticFiles(diagnosticDirectory);
            }
            OfficialWchIspAdapter.DeviceDetectionResult detection = prepared == null
                ? officialAdapter.detectDevice()
                : officialAdapter.detectDevice(prepared.session());
            runtime = detection.runtime();
            if (runtime != null) writeRuntimeEvidence(diagnosticDirectory, runtime);
            if (prepared != null && detection.ispPresent()) prepared.session().markDeviceDetected();
            String detail = "RUNTIME_READY=" + (runtime == null ? "NO" : "YES") + "\n"
                + "ISP_PRESENT=" + (detection.ispPresent() ? "YES" : "NO") + "\n"
                + "OFFICIAL_ADAPTER_READY=" + (detection.ispPresent() ? "YES" : "NO") + "\n"
                + "UID_CONFIRMED=" + (detection.uid().isPresent() ? "YES" : "NO") + "\n"
                + "UID_SOURCE=OPTIONAL_VENDOR_CONTROL_PROCESS\n"
                + "OPERATION_ID=" + operationId + "\n"
                + "DIAGNOSTIC_DIRECTORY=" + (diagnosticDirectory == null ? "" : diagnosticDirectory) + "\n"
                + detection.detail();
            diagnostics.write(diagnosticDirectory, "adapter-detection.txt", detail + "\n");
            writeDiagnosticResult(diagnosticDirectory, null, detail,
                detection.ispPresent() ? null : FirmwareUpdateError.ISP_NOT_PRESENT);
            return new DiagnosticResult(runtime != null, detection.ispPresent(),
                detection.uid().isPresent(), runtime, detail,
                detection.ispPresent() ? null : FirmwareUpdateError.ISP_NOT_PRESENT,
                operationId, diagnosticDirectory, null, null, false, detection.ispPresent());
        } catch (Exception failure) {
            String detail = "OFFICIAL_ADAPTER_READY=NO\n"
                + "UID_CONFIRMED=NO\n"
                + "OPERATION_ID=" + operationId + "\n"
                + "DIAGNOSTIC_DIRECTORY=" + (diagnosticDirectory == null ? "" : diagnosticDirectory) + "\n"
                + (failure.getMessage() == null ? failure.toString() : failure.getMessage());
            writeDiagnosticResult(diagnosticDirectory, null, detail, FirmwareUpdateError.RUNTIME_INVALID);
            return new DiagnosticResult(runtime != null, false, false, runtime, detail,
                FirmwareUpdateError.RUNTIME_INVALID, operationId, diagnosticDirectory,
                null, null, false, false);
        } finally {
            diagnosticActive.set(false);
        }
    }

    public FirmwareOperationHandle activeOperation() {
        return active.get();
    }

    private void runOperation(FirmwareOperationHandle handle,
                              FirmwareUpdateRequest request,
                              AtomicBoolean cancellation) {
        if (officialAdapter != null) {
            runOfficialOperation(handle, request, cancellation);
            return;
        }
        Path diagnosticDirectory = null;
        try {
            diagnosticDirectory = diagnostics.begin(handle.operationId(), request);
            transition(handle, FirmwareUpdateState.PREFLIGHT, "正在检查固件和 WCHISP 运行环境", 0.02, null);
            PreflightResult preflight = preflight(request);
            if (!preflight.success()) {
                finish(handle, FirmwareUpdateState.FAILED, preflight.error(), preflight.detail(), diagnosticDirectory);
                return;
            }
            checkCancelled(cancellation);
            try (WchIspWorkspace workspace = WchIspWorkspace.create(workspaceParent, handle.operationId())) {
                WchIspWorkspace.PreparedWorkspace detectWorkspace = workspace.prepareForDetect(preflight.runtime());
                WchIspWorkspace.PreparedWorkspace flashWorkspace = workspace.prepareForFlash(
                    preflight.runtime(), request.firmwareHex());
                diagnostics.write(diagnosticDirectory, "runtime.json",
                    "{\"root\":\"" + escape(preflight.runtime().root().toString())
                        + "\",\"configSha256\":\"" + preflight.runtime().identity().configSha256() + "\"}\n");
                diagnostics.write(diagnosticDirectory, "effective-config-hash.txt",
                    "detect=" + WchIspConfigLayout.fingerprint(Files.readAllBytes(detectWorkspace.effectiveConfig()))
                        + "\nflash=" + WchIspConfigLayout.fingerprint(Files.readAllBytes(flashWorkspace.effectiveConfig())) + "\n");
                diagnostics.write(diagnosticDirectory, "firmware-info.txt",
                    "detectInput=" + detectWorkspace.firmwareInput() + "\nflashInput="
                        + flashWorkspace.firmwareInput() + "\ntarget=" + request.targetVersion() + "\n");

                transition(handle, FirmwareUpdateState.WAITING_ISP,
                    "请进入 CH582 ISP 模式，正在等待设备", 0.08, diagnosticDirectory);
                awaitIsp(cancellation);
                transition(handle, FirmwareUpdateState.DETECTING, "正在确认 CH582 ISP 设备", 0.12, diagnosticDirectory);
                ChipMatched.ChipMatchResult chip = inspectChip();
                boolean chipGateAllowed = chipGateAllowed(chip);
                writeChipEvidence(diagnosticDirectory, chip, chipGateAllowed);
                if (!chipGateAllowed) {
                    FirmwareUpdateError chipError = chip.mismatch()
                        ? FirmwareUpdateError.CHIP_MISMATCH : FirmwareUpdateError.CHIP_UNKNOWN;
                    finish(handle, FirmwareUpdateState.FAILED, chipError,
                        "CHIP_MATCH_STATUS=" + chip.status() + "\n" + chip.detail(), diagnosticDirectory);
                    return;
                }
                WchIspResultParser.UidQueryResult uid = null;
                String uidWarning = "";
                WchIspRunner.WchIspCommand uidCommand = new WchIspRunner.WchIspCommand(
                    detectWorkspace.executable(), workspace.toolDirectory(),
                    List.of("-c", detectWorkspace.configIni().toString(), "-u", "get"), UID_TIMEOUT,
                    handle.operationId());
                try {
                    WchIspRunner.WchIspProcessResult uidRaw = runner.run(uidCommand, cancellation::get);
                    saveProcess(diagnosticDirectory, "uid", uidCommand, uidRaw);
                    uid = WchIspResultParser.parseUid(uidRaw);
                    if (!uid.success()) uidWarning = uid.detail();
                } catch (Exception failure) {
                    if (cancellation.get()) throw new CancelledException();
                    if (failure instanceof InterruptedException) {
                        Thread.currentThread().interrupt();
                        throw new CancelledException();
                    }
                    uidWarning = failure.getMessage() == null ? failure.toString() : failure.getMessage();
                }
                if (!uidWarning.isBlank()) {
                    diagnostics.write(diagnosticDirectory, "uid-warning.txt", uidWarning);
                }
                transition(handle, FirmwareUpdateState.READY,
                    "已满足 CH582 烧录准备条件（UID "
                        + (uid != null && uid.success() ? uid.deviceUid() : "未确认")
                        + (uidWarning.isBlank() ? "" : "；UID 查询仅作警告：" + uidWarning)
                        + "），准备烧录", 0.18, diagnosticDirectory);

                checkCancelled(cancellation);
                transition(handle, FirmwareUpdateState.FLASHING,
                    "正在烧录固件，请勿断开 USB", 0.20, diagnosticDirectory);
                WchIspRunner.WchIspCommand flashCommand = new WchIspRunner.WchIspCommand(
                    flashWorkspace.executable(), workspace.toolDirectory(),
                    List.of("-c", flashWorkspace.configIni().toString(), "-o", "download", "-f",
                        flashWorkspace.firmwareInput().toString()), FLASH_TIMEOUT, handle.operationId());
                WchIspRunner.WchIspProcessResult flashRaw = runner.run(flashCommand, cancellation::get);
                saveProcess(diagnosticDirectory, "flash", flashCommand, flashRaw);
                WchIspResultParser.FlashExecutionResult flash = WchIspResultParser.parseFlash(flashRaw);
                if (!flash.success()) {
                    finish(handle, FirmwareUpdateState.FAILED, flash.error(), flash.detail(), diagnosticDirectory);
                    return;
                }
            }
            transition(handle, FirmwareUpdateState.WAITING_RECONNECT,
                "烧录完成，请退出 ISP 并正常重新连接设备", 0.92, diagnosticDirectory);
            checkCancelled(cancellation);
            if (postVerifier == null) {
                finish(handle, FirmwareUpdateState.FAILED, FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED,
                    "未配置设备回读校验器", diagnosticDirectory);
                return;
            }
            if (!postVerifier.awaitReconnect(RECONNECT_TIMEOUT, cancellation::get)) {
                finish(handle, FirmwareUpdateState.FAILED, FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED,
                    "设备未在时限内正常重连", diagnosticDirectory);
                return;
            }
            transition(handle, FirmwareUpdateState.VERIFYING,
                "正在读取设备版本并校验协议能力", 0.95, diagnosticDirectory);
            FirmwarePostVerifier.Verification verification = postVerifier.verify(
                request.targetVersion(), RECONNECT_TIMEOUT, cancellation::get);
            if (!verification.success()) {
                finish(handle, FirmwareUpdateState.FAILED, verification.error(), verification.detail(), diagnosticDirectory);
                return;
            }
            checkCancelled(cancellation);
            String completionDetail = verification.detail();
            Path uidWarningFile = diagnosticDirectory == null ? null : diagnosticDirectory.resolve("uid-warning.txt");
            if (uidWarningFile != null && Files.isRegularFile(uidWarningFile)) {
                try {
                    completionDetail = "UID_QUERY_WARNING=" + Files.readString(uidWarningFile)
                        + "\n" + completionDetail;
                } catch (IOException ignored) {
                    completionDetail = "UID_QUERY_WARNING=see diagnostic directory\n" + completionDetail;
                }
            }
            finish(handle, FirmwareUpdateState.SUCCESS, null, completionDetail, diagnosticDirectory);
        } catch (CancelledException cancelledException) {
            finish(handle, FirmwareUpdateState.CANCELLED, FirmwareUpdateError.CANCELLED,
                "固件操作已取消", diagnosticDirectory);
        } catch (Exception failure) {
            if (cancellation.get() || failure instanceof InterruptedException) {
                finish(handle, FirmwareUpdateState.CANCELLED, FirmwareUpdateError.CANCELLED,
                    "固件操作已取消", diagnosticDirectory);
                return;
            }
            FirmwareUpdateError error = classify(failure);
            finish(handle, FirmwareUpdateState.FAILED, error,
                failure.getMessage() == null ? failure.toString() : failure.getMessage(), diagnosticDirectory);
        }
    }

    /** Production path: Studio orchestrates states while the vendor adapter
     * performs detection and download.  No generated WCHISP workspace,
     * patched CONFIG, or {@code -u get} query is involved. */
    private void runOfficialOperation(FirmwareOperationHandle handle,
                                      FirmwareUpdateRequest request,
                                      AtomicBoolean cancellation) {
        Path diagnosticDirectory = null;
        try {
            diagnosticDirectory = diagnostics.begin(handle.operationId(), request);
            transition(handle, FirmwareUpdateState.PREFLIGHT,
                "正在检查固件和官方 WCHISP 运行环境", 0.02, diagnosticDirectory);
            PreflightResult preflight = preflight(request);
            if (!preflight.success()) {
                finish(handle, FirmwareUpdateState.FAILED, preflight.error(), preflight.detail(), diagnosticDirectory);
                return;
            }
            writeRuntimeEvidence(diagnosticDirectory, preflight.runtime());
            checkCancelled(cancellation);

            transition(handle, FirmwareUpdateState.WAITING_ISP,
                "请进入 CH582 ISP 模式，正在等待官方工具检测", 0.08, diagnosticDirectory);
            checkCancelled(cancellation);
            transition(handle, FirmwareUpdateState.DETECTING,
                "正在调用官方 WCHISP 检测设备", 0.12, diagnosticDirectory);
            OfficialWchIspAdapter.DeviceDetectionResult detection = officialAdapter.detectDevice();
            diagnostics.write(diagnosticDirectory, "adapter-detection.txt",
                "ISP_PRESENT=" + (detection.ispPresent() ? "YES" : "NO") + "\n"
                    + "UID_CONFIRMED=" + (detection.uid().isPresent() ? "YES" : "NO") + "\n"
                    + "UID_SOURCE=OPTIONAL_VENDOR_CONTROL_PROCESS\n"
                    + detection.detail() + "\n");
            if (!detection.ispPresent()) {
                finish(handle, FirmwareUpdateState.FAILED, FirmwareUpdateError.ISP_NOT_PRESENT,
                    "官方 WCHISP 未检测到 ISP 设备", diagnosticDirectory);
                return;
            }
            transition(handle, FirmwareUpdateState.READY,
                "官方 WCHISP 已检测到设备（UID 仅作可选信息），准备烧录", 0.18, diagnosticDirectory);
            checkCancelled(cancellation);

            transition(handle, FirmwareUpdateState.FLASHING,
                "正在调用官方 WCHISP 下载固件，请勿断开 USB", 0.20, diagnosticDirectory);
            OfficialWchIspAdapter.FlashResult flash = officialAdapter.flashFirmware(
                request.firmwareHex(), cancellation::get);
            saveAdapterProcess(diagnosticDirectory, flash);
            if (!flash.success()) {
                finish(handle, FirmwareUpdateState.FAILED, flashFailureError(flash),
                    flash.detail(), diagnosticDirectory);
                return;
            }

            transition(handle, FirmwareUpdateState.WAITING_RECONNECT,
                "官方 WCHISP 下载完成，请退出 ISP 并正常重新连接设备", 0.92, diagnosticDirectory);
            checkCancelled(cancellation);
            if (postVerifier == null) {
                finish(handle, FirmwareUpdateState.FAILED, FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED,
                    "未配置设备回读校验器", diagnosticDirectory);
                return;
            }
            if (!postVerifier.awaitReconnect(RECONNECT_TIMEOUT, cancellation::get)) {
                finish(handle, FirmwareUpdateState.FAILED, FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED,
                    "设备未在时限内正常重连", diagnosticDirectory);
                return;
            }
            transition(handle, FirmwareUpdateState.VERIFYING,
                "正在读取设备版本并校验协议能力", 0.95, diagnosticDirectory);
            FirmwarePostVerifier.Verification verification = postVerifier.verify(
                request.targetVersion(), RECONNECT_TIMEOUT, cancellation::get);
            if (!verification.success()) {
                finish(handle, FirmwareUpdateState.FAILED, verification.error(), verification.detail(), diagnosticDirectory);
                return;
            }
            checkCancelled(cancellation);
            finish(handle, FirmwareUpdateState.SUCCESS, null, verification.detail(), diagnosticDirectory);
        } catch (CancelledException cancelledException) {
            finish(handle, FirmwareUpdateState.CANCELLED, FirmwareUpdateError.CANCELLED,
                "固件操作已取消", diagnosticDirectory);
        } catch (Exception failure) {
            if (cancellation.get() || failure instanceof InterruptedException) {
                finish(handle, FirmwareUpdateState.CANCELLED, FirmwareUpdateError.CANCELLED,
                    "固件操作已取消", diagnosticDirectory);
                return;
            }
            finish(handle, FirmwareUpdateState.FAILED, classify(failure),
                failure.getMessage() == null ? failure.toString() : failure.getMessage(), diagnosticDirectory);
        }
    }

    /** Executes a session whose runtime, CONFIG and command were prepared before ISP. */
    private void runPreparedOfficialOperation(FirmwareOperationHandle handle,
                                              PreparedFirmwareOperation prepared,
                                              AtomicBoolean cancellation,
                                              Instant flashClickTime) {
        Path diagnosticDirectory = prepared.diagnosticDirectory();
        try {
            checkCancelled(cancellation);
            // Preparation and the ISP probe happened before the explicit click;
            // publish the already reached READY state without repeating them.
            handle.forceState(FirmwareUpdateState.READY);
            publish(new FirmwareUpdateStatus(handle.operationId(), FirmwareUpdateState.READY,
                null, "官方 WCHISP 会话已准备，准备烧录", 0.18, Instant.now()));
            if (diagnosticDirectory != null) diagnostics.write(diagnosticDirectory, "timing.json",
                "state=READY\nat=" + Instant.now() + "\n");
            checkCancelled(cancellation);

            transition(handle, FirmwareUpdateState.FLASHING,
                "正在立即调用官方 WCHISP 下载固件，请勿断开 USB", 0.20, diagnosticDirectory);
            OfficialWchIspAdapter.FlashResult flash = officialAdapter.flashPrepared(
                prepared.session(), cancellation::get);
            saveAdapterProcess(diagnosticDirectory, flash);
            Instant actualProcessStartTime = flash == null || flash.processResult() == null
                ? prepared.session().launchContext() == null
                    ? null : prepared.session().launchContext().actualProcessStartTime()
                : flash.processResult().actualProcessStartTime();
            writeFlashTiming(diagnosticDirectory, flashClickTime,
                prepared.session().launchContext(), actualProcessStartTime, flash);
            if (!flash.success()) {
                finish(handle, FirmwareUpdateState.FAILED, flashFailureError(flash),
                    flash.detail(), diagnosticDirectory);
                return;
            }

            transition(handle, FirmwareUpdateState.WAITING_RECONNECT,
                "官方 WCHISP 下载完成，请退出 ISP 并正常重新连接设备", 0.92, diagnosticDirectory);
            checkCancelled(cancellation);
            if (postVerifier == null) {
                finish(handle, FirmwareUpdateState.FAILED,
                    FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED,
                    "未配置设备回读校验器", diagnosticDirectory);
                return;
            }
            if (!postVerifier.awaitReconnect(RECONNECT_TIMEOUT, cancellation::get)) {
                finish(handle, FirmwareUpdateState.FAILED,
                    FirmwareUpdateError.POST_FLASH_DEVICE_NOT_RECONNECTED,
                    "设备未在时限内正常重连", diagnosticDirectory);
                return;
            }
            transition(handle, FirmwareUpdateState.VERIFYING,
                "正在读取设备版本并校验协议能力", 0.95, diagnosticDirectory);
            FirmwarePostVerifier.Verification verification = postVerifier.verify(
                prepared.request().targetVersion(), RECONNECT_TIMEOUT, cancellation::get);
            if (!verification.success()) {
                finish(handle, FirmwareUpdateState.FAILED, verification.error(),
                    verification.detail(), diagnosticDirectory);
                return;
            }
            checkCancelled(cancellation);
            finish(handle, FirmwareUpdateState.SUCCESS, null, verification.detail(), diagnosticDirectory);
        } catch (CancelledException cancelledException) {
            finish(handle, FirmwareUpdateState.CANCELLED, FirmwareUpdateError.CANCELLED,
                "固件操作已取消", diagnosticDirectory);
        } catch (Exception failure) {
            if (cancellation.get() || failure instanceof InterruptedException) {
                finish(handle, FirmwareUpdateState.CANCELLED, FirmwareUpdateError.CANCELLED,
                    "固件操作已取消", diagnosticDirectory);
                return;
            }
            finish(handle, FirmwareUpdateState.FAILED, classify(failure),
                failure.getMessage() == null ? failure.toString() : failure.getMessage(),
                diagnosticDirectory);
        } finally {
            preparedSessions.remove(prepared.session().operationId());
        }
    }

    private void awaitIsp(AtomicBoolean cancellation) throws Exception {
        if (!ispProbe.awaitPresent(ISP_TIMEOUT, cancellation::get)) {
            throw new IOException("未检测到 CH582 ISP 设备");
        }
    }

    private ChipMatched.ChipMatchResult inspectChip() {
        try {
            ChipMatched.ChipMatchResult result = chipMatched.inspect();
            return result == null
                ? ChipMatched.ChipMatchResult.unknown("芯片匹配器未返回结果") : result;
        } catch (Exception failure) {
            return ChipMatched.ChipMatchResult.unknown(
                "芯片匹配失败：" + (failure.getMessage() == null ? failure : failure.getMessage()));
        }
    }

    private boolean chipGateAllowed(ChipMatched.ChipMatchResult result) {
        return result != null && (result.matched() || (result.unknown() && allowUnknownChip));
    }

    private void writeChipEvidence(Path directory,
                                   ChipMatched.ChipMatchResult result,
                                   boolean gateAllowed) {
        if (directory == null) return;
        String status = result == null ? ChipMatched.Status.UNKNOWN.name() : result.status().name();
        String detail = result == null ? "" : result.detail();
        diagnostics.write(directory, "chip-match.txt", "CHIP_MATCH_STATUS=" + status + "\n"
            + "CHIP_GATE_ALLOWED=" + (gateAllowed ? "YES" : "NO") + "\n"
            + "DEV_ALLOW_UNKNOWN_CHIP=" + (allowUnknownChip ? "YES" : "NO") + "\n"
            + "DETAIL=" + detail + "\n");
    }

    private void transition(FirmwareOperationHandle handle, FirmwareUpdateState next,
                            String detail, double progress, Path diagnosticDirectory) {
        FirmwareUpdateState current = handle.state();
        if (!handle.transition(current, next)) {
            throw new IllegalStateException("非法固件状态转换: " + current + " -> " + next);
        }
        publish(new FirmwareUpdateStatus(handle.operationId(), next, null, detail, progress, Instant.now()));
        if (diagnosticDirectory != null) diagnostics.write(diagnosticDirectory, "timing.json",
            "state=" + next + "\nat=" + Instant.now() + "\n");
    }

    private void finish(FirmwareOperationHandle handle, FirmwareUpdateState state,
                        FirmwareUpdateError error, String detail, Path diagnosticDirectory) {
        if (!state.terminal()) throw new IllegalArgumentException("terminal state required");
        FirmwareUpdateResult result = new FirmwareUpdateResult(handle.operationId(), state, error,
            detail == null ? "" : detail, diagnosticDirectory, Instant.now());
        handle.complete(result);
        if (diagnosticDirectory != null) diagnostics.writeResult(diagnosticDirectory, result);
        publish(new FirmwareUpdateStatus(handle.operationId(), state, error, result.detail(),
            state == FirmwareUpdateState.SUCCESS ? 1.0 : 0.0, Instant.now()));
        active.compareAndSet(handle, null);
    }

    private void saveProcess(Path directory, String prefix, WchIspRunner.WchIspCommand command,
                             WchIspRunner.WchIspProcessResult result) {
        if (directory == null || result == null) return;
        if (command != null) {
            String commandText = command.executable() + " " + String.join(" ", command.arguments())
                + "\noperationId=" + command.operationId() + "\ntimeout=" + command.timeout() + "\n";
            diagnostics.write(directory, prefix + "-command.txt", commandText);
            diagnostics.write(directory, "command.txt", commandText);
        }
        diagnostics.write(directory, prefix + "-stdout.txt", result.stdout());
        diagnostics.write(directory, prefix + "-stderr.txt", result.stderr());
        diagnostics.write(directory, prefix + "-console.txt", result.console());
        diagnostics.write(directory, "stdout.txt", result.stdout());
        diagnostics.write(directory, "stderr.txt", result.stderr());
        diagnostics.write(directory, "console.txt", result.console());
        String resultJson = processResultJson(result);
        diagnostics.write(directory, prefix + "-result.json", resultJson);
        diagnostics.write(directory, "result.json", resultJson);
        diagnostics.write(directory, "timing.json", "{\n"
            + "  \"operationId\": \"" + result.operationId() + "\",\n"
            + "  \"durationMs\": " + result.duration().toMillis() + ",\n"
            + "  \"timedOut\": " + result.timedOut() + ",\n"
            + "  \"cancelled\": " + result.cancelled() + "\n"
            + "}\n");
    }

    private void saveAdapterProcess(Path directory, OfficialWchIspAdapter.FlashResult flash) {
        if (directory == null || flash == null) return;
        diagnostics.write(directory, "flash-command.txt", flash.detail());
        WchIspRunner.WchIspProcessResult result = flash.processResult();
        if (result == null) return;
        diagnostics.write(directory, "flash-stdout.txt", result.stdout());
        diagnostics.write(directory, "flash-stderr.txt", result.stderr());
        diagnostics.write(directory, "flash-console.txt", result.console());
        diagnostics.write(directory, "stdout.txt", result.stdout());
        diagnostics.write(directory, "stderr.txt", result.stderr());
        diagnostics.write(directory, "console.txt", result.console());
        String json = processResultJson(result);
        diagnostics.write(directory, "flash-result.json", json);
        diagnostics.write(directory, "result.json", json);
        String terminalResult = terminalResultFor(result);
        Instant processEnd = result.actualProcessStartTime() == null ? null
            : result.actualProcessStartTime().plus(result.duration());
        diagnostics.write(directory, "result.txt",
            "WCHISP_CHILD_PID=" + result.pid() + "\n"
                + "WCHISP_PROCESS_START_TIME="
                + (result.actualProcessStartTime() == null ? "" : result.actualProcessStartTime()) + "\n"
                + "WCHISP_PROCESS_END_TIME=" + (processEnd == null ? "" : processEnd) + "\n"
                + "WCHISP_DURATION_MS=" + result.duration().toMillis() + "\n"
                + "ELEVATION_USED=" + (result.elevationUsed() ? "YES" : "NO") + "\n"
                + "STDOUT_BYTES=" + utf8Bytes(result.stdout()) + "\n"
                + "STDERR_BYTES=" + utf8Bytes(result.stderr()) + "\n"
                + "CONSOLE_BYTES=" + utf8Bytes(result.console()) + "\n"
                + "TERMINAL_RESULT=" + terminalResult + "\n"
                + "TERMINAL_CODE=" + result.exitCode() + "\n"
                + "TERMINATION_REASON=" + result.terminationReason() + "\n");
        diagnostics.write(directory, "timing.json", "{\n"
            + "  \"operationId\": " + json(result.operationId().toString()) + ",\n"
            + "  \"processStartTime\": "
            + json(result.actualProcessStartTime() == null ? "" : result.actualProcessStartTime().toString()) + ",\n"
            + "  \"processEndTime\": " + json(processEnd == null ? "" : processEnd.toString()) + ",\n"
            + "  \"durationMs\": " + result.duration().toMillis() + ",\n"
            + "  \"exitCode\": " + result.exitCode() + ",\n"
            + "  \"terminationReason\": " + json(result.terminationReason()) + "\n"
            + "}\n");
    }

    private void initializeDiagnosticFiles(Path directory) {
        if (directory == null) return;
        diagnostics.write(directory, "command.txt", "UID_QUERY_NOT_STARTED\n");
        diagnostics.write(directory, "stdout.txt", "");
        diagnostics.write(directory, "stderr.txt", "");
        diagnostics.write(directory, "console.txt", "");
        diagnostics.write(directory, "runtime.json", "{\n  \"status\": \"NOT_RESOLVED\"\n}\n");
        diagnostics.write(directory, "result.json", "{\n  \"status\": \"NOT_STARTED\"\n}\n");
        diagnostics.write(directory, "timing.json", "{\n  \"status\": \"STARTED\"\n}\n");
    }

    private void writeRuntimeEvidence(Path directory, RuntimeBundle runtime) {
        if (directory == null || runtime == null) return;
        RuntimeIdentity identity = runtime.identity();
        diagnostics.write(directory, "runtime.json", "{\n"
            + "  \"root\": " + json(runtime.root().toString()) + ",\n"
            + "  \"executable\": " + json(runtime.executable().toString()) + ",\n"
            + "  \"executableFileVersion\": " + json(identity.executableFileVersion().orElse("")) + ",\n"
            + "  \"ispDllFileVersion\": " + json(identity.ispDllFileVersion().orElse("")) + ",\n"
            + "  \"ch343FileVersion\": " + json(identity.ch343FileVersion().orElse("")) + ",\n"
            + "  \"validationStatus\": " + json(identity.validationStatus().name()) + ",\n"
            + "  \"executableSha256\": " + json(identity.executableSha256()) + ",\n"
            + "  \"ispDllSha256\": " + json(identity.ispDllSha256()) + ",\n"
            + "  \"ch343Sha256\": " + json(identity.ch343Sha256()) + ",\n"
            + "  \"configSha256\": " + json(identity.configSha256()) + "\n"
            + "}\n");
    }

    private void writeDiagnosticResult(Path directory,
                                       WchIspRunner.WchIspProcessResult processResult,
                                       String detail, FirmwareUpdateError error) {
        if (directory == null) return;
        if (processResult == null) {
            diagnostics.write(directory, "result.json", "{\n"
                + "  \"status\": " + json(error == null ? "NO_PROCESS" : error.name()) + ",\n"
                + "  \"detail\": " + json(detail) + "\n}\n");
        }
        if (processResult == null) {
            diagnostics.write(directory, "timing.json", "{\n"
                + "  \"status\": " + json(error == null ? "COMPLETED" : error.name()) + ",\n"
                + "  \"operationId\": " + json(directory.getFileName().toString()) + "\n}\n");
        }
    }

    private void writePreparedSessionEvidence(Path directory, PreparedFlashSession session) {
        if (directory == null || session == null) return;
        WchIspRunner.WchIspCommand command = session.command();
        PreparedLaunchContext launch = session.launchContext();
        diagnostics.write(directory, "command.txt", command.executable() + " "
            + String.join(" ", command.arguments()) + "\noperationId="
            + command.operationId() + "\ntimeout=" + command.timeout() + "\n");
        diagnostics.write(directory, "prepared-session.json", "{\n"
            + "  \"operationId\": " + json(session.operationId().toString()) + ",\n"
            + "  \"runtime\": " + json(session.runtime().root().toString()) + ",\n"
            + "  \"config\": " + json(session.configPath().toString()) + ",\n"
            + "  \"hex\": " + json(session.hexPath().toString()) + ",\n"
            + "  \"SELECTED_HEX_PATH\": " + json(session.hexPath().toString()) + ",\n"
            + "  \"FLASH_COMMAND_HEX_PATH\": " + json(flashHexPath(command)) + ",\n"
            + "  \"createdAt\": " + json(session.createdAt().toString()) + ",\n"
            + "  \"state\": " + json(session.state().name()) + ",\n"
            + "  \"workerOwner\": " + json(session.workerOwner()) + ",\n"
            + "  \"launchContextReady\": " + (launch != null && launch.ready()) + ",\n"
            + "  \"workerRunning\": " + (launch != null && launch.workerRunning()) + ",\n"
            + "  \"workerPid\": " + (launch == null ? -1 : launch.workerPid()) + ",\n"
            + "  \"wrapperPid\": " + (launch == null ? -1 : launch.wrapperPid()) + ",\n"
            + "  \"controlDirectory\": " + json(launch == null ? "" : launch.controlDirectory().toString()) + ",\n"
            + "  \"nonce\": " + json(launch == null ? "" : launch.nonce()) + "\n"
            + "}\n");
    }

    private void writeFlashTiming(Path directory, Instant clickTime,
                                  PreparedLaunchContext launchContext,
                                  Instant actualProcessStartTime,
                                  OfficialWchIspAdapter.FlashResult flash) {
        if (directory == null) return;
        Instant goSignalTime = launchContext == null ? null : launchContext.goSignalTime();
        long clickToGo = clickTime == null || goSignalTime == null ? -1
            : Math.max(0, java.time.Duration.between(clickTime, goSignalTime).toMillis());
        long goToStart = goSignalTime == null || actualProcessStartTime == null ? -1
            : Math.max(0, java.time.Duration.between(goSignalTime, actualProcessStartTime).toMillis());
        long clickToStart = clickTime == null || actualProcessStartTime == null ? -1
            : Math.max(0, java.time.Duration.between(clickTime, actualProcessStartTime).toMillis());
        long duration = flash == null || flash.processResult() == null
            ? -1 : flash.processResult().duration().toMillis();
        diagnostics.write(directory, "flash-timing.json", "{\n"
            + "  \"FLASH_CLICK_TIME\": " + json(clickTime == null ? "" : clickTime.toString()) + ",\n"
            + "  \"GO_SIGNAL_TIME\": " + json(goSignalTime == null ? "" : goSignalTime.toString()) + ",\n"
            + "  \"ACTUAL_WCHISP_PROCESS_START_TIME\": "
            + json(actualProcessStartTime == null ? "" : actualProcessStartTime.toString()) + ",\n"
            + "  \"CLICK_TO_GO_MS\": " + clickToGo + ",\n"
            + "  \"GO_TO_WCHISP_START_MS\": " + goToStart + ",\n"
            + "  \"CLICK_TO_WCHISP_START_MS\": " + clickToStart + ",\n"
            + "  \"DOWNLOAD_PROCESS_DURATION_MS\": " + duration + "\n"
            + "}\n");
    }

    private static String diagnosticDetail(UUID operationId, Path directory,
                                           RuntimeBundle runtime, boolean ispPresent,
                                           ChipMatched.ChipMatchResult chip,
                                           boolean chipGateAllowed,
                                           WchIspResultParser.UidQueryResult uid,
                                           WchIspRunner.WchIspProcessResult processResult,
                                           String summary) {
        StringBuilder detail = new StringBuilder()
            .append("RUNTIME_READY=").append(runtime == null ? "NO" : "YES").append('\n')
            .append("ISP_PRESENT=").append(ispPresent ? "YES" : "NO").append('\n')
            .append("CHIP_MATCHED=").append(chip != null && chip.matched() ? "YES" : "NO").append('\n')
            .append("CHIP_MATCH_STATUS=").append(chip == null ? ChipMatched.Status.UNKNOWN : chip.status()).append('\n')
            .append("CHIP_GATE_ALLOWED=").append(chipGateAllowed ? "YES" : "NO").append('\n')
            .append("UID_CONFIRMED=").append(uid != null && uid.success() ? "YES" : "NO").append('\n')
            .append("OPERATION_ID=").append(operationId).append('\n')
            .append("DIAGNOSTIC_DIRECTORY=").append(directory == null ? "" : directory).append('\n');
        if (processResult == null) {
            detail.append("UID_QUERY_EXIT_CODE=NOT_STARTED\n")
                .append("UID_QUERY_DURATION_MS=NOT_STARTED\n")
                .append("WCHISP_PID=NOT_STARTED\n")
                .append("ELEVATION_USED=NOT_STARTED\n")
                .append("TERMINATION_REASON=NOT_STARTED\n")
                .append("STDOUT=\nSTDERR=\nCONSOLE=\n");
        } else {
            detail.append("UID_QUERY_EXIT_CODE=").append(processResult.exitCode()).append('\n')
                .append("UID_QUERY_DURATION_MS=").append(processResult.duration().toMillis()).append('\n')
                .append("WCHISP_PID=").append(processResult.pid()).append('\n')
                .append("ELEVATION_USED=").append(processResult.elevationUsed() ? "YES" : "NO").append('\n')
                .append("TERMINATION_REASON=").append(processResult.terminationReason()).append('\n')
                .append("OWNED_PROCESS_IDS=").append(processResult.ownedProcessIds()).append('\n')
                .append("STDOUT=").append(summarize(processResult.stdout())).append('\n')
                .append("STDERR=").append(summarize(processResult.stderr())).append('\n')
                .append("CONSOLE=").append(summarize(processResult.console())).append('\n');
        }
        detail.append(summary == null ? "" : summary);
        return detail.toString();
    }

    private static String commandText(WchIspRunner.WchIspCommand command) {
        return command.executable() + " " + String.join(" ", command.arguments())
            + "\noperationId=" + command.operationId() + "\ntimeout=" + command.timeout() + "\n";
    }

    private static String flashHexPath(WchIspRunner.WchIspCommand command) {
        if (command == null) return "";
        List<String> arguments = command.arguments();
        for (int index = 0; index + 1 < arguments.size(); index++) {
            if ("-f".equalsIgnoreCase(arguments.get(index))) {
                return Path.of(arguments.get(index + 1)).toAbsolutePath().normalize().toString();
            }
        }
        return "";
    }

    private static String processResultJson(WchIspRunner.WchIspProcessResult result) {
        return "{\n"
            + "  \"operationId\": " + json(result.operationId().toString()) + ",\n"
            + "  \"pid\": " + result.pid() + ",\n"
            + "  \"ownedProcessIds\": " + json(result.ownedProcessIds().toString()) + ",\n"
            + "  \"exitCode\": " + result.exitCode() + ",\n"
            + "  \"timedOut\": " + result.timedOut() + ",\n"
            + "  \"cancelled\": " + result.cancelled() + ",\n"
            + "  \"durationMs\": " + result.duration().toMillis() + ",\n"
            + "  \"actualProcessStartTime\": "
            + json(result.actualProcessStartTime() == null ? "" : result.actualProcessStartTime().toString()) + ",\n"
            + "  \"actualProcessEndTime\": "
            + json(result.actualProcessStartTime() == null ? ""
                : result.actualProcessStartTime().plus(result.duration()).toString()) + ",\n"
            + "  \"stdoutBytes\": " + utf8Bytes(result.stdout()) + ",\n"
            + "  \"stderrBytes\": " + utf8Bytes(result.stderr()) + ",\n"
            + "  \"consoleBytes\": " + utf8Bytes(result.console()) + ",\n"
            + "  \"terminalResult\": "
            + json(terminalResultFor(result)) + ",\n"
            + "  \"terminalCode\": " + result.exitCode() + ",\n"
            + "  \"elevationUsed\": " + result.elevationUsed() + ",\n"
            + "  \"terminationReason\": " + json(result.terminationReason()) + "\n"
            + "}\n";
    }

    private static int utf8Bytes(String value) {
        return (value == null ? "" : value).getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
    }

    private static String terminalResultFor(WchIspRunner.WchIspProcessResult result) {
        if (result.timedOut()) return "TIMEOUT";
        String output = result.stdout() + "\n" + result.stderr() + "\n" + result.console();
        if (output.contains("Device UID:")) return "DEVICE_UID";
        return WchIspResultParser.parseFlash(result).success() ? "SUCCESS" : "FAIL";
    }

    private static String summarize(String value) {
        if (value == null || value.isEmpty()) return "";
        String normalized = value.replace("\r", "").replace("\n", "\\n");
        return normalized.length() <= 2048 ? normalized : normalized.substring(0, 2048) + "... [truncated; see console.txt]";
    }

    private static String json(String value) {
        return "\"" + (value == null ? "" : value)
            .replace("\\", "\\\\").replace("\"", "\\\"")
            .replace("\r", "\\r").replace("\n", "\\n") + "\"";
    }

    private static FirmwareUpdateError classify(Exception failure) {
        if (failure instanceof IOException) {
            String message = String.valueOf(failure.getMessage()).toLowerCase();
            if (message.contains("runtime")) return FirmwareUpdateError.RUNTIME_INVALID;
            if (message.contains("hex")) return FirmwareUpdateError.HEX_INVALID;
            if (message.contains("isp")) return FirmwareUpdateError.ISP_NOT_PRESENT;
        }
        return FirmwareUpdateError.INTERNAL_ERROR;
    }

    static FirmwareUpdateError flashFailureError(OfficialWchIspAdapter.FlashResult flash) {
        if (flash == null || flash.processResult() == null) {
            return FirmwareUpdateError.FLASH_FAILED;
        }
        return WchIspResultParser.parseFlash(flash.processResult()).error();
    }

    private void publish(FirmwareUpdateStatus status) {
        listeners.forEach(listener -> {
            try { listener.accept(status); } catch (RuntimeException ignored) { }
        });
    }

    private static void checkCancelled(AtomicBoolean cancelled) throws CancelledException {
        if (cancelled.get()) throw new CancelledException();
    }

    private static String escape(String value) {
        return value == null ? "" : value.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    static boolean isLegalTransition(FirmwareUpdateState from, FirmwareUpdateState to) {
        if (from == null || to == null || from.terminal()) return false;
        return switch (from) {
            case IDLE -> to == FirmwareUpdateState.PREFLIGHT || to == FirmwareUpdateState.CANCELLED;
            case PREFLIGHT -> to == FirmwareUpdateState.WAITING_ISP || to == FirmwareUpdateState.FAILED
                || to == FirmwareUpdateState.CANCELLED;
            case WAITING_ISP -> to == FirmwareUpdateState.DETECTING || to == FirmwareUpdateState.FAILED
                || to == FirmwareUpdateState.CANCELLED;
            case DETECTING -> to == FirmwareUpdateState.READY || to == FirmwareUpdateState.FAILED
                || to == FirmwareUpdateState.CANCELLED;
            case READY -> to == FirmwareUpdateState.FLASHING || to == FirmwareUpdateState.FAILED
                || to == FirmwareUpdateState.CANCELLED;
            case FLASHING -> to == FirmwareUpdateState.WAITING_RECONNECT || to == FirmwareUpdateState.FAILED
                || to == FirmwareUpdateState.CANCELLED;
            case WAITING_RECONNECT -> to == FirmwareUpdateState.VERIFYING || to == FirmwareUpdateState.FAILED
                || to == FirmwareUpdateState.CANCELLED;
            case VERIFYING -> to == FirmwareUpdateState.SUCCESS || to == FirmwareUpdateState.FAILED
                || to == FirmwareUpdateState.CANCELLED;
            default -> false;
        };
    }

    static final class CancelledException extends Exception { }

    @Override
    public void close() {
        shutdown();
    }

    public void shutdown() {
        if (!shuttingDown.compareAndSet(false, true)) return;
        preparedSessions.values().forEach(PreparedFlashSession::cancel);
        preparedSessions.clear();
        FirmwareOperationHandle current = active.get();
        if (current != null) current.cancel();
        executor.shutdownNow();
        try { executor.awaitTermination(2, TimeUnit.SECONDS); }
        catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); }
    }

    public record OperationStart(boolean accepted, FirmwareOperationHandle handle,
                                 FirmwareUpdateResult rejection) {
        static OperationStart accepted(FirmwareOperationHandle handle) {
            return new OperationStart(true, handle, null);
        }
        static OperationStart busy() { return rejected(FirmwareUpdateError.BUSY, "另一个固件操作正在执行"); }
        static OperationStart rejected(FirmwareUpdateError error, String detail) {
            return new OperationStart(false, null, new FirmwareUpdateResult(null,
                FirmwareUpdateState.FAILED, error, detail, null, Instant.now()));
        }
    }

    public record PreflightResult(boolean success, FirmwareUpdateError error,
                                  String detail, RuntimeBundle runtime) {
        static PreflightResult failure(FirmwareUpdateError error, String detail) {
            return new PreflightResult(false, error, detail == null ? "" : detail, null);
        }
    }

    public record PreparedFirmwareOperation(FirmwareUpdateRequest request,
                                            PreparedFlashSession session,
                                            Path diagnosticDirectory) {
        public PreparedFirmwareOperation {
            if (request == null || session == null) {
                throw new IllegalArgumentException("prepared operation inputs are missing");
            }
            diagnosticDirectory = diagnosticDirectory == null ? null
                : diagnosticDirectory.toAbsolutePath().normalize();
        }

        public boolean cancel() { return session.cancel(); }
        public boolean armed() { return session.state() == PreparedFlashSession.State.ARMED; }
    }

    public record PreparationResult(boolean prepared,
                                    FirmwareUpdateError error,
                                    String detail,
                                    PreparedFirmwareOperation operation,
                                    Path diagnosticDirectory) {
        public PreparationResult {
            detail = detail == null ? "" : detail;
            diagnosticDirectory = diagnosticDirectory == null ? null
                : diagnosticDirectory.toAbsolutePath().normalize();
        }

        static PreparationResult success(PreparedFirmwareOperation operation) {
            return new PreparationResult(true, null, "烧录会话已准备", operation,
                operation.diagnosticDirectory());
        }

        static PreparationResult failure(FirmwareUpdateError error, String detail) {
            return failure(error, detail, null);
        }

        static PreparationResult failure(FirmwareUpdateError error, String detail,
                                         Path diagnosticDirectory) {
            return new PreparationResult(false, error, detail, null, diagnosticDirectory);
        }

        static PreparationResult busy() {
            return failure(FirmwareUpdateError.BUSY, "另一个固件操作正在执行");
        }
    }

    public record DiagnosticResult(boolean runtimeReady, boolean ispPresent,
                                   boolean uidConfirmed, RuntimeBundle runtime,
                                   String detail, FirmwareUpdateError error,
                                   UUID operationId, Path diagnosticDirectory,
                                   WchIspRunner.WchIspProcessResult processResult,
                                   ChipMatched.ChipMatchResult chipMatch,
                                   boolean chipGateAllowed,
                                   boolean officialAdapterReady) {
        public DiagnosticResult(boolean ispPresent, RuntimeBundle runtime,
                                String detail, FirmwareUpdateError error) {
            this(runtime != null, ispPresent, false, runtime, detail, error,
                null, null, null, null, false, false);
        }
        public DiagnosticResult(boolean runtimeReady, boolean ispPresent,
                                boolean uidConfirmed, RuntimeBundle runtime,
                                String detail, FirmwareUpdateError error) {
            this(runtimeReady, ispPresent, uidConfirmed, runtime, detail, error,
                null, null, null, null, false, false);
        }
        public boolean chipMatched() { return chipMatch != null && chipMatch.matched(); }
        public String chipMatchStatus() {
            return chipMatch == null ? ChipMatched.Status.UNKNOWN.name() : chipMatch.status().name();
        }
        public boolean ready() {
            return runtimeReady && ispPresent && (officialAdapterReady || chipGateAllowed) && error == null;
        }
        static DiagnosticResult failure(FirmwareUpdateError error, String detail) {
            return new DiagnosticResult(false, false, false, null, detail == null ? "" : detail, error,
                null, null, null, null, false, false);
        }
        static DiagnosticResult failure(String detail, FirmwareUpdateError error) {
            return failure(error, detail);
        }
    }
}
