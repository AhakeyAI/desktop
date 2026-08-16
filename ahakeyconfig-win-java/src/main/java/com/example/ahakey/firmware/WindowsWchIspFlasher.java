package com.example.ahakey.firmware;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class WindowsWchIspFlasher implements FirmwareFlasher {
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

    public WindowsWchIspFlasher() {
        this(locateExecutable());
    }

    public WindowsWchIspFlasher(Path executable) {
        this.executable = executable;
    }

    public Path executable() {
        return executable;
    }

    /** Performs non-destructive checks that are safe to include in a support report. */
    public EnvironmentReport diagnoseEnvironment() {
        List<String> checks = new ArrayList<>();
        boolean ready = true;
        Path tool = executable.toAbsolutePath().normalize();
        Path directory = tool.getParent();
        ready &= check(checks, Files.isRegularFile(tool), "WCHISP 主程序", tool);
        if (directory == null) {
            checks.add("[失败] WCHISP 工具目录无效");
            return new EnvironmentReport(false, checks);
        }
        ready &= check(checks, Files.isRegularFile(directory.resolve("CH343PT.DLL")),
            "CH343PT.DLL", directory.resolve("CH343PT.DLL"));
        ready &= check(checks, Files.isRegularFile(directory.resolve("WCH55xISPDLL.dll")),
            "WCH55xISPDLL.dll", directory.resolve("WCH55xISPDLL.dll"));
        Path raw = directory.resolve("CONFIG_CH57X59X.WCH");
        Path excluded = directory.resolve("CONFIG_CH57X59X.WCH.excluded");
        ready &= check(checks, Files.isRegularFile(raw) || Files.isRegularFile(excluded),
            "CH57x-59x 基础配置", Files.isRegularFile(raw) ? raw : excluded);
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
                    : WchIspExitCodes.describe(result.exitCode())
                        + outputSuffix(result)
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
                return new CommandResult(
                    terminalCode,
                    output.toString(Charset.defaultCharset())
                );
            }
            if (!process.isAlive() && process.exitValue() != 0) {
                if (nonZeroExitAt == 0) {
                    nonZeroExitAt = System.nanoTime();
                } else if (System.nanoTime() - nonZeroExitAt
                    >= Duration.ofSeconds(2).toNanos()) {
                    reader.join(1_000);
                    return new CommandResult(
                        process.exitValue(),
                        output.toString(Charset.defaultCharset())
                    );
                }
            }
            Thread.sleep(100);
        }
        if (process.isAlive()) {
            process.destroyForcibly();
        }
        throw new IOException(
            "WCHISP 操作超时：未收到 Finished/Code 0/Succeed 最终结果"
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
                throw new IOException(
                    "WCHISP 管理员操作超时：未收到最终烧录结果"
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
                throw new IOException("用户取消了 WCHISP 管理员授权");
            }
            if (code == -1073741510) {
                throw new IOException(
                    "WCHISP 管理员窗口被手动关闭，请等待窗口自动结束"
                );
            }
            if (code == 124) {
                throw new IOException(
                    "WCHISP 操作超时：未收到 Finished/Code 0/Succeed 最终结果"
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
                return new CommandResult(
                    markerCode,
                    joinOutput(output, markerCode == 0
                        ? "WCHISP elevated worker confirmed the terminal result."
                        : "WCHISP elevated worker reported failure code " + markerCode)
                );
            }
            if (terminalCode == null) {
                Path diagnostics = preserveDiagnostics(
                    stdout, stderr, consoleCapture, resultMarker);
                return new CommandResult(
                    code == 0 ? 100 : code,
                    joinOutput(
                        output,
                        "WCHISP 未返回可确认的最终结果",
                        diagnostics == null ? "" : "诊断日志: " + diagnostics
                    )
                );
            }
            return new CommandResult(terminalCode, output);
        } finally {
            Files.deleteIfExists(wrapper);
            Files.deleteIfExists(elevatedWorker);
            Files.deleteIfExists(stdout);
            Files.deleteIfExists(stderr);
            Files.deleteIfExists(consoleCapture);
            Files.deleteIfExists(resultMarker);
        }
    }

    private Path preserveDiagnostics(Path... sources) {
        try {
            Path destination = Path.of(
                System.getProperty("user.home"),
                ".ahakey",
                "logs",
                "wchisp-last-failure"
            );
            Files.createDirectories(destination);
            for (Path source : sources) {
                if (source != null && Files.isRegularFile(source)) {
                    Files.copy(
                        source,
                        destination.resolve(source.getFileName()),
                        StandardCopyOption.REPLACE_EXISTING
                    );
                }
            }
            return destination;
        } catch (IOException ignored) {
            return null;
        }
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
        copyDirectory(sourceDirectory, destination);

        Path preparedExecutable = destination.resolve(executable.getFileName());
        Path defaultConfig = destination.resolve("CONFIG_CH57X59X.WCH");
        Path excludedConfig = destination.resolve("CONFIG_CH57X59X.WCH.excluded");
        if (!Files.isRegularFile(defaultConfig) && Files.isRegularFile(excludedConfig)) {
            Files.copy(excludedConfig, defaultConfig, StandardCopyOption.REPLACE_EXISTING);
        }
        if (!Files.isRegularFile(defaultConfig)) {
            throw new IOException(
                "WCHISP 工具包缺少必需的 CONFIG_CH57X59X.WCH 基础配置"
            );
        }
        patchCh582FirmwarePath(defaultConfig, firmwareHex);
        if (!Files.isRegularFile(defaultConfig) || Files.size(defaultConfig) < 1024) {
            throw new IOException("WCHISP 临时基础配置生成失败或文件不完整");
        }
        return preparedExecutable;
    }

    private void copyDirectory(Path source, Path destination) throws IOException {
        try (var paths = Files.walk(source)) {
            for (Path path : paths.toList()) {
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

    static void patchCh582FirmwarePath(Path config, Path firmwareHex)
        throws IOException {
        byte[] bytes = Files.readAllBytes(config);
        List<Utf16Path> paths = findFirmwarePaths(bytes);
        if (paths.size() != 1) {
            throw new IOException(
                "WCHISP 基础配置中的固件路径数量异常：" + paths.size()
            );
        }

        Utf16Path existing = paths.get(0);
        byte[] replacement = firmwareHex.toAbsolutePath().normalize()
            .toString()
            .getBytes(StandardCharsets.UTF_16LE);
        int fieldBytes = 520;
        if (replacement.length + 2 > fieldBytes
            || existing.offset() + fieldBytes > bytes.length) {
            throw new IOException("固件路径过长，WCHISP 配置无法保存");
        }
        for (int index = existing.offset();
             index < existing.offset() + fieldBytes;
             index++) {
            bytes[index] = 0;
        }
        System.arraycopy(replacement, 0, bytes, existing.offset(), replacement.length);
        Files.write(config, bytes);
    }

    private static List<Utf16Path> findFirmwarePaths(byte[] bytes) {
        List<Utf16Path> paths = new ArrayList<>();
        int index = 0;
        while (index + 1 < bytes.length) {
            int start = index;
            StringBuilder value = new StringBuilder();
            while (index + 1 < bytes.length
                && bytes[index + 1] == 0
                && bytes[index] >= 0x20
                && bytes[index] <= 0x7E) {
                value.append((char) bytes[index]);
                index += 2;
            }
            String text = value.toString().toLowerCase(Locale.ROOT);
            if (value.length() >= 4
                && (text.endsWith(".hex") || text.endsWith(".bin"))) {
                paths.add(new Utf16Path(start));
            }
            index = Math.max(index + 1, start + 1);
        }
        return paths;
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

    private record CommandResult(int exitCode, String output) {}
    private record Utf16Path(int offset) {}
    public record EnvironmentReport(boolean ready, List<String> checks) {}
}
