package com.example.ahakey.firmware;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/** Single process boundary for direct/elevated WCHISP execution. */
public class WchIspRunner {
    private final Backend backend;
    private final ElevatedBackend elevatedBackend;

    public WchIspRunner() {
        this(new ProcessBuilderBackend(), new WindowsRunAsBackend());
    }

    public WchIspRunner(Backend backend) {
        this(backend, new WindowsRunAsBackend());
    }

    WchIspRunner(Backend backend, ElevatedBackend elevatedBackend) {
        this.backend = backend == null ? new ProcessBuilderBackend() : backend;
        this.elevatedBackend = elevatedBackend == null ? new WindowsRunAsBackend() : elevatedBackend;
    }

    public WchIspProcessResult run(WchIspCommand command, CancellationToken cancellation)
        throws Exception {
        if (command == null) throw new IllegalArgumentException("command is required");
        CancellationToken token = cancellation == null ? CancellationToken.NONE : cancellation;
        try {
            return backend.run(command, token);
        } catch (ElevationRequiredException elevationRequired) {
            if (!isWindows() && elevatedBackend instanceof WindowsRunAsBackend) {
                return WchIspProcessResult.startFailure(command.operationId(), elevationRequired);
            }
            return elevatedBackend.run(command, token);
        }
    }

    @FunctionalInterface
    public interface Backend {
        WchIspProcessResult run(WchIspCommand command, CancellationToken cancellation)
            throws Exception;
    }

    @FunctionalInterface
    public interface ElevatedBackend {
        WchIspProcessResult run(WchIspCommand command, CancellationToken cancellation)
            throws Exception;
    }

    /** Package-visible test hook for a fake direct backend that observes UAC 740. */
    static final class ElevationRequiredException extends IOException {
        ElevationRequiredException(IOException cause) {
            super(cause == null ? "CreateProcess error=740" : cause.getMessage(), cause);
        }
    }

    @FunctionalInterface
    public interface CancellationToken {
        boolean cancelled();
        CancellationToken NONE = () -> false;
    }

    public record WchIspCommand(
        Path executable,
        Path workingDirectory,
        List<String> arguments,
        Duration timeout,
        UUID operationId
    ) {
        public WchIspCommand {
            if (executable == null || workingDirectory == null || operationId == null) {
                throw new IllegalArgumentException("command paths and operationId are required");
            }
            arguments = arguments == null ? List.of() : List.copyOf(arguments);
            timeout = timeout == null || timeout.isNegative() || timeout.isZero()
                ? Duration.ofSeconds(20) : timeout;
        }
    }

    public record WchIspProcessResult(
        UUID operationId,
        boolean processStarted,
        long pid,
        int exitCode,
        boolean timedOut,
        boolean cancelled,
        String stdout,
        String stderr,
        String console,
        Duration duration,
        boolean elevationUsed,
        Map<String, Path> rawArtifacts,
        String terminationReason,
        List<Long> ownedProcessIds
    ) {
        public WchIspProcessResult {
            stdout = stdout == null ? "" : stdout;
            stderr = stderr == null ? "" : stderr;
            console = console == null ? stdout + stderr : console;
            duration = duration == null ? Duration.ZERO : duration;
            rawArtifacts = rawArtifacts == null ? Map.of() : Map.copyOf(rawArtifacts);
            terminationReason = terminationReason == null ? "" : terminationReason;
            ownedProcessIds = ownedProcessIds == null ? List.of() : ownedProcessIds.stream()
                .filter(value -> value != null && value > 0).distinct().toList();
        }

        /** Compatibility constructor for callers that only know the primary PID. */
        public WchIspProcessResult(UUID operationId, boolean processStarted, long pid,
                                   int exitCode, boolean timedOut, boolean cancelled,
                                   String stdout, String stderr, String console,
                                   Duration duration, boolean elevationUsed,
                                   Map<String, Path> rawArtifacts, String terminationReason) {
            this(operationId, processStarted, pid, exitCode, timedOut, cancelled,
                stdout, stderr, console, duration, elevationUsed, rawArtifacts,
                terminationReason, pid > 0 ? List.of(pid) : List.of());
        }

        public static WchIspProcessResult startFailure(UUID operationId, Exception error) {
            return new WchIspProcessResult(operationId, false, -1, -1, false, false,
                "", error == null ? "" : String.valueOf(error.getMessage()), "",
                Duration.ZERO, false, Map.of(), "PROCESS_START_FAILED");
        }
    }

