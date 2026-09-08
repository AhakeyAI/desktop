package com.example.ahakey.firmware;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
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
        boolean present = ispProbe.isPresent();
        String detail = present
            ? "OFFICIAL_WCHISP_ADAPTER=YES\nISP_PRESENT=YES\nUID=OPTIONAL_NOT_QUERIED"
            : "OFFICIAL_WCHISP_ADAPTER=YES\nISP_PRESENT=NO";
        return present
            ? DeviceDetectionResult.present(runtime, detail)
            : DeviceDetectionResult.notPresent(runtime, detail);
    }

    @Override
    public FlashResult flashFirmware(Path hex) throws Exception {
        return flashFirmware(hex, WchIspRunner.CancellationToken.NONE);
    }

    @Override
    public FlashResult flashFirmware(Path hex, WchIspRunner.CancellationToken cancellation)
        throws Exception {
        if (hex == null || !Files.isRegularFile(hex)) {
            throw new IOException("固件 HEX 文件不存在: " + hex);
        }
        IntelHexValidator.validate(hex);
        RuntimeBundle runtime = runtimeLocator.resolve();
        UUID operationId = UUID.randomUUID();
        WchIspRunner.WchIspCommand command = new WchIspRunner.WchIspCommand(
            runtime.executable(), runtime.root(),
            List.of("-o", "download", "-f", hex.toAbsolutePath().normalize().toString()),
            FLASH_TIMEOUT, operationId);
        WchIspRunner.WchIspProcessResult process = runner.run(command,
            cancellation == null ? WchIspRunner.CancellationToken.NONE : cancellation);
        boolean success = process != null && process.processStarted()
            && !process.timedOut() && !process.cancelled() && process.exitCode() == 0;
        String detail = "OFFICIAL_WCHISP_COMMAND=" + command.executable() + " "
            + String.join(" ", command.arguments()) + "\n"
            + "PROCESS_STARTED=" + (process != null && process.processStarted() ? "YES" : "NO") + "\n"
            + "EXIT_CODE=" + (process == null ? "NONE" : process.exitCode()) + "\n"
            + "POST_VERIFY_REQUIRED=YES";
        return new FlashResult(success, detail, process, runtime);
    }
}
