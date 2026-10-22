package com.example.ahakey.firmware;

import java.nio.charset.Charset;
import java.time.Duration;
import java.util.Locale;
import java.util.function.BooleanSupplier;

/** PnP presence probe; presence is not equivalent to a successful UID query. */
@FunctionalInterface
public interface IspDeviceProbe {
    boolean isPresent() throws Exception;

    /** Waits using one replaceable probe operation instead of spawning a shell per poll. */
    default boolean awaitPresent(Duration timeout, BooleanSupplier cancelled) throws Exception {
        Duration effective = timeout == null || timeout.isNegative() ? Duration.ZERO : timeout;
        BooleanSupplier stop = cancelled == null ? () -> false : cancelled;
        long deadline = System.nanoTime() + effective.toNanos();
        while (System.nanoTime() < deadline) {
            if (stop.getAsBoolean()) throw new InterruptedException("ISP wait cancelled");
            if (isPresent()) return true;
            Thread.sleep(25);
        }
        return false;
    }

    static IspDeviceProbe windowsDefault() {
        return new IspDeviceProbe() {
            @Override public boolean isPresent() throws Exception {
                return runProbe(Duration.ofSeconds(5), false, () -> false);
            }

            @Override public boolean awaitPresent(Duration timeout, BooleanSupplier cancelled)
                throws Exception {
                return runProbe(timeout, true, cancelled);
            }
        };
    }

    private static boolean runProbe(Duration timeout, boolean wait, BooleanSupplier cancelled)
        throws Exception {
        if (!System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("win")) return false;
        Duration effective = timeout == null || timeout.isNegative() ? Duration.ZERO : timeout;
        String command = wait
            ? "$deadline=(Get-Date).AddMilliseconds(" + Math.max(0, effective.toMillis())
                + "); while((Get-Date) -lt $deadline){$d=Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_4348&PID_55E0' } | Select-Object -First 1; if($d){$d.InstanceId; exit 0}; Start-Sleep -Milliseconds 25}; exit 2"
            : "Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_4348&PID_55E0' } | Select-Object -First 1 -ExpandProperty InstanceId";
        Process process = new ProcessBuilder("powershell.exe", "-NoProfile", "-NonInteractive",
            "-Command", command).redirectErrorStream(true).start();
        long deadline = System.nanoTime() + Math.max(1, effective.toNanos());
        try {
            while (process.isAlive()) {
                if (cancelled != null && cancelled.getAsBoolean()) {
                    process.destroyForcibly();
                    throw new InterruptedException("ISP wait cancelled");
                }
                if (wait && System.nanoTime() >= deadline) {
                    process.destroyForcibly();
                    return false;
                }
                process.waitFor(25, java.util.concurrent.TimeUnit.MILLISECONDS);
            }
            String output = new String(process.getInputStream().readAllBytes(), Charset.defaultCharset());
            return process.exitValue() == 0
                && output.toUpperCase(Locale.ROOT).contains("VID_4348&PID_55E0");
        } finally {
            process.getInputStream().close();
        }
    }
}