    private static final class ProcessBuilderBackend implements Backend {
        @Override
        public WchIspProcessResult run(WchIspCommand command, CancellationToken cancellation)
            throws Exception {
            long startedAt = System.nanoTime();
            List<String> invocation = new ArrayList<>();
            invocation.add(command.executable().toString());
            invocation.addAll(command.arguments());
            Process process;
            try {
                process = new ProcessBuilder(invocation)
                    .directory(command.workingDirectory().toFile())
                    .redirectErrorStream(false)
                    .start();
            } catch (IOException startFailure) {
                if (startFailure.getMessage() != null
                    && startFailure.getMessage().contains("740")) {
                    throw new ElevationRequiredException(startFailure);
                }
                return WchIspProcessResult.startFailure(command.operationId(), startFailure);
            }
            long pid = process.pid();
            ByteArrayOutputStream stdout = new ByteArrayOutputStream();
            ByteArrayOutputStream stderr = new ByteArrayOutputStream();
            Thread outReader = reader(process.getInputStream(), stdout, "wchisp-stdout");
            Thread errReader = reader(process.getErrorStream(), stderr, "wchisp-stderr");
            outReader.start();
            errReader.start();
            boolean timedOut = false;
            boolean cancelled = false;
            String reason = "PROCESS_EXIT";
            long deadline = System.nanoTime() + command.timeout().toNanos();
            while (process.isAlive()) {
                if (cancellation.cancelled()) {
                    cancelled = true;
                    reason = "CANCELLED";
                    terminateOwnedTree(process);
                    break;
                }
                if (System.nanoTime() >= deadline) {
                    timedOut = true;
                    reason = "TIMEOUT";
                    terminateOwnedTree(process);
                    break;
                }
                process.waitFor(50, TimeUnit.MILLISECONDS);
            }
            if (process.isAlive()) terminateOwnedTree(process);
            process.waitFor(2, TimeUnit.SECONDS);
            outReader.join(2_000);
            errReader.join(2_000);
            int exit = process.isAlive() ? -1 : process.exitValue();
            String out = stdout.toString(Charset.defaultCharset());
            String err = stderr.toString(Charset.defaultCharset());
            return new WchIspProcessResult(command.operationId(), true, pid, exit,
                timedOut, cancelled, out, err, out + System.lineSeparator() + err,
                Duration.ofNanos(System.nanoTime() - startedAt), false, Map.of(), reason,
                List.of(pid));
        }

        private static Thread reader(InputStream input, ByteArrayOutputStream output, String name) {
            Thread thread = new Thread(() -> {
                try (input; output) { input.transferTo(output); } catch (IOException ignored) { }
            }, name);
            thread.setDaemon(true);
            return thread;
        }

        private static void terminateOwnedTree(Process process) {
            ProcessHandle handle = process.toHandle();
            handle.descendants().toList().forEach(child -> {
                try { child.destroy(); } catch (RuntimeException ignored) { }
            });
            try { handle.destroy(); } catch (RuntimeException ignored) { }
            try { process.waitFor(250, TimeUnit.MILLISECONDS); } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            if (process.isAlive()) {
                handle.descendants().toList().forEach(child -> {
                    try { child.destroyForcibly(); } catch (RuntimeException ignored) { }
                });
                try { handle.destroyForcibly(); } catch (RuntimeException ignored) { }
            }
        }
    }

