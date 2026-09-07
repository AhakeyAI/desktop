package com.example.ahakey.firmware;

import java.nio.charset.Charset;
import java.util.Locale;

/** PnP presence probe; presence is not equivalent to a successful UID query. */
@FunctionalInterface
public interface IspDeviceProbe {
    boolean isPresent() throws Exception;

    static IspDeviceProbe windowsDefault() {
        return () -> {
            if (!System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("win")) {
                return false;
            }
            Process process = new ProcessBuilder(
                "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
                "Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_4348&PID_55E0' } | Select-Object -First 1 -ExpandProperty InstanceId"
            ).redirectErrorStream(true).start();
            try {
                if (!process.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)) {
                    process.destroyForcibly();
                    return false;
                }
                String output = new String(process.getInputStream().readAllBytes(), Charset.defaultCharset());
                return process.exitValue() == 0
                    && output.toUpperCase(Locale.ROOT).contains("VID_4348&PID_55E0");
            } finally {
                process.getInputStream().close();
            }
        };
    }
}
