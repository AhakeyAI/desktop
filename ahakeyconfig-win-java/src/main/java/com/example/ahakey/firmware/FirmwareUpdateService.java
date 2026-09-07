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

    private final RuntimeProvider runtimeProvider;
    private final IspDeviceProbe ispProbe;
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

    public FirmwareUpdateService(BleManager manager) {
        this(new WchIspRuntimeProvider(), IspDeviceProbe.windowsDefault(), new WchIspRunner(),
            manager == null ? null : new FirmwarePostVerifier(manager),
            new FirmwareUpdateDiagnostics(), Path.of(System.getProperty("java.io.tmpdir")));
    }

    public FirmwareUpdateService(RuntimeProvider runtimeProvider,
                                 IspDeviceProbe ispProbe,
                                 WchIspRunner runner,
                                 FirmwarePostVerifier postVerifier,
                                 FirmwareUpdateDiagnostics diagnostics,
                                 Path workspaceParent) {
        this.runtimeProvider = runtimeProvider == null ? new WchIspRuntimeProvider() : runtimeProvider;
        this.ispProbe = ispProbe == null ? IspDeviceProbe.windowsDefault() : ispProbe;
        this.runner = runner == null ? new WchIspRunner() : runner;
        this.postVerifier = postVerifier;
        this.diagnostics = diagnostics == null ? new FirmwareUpdateDiagnostics() : diagnostics;
        this.workspaceParent = workspaceParent == null
            ? Path.of(System.getProperty("java.io.tmpdir")) : workspaceParent;
        this.executor = Executors.newSingleThreadExecutor(task -> {
            Thread thread = new Thread(task, "firmware-update");
            thread.setDaemon(true);
            return thread;
        });
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

    /** Non-destructive environment/ISP report used by the maintenance UI. */
    public DiagnosticResult diagnose() {
        synchronized (admissionMonitor) {
            if (shuttingDown.get()) return DiagnosticResult.failure(FirmwareUpdateError.CANCELLED, "应用正在退出");
            if (active.get() != null || !diagnosticActive.compareAndSet(false, true)) {
                return DiagnosticResult.failure(FirmwareUpdateError.BUSY, "固件操作正在执行");
            }
        }
        try {
            RuntimeBundle runtime = runtimeProvider.resolve();
            boolean present = ispProbe.isPresent();
            if (!present) return new DiagnosticResult(true, false, false, runtime,
                "RUNTIME_READY=YES\nISP_PRESENT=NO\nUID_CONFIRMED=NO\n未检测到 CH582 ISP 设备", null);
            try (WchIspWorkspace workspace = WchIspWorkspace.create(workspaceParent, UUID.randomUUID())) {
                WchIspWorkspace.PreparedWorkspace detect = workspace.prepareForDetect(runtime);
                WchIspRunner.WchIspCommand command = new WchIspRunner.WchIspCommand(
                    detect.executable(), workspace.toolDirectory(),
                    List.of("-c", detect.configIni().toString(), "-u", "get"), UID_TIMEOUT,
                    UUID.randomUUID());
                WchIspResultParser.UidQueryResult uid = WchIspResultParser.parseUid(
                    runner.run(command, WchIspRunner.CancellationToken.NONE));
                return new DiagnosticResult(true, true, uid.success(), runtime,
                    "RUNTIME_READY=YES\nISP_PRESENT=YES\nUID_CONFIRMED="
                        + (uid.success() ? "YES" : "NO") + "\n" + uid.detail(),
                    uid.success() ? null : uid.error());
            }
        } catch (Exception failure) {
            return DiagnosticResult.failure(
                failure.getMessage() == null ? failure.toString() : failure.getMessage(),
                failure instanceof IOException
                    ? (String.valueOf(failure.getMessage()).toLowerCase().contains("not found")
                        ? FirmwareUpdateError.RUNTIME_NOT_FOUND : FirmwareUpdateError.RUNTIME_INVALID)
                    : FirmwareUpdateError.INTERNAL_ERROR);
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
                transition(handle, FirmwareUpdateState.DETECTING, "正在读取设备 UID", 0.12, diagnosticDirectory);
                WchIspRunner.WchIspCommand uidCommand = new WchIspRunner.WchIspCommand(
                    detectWorkspace.executable(), workspace.toolDirectory(),
                    List.of("-c", detectWorkspace.configIni().toString(), "-u", "get"), UID_TIMEOUT,
                    handle.operationId());
                WchIspRunner.WchIspProcessResult uidRaw = runner.run(uidCommand, cancellation::get);
                saveProcess(diagnosticDirectory, "uid", uidCommand, uidRaw);
                WchIspResultParser.UidQueryResult uid = WchIspResultParser.parseUid(uidRaw);
                if (!uid.success()) {
                    finish(handle, FirmwareUpdateState.FAILED, uid.error(), uid.detail(), diagnosticDirectory);
                    return;
                }
                transition(handle, FirmwareUpdateState.READY,
                    "已检测到 CH582（UID " + uid.deviceUid() + "），准备烧录", 0.18, diagnosticDirectory);

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
            FirmwareUpdateError error = classify(failure);
            finish(handle, FirmwareUpdateState.FAILED, error,
                failure.getMessage() == null ? failure.toString() : failure.getMessage(), diagnosticDirectory);
        }
    }

    private void awaitIsp(AtomicBoolean cancellation) throws Exception {
        if (!ispProbe.awaitPresent(ISP_TIMEOUT, cancellation::get)) {
            throw new IOException("未检测到 CH582 ISP 设备");
        }
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
        diagnostics.write(directory, prefix + "-result.json",
            "operationId=" + result.operationId() + "\npid=" + result.pid()
                + "\nownedPids=" + result.ownedProcessIds() + "\nexitCode=" + result.exitCode()
                + "\nreason=" + result.terminationReason() + "\n");
        diagnostics.write(directory, "result.json",
            "operationId=" + result.operationId() + "\npid=" + result.pid()
                + "\nownedPids=" + result.ownedProcessIds() + "\nexitCode=" + result.exitCode()
                + "\nreason=" + result.terminationReason() + "\n");
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

    public record DiagnosticResult(boolean runtimeReady, boolean ispPresent,
                                   boolean uidConfirmed, RuntimeBundle runtime,
                                   String detail, FirmwareUpdateError error) {
        public DiagnosticResult(boolean ispPresent, RuntimeBundle runtime,
                                String detail, FirmwareUpdateError error) {
            this(runtime != null, ispPresent, false, runtime, detail, error);
        }
        public boolean ready() { return runtimeReady && ispPresent && uidConfirmed && error == null; }
        static DiagnosticResult failure(FirmwareUpdateError error, String detail) {
            return new DiagnosticResult(false, false, false, null, detail == null ? "" : detail, error);
        }
        static DiagnosticResult failure(String detail, FirmwareUpdateError error) {
            return failure(error, detail);
        }
    }
}