    /**
     * Minimal RunAs bridge used only after the direct launch reports Windows
     * error 740.  The elevated worker writes raw streams and a marker; Java
     * still owns the sole result parsing decision.
     */
    private static final class WindowsRunAsBackend implements ElevatedBackend {
        @Override
        public WchIspProcessResult run(WchIspCommand command, CancellationToken cancellation)
            throws Exception {
            Path directory = java.nio.file.Files.createTempDirectory("ahakey-wchisp-runas-");
            Path wrapper = directory.resolve("runas-wrapper.ps1");
            Path worker = directory.resolve("worker.ps1");
            Path stdout = directory.resolve("stdout.txt");
            Path stderr = directory.resolve("stderr.txt");
            Path marker = directory.resolve("result.txt");
            Path pidFile = directory.resolve("pid.txt");
            Path workerPidFile = directory.resolve("worker-pid.txt");
            java.nio.file.Files.writeString(wrapper, wrapperScript(), java.nio.charset.StandardCharsets.UTF_8);
            java.nio.file.Files.writeString(worker, workerScript(), java.nio.charset.StandardCharsets.UTF_8);
            List<String> invocation = List.of(
                "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                "-File", wrapper.toString(), worker.toString(), command.executable().toString(),
                command.workingDirectory().toString(), stdout.toString(), stderr.toString(),
                marker.toString(), pidFile.toString(), workerPidFile.toString(),
                Long.toString(Math.max(1, command.timeout().toSeconds())),
                Base64.getEncoder().encodeToString(String.join("\u0000", command.arguments())
                    .getBytes(java.nio.charset.StandardCharsets.UTF_8)));
            Process elevation = new ProcessBuilder(invocation).redirectErrorStream(true).start();
            long deadline = System.nanoTime() + command.timeout().plusSeconds(5).toNanos();
            while (elevation.isAlive() && System.nanoTime() < deadline) {
                if (cancellation.cancelled()) {
                    long workerPid = readPid(workerPidFile);
                    long childPid = readPid(pidFile);
                    terminateOwnedPids(elevation.pid(), workerPid, childPid);
                    elevation.waitFor(2, TimeUnit.SECONDS);
                    boolean incomplete = ownershipIncomplete(elevation.pid(), workerPid, childPid);
                    String reason = "UAC_CANCELLED" + (incomplete ? "/PROCESS_OWNERSHIP_INCOMPLETE" : "");
                    return new WchIspProcessResult(command.operationId(), true, elevation.pid(), -1,
                        false, true, read(stdout), read(stderr), read(stdout) + read(stderr),
                        command.timeout(), true, artifacts(stdout, stderr, marker, pidFile, workerPidFile), reason,
                        ownedPids(elevation.pid(), workerPid, childPid));
                }
                elevation.waitFor(100, TimeUnit.MILLISECONDS);
            }
            boolean timedOut = elevation.isAlive();
            long workerPid = readPid(workerPidFile);
            long childPid = readPid(pidFile);
            if (timedOut) terminateOwnedPids(elevation.pid(), workerPid, childPid);
            elevation.waitFor(2, TimeUnit.SECONDS);
            int wrapperExit = elevation.isAlive() ? -1 : elevation.exitValue();
            String markerValue = read(marker).trim();
            int exitCode = parseExitCode(markerValue, wrapperExit);
            boolean cancelled = wrapperExit == 1223 || "UAC_CANCELLED".equals(markerValue);
            childPid = readPid(pidFile);
            workerPid = readPid(workerPidFile);
            boolean ownershipIncomplete = (timedOut || cancelled)
                && ownershipIncomplete(elevation.pid(), workerPid, childPid);
            String reason = timedOut ? "TIMEOUT" : cancelled ? "UAC_CANCELLED" : "ELEVATED_PROCESS_EXIT";
            if (ownershipIncomplete) reason += "/PROCESS_OWNERSHIP_INCOMPLETE";
            long primaryPid = childPid > 0 ? childPid : workerPid > 0 ? workerPid : elevation.pid();
            return new WchIspProcessResult(command.operationId(), true, primaryPid, exitCode,
                timedOut, cancelled, read(stdout), read(stderr), read(stdout) + read(stderr),
                command.timeout(), true, artifacts(stdout, stderr, marker, pidFile, workerPidFile), reason,
                ownedPids(elevation.pid(), workerPid, childPid));
        }

        private static Map<String, Path> artifacts(Path stdout, Path stderr, Path marker,
                                                   Path pidFile, Path workerPidFile) {
            Map<String, Path> result = new HashMap<>();
            result.put("stdout", stdout);
            result.put("stderr", stderr);
            result.put("result", marker);
            result.put("pid", pidFile);
            result.put("workerPid", workerPidFile);
            return result;
        }

        private static List<Long> ownedPids(long wrapperPid, long workerPid, long childPid) {
            return List.of(wrapperPid, workerPid, childPid).stream()
                .filter(pid -> pid > 0).distinct().toList();
        }

