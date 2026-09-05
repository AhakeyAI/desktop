package com.example.ahakey.firmware;

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
    static final int WCH_CONFIG_LENGTH = 66841;
    static final int WCH_PATH_SLOT_BYTES = 520;
    static final int[] WCH_PATH_SLOT_OFFSETS = {
        36486, 37006, 37526, 63172, 63692
    };
    static final int CH582_SLOT_INDEX = 0;
    static final String SANITIZED_LAYOUT_SHA256 =
        "4dd3ac5911ff428b92200745a26c34c674235c04ac40a77f7cfb61d6fb6241e8";
    private static final Duration COMMAND_TIMEOUT = Duration.ofMinutes(5);
    private static final Pattern STATUS_PATTERN = Pattern.compile(
        "\"Status\"\\s*:\\s*\"(Finished|Fail)\""
    );
    private static final Pattern CODE_PATTERN = Pattern.compile(
        "\"Code\"\\s*:\\s*(\\d+)"
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
                return new CommandResult(terminalCode, text);
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
                        persistDiagnostics(commandExecutable, arguments, text, exitCode)));
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
        Path wrapper = Files.createTempFile("ahakey-wchisp-elevated-", ".ps1");
        Path elevatedWorker = Files.createTempFile("ahakey-wchisp-worker-", ".ps1");
        Path stdout = Files.createTempFile("ahakey-wchisp-stdout-", ".log");
        Path stderr = Files.createTempFile("ahakey-wchisp-stderr-", ".log");
        Path consoleCapture = Files.createTempFile(
            "ahakey-wchisp-console-",
            ".log"
        );
        Path resultMarker = Files.createTempFile("ahakey-wchisp-result-", ".txt");
        String script = """
            param(
                [Parameter(Mandatory = $true)][string]$Worker,
                [Parameter(Mandatory = $true)][string]$Tool,
                [Parameter(Mandatory = $true)][string]$Work,
                [Parameter(Mandatory = $true)][string]$Stdout,
                [Parameter(Mandatory = $true)][string]$Stderr,
                [Parameter(Mandatory = $true)][string]$ConsoleCapture,
                [Parameter(Mandatory = $true)][string]$Result,
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
        String workerScript = """
            param(
                [Parameter(Mandatory = $true)][string]$Tool,
                [Parameter(Mandatory = $true)][string]$Work,
                [Parameter(Mandatory = $true)][string]$Stdout,
                [Parameter(Mandatory = $true)][string]$Stderr,
                [Parameter(Mandatory = $true)][string]$ConsoleCapture,
                [Parameter(Mandatory = $true)][string]$Result,
                [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
                [Parameter(Mandatory = $true)][string]$EncodedArguments
            )
            function Get-ConsoleTail {
                try {
                    $raw = $Host.UI.RawUI
                    $width = [Math]::Max(1, $raw.BufferSize.Width)
                    $bottom = [Math]::Max(0, $raw.CursorPosition.Y)
                    $top = [Math]::Max(0, $bottom - 120)
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
                $toolProcess = Start-Process -FilePath $Tool `
                    -WorkingDirectory $Work `
                    -ArgumentList $quotedToolArguments `
                    -RedirectStandardOutput $Stdout `
                    -RedirectStandardError $Stderr `
                    -PassThru
                $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
                while ((Get-Date) -lt $deadline) {
                    try {
                        $fileText = [System.IO.File]::ReadAllText($Stdout)
                    } catch {
                        $fileText = ''
                    }
                    $consoleText = Get-ConsoleTail
                    $text = $fileText + "`n" + $consoleText
                    if ($text -match '"Status"\\s*:\\s*"Fail"') {
                        if (-not $toolProcess.HasExited) {
                            Stop-Process -Id $toolProcess.Id -Force -ErrorAction SilentlyContinue
                        }
                        $consoleText | Out-File -LiteralPath $ConsoleCapture `
                            -Encoding utf8
                        $failureCode = 1
                        if ($text -match '"Code"\\s*:\\s*(\\d+)') {
                            $failureCode = [Math]::Min([int]$Matches[1], 255)
                        }
                        "FAIL:$failureCode" | Out-File -LiteralPath $Result `
                            -Encoding ascii
                        exit $failureCode
                    }
                    if ($text -match '"Status"\\s*:\\s*"Finished"' -and
                        $text -match '"Code"\\s*:\\s*0' -and
                        $text -match '"Message"\\s*:\\s*"Succeed"') {
                        if (-not $toolProcess.HasExited) {
                            Stop-Process -Id $toolProcess.Id -Force -ErrorAction SilentlyContinue
                        }
                        $consoleText | Out-File -LiteralPath $ConsoleCapture `
                            -Encoding utf8
                        'SUCCESS' | Out-File -LiteralPath $Result -Encoding ascii
                        exit 0
                    }
                    if (($toolArguments -contains 'get') -and
                        $text -match 'Device UID\\s*:') {
                        if (-not $toolProcess.HasExited) {
                            Stop-Process -Id $toolProcess.Id -Force -ErrorAction SilentlyContinue
                        }
                        $consoleText | Out-File -LiteralPath $ConsoleCapture `
                            -Encoding utf8
                        'DEVICE_UID' | Out-File -LiteralPath $Result -Encoding ascii
                        exit 0
                    }
                    if ($toolProcess.HasExited -and $toolProcess.ExitCode -ne 0) {
                        "PROCESS_EXIT:$($toolProcess.ExitCode)" |
                            Out-File -LiteralPath $Result -Encoding ascii
                        exit $toolProcess.ExitCode
                    }
                    Start-Sleep -Milliseconds 200
                }
                if (-not $toolProcess.HasExited) {
                    Stop-Process -Id $toolProcess.Id -Force -ErrorAction SilentlyContinue
                }
                'TIMEOUT' | Out-File -LiteralPath $Result -Encoding ascii
                exit 124
            } catch {
                ($_ | Out-String) | Out-File -LiteralPath $Stderr -Encoding utf8
                'ERROR' | Out-File -LiteralPath $Result -Encoding ascii
                exit 1
            }
            """;
        Files.writeString(wrapper, script, StandardCharsets.UTF_8);
        Files.writeString(elevatedWorker, workerScript, StandardCharsets.UTF_8);
        try {
            List<String> command = new ArrayList<>();
            command.add("powershell.exe");
            command.add("-NoProfile");
            command.add("-NonInteractive");
            command.add("-ExecutionPolicy");
            command.add("Bypass");
            command.add("-File");
            command.add(wrapper.toString());
            command.add(elevatedWorker.toString());
            command.add(commandExecutable.toString());
            command.add(commandExecutable.getParent().toString());
            command.add(stdout.toString());
            command.add(stderr.toString());
            command.add(consoleCapture.toString());
            command.add(resultMarker.toString());
            command.add(Long.toString(Math.max(1, timeout.toSeconds())));
            command.add(encodeArguments(arguments));
            Process process = new ProcessBuilder(command)
                .redirectErrorStream(true)
                .start();
            ByteArrayOutputStream wrapperOutput = new ByteArrayOutputStream();
            Thread reader = new Thread(() -> copy(process.getInputStream(), wrapperOutput),
                "wchisp-elevated-output");
            reader.setDaemon(true);
            reader.start();
            long deadline = System.nanoTime()
                + timeout.plusSeconds(5).toNanos();
            int lastProgress = -1;
            while (process.isAlive() && System.nanoTime() < deadline) {
                lastProgress = reportProgress(
                    readQuietly(stdout),
                    lastProgress,
                    listener
                );
                Thread.sleep(200);
            }
            if (process.isAlive()) {
                process.destroyForcibly();
                String diagnostics = persistDiagnostics(
                    commandExecutable, arguments, wrapperOutput.toString(Charset.defaultCharset()), 124);
                throw new IOException(
                    "WCHISP 管理员操作超时：未收到最终烧录结果"
                        + (diagnostics.isBlank() ? "" : "\n诊断日志: " + diagnostics)
                );
            }
            reader.join(2_000);
            int code = process.exitValue();
            String output = joinOutput(
                wrapperOutput.toString(Charset.defaultCharset()),
                readQuietly(stdout),
                readQuietly(stderr),
                readQuietly(consoleCapture)
            );
            if (code == 1223) {
                String diagnostics = persistDiagnostics(commandExecutable, arguments, output, code);
                throw new IOException("用户取消了 WCHISP 管理员授权"
                    + (diagnostics.isBlank() ? "" : "\n诊断日志: " + diagnostics));
            }
            if (code == -1073741510) {
                String diagnostics = persistDiagnostics(commandExecutable, arguments, output, code);
                throw new IOException(
                    "WCHISP 管理员窗口被手动关闭，请等待窗口自动结束"
                        + (diagnostics.isBlank() ? "" : "\n诊断日志: " + diagnostics)
                );
            }
            if (code == 124) {
                String diagnostics = persistDiagnostics(
                    commandExecutable, arguments, output, 124);
                throw new IOException(
                    "WCHISP 操作超时：未收到 Finished/Code 0/Succeed 最终结果"
                        + (diagnostics.isBlank() ? "" : "\n诊断日志: " + diagnostics)
                );
            }
            Integer terminalCode = terminalExitCode(
                output,
                arguments.contains("get")
            );
            Integer markerCode = elevatedResultCode(
                readQuietly(resultMarker),
                arguments.contains("get")
            );
            if (markerCode != null) {
                String finalOutput = joinOutput(output,
                    markerCode == 0
                        ? "WCHISP elevated worker confirmed the terminal result."
                        : "WCHISP elevated worker reported failure code " + markerCode);
                if (markerCode != 0) {
                    finalOutput = appendDiagnostics(finalOutput, persistDiagnostics(
                        commandExecutable, arguments, finalOutput, markerCode));
                }
                return new CommandResult(
                    markerCode,
                    finalOutput
                );
            }
            if (terminalCode == null) {
                String diagnostics = persistDiagnostics(
                    commandExecutable, arguments, output, code == 0 ? 100 : code);
                return new CommandResult(
                    code == 0 ? 100 : code,
                    joinOutput(
                        output,
                        "WCHISP 未返回可确认的最终结果",
                        diagnostics.isBlank() ? "" : "诊断日志: " + diagnostics
                    )
                );
            }
            return new CommandResult(terminalCode, terminalCode == 0
                ? output
                : appendDiagnostics(output, persistDiagnostics(
                    commandExecutable, arguments, output, terminalCode)));
        } finally {
            Files.deleteIfExists(wrapper);
            Files.deleteIfExists(elevatedWorker);
            Files.deleteIfExists(stdout);
            Files.deleteIfExists(stderr);
            Files.deleteIfExists(consoleCapture);
            Files.deleteIfExists(resultMarker);
        }
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

    private String readQuietly(Path path) {
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
        if (parsedCode == 0 && output.substring(status.start()).contains("\"Message\":\"Succeed\"")) {
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
        if (bytes == null || bytes.length != WCH_CONFIG_LENGTH) {
            throw unsupportedLayout("配置长度不匹配");
        }
        byte[] normalized = Arrays.copyOf(bytes, bytes.length);
        for (int offset : WCH_PATH_SLOT_OFFSETS) {
            if (offset < 0 || offset + WCH_PATH_SLOT_BYTES > normalized.length) {
                throw unsupportedLayout("path slot 边界无效");
            }
            Arrays.fill(normalized, offset, offset + WCH_PATH_SLOT_BYTES, (byte) 0);
        }
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(normalized);
            StringBuilder hex = new StringBuilder(digest.length * 2);
            for (byte value : digest) hex.append(String.format("%02x", value & 0xFF));
            return hex.toString();
        } catch (java.security.NoSuchAlgorithmException impossible) {
            throw new IOException("JVM 缺少 SHA-256", impossible);
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

    private record CommandResult(int exitCode, String output) {}
    @FunctionalInterface
    interface IspDeviceProbe {
        boolean isEnumerated();
    }

    public record EnvironmentReport(boolean ready, List<String> checks) {}
}
