package com.example.ahakey.firmware;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/** Single process boundary for direct/elevated WCHISP execution. */
public class WchIspRunner {
    private final Backend backend;

    public WchIspRunner() {
        this(new ProcessBuilderBackend());
    }

    public WchIspRunner(Backend backend) {
        this.backend = backend == null ? new ProcessBuilderBackend() : backend;
    }

    public WchIspProcessResult run(WchIspCommand command, CancellationToken cancellation)
        throws Exception {
        if (command == null) throw new IllegalArgumentException("command is required");
        return backend.run(command, cancellation == null ? CancellationToken.NONE : cancellation);
    }

    @FunctionalInterface
    public interface Backend {
        WchIspProcessResult run(WchIspCommand command, CancellationToken cancellation)
            throws Exception;
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
        String terminationReason
    ) {
        public WchIspProcessResult {
            stdout = stdout == null ? "" : stdout;
            stderr = stderr == null ? "" : stderr;
            console = console == null ? stdout + stderr : console;
            duration = duration == null ? Duration.ZERO : duration;
            rawArtifacts = rawArtifacts == null ? Map.of() : Map.copyOf(rawArtifacts);
            terminationReason = terminationReason == null ? "" : terminationReason;
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
                Duration.ofNanos(System.nanoTime() - startedAt), false, Map.of(), reason);
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
}
