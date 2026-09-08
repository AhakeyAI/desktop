package com.example.ahakey.firmware;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Production adapter for the vendor WCHISP runtime.  No generated workspace,
 * patched CONFIG, or UID CLI query is used here: the official executable is
 * invoked directly and post-verification remains the source of truth.
 */
public final class DefaultOfficialWchIspAdapter implements OfficialWchIspAdapter {
    private static final Duration FLASH_TIMEOUT = Duration.ofMinutes(5);

    private final RuntimeLocator runtimeLocator;
    private final IspDeviceProbe ispProbe;
    private final WchIspRunner runner;

    public DefaultOfficialWchIspAdapter() {
        this(new InstalledRuntimeLocator(), IspDeviceProbe.windowsDefault(), new WchIspRunner());
    }

    DefaultOfficialWchIspAdapter(RuntimeLocator runtimeLocator,
                                  IspDeviceProbe ispProbe,
                                  WchIspRunner runner) {
        this.runtimeLocator = runtimeLocator == null ? new InstalledRuntimeLocator() : runtimeLocator;
        this.ispProbe = ispProbe == null ? IspDeviceProbe.windowsDefault() : ispProbe;
        this.runner = runner == null ? new WchIspRunner() : runner;
    }

    @Override
    public DeviceDetectionResult detectDevice() throws Exception {
        RuntimeBundle runtime = runtimeLocator.resolve();
        return detectDeviceWithRuntime(runtime);
    }

    @Override
    public DeviceDetectionResult detectDevice(PreparedFlashSession session) throws Exception {
        RuntimeBundle runtime = session == null ? runtimeLocator.resolve() : session.runtime();
        return detectDeviceWithRuntime(runtime);
    }

    private DeviceDetectionResult detectDeviceWithRuntime(RuntimeBundle runtime) throws Exception {
        boolean present = ispProbe.isPresent();
        String detail = present
            ? "OFFICIAL_WCHISP_ADAPTER=YES\nISP_PRESENT=YES\nUID=OPTIONAL_NOT_QUERIED"
            : "OFFICIAL_WCHISP_ADAPTER=YES\nISP_PRESENT=NO";
        return present
            ? DeviceDetectionResult.present(runtime, detail)
            : DeviceDetectionResult.notPresent(runtime, detail);
    }

    @Override
    public PreparedFlashSession prepareFlash(Path hex, UUID operationId,
                                              Path operationDirectory,
                                              RuntimeBundle preparedRuntime) throws Exception {
        if (hex == null || !Files.isRegularFile(hex)) {
            throw new IOException("固件 HEX 文件不存在: " + hex);
        }
        IntelHexValidator.validate(hex);
        if (operationId == null) throw new IOException("固件操作 ID 缺失");
        if (operationDirectory == null) throw new IOException("固件诊断目录缺失");
        RuntimeBundle runtime = preparedRuntime == null ? runtimeLocator.resolve() : preparedRuntime;
        Path directory = operationDirectory.toAbsolutePath().normalize();
        Files.createDirectories(directory);
        Path config = directory.resolve("flash-config.ini");
        Path normalizedHex = hex.toAbsolutePath().normalize();
        Files.writeString(config, WchIspConfig.forCh582(normalizedHex), StandardCharsets.UTF_8);
        WchIspRunner.WchIspCommand command = new WchIspRunner.WchIspCommand(
            runtime.executable(), runtime.root(),
            List.of("-c", config.toString(), "-o", "download", "-f", normalizedHex.toString()),
            FLASH_TIMEOUT, operationId);
        PreparedLaunchContext launchContext = runner.prepareElevatedLaunch(command);
        return new PreparedFlashSession(operationId, runtime, config, normalizedHex, command,
            Instant.now(), launchContext, "firmware-operation:" + operationId);
    }

    @Override
    public FlashResult flashFirmware(Path hex) throws Exception {
        return flashFirmware(hex, WchIspRunner.CancellationToken.NONE);
    }

    @Override
    public FlashResult flashFirmware(Path hex, WchIspRunner.CancellationToken cancellation)
        throws Exception {
        UUID operationId = UUID.randomUUID();
        Path directory = Files.createTempDirectory("ahakey-wchisp-flash-" + operationId + "-");
        RuntimeBundle runtime = runtimeLocator.resolve();
        PreparedFlashSession session = prepareFlash(hex, operationId, directory, runtime);
        session.markDeviceDetected();
        return flashPrepared(session, cancellation);
    }

    @Override
    public FlashResult flashPrepared(PreparedFlashSession session,
                                     WchIspRunner.CancellationToken cancellation)
        throws Exception {
        if (session == null) throw new IOException("预备烧录会话缺失");
        if (!session.beginLaunch()) {
            throw new IOException("预备烧录会话不可启动: " + session.state());
        }
        WchIspRunner.WchIspCommand command = session.command();
        WchIspRunner.WchIspProcessResult process;
        try {
            PreparedLaunchContext launchContext = session.launchContext();
            process = launchContext == null
                ? runner.run(command, cancellation == null ? WchIspRunner.CancellationToken.NONE : cancellation)
                : launchContext.launch(cancellation);
        } catch (Exception failure) {
            session.failLaunch();
            throw failure;
        }
        session.complete(process);
        boolean success = process != null && process.processStarted()
            && !process.timedOut() && !process.cancelled() && process.exitCode() == 0;
        String detail = "OFFICIAL_WCHISP_COMMAND=" + command.executable() + " "
            + String.join(" ", command.arguments()) + "\n"
            + "PROCESS_STARTED=" + (process != null && process.processStarted() ? "YES" : "NO") + "\n"
            + "EXIT_CODE=" + (process == null ? "NONE" : process.exitCode()) + "\n"
            + "POST_VERIFY_REQUIRED=YES";
        return new FlashResult(success, detail, process, session.runtime());
    }
}
