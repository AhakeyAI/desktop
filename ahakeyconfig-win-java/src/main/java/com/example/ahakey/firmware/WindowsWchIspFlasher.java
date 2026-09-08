package com.example.ahakey.firmware;

import com.sun.jna.platform.win32.Advapi32Util;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class WindowsWchIspFlasher implements FirmwareFlasher {
    static final String SANITIZED_CONFIG_RESOURCE =
        "/wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH";
    /** @deprecated use {@link WchIspConfigLayout}; retained for test compatibility. */
    @Deprecated static final int WCH_CONFIG_LENGTH = WchIspConfigLayout.CONFIG_SIZE;
    @Deprecated static final int WCH_PATH_SLOT_BYTES = WchIspConfigLayout.SLOT_SIZE;
    @Deprecated static final int[] WCH_PATH_SLOT_OFFSETS = WchIspConfigLayout.SLOT_OFFSETS;
    @Deprecated static final int CH582_SLOT_INDEX = WchIspConfigLayout.CH582_SLOT_INDEX;
    @Deprecated static final String SANITIZED_LAYOUT_SHA256 = WchIspConfigLayout.FINGERPRINT;
    private static final Duration COMMAND_TIMEOUT = Duration.ofMinutes(5);
    private static final Pattern STATUS_PATTERN = Pattern.compile(
        "\"Status\"\\s*:\\s*\"(Finished|Fail)\""
    );
    private static final Pattern CODE_PATTERN = Pattern.compile(
        "\"Code\"\\s*:\\s*(\\d+)"
    );
    private static final Pattern SUCCESS_MESSAGE_PATTERN = Pattern.compile(
        "\"Message\"\\s*:\\s*\"Succeed\""
    );
    private static final Pattern PROGRESS_PATTERN = Pattern.compile(
        "\"Status\"\\s*:\\s*\"Programming\"\\s*,\\s*\"Progress\"\\s*:\\s*(\\d+)%"
    );
    private final Path executable;
    private final IspDeviceProbe ispDeviceProbe;

    public WindowsWchIspFlasher() {
        this(locateExecutable());
    }

    public WindowsWchIspFlasher(Path executable) {
        this(executable, WindowsWchIspFlasher::isIspDeviceEnumerated);
    }

    WindowsWchIspFlasher(Path executable, IspDeviceProbe ispDeviceProbe) {
        this.executable = executable;
        this.ispDeviceProbe = ispDeviceProbe == null
            ? WindowsWchIspFlasher::isIspDeviceEnumerated : ispDeviceProbe;
    }

    public Path executable() {
        return executable;
    }

    /** Performs non-destructive checks that are safe to include in a support report. */
    public EnvironmentReport diagnoseEnvironment() {
        List<String> checks = new ArrayList<>();
        boolean ready = true;
        Path tool = executable == null ? null : executable.toAbsolutePath().normalize();
        Path directory = tool == null ? null : tool.getParent();
        ready &= check(checks, tool != null && Files.isRegularFile(tool), "WCHISP 主程序", tool);
        if (directory == null) {
            checks.add("[失败] WCHISP 工具目录无效");
            return new EnvironmentReport(false, checks);
        }
        ready &= check(checks, Files.isRegularFile(directory.resolve("CH343PT.DLL")),
            "CH343PT.DLL", directory.resolve("CH343PT.DLL"));
        ready &= check(checks, Files.isRegularFile(directory.resolve("WCH55xISPDLL.dll")),
            "WCH55xISPDLL.dll", directory.resolve("WCH55xISPDLL.dll"));
        ready &= check(checks, bundledSanitizedConfigAvailable(),
            "受控脱敏 CH57x-59x 基础配置", Path.of(SANITIZED_CONFIG_RESOURCE.substring(1)));
        WchIspRuntimeContract.Validation contract =
            WchIspRuntimeContract.validate(directory);
        if (contract.supported()) {
            checks.add("[通过] WCHISP 运行环境版本合同: "
                + WchIspRuntimeContract.EXPECTED_VERSION);
        } else {
            checks.add("[失败] " + contract.summary());
            ready = false;
        }
        try {
            Path probe = Files.createTempFile("ahakey-wchisp-write-test-", ".tmp");
            Files.deleteIfExists(probe);
            checks.add("[通过] 临时目录可读写");
        } catch (IOException exception) {
            checks.add("[失败] 临时目录不可写: " + exception.getMessage());
            ready = false;
        }
        checks.add("[提示] ISP/驱动检测需设备进入 ISP 模式后执行");
        return new EnvironmentReport(ready, checks);
    }

    private static boolean check(
        List<String> checks, boolean passed, String name, Path path
    ) {
        String safeName = path == null || path.getFileName() == null
            ? "未知文件"
            : path.getFileName().toString();
        checks.add((passed ? "[通过] " : "[失败] ") + name + ": " + safeName);
        return passed;
    }

    @Override
    public DeviceInfo detect() throws Exception {
        ensureAvailable();
        Path workDir = Files.createTempDirectory("ahakey-wchisp-detect-");
        try {
            Path placeholder = workDir.resolve("unused.hex");
            Files.writeString(
                placeholder,
                ":00000001FF\n",
                StandardCharsets.US_ASCII
            );
            Path preparedExecutable = prepareToolWorkspace(
                workDir.resolve("tool"),
                placeholder
            );
            Path config = workDir.resolve("config.ini");
            Files.writeString(
                config,
                WchIspConfig.forCh582(placeholder),
                StandardCharsets.UTF_8
            );
            CommandResult result = run(
                preparedExecutable,
                List.of("-c", config.toString(), "-u", "get"),
                Duration.ofSeconds(20),
                null
            );
            return new DeviceInfo(
                result.exitCode() == 0,
                result.exitCode() == 0
                    ? result.output()
                    : detectionFailureDetail(result)
            );
        } finally {
            deleteQuietly(workDir);
        }
    }

    @Override
    public FlashResult flashAndVerify(Path firmwareHex, ProgressListener listener)
        throws Exception {
        ensureAvailable();
        Path normalized = firmwareHex.toAbsolutePath().normalize();
        if (!Files.isRegularFile(normalized)
            || !normalized.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".hex")) {
            throw new IOException("请选择有效的 .hex 固件文件");
        }
        IntelHexValidator.validate(normalized);

        Path workDir = Files.createTempDirectory("ahakey-wchisp-");
        try {
            Path preparedExecutable = prepareToolWorkspace(
                workDir.resolve("tool"),
                normalized
            );
            Path config = workDir.resolve("config.ini");
            Files.writeString(
                config,
                WchIspConfig.forCh582(normalized),
                StandardCharsets.UTF_8
            );

            listener.onProgress("download", 0.10, "正在检测 CH582 并烧录，请勿断开 USB…");
            CommandResult download = run(
                preparedExecutable,
                List.of("-c", config.toString(), "-o", "download", "-f", normalized.toString()),
                COMMAND_TIMEOUT,
                listener
            );
            if (download.exitCode() != 0) {
                return failed("download", download);
            }

            listener.onProgress(
                "complete",
                1.0,
                "WCHISP 已完成写入和字节校验，等待设备运行版本确认"
            );
            return new FlashResult(true, "complete", download.output());
        } finally {
            deleteQuietly(workDir);
        }
    }

    private FlashResult failed(String stage, CommandResult result) {
        return new FlashResult(
            false,
            stage,
            WchIspExitCodes.describe(result.exitCode()) + outputSuffix(result)
        );
    }

    private String outputSuffix(CommandResult result) {
        return result.output().isBlank() ? "" : "\n" + result.output().trim();
    }

    private String detectionFailureDetail(CommandResult result) {
        boolean enumerated = false;
        try {
            enumerated = ispDeviceProbe.isEnumerated();
        } catch (RuntimeException ignored) {
            // A failed enumeration probe is treated as not proven present.
        }
        return detectionFailureDetail(result.exitCode(), enumerated, outputSuffix(result));
    }

    static String detectionFailureDetail(int exitCode, boolean enumerated, String suffix) {
        suffix = suffix == null ? "" : suffix;
        if (exitCode == 100 && enumerated) {
            return "已检测到 WCH ISP 设备，但 WCHISP 工具读取设备 UID 失败（错误码 100）"
                + suffix;
        }
        if (!enumerated) {
            return "未检测到 WCH ISP 设备（WCHISP 返回错误码 "
                + exitCode + "）" + suffix;
        }
        return "已检测到 WCH ISP 设备，但 WCHISP 返回错误码 "
            + exitCode + suffix;
    }

    private CommandResult run(
        Path commandExecutable,
        List<String> arguments,
        Duration timeout,
        ProgressListener listener
    ) throws Exception {
        long startedAt = System.nanoTime();
        java.time.Instant actualStart = java.time.Instant.now();
        List<String> command = new ArrayList<>();
        command.add(commandExecutable.toString());
        command.addAll(arguments);
        Process process;
        try {
            process = new ProcessBuilder(command)
                .directory(commandExecutable.getParent().toFile())
                .redirectErrorStream(true)
                .start();
        } catch (IOException exception) {
            if (exception.getMessage() == null
                || !exception.getMessage().contains("CreateProcess error=740")) {
                throw exception;
            }
            return runElevated(commandExecutable, arguments, timeout, listener);
        }
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        Thread reader = new Thread(() -> copy(process.getInputStream(), output), "wchisp-output");
        reader.setDaemon(true);
        reader.start();

        boolean allowDeviceUid = arguments.contains("get");
        long deadline = System.nanoTime() + timeout.toNanos();
        long nonZeroExitAt = 0;
        int lastProgress = -1;
        while (System.nanoTime() < deadline) {
            String currentOutput = output.toString(Charset.defaultCharset());
            lastProgress = reportProgress(currentOutput, lastProgress, listener);
            Integer terminalCode = terminalExitCode(currentOutput, allowDeviceUid);
            if (terminalCode != null) {
                if (process.isAlive()) {
                    process.destroy();
                    if (!process.waitFor(1, java.util.concurrent.TimeUnit.SECONDS)) {
                        process.destroyForcibly();
                    }
                }
                reader.join(1_000);
                String text = output.toString(Charset.defaultCharset());
                if (terminalCode != 0) {
                    text = appendDiagnostics(text, persistDiagnostics(
                        commandExecutable, arguments, text, terminalCode));
                }
                return new CommandResult(terminalCode, text, process.pid(), false,
                    Duration.ofNanos(System.nanoTime() - startedAt),
                    terminalCode == 0 ? "COMPLETED" : "PROCESS_EXIT",
                    List.of(process.pid()), actualStart);
            }
            if (!process.isAlive() && process.exitValue() != 0) {
                if (nonZeroExitAt == 0) {
                    nonZeroExitAt = System.nanoTime();
                } else if (System.nanoTime() - nonZeroExitAt
                    >= Duration.ofSeconds(2).toNanos()) {
                    reader.join(1_000);
                    String text = output.toString(Charset.defaultCharset());
                    int exitCode = process.exitValue();
                    return new CommandResult(exitCode, appendDiagnostics(text,
                        persistDiagnostics(commandExecutable, arguments, text, exitCode)),
                        process.pid(), false,
                        Duration.ofNanos(System.nanoTime() - startedAt),
                        "PROCESS_EXIT", List.of(process.pid()), actualStart);
                }
            }
            Thread.sleep(100);
        }
        if (process.isAlive()) {
            process.destroyForcibly();
        }
        String text = output.toString(Charset.defaultCharset());
        String diagnostics = persistDiagnostics(commandExecutable, arguments, text, 124);
        throw new IOException(
            "WCHISP 操作超时：未收到 Finished/Code 0/Succeed 最终结果"
                + (diagnostics.isBlank() ? "" : "\n诊断日志: " + diagnostics)
        );
    }

    /**
     * WCHISPStudio carries a requireAdministrator manifest. If Windows rejects
     * direct creation with error 740, use the standard UAC "runas" flow and
     * propagate the official WCHISP exit code.
     */
    private CommandResult runElevated(
        Path commandExecutable,
        List<String> arguments,
        Duration timeout,
        ProgressListener listener
    )
        throws Exception {
        return runCaptureWorker(commandExecutable, commandExecutable.getParent(), arguments,
            timeout, listener, true);
    }

    /**
     * Runs WCHISP through one operation-scoped PowerShell worker. The worker is
     * the single owner of the vendor child and inspects redirected streams and
     * the Windows console buffer for the vendor terminal-result contract.
     */
    private CommandResult runCaptureWorker(
        Path commandExecutable,
        Path workingDirectory,
        List<String> arguments,
        Duration timeout,
        ProgressListener listener,
        boolean useRunAs
    ) throws Exception {
        Path wrapper = useRunAs
            ? Files.createTempFile("ahakey-wchisp-elevated-", ".ps1") : null;
        Path worker = Files.createTempFile("ahakey-wchisp-worker-", ".ps1");
        Path stdout = Files.createTempFile("ahakey-wchisp-stdout-", ".log");
        Path stderr = Files.createTempFile("ahakey-wchisp-stderr-", ".log");
        Path consoleCapture = Files.createTempFile(
            "ahakey-wchisp-console-",
            ".log"
        );
        Path resultMarker = Files.createTempFile("ahakey-wchisp-result-", ".txt");
        Path childPid = Files.createTempFile("ahakey-wchisp-child-pid-", ".txt");
        Path childStarted = Files.createTempFile("ahakey-wchisp-child-start-", ".txt");
        Path childEnded = Files.createTempFile("ahakey-wchisp-child-end-", ".txt");
        String wrapperScript = """
            param(
                [Parameter(Mandatory = $true)][string]$Worker,
                [Parameter(Mandatory = $true)][string]$Tool,
                [Parameter(Mandatory = $true)][string]$Work,
                [Parameter(Mandatory = $true)][string]$Stdout,
                [Parameter(Mandatory = $true)][string]$Stderr,
                [Parameter(Mandatory = $true)][string]$ConsoleCapture,
                [Parameter(Mandatory = $true)][string]$Result,
                [Parameter(Mandatory = $true)][string]$ChildPid,
                [Parameter(Mandatory = $true)][string]$ChildStarted,
                [Parameter(Mandatory = $true)][string]$ChildEnded,
                [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
                [Parameter(Mandatory = $true)][string]$EncodedArguments
            )
            $elevatedArgs = @(
                '-NoProfile',
                '-NonInteractive',
                '-ExecutionPolicy',
                'Bypass',
                '-File',
                $Worker,
                $Tool,
                $Work,
                $Stdout,
                $Stderr,
                $ConsoleCapture,
                $Result,
                $ChildPid,
                $ChildStarted,
                $ChildEnded,
                $TimeoutSeconds,
                $EncodedArguments
            )
            $quotedArgs = $elevatedArgs | ForEach-Object {
                    '"' + ($_ -replace '"', '\\"') + '"'
            }
            try {
                $process = Start-Process -FilePath 'powershell.exe' `
                    -WorkingDirectory $Work -ArgumentList $quotedArgs `
                    -Verb RunAs -Wait -PassThru
                exit $process.ExitCode
            } catch {
                ($_ | Out-String) | Out-File -LiteralPath $Stderr -Encoding utf8
                if ($_.Exception.NativeErrorCode -eq 1223 -or
                    $_.Exception.Message -match 'cancel|取消') {
                    exit 1223
                }
                exit 1
            }
            """;
        String workerScript = captureWorkerScript();
        if (wrapper != null) {
            Files.writeString(wrapper, wrapperScript, StandardCharsets.UTF_8);
        }
        Files.writeString(worker, workerScript, StandardCharsets.UTF_8);
        try {
            List<String> workerArguments = new ArrayList<>();
            workerArguments.add(worker.toString());
            workerArguments.add(commandExecutable.toString());
            workerArguments.add(workingDirectory.toString());
            workerArguments.add(stdout.toString());
            workerArguments.add(stderr.toString());
            workerArguments.add(consoleCapture.toString());
            workerArguments.add(resultMarker.toString());
            workerArguments.add(childPid.toString());
            workerArguments.add(childStarted.toString());
            workerArguments.add(childEnded.toString());
            workerArguments.add(Long.toString(Math.max(1, timeout.toSeconds())));
            workerArguments.add(encodeArguments(arguments));

            List<String> command = new ArrayList<>();
            command.add("powershell.exe");
            command.add("-NoProfile");
            command.add("-NonInteractive");
            command.add("-ExecutionPolicy");
            command.add("Bypass");
            command.add("-File");
            if (useRunAs) {
                command.add(wrapper.toString());
            }
            command.addAll(workerArguments);

            long startedAt = System.nanoTime();
            Process process = new ProcessBuilder(command)
                .directory(workingDirectory.toFile())
                .redirectErrorStream(true)
                .start();
            ByteArrayOutputStream wrapperOutput = new ByteArrayOutputStream();
            Thread reader = new Thread(() -> copy(process.getInputStream(), wrapperOutput),
                useRunAs ? "wchisp-elevated-output" : "wchisp-worker-output");
            reader.setDaemon(true);
            reader.start();
            long deadline = System.nanoTime() + timeout.plusSeconds(5).toNanos();
            int lastProgress = -1;
            while (process.isAlive() && System.nanoTime() < deadline) {
                lastProgress = reportProgress(joinOutput(
                    readQuietly(stdout), readQuietly(stderr), readQuietly(consoleCapture)),
                    lastProgress, listener);
                Thread.sleep(200);
            }
            if (process.isAlive()) {
                process.destroyForcibly();
                terminateOwnedChild(readLongQuietly(childPid));
            }
            reader.join(2_000);

            int wrapperCode = process.isAlive() ? 124 : process.exitValue();
            String stdoutText = readQuietly(stdout);
            String stderrText = joinOutput(
                wrapperOutput.toString(Charset.defaultCharset()), readQuietly(stderr));
            String consoleText = readQuietly(consoleCapture);
            String marker = readQuietly(resultMarker).trim();
            boolean allowDeviceUid = arguments.contains("get");
            Integer markerCode = elevatedResultCode(marker, allowDeviceUid);
            Integer terminalCode = terminalExitCode(
                joinOutput(stdoutText, stderrText, consoleText), allowDeviceUid);
            int finalCode = markerCode != null ? markerCode
                : terminalCode != null ? terminalCode
                : wrapperCode == 0 ? 100 : wrapperCode;
            String terminalResult = terminalResult(marker, finalCode);
            if (wrapperCode == 124 && "MISSING".equals(terminalResult)) {
                terminalResult = "TIMEOUT";
            }
            String reason = switch (terminalResult) {
                case "SUCCESS", "DEVICE_UID" -> "COMPLETED";
                case "TIMEOUT" -> "FLASH_TERMINAL_RESULT_TIMEOUT";
                case "CANCELLED" -> "UAC_CANCELLED";
                case "MISSING" -> "TERMINAL_RESULT_MISSING";
                default -> "PROCESS_EXIT";
            };
            java.time.Instant actualStart = readInstantQuietly(childStarted);
            java.time.Instant actualEnd = readInstantQuietly(childEnded);
            Duration duration = actualStart != null && actualEnd != null
                ? Duration.between(actualStart, actualEnd)
                : Duration.ofNanos(System.nanoTime() - startedAt);
            long pid = readLongQuietly(childPid);
            String combined = joinOutput(stdoutText, stderrText, consoleText,
                "WCHISP capture worker result: " + terminalResult);

            if (wrapperCode == 1223) {
                reason = "UAC_CANCELLED";
                finalCode = 1223;
                terminalResult = "CANCELLED";
            }
            if (finalCode != 0 && finalCode != 124) {
                combined = appendDiagnostics(combined, persistDiagnostics(
                    commandExecutable, arguments, combined, finalCode));
            }
            return new CommandResult(finalCode, combined, pid, true, duration, reason,
                pid > 0 ? List.of(pid) : List.of(), actualStart, actualEnd,
                stdoutText, stderrText, consoleText, terminalResult);
        } finally {
            if (wrapper != null) Files.deleteIfExists(wrapper);
            Files.deleteIfExists(worker);
            Files.deleteIfExists(stdout);
            Files.deleteIfExists(stderr);
            Files.deleteIfExists(consoleCapture);
            Files.deleteIfExists(resultMarker);
            Files.deleteIfExists(childPid);
            Files.deleteIfExists(childStarted);
            Files.deleteIfExists(childEnded);
        }
    }

    static String captureWorkerScript() {
        return """
            param(
                [Parameter(Mandatory = $true)][string]$Tool,
                [Parameter(Mandatory = $true)][string]$Work,
                [Parameter(Mandatory = $true)][string]$Stdout,
                [Parameter(Mandatory = $true)][string]$Stderr,
                [Parameter(Mandatory = $true)][string]$ConsoleCapture,
                [Parameter(Mandatory = $true)][string]$Result,
                [Parameter(Mandatory = $true)][string]$ChildPid,
                [Parameter(Mandatory = $true)][string]$ChildStarted,
                [Parameter(Mandatory = $true)][string]$ChildEnded,
                [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
                [Parameter(Mandatory = $true)][string]$EncodedArguments
            )
            function Get-ConsoleTail {
                try {
                    $raw = $Host.UI.RawUI
                    $width = [Math]::Max(1, $raw.BufferSize.Width)
                    $bottom = [Math]::Max(0, $raw.CursorPosition.Y)
                    $top = if ($null -eq $script:ConsoleStartRow) {
                        [Math]::Max(0, $bottom - 120)
                    } elseif ($bottom -lt $script:ConsoleStartRow) {
                        [Math]::Max(0, $bottom - 120)
                    } else {
                        [Math]::Max(0, $script:ConsoleStartRow)
                    }
                    $rectangle = [System.Management.Automation.Host.Rectangle]::new(
                        0,
                        $top,
                        $width - 1,
                        $bottom
                    )
                    $cells = $raw.GetBufferContents($rectangle)
                    $builder = [Text.StringBuilder]::new()
                    for ($row = 0; $row -lt $cells.GetLength(0); $row++) {
                        for ($column = 0;
                             $column -lt $cells.GetLength(1);
                             $column++) {
                            [void]$builder.Append(
                                $cells.GetValue($row, $column).Character
                            )
                        }
                        [void]$builder.AppendLine()
                    }
                    return $builder.ToString()
                } catch {
                    return ''
                }
            }
            function Complete-WorkerResult {
                param([string]$Marker, [int]$ExitCode, [string]$ConsoleText)
                $ConsoleText | Out-File -LiteralPath $ConsoleCapture -Encoding utf8
                $Marker | Out-File -LiteralPath $Result -Encoding ascii
                [DateTimeOffset]::UtcNow.ToString('o') |
                    Out-File -LiteralPath $ChildEnded -Encoding ascii
                exit $ExitCode
            }
            try {
                Set-Location -LiteralPath $Work
                $decodedArguments = [Text.Encoding]::UTF8.GetString(
                    [Convert]::FromBase64String($EncodedArguments)
                )
                $toolArguments = if ($decodedArguments.Length -eq 0) {
                    @()
                } else {
                    @($decodedArguments -split "`0")
                }
                $quotedToolArguments = $toolArguments | ForEach-Object {
                    '"' + ($_ -replace '"', '\"') + '"'
                }
                try {
                    $script:ConsoleStartRow = $Host.UI.RawUI.CursorPosition.Y
                } catch {
                    $script:ConsoleStartRow = $null
                }
                $toolProcess = Start-Process -FilePath $Tool `
                    -WorkingDirectory $Work `
                    -ArgumentList $quotedToolArguments `
                    -RedirectStandardOutput $Stdout `
                    -RedirectStandardError $Stderr `
                    -PassThru
                $toolProcess.Id | Out-File -LiteralPath $ChildPid -Encoding ascii
                [DateTimeOffset]::UtcNow.ToString('o') |
                    Out-File -LiteralPath $ChildStarted -Encoding ascii
                $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
                while ((Get-Date) -lt $deadline) {
                    try {
                        $fileText = [System.IO.File]::ReadAllText($Stdout)
                    } catch {
                        $fileText = ''
                    }
                    try {
                        $errorText = [System.IO.File]::ReadAllText($Stderr)
                    } catch {
                        $errorText = ''
                    }
                    $consoleText = Get-ConsoleTail
                    $consoleText | Out-File -LiteralPath $ConsoleCapture -Encoding utf8
                    $text = $fileText + "`n" + $errorText + "`n" + $consoleText
                    if ($text -match '"Status"\\s*:\\s*"Fail"') {
                        if (-not $toolProcess.HasExited) {
                            Stop-Process -Id $toolProcess.Id -Force -ErrorAction SilentlyContinue
                        }
                        $failureCode = 1
                        if ($text -match '"Code"\\s*:\\s*(\\d+)') {
                            $failureCode = [Math]::Min([int]$Matches[1], 255)
                        }
                        Complete-WorkerResult "FAIL:$failureCode" $failureCode $consoleText
                    }
                    if ($text -match '"Status"\\s*:\\s*"Finished"' -and
                        $text -match '"Code"\\s*:\\s*0' -and
                        $text -match '"Message"\\s*:\\s*"Succeed"') {
                        if (-not $toolProcess.HasExited) {
                            Stop-Process -Id $toolProcess.Id -Force -ErrorAction SilentlyContinue
                        }
                        Complete-WorkerResult 'SUCCESS' 0 $consoleText
                    }
                    if (($toolArguments -contains 'get') -and
                        $text -match 'Device UID\\s*:') {
                        if (-not $toolProcess.HasExited) {
                            Stop-Process -Id $toolProcess.Id -Force -ErrorAction SilentlyContinue
                        }
                        Complete-WorkerResult 'DEVICE_UID' 0 $consoleText
                    }
                    if ($toolProcess.HasExited -and $toolProcess.ExitCode -ne 0) {
                        Complete-WorkerResult "PROCESS_EXIT:$($toolProcess.ExitCode)" `
                            $toolProcess.ExitCode $consoleText
                    }
                    Start-Sleep -Milliseconds 200
                }
                if (-not $toolProcess.HasExited) {
                    Stop-Process -Id $toolProcess.Id -Force -ErrorAction SilentlyContinue
                }
                Complete-WorkerResult 'TIMEOUT' 124 (Get-ConsoleTail)
            } catch {
                ($_ | Out-String) | Out-File -LiteralPath $Stderr -Encoding utf8
                Complete-WorkerResult 'ERROR' 1 (Get-ConsoleTail)
            }
            """;
    }

    private static String terminalResult(String marker, int code) {
        if (marker == null || marker.isBlank()) return "MISSING";
        String value = marker.trim();
        if ("SUCCESS".equals(value) || "DEVICE_UID".equals(value)
            || "TIMEOUT".equals(value) || "ERROR".equals(value)) return value;
        if (value.startsWith("FAIL:")) return "FAIL";
        if (value.startsWith("PROCESS_EXIT:")) return "PROCESS_EXIT";
        return code == 0 ? "SUCCESS" : "MISSING";
    }

    private static long readLongQuietly(Path path) {
        try {
            String value = readQuietly(path).trim();
            return value.isBlank() ? -1 : Long.parseLong(value);
        } catch (RuntimeException ignored) {
            return -1;
        }
    }

    private static java.time.Instant readInstantQuietly(Path path) {
        try {
            String value = readQuietly(path).trim();
            return value.isBlank() ? null : java.time.Instant.parse(value);
        } catch (RuntimeException ignored) {
            return null;
        }
    }

    private static void terminateOwnedChild(long pid) {
        if (pid <= 0) return;
        ProcessHandle.of(pid).filter(ProcessHandle::isAlive).ifPresent(ProcessHandle::destroyForcibly);
    }

    private String persistDiagnostics(
        Path commandExecutable,
        List<String> arguments,
        String output,
        int resultCode
    ) {
        Path destination = Path.of(
            System.getProperty("user.home"),
            ".ahakey",
            "logs",
            "wchisp-last-failure"
        );
        return persistDiagnosticsAt(destination, commandExecutable, arguments, output, resultCode);
    }

    /** Runs a prepared command through the shared one-shot console-capture worker. */
    WchIspRunner.WchIspProcessResult runOfficialCommand(
        WchIspRunner.WchIspCommand command,
        WchIspRunner.CancellationToken cancellation
    ) throws Exception {
        if (command == null) throw new IllegalArgumentException("command is required");
        WchIspRunner.CancellationToken token = cancellation == null
            ? WchIspRunner.CancellationToken.NONE : cancellation;
        if (token.cancelled()) {
            return new WchIspRunner.WchIspProcessResult(
                command.operationId(), false, -1, -1, false, true,
                "", "", "", Duration.ZERO, false, java.util.Map.of(),
                "CANCELLED", java.util.List.of()
            );
        }
        CaptureLaunchMode launchMode = captureLaunchMode(isCurrentProcessElevated());
        CommandResult result = runCaptureWorker(
            command.executable(), command.workingDirectory(), command.arguments(),
            command.timeout(), null, launchMode == CaptureLaunchMode.RUNAS_WORKER
        );
        String reason = result.exitCode() == 0 ? "COMPLETED" : "PROCESS_EXIT";
        boolean timedOut = "FLASH_TERMINAL_RESULT_TIMEOUT".equals(result.terminationReason());
        boolean cancelled = "UAC_CANCELLED".equals(result.terminationReason());
        return new WchIspRunner.WchIspProcessResult(
            command.operationId(), result.pid() > 0, result.pid(), result.exitCode(), timedOut, cancelled,
            result.stdout(), result.stderr(), result.console(), result.duration(),
            result.elevationUsed(), java.util.Map.of(),
            result.terminationReason().isBlank() ? reason : result.terminationReason(),
            result.ownedProcessIds(), result.actualProcessStartTime()
        );
    }

    static CaptureLaunchMode captureLaunchMode(boolean studioElevated) {
        return studioElevated ? CaptureLaunchMode.DIRECT_WORKER : CaptureLaunchMode.RUNAS_WORKER;
    }

    private static boolean isCurrentProcessElevated() {
        if (!System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("win")) {
            return false;
        }
        try {
            return Advapi32Util.isCurrentProcessElevated();
        } catch (RuntimeException | UnsatisfiedLinkError ignored) {
            return false;
        }
    }

    static String persistDiagnosticsForTest(
        Path destination,
        Path commandExecutable,
        List<String> arguments,
        String output,
        int resultCode
    ) {
        return persistDiagnosticsAt(destination, commandExecutable, arguments, output, resultCode);
    }

    private static String persistDiagnosticsAt(
        Path destination,
        Path commandExecutable,
        List<String> arguments,
        String output,
        int resultCode
    ) {
        try {
            Files.createDirectories(destination);
            String command = commandExecutable == null ? "" : commandExecutable.toString();
            if (arguments != null && !arguments.isEmpty()) {
                command += " " + String.join(" ", arguments);
            }
            Files.writeString(destination.resolve("command.txt"), command,
                StandardCharsets.UTF_8);
            String captured = output == null ? "" : output;
            Files.writeString(destination.resolve("stdout.txt"), captured,
                StandardCharsets.UTF_8);
            Files.writeString(destination.resolve("stderr.txt"), "",
                StandardCharsets.UTF_8);
            Files.writeString(destination.resolve("console.txt"), captured,
                StandardCharsets.UTF_8);
            Files.writeString(destination.resolve("result.txt"),
                "PROCESS_EXIT:" + resultCode + System.lineSeparator(),
                StandardCharsets.UTF_8);
            Path runtimeDirectory = commandExecutable == null
                ? null : commandExecutable.toAbsolutePath().normalize().getParent();
            Path metadata = runtimeDirectory == null
                ? null : runtimeDirectory.resolve(WchIspRuntimeContract.METADATA_FILE);
            Files.writeString(destination.resolve("runtime-version.txt"),
                metadata != null && Files.isRegularFile(metadata)
                    ? Files.readString(metadata, StandardCharsets.UTF_8)
                    : "unknown runtime metadata" + System.lineSeparator(),
                StandardCharsets.UTF_8);
            Path config = arguments == null ? null : configArgument(arguments);
            String fingerprint = "unknown";
            if (config != null && Files.isRegularFile(config)) {
                try {
                    fingerprint = WchIspRuntimeContract.configFingerprint(
                        Files.readAllBytes(config));
                } catch (IOException ignored) {
                    fingerprint = "invalid";
                }
            }
            Files.writeString(destination.resolve("config-fingerprint.txt"),
                fingerprint + System.lineSeparator(), StandardCharsets.UTF_8);
            return destination.toString();
        } catch (IOException ignored) {
            return "";
        }
    }

    private String appendDiagnostics(String output, String diagnostics) {
        if (diagnostics == null || diagnostics.isBlank()) return output;
        return joinOutput(output, "诊断日志: " + diagnostics);
    }

    private static Path configArgument(List<String> arguments) {
        for (int index = 0; index + 1 < arguments.size(); index++) {
            if ("-c".equalsIgnoreCase(arguments.get(index))) {
                try {
                    return Path.of(arguments.get(index + 1));
                } catch (RuntimeException ignored) {
                    return null;
                }
            }
        }
        return null;
    }

    private static String readQuietly(Path path) {
        try {
            return decodeOutput(Files.readAllBytes(path));
        } catch (IOException ignored) {
            return "";
        }
    }

    static String decodeOutput(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            return "";
        }
        if (bytes.length >= 3
            && (bytes[0] & 0xFF) == 0xEF
            && (bytes[1] & 0xFF) == 0xBB
            && (bytes[2] & 0xFF) == 0xBF) {
            return new String(
                bytes,
                3,
                bytes.length - 3,
                StandardCharsets.UTF_8
            );
        }
        if (bytes.length >= 2
            && (bytes[0] & 0xFF) == 0xFF
            && (bytes[1] & 0xFF) == 0xFE) {
            return new String(
                bytes,
                2,
                bytes.length - 2,
                StandardCharsets.UTF_16LE
            );
        }
        if (bytes.length >= 2
            && (bytes[0] & 0xFF) == 0xFE
            && (bytes[1] & 0xFF) == 0xFF) {
            return new String(
                bytes,
                2,
                bytes.length - 2,
                StandardCharsets.UTF_16BE
            );
        }
        int sampleLength = Math.min(bytes.length, 256);
        int oddNuls = 0;
        int evenNuls = 0;
        for (int index = 0; index < sampleLength; index++) {
            if (bytes[index] == 0) {
                if ((index & 1) == 0) {
                    evenNuls++;
                } else {
                    oddNuls++;
                }
            }
        }
        if (oddNuls > sampleLength / 8) {
            return new String(bytes, StandardCharsets.UTF_16LE);
        }
        if (evenNuls > sampleLength / 8) {
            return new String(bytes, StandardCharsets.UTF_16BE);
        }
        return new String(bytes, Charset.defaultCharset());
    }

    private String joinOutput(String... values) {
        StringBuilder output = new StringBuilder();
        for (String value : values) {
            if (value == null || value.isBlank()) {
                continue;
            }
            if (!output.isEmpty()) {
                output.append(System.lineSeparator());
            }
            output.append(value.trim());
        }
        return output.toString();
    }

    static Integer terminalExitCode(String output, boolean allowDeviceUid) {
        if (allowDeviceUid && output != null && output.contains("Device UID:")) {
            return 0;
        }
        if (output == null || output.isBlank()) {
            return null;
        }
        Matcher status = STATUS_PATTERN.matcher(output);
        if (!status.find()) {
            return null;
        }
        Matcher code = CODE_PATTERN.matcher(output.substring(status.start()));
        int parsedCode = code.find() ? Integer.parseInt(code.group(1)) : 100;
        if ("Fail".equals(status.group(1))) {
            return parsedCode == 0 ? 100 : parsedCode;
        }
        if (parsedCode == 0
            && SUCCESS_MESSAGE_PATTERN.matcher(output.substring(status.start())).find()) {
            return 0;
        }
        return parsedCode == 0 ? 100 : parsedCode;
    }

    static Integer elevatedResultCode(String marker, boolean allowDeviceUid) {
        if (marker == null || marker.isBlank()) {
            return null;
        }
        String value = marker.trim();
        if ("SUCCESS".equals(value)) {
            return 0;
        }
        if ("DEVICE_UID".equals(value)) {
            return allowDeviceUid ? 0 : null;
        }
        if ("TIMEOUT".equals(value)) {
            return 124;
        }
        if ("ERROR".equals(value)) {
            return 1;
        }
        for (String prefix : List.of("FAIL:", "PROCESS_EXIT:")) {
            if (!value.startsWith(prefix)) {
                continue;
            }
            try {
                int code = Integer.parseInt(value.substring(prefix.length()).trim());
                return code == 0 ? 100 : code;
            } catch (NumberFormatException ignored) {
                return 100;
            }
        }
        return null;
    }

    private static boolean isIspDeviceEnumerated() {
        if (!System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("win")) {
            return false;
        }
        try {
            Process process = new ProcessBuilder(
                "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
                "Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_4348&PID_55E0' } | Select-Object -First 1 -ExpandProperty InstanceId"
            ).redirectErrorStream(true).start();
            if (!process.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)) {
                process.destroyForcibly();
                return false;
            }
            String output = new String(process.getInputStream().readAllBytes(),
                Charset.defaultCharset());
            return process.exitValue() == 0 && output.toUpperCase(Locale.ROOT)
                .contains("VID_4348&PID_55E0");
        } catch (Exception ignored) {
            return false;
        }
    }

    static String encodeArguments(List<String> arguments) {
        String joined = String.join("\u0000", arguments);
        return Base64.getEncoder().encodeToString(
            joined.getBytes(StandardCharsets.UTF_8)
        );
    }

    private int reportProgress(
        String output,
        int previousProgress,
        ProgressListener listener
    ) {
        if (listener == null || output == null || output.isBlank()) {
            return previousProgress;
        }
        Matcher matcher = PROGRESS_PATTERN.matcher(output);
        int latest = previousProgress;
        while (matcher.find()) {
            latest = Math.max(latest, Integer.parseInt(matcher.group(1)));
        }
        if (latest > previousProgress) {
            double appProgress = 0.10 + latest * 0.008;
            listener.onProgress(
                "download",
                Math.min(0.90, appProgress),
                "正在烧录 CH582：" + latest + "%"
            );
        }
        return latest;
    }

    private Path prepareToolWorkspace(Path destination, Path firmwareHex)
        throws IOException {
        Path sourceDirectory = executable.toAbsolutePath().normalize().getParent();
        if (sourceDirectory == null) {
            throw new IOException("WCHISP 工具目录无效");
        }
        WchIspRuntimeContract.Validation contract =
            WchIspRuntimeContract.validate(sourceDirectory);
        if (!contract.supported()) {
            throw new IOException(contract.summary());
        }
        copyDirectory(sourceDirectory, destination);

        Path preparedExecutable = destination.resolve(executable.getFileName());
        Path defaultConfig = destination.resolve("CONFIG_CH57X59X.WCH");
        // The mutable machine CONFIG is deliberately excluded. Every invocation
        // starts from the repository-controlled, fingerprinted sanitized baseline.
        copyBundledSanitizedConfig(defaultConfig);
        patchCh582FirmwarePath(defaultConfig, firmwareHex);
        if (!Files.isRegularFile(defaultConfig) || Files.size(defaultConfig) < 1024) {
            throw new IOException("WCHISP 临时基础配置生成失败或文件不完整");
        }
        return preparedExecutable;
    }

    private void copyDirectory(Path source, Path destination) throws IOException {
        try (var paths = Files.walk(source)) {
            for (Path path : paths.toList()) {
                if (Files.isRegularFile(path)
                    && (path.getFileName().toString().equalsIgnoreCase("CONFIG_CH57X59X.WCH")
                        || path.getFileName().toString().equalsIgnoreCase("CONFIG_CH57X59X.WCH.excluded"))) {
                    continue;
                }
                Path target = destination.resolve(source.relativize(path));
                if (Files.isDirectory(path)) {
                    Files.createDirectories(target);
                } else {
                    Files.createDirectories(target.getParent());
                    Files.copy(path, target, StandardCopyOption.REPLACE_EXISTING,
                        StandardCopyOption.COPY_ATTRIBUTES);
                }
            }
        }
    }

    private static boolean bundledSanitizedConfigAvailable() {
        try (InputStream stream = WindowsWchIspFlasher.class
            .getResourceAsStream(SANITIZED_CONFIG_RESOURCE)) {
            return stream != null;
        } catch (IOException exception) {
            return false;
        }
    }

    private static void copyBundledSanitizedConfig(Path destination) throws IOException {
        try (InputStream stream = WindowsWchIspFlasher.class
            .getResourceAsStream(SANITIZED_CONFIG_RESOURCE)) {
            if (stream == null) {
                throw new IOException("缺少受控脱敏 WCHISP 基础配置资源");
            }
            Files.copy(stream, destination, StandardCopyOption.REPLACE_EXISTING);
        }
        byte[] bytes = Files.readAllBytes(destination);
        if (!SANITIZED_LAYOUT_SHA256.equals(layoutFingerprint(bytes))) {
            throw new IOException("受控脱敏 WCHISP 基础配置指纹不匹配");
        }
    }

    static void patchCh582FirmwarePath(Path config, Path firmwareHex)
        throws IOException {
        byte[] bytes = Files.readAllBytes(config);
        WchConfigLayout layout = inspectLayout(bytes);
        byte[] replacement = firmwareHex.toAbsolutePath().normalize()
            .toString().getBytes(StandardCharsets.UTF_16BE);
        if (replacement.length + 2 > WCH_PATH_SLOT_BYTES) {
            throw new IOException("固件路径过长，WCHISP 配置无法保存");
        }
        int targetOffset = layout.slotOffsets()[CH582_SLOT_INDEX];
        Arrays.fill(bytes, targetOffset, targetOffset + WCH_PATH_SLOT_BYTES, (byte) 0);
        System.arraycopy(replacement, 0, bytes, targetOffset, replacement.length);
        Files.write(config, bytes);
    }

    static WchConfigLayout inspectLayout(byte[] bytes) throws IOException {
        if (bytes == null || bytes.length != WCH_CONFIG_LENGTH) {
            throw unsupportedLayout("配置长度不匹配");
        }
        if (!SANITIZED_LAYOUT_SHA256.equals(layoutFingerprint(bytes))) {
            throw unsupportedLayout("layout fingerprint 不匹配");
        }
        String[] slots = new String[WCH_PATH_SLOT_OFFSETS.length];
        for (int index = 0; index < WCH_PATH_SLOT_OFFSETS.length; index++) {
            slots[index] = decodePathSlot(bytes, WCH_PATH_SLOT_OFFSETS[index]);
            if (!slots[index].isBlank()
                && !slots[index].toLowerCase(Locale.ROOT).endsWith(".hex")
                && !slots[index].toLowerCase(Locale.ROOT).endsWith(".bin")) {
                throw unsupportedLayout("path slot " + index + " 不是合法 .hex/.bin UTF-16BE 字段");
            }
        }
        String target = slots[CH582_SLOT_INDEX].toLowerCase(Locale.ROOT);
        if (!target.isBlank() && !target.contains("ch582")) {
            throw unsupportedLayout("CH582 target slot 当前值无效");
        }
        return new WchConfigLayout(Arrays.copyOf(WCH_PATH_SLOT_OFFSETS,
            WCH_PATH_SLOT_OFFSETS.length), slots);
    }

    private static String decodePathSlot(byte[] bytes, int offset) throws IOException {
        if ((offset & 1) != 0 || offset < 0
            || offset + WCH_PATH_SLOT_BYTES > bytes.length) {
            throw unsupportedLayout("path slot 边界无效");
        }
        StringBuilder value = new StringBuilder();
        boolean terminated = false;
        for (int index = offset; index < offset + WCH_PATH_SLOT_BYTES; index += 2) {
            int codeUnit = ((bytes[index] & 0xFF) << 8) | (bytes[index + 1] & 0xFF);
            if (codeUnit == 0) {
                terminated = true;
                for (int rest = index + 2; rest < offset + WCH_PATH_SLOT_BYTES; rest++) {
                    if (bytes[rest] != 0) throw unsupportedLayout("path slot 尾部不是零填充");
                }
                break;
            }
            if (codeUnit < 0x20 || codeUnit > 0x7E) {
                throw unsupportedLayout("path slot 含非法 UTF-16 字符");
            }
            value.append((char) codeUnit);
        }
        if (!terminated) throw unsupportedLayout("path slot 缺少 UTF-16 NUL 终止符");
        return value.toString();
    }

    static String layoutFingerprint(byte[] bytes) throws IOException {
        try {
            return WchIspConfigLayout.fingerprint(bytes);
        } catch (IOException failure) {
            throw unsupportedLayout(failure.getMessage());
        }
    }

    private static IOException unsupportedLayout(String detail) {
        return new IOException("Unsupported WCHISP configuration layout: " + detail);
    }

    private static void copy(InputStream input, ByteArrayOutputStream output) {
        try (input; output) {
            input.transferTo(output);
        } catch (IOException ignored) {
        }
    }

    private void ensureAvailable() throws IOException {
        if (!System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("win")) {
            throw new IOException("当前版本仅支持 Windows 10/11 x64，已保留其他平台接口");
        }
        if (executable == null || !Files.isRegularFile(executable)) {
            throw new IOException(
                "未找到 WCHISP 命令行工具。请安装官方 WCHISPStudio，或通过 "
                    + "-Dahakey.wchisp.path=完整路径 指定工具。"
            );
        }
        Path directory = executable.toAbsolutePath().normalize().getParent();
        WchIspRuntimeContract.Validation contract =
            WchIspRuntimeContract.validate(directory);
        if (!contract.supported()) {
            throw new IOException(contract.summary());
        }
    }

    public static Path locateExecutable() {
        String override = System.getProperty("ahakey.wchisp.path", "").trim();
        List<Path> candidates = new ArrayList<>();
        if (!override.isBlank()) {
            candidates.add(Path.of(override));
        }
        String appDir = System.getProperty("jpackage.app-path", "");
        if (!appDir.isBlank()) {
            Path parent = Path.of(appDir).toAbsolutePath().getParent();
            if (parent != null) {
                candidates.add(parent.resolve("app").resolve("tools")
                    .resolve("wchisp")
                    .resolve("WCHISPTool_CH57x-59x.exe"));
                candidates.add(parent.resolve("tools").resolve("wchisp")
                    .resolve("WCHISPTool_CH57x-59x.exe"));
            }
        }
        candidates.add(Path.of("C:\\app\\WCHISPTool\\WCHISPTool_CH57x-59x",
            "WCHISPTool_CH57x-59x.exe"));
        candidates.add(Path.of("C:\\app\\WCHISPTool\\WchIspStudio.exe"));
        for (Path candidate : candidates) {
            if (Files.isRegularFile(candidate)) {
                return candidate.toAbsolutePath().normalize();
            }
        }
        return candidates.get(0).toAbsolutePath().normalize();
    }

    private static void deleteQuietly(Path root) {
        if (root == null || !Files.exists(root)) {
            return;
        }
        try (var paths = Files.walk(root)) {
            paths.sorted((a, b) -> b.compareTo(a)).forEach(path -> {
                try {
                    Files.deleteIfExists(path);
                } catch (IOException ignored) {
                }
            });
        } catch (IOException ignored) {
        }
    }

    record WchConfigLayout(int[] slotOffsets, String[] slotValues) {
        WchConfigLayout {
            slotOffsets = Arrays.copyOf(slotOffsets, slotOffsets.length);
            slotValues = Arrays.copyOf(slotValues, slotValues.length);
        }
    }

    private record CommandResult(
        int exitCode,
        String output,
        long pid,
        boolean elevationUsed,
        Duration duration,
        String terminationReason,
        List<Long> ownedProcessIds,
        java.time.Instant actualProcessStartTime,
        java.time.Instant actualProcessEndTime,
        String stdout,
        String stderr,
        String console,
        String terminalResult
    ) {
        private CommandResult(int exitCode, String output, long pid,
                              boolean elevationUsed, Duration duration,
                              String terminationReason, List<Long> ownedProcessIds,
                              java.time.Instant actualProcessStartTime) {
            this(exitCode, output, pid, elevationUsed, duration, terminationReason,
                ownedProcessIds, actualProcessStartTime,
                actualProcessStartTime == null ? null : actualProcessStartTime.plus(duration),
                output, "", output, exitCode == 0 ? "SUCCESS" : "PROCESS_EXIT");
        }

        private CommandResult(int exitCode, String output) {
            this(exitCode, output, -1, false, Duration.ZERO, "", List.of(), null);
        }
    }

    enum CaptureLaunchMode {
        DIRECT_WORKER,
        RUNAS_WORKER
    }
    @FunctionalInterface
    interface IspDeviceProbe {
        boolean isEnumerated();
    }

    public record EnvironmentReport(boolean ready, List<String> checks) {}
}
