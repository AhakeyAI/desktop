package com.example.ahakey.service;

import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinDef.HWND;
import com.sun.jna.platform.win32.WinUser;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Optional;
import java.util.concurrent.TimeUnit;

/** Owns or adopts exactly one BLE bridge process for this Studio instance. */
public final class BleBridgeProcessOwner {
    public static final String WINDOW_TITLE = "AhaKey BLE TCP Driver";

    private static ManagedProcess owned;

    private BleBridgeProcessOwner() {}

    public static synchronized void register(Process process, Path executable) {
        if (process == null) return;
        owned = new ManagedProcess(
            process.toHandle(), normalize(executable), process
        );
    }

    /** Backward-compatible registration for callers that already started a process. */
    public static synchronized void register(Process process) {
        if (process == null) return;
        owned = new ManagedProcess(
            process.toHandle(), commandPath(process.toHandle()), process
        );
    }

    /**
     * Finds an exact executable-path match, adopts it, and restores its window.
     * A missing/unknown command path is never adopted, preventing same-name
     * unrelated processes from being terminated on Studio exit.
     */
    public static synchronized boolean activateOrAdopt(Path executable) {
        Path expected = normalize(executable);
        if (expected == null) return false;

        if (owned != null && owned.isAlive()
            && sameExecutable(owned.executable(), expected)) {
            activateWindow();
            return true;
        }
        if (owned != null && !owned.isAlive()) owned = null;

        Optional<ProcessHandle> match = findExactProcess(expected);
        if (match.isEmpty()) return false;
        owned = new ManagedProcess(match.get(), expected, null);
        activateWindow();
        return true;
    }

    /** Retries foreground activation after a newly started WinForms window appears. */
    public static synchronized boolean activateOwnedWindow() {
        return activateWindow();
    }

    public static synchronized Optional<Long> findExactPid(Path executable) {
        Path expected = normalize(executable);
        if (expected == null) return Optional.empty();
        return findExactProcess(expected).map(ProcessHandle::pid);
    }

    public static synchronized boolean stopOwned() {
        ManagedProcess process = owned;
        owned = null;
        if (process == null || !process.isAlive()) return false;

        boolean destroyed = process.destroy();
        try {
            if (!process.awaitExit(2, TimeUnit.SECONDS)) {
                destroyed |= process.destroyForcibly();
            }
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            destroyed |= process.destroyForcibly();
        }
        return destroyed;
    }

    static boolean sameExecutable(Path actual, Path expected) {
        if (actual == null || expected == null) return false;
        return actual.toAbsolutePath().normalize().toString()
            .equalsIgnoreCase(expected.toAbsolutePath().normalize().toString());
    }

    private static Optional<ProcessHandle> findExactProcess(Path expected) {
        try {
            return ProcessHandle.allProcesses()
                .filter(ProcessHandle::isAlive)
                .filter(handle -> commandPath(handle) != null
                    && sameExecutable(commandPath(handle), expected))
                .findFirst();
        } catch (SecurityException exception) {
            return Optional.empty();
        }
    }

    private static Path commandPath(ProcessHandle handle) {
        try {
            return handle.info().command()
                .map(Paths::get)
                .map(BleBridgeProcessOwner::normalize)
                .orElse(null);
        } catch (SecurityException exception) {
            return null;
        }
    }

    private static Path normalize(Path path) {
        return path == null ? null : path.toAbsolutePath().normalize();
    }

    private static boolean activateWindow() {
        if (!isWindows()) return false;
        try {
            HWND hwnd = User32.INSTANCE.FindWindow(null, WINDOW_TITLE);
            if (hwnd == null) return false;
            User32.INSTANCE.ShowWindow(hwnd, WinUser.SW_RESTORE);
            User32.INSTANCE.BringWindowToTop(hwnd);
            return User32.INSTANCE.SetForegroundWindow(hwnd);
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static boolean isWindows() {
        return System.getProperty("os.name", "")
            .toLowerCase(java.util.Locale.ROOT).contains("win");
    }

    private static final class ManagedProcess {
        private final ProcessHandle handle;
        private final Path executable;
        private final Process process;

        private ManagedProcess(ProcessHandle handle, Path executable, Process process) {
            this.handle = handle;
            this.executable = executable;
            this.process = process;
        }

        private Path executable() { return executable; }
        private boolean isAlive() { return process != null ? process.isAlive() : handle.isAlive(); }
        private boolean destroy() {
            if (process != null) {
                process.destroy();
                return true;
            }
            return handle.destroy();
        }
        private boolean destroyForcibly() {
            if (process != null) {
                process.destroyForcibly();
                return true;
            }
            return handle.destroyForcibly();
        }
        private boolean awaitExit(long timeout, TimeUnit unit) throws InterruptedException {
            if (process != null) return process.waitFor(timeout, unit);
            try {
                return handle.onExit().get(timeout, unit) != null;
            } catch (java.util.concurrent.ExecutionException exception) {
                return !handle.isAlive();
            } catch (java.util.concurrent.TimeoutException timeoutException) {
                return false;
            }
        }
    }
}