        private static boolean ownershipIncomplete(long wrapperPid, long workerPid, long childPid) {
            for (long pid : ownedPids(wrapperPid, workerPid, childPid)) {
                try {
                    if (ProcessHandle.of(pid).map(ProcessHandle::isAlive).orElse(false)) return true;
                } catch (RuntimeException ignored) { return true; }
            }
            return workerPid <= 0 || childPid <= 0;
        }

        private static void terminateOwnedPids(long wrapperPid, long workerPid, long childPid) {
            List<Long> pids = ownedPids(wrapperPid, workerPid, childPid);
            pids.stream().filter(pid -> pid != wrapperPid).forEach(WindowsRunAsBackend::destroy);
            destroy(wrapperPid);
            long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(500);
            while (System.nanoTime() < deadline && pids.stream().anyMatch(WindowsRunAsBackend::alive)) {
                try { Thread.sleep(20); } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
            pids.stream().filter(WindowsRunAsBackend::alive).forEach(WindowsRunAsBackend::destroyForcibly);
        }

        private static boolean alive(long pid) {
            return ProcessHandle.of(pid).map(ProcessHandle::isAlive).orElse(false);
        }

        private static void destroy(long pid) {
            ProcessHandle.of(pid).ifPresent(handle -> {
                try { handle.destroy(); } catch (RuntimeException ignored) { }
            });
        }

        private static void destroyForcibly(long pid) {
            ProcessHandle.of(pid).ifPresent(handle -> {
                try { handle.destroyForcibly(); } catch (RuntimeException ignored) { }
            });
        }

        private static long readPid(Path path) {
            try { return Long.parseLong(read(path).trim()); } catch (RuntimeException ignored) { return -1; }
        }

        private static int parseExitCode(String marker, int fallback) {
            if (marker.startsWith("PROCESS_EXIT:")) {
                try { return Integer.parseInt(marker.substring("PROCESS_EXIT:".length()).trim()); }
                catch (NumberFormatException ignored) { }
            }
            return fallback;
        }

        private static String read(Path path) {
            try { return java.nio.file.Files.isRegularFile(path)
                ? java.nio.file.Files.readString(path) : ""; }
            catch (IOException ignored) { return ""; }
        }

        private static String wrapperScript() {
            return "param([string]$Worker,[string]$Tool,[string]$Work,[string]$Stdout,[string]$Stderr,[string]$Result,[string]$Pid,[string]$WorkerPid,[int]$Timeout,[string]$Args)`n"
                + "$list=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Worker,$Tool,$Work,$Stdout,$Stderr,$Result,$Pid,$WorkerPid,$Timeout,$Args)`n"
                + "$quoted=$list|ForEach-Object{\"'\"+($_ -replace \"'\",\"''\")+\"'\"}`n"
                + "try{$p=Start-Process powershell.exe -Verb RunAs -ArgumentList ($quoted -join ' ') -Wait -PassThru;exit $p.ExitCode}catch{if($_.Exception.Message -match 'cancel|1223'){exit 1223};exit 1}`n";
        }

        private static String workerScript() {
            return "param([string]$Tool,[string]$Work,[string]$Stdout,[string]$Stderr,[string]$Result,[string]$Pid,[string]$WorkerPid,[int]$Timeout,[string]$Args)`n"
                + "$PID|Out-File -LiteralPath $WorkerPid -Encoding ascii`n"
                + "try{$decoded=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Args));$a=if($decoded){@($decoded -split \"`0\")}else{@()};$p=Start-Process -FilePath $Tool -WorkingDirectory $Work -ArgumentList $a -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru;$p.Id|Out-File -LiteralPath $Pid -Encoding ascii;$p.WaitForExit($Timeout*1000)|Out-Null;if(-not $p.HasExited){$p.Kill();'TIMEOUT'|Out-File -LiteralPath $Result -Encoding ascii;exit 124};(\"PROCESS_EXIT:\"+$p.ExitCode)|Out-File -LiteralPath $Result -Encoding ascii;exit $p.ExitCode}catch{($_|Out-String)|Out-File -LiteralPath $Stderr -Encoding utf8;'PROCESS_START_FAILED'|Out-File -LiteralPath $Result -Encoding ascii;exit 1}`n";
        }
    }

    private static boolean isWindows() {
        return System.getProperty("os.name", "").toLowerCase(java.util.Locale.ROOT).contains("win");
    }
}
