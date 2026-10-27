package com.example.ahakey.update;

import com.example.ahakey.firmware.DeviceMaintenanceCoordinator;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** A ready worker is only permission to exit, never proof of installation. */
public final class WindowsUpdateInstaller {
    public record Handshake(Path directory, String operationId, String requestHash) {}
    @FunctionalInterface public interface Launcher { Process launch(List<String> command, Path log) throws IOException; }
    private static final ObjectMapper JSON = new ObjectMapper();
    private final Launcher launcher;
    private final WindowsInstalledApplication.Locator installed;
    public WindowsUpdateInstaller() { this((command, log) -> new ProcessBuilder(command).redirectErrorStream(true).redirectOutput(log.toFile()).start()); }
    public WindowsUpdateInstaller(Launcher launcher) { this(launcher,WindowsInstalledApplication::read); }
    public WindowsUpdateInstaller(Launcher launcher, WindowsInstalledApplication.Locator installed) { this.launcher = launcher; this.installed=installed; }
    public static Path worker(Path directory) throws IOException {
        Files.createDirectories(directory); Path path = directory.resolve("windows-update-worker.ps1");
        for(String resource:List.of("windows-update-worker.ps1","InstalledApplication.cs")) {
            try (var in = WindowsUpdateInstaller.class.getResourceAsStream("/update/"+resource)) {
                if (in == null) throw new IOException("安装协调资源缺失。"); Files.copy(in, directory.resolve(resource), StandardCopyOption.REPLACE_EXISTING);
            }
        }
        return path;
    }
    public static String powershell() { return Path.of(System.getenv().getOrDefault("SystemRoot", "C:\\Windows"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe").toString(); }
    public static InstallerTrustPolicy.Evidence inspect(Path exe, Path work) throws Exception {
        Path directory = Files.createTempDirectory(work, "inspect-"); Path script = worker(directory), result = directory.resolve("inspection.json");
        Process p = new ProcessBuilder(powershell(), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script.toString(),
                "-Mode", "Inspect", "-Executable", exe.toAbsolutePath().toString(), "-Result", result.toString()).redirectErrorStream(true).redirectOutput(directory.resolve("inspect.log").toFile()).start();
        if (!p.waitFor(60, TimeUnit.SECONDS)) {p.destroyForcibly();p.waitFor(3,TimeUnit.SECONDS);throw new IOException("签名/安装身份检查超时。");}
        if (p.exitValue() != 0 || !Files.exists(result)) throw new IOException("无法读取安装包签名或 MSI 身份。");
        var evidence=JSON.readValue(result.toFile(), InstallerTrustPolicy.Evidence.class);
        if(evidence.msiSha256()==null)throw new IOException("实际MSI摘要缺失。");
        return evidence;
    }
    public Handshake prepare(DeviceMaintenanceCoordinator.Operation op, Path file, ReleaseManifest.WindowsRelease release,
                             InstalledAppIdentity app, InstallerTrustPolicy trust, Path root, Path currentLauncher) throws Exception {
        trust.verify(file, release, app);
        if (!Files.isRegularFile(currentLauncher) || !currentLauncher.getFileName().toString().equalsIgnoreCase("AhaKeyStudio.exe")) throw new IOException("当前安装启动入口不可确认。");
        Path directory = Files.createDirectory(root.resolve(op.id().toString()));
        var source=installed.read(currentLauncher,directory);
        if(source.context()!=4 || !source.version().equals(app.version()) || !source.variant().equals(app.variant())
                || !source.arch().equals(app.arch()) || !source.upgradeCode().equalsIgnoreCase(app.upgradeCode())
                || !source.buildId().equals(app.buildId()) || !WindowsInstalledApplication.samePath(source.launcher(),currentLauncher.toString()))
            throw new IOException("运行中的应用与 MSI 安装身份不一致。");
        Path frozen = directory.resolve("installer.exe"); Files.copy(file, frozen); var target=trust.verify(frozen, release, app);
        if(target.msiSha256()==null || target.buildId()==null || !target.buildId().matches("[a-f0-9]{64}"))throw new IOException("目标包缺少可确认的构建身份。");
        Path script = worker(directory); Map<String,Object> request = new LinkedHashMap<>();
        request.put("operationId", op.id().toString()); request.put("installer", frozen.toAbsolutePath().toString()); request.put("sha256", VerifiedDownload.sha256(frozen));
        request.put("size", Files.size(frozen));
        request.put("version", release.version()); request.put("variant", release.variant()); request.put("arch", release.arch());
        request.put("productId", release.productId()); request.put("upgradeCode", release.upgradeCode()); request.put("launcher", currentLauncher.toAbsolutePath().toString());
        request.put("source",source);request.put("targetProductCode",target.productCode());request.put("targetMsiSha256",target.msiSha256());request.put("targetBuildId",target.buildId());
        request.put("parentPid", ProcessHandle.current().pid()); request.put("parentStart", ProcessHandle.current().info().startInstant().orElseThrow().toEpochMilli());
        Path input = directory.resolve("request.json"); JSON.writeValue(input.toFile(), request); String hash = VerifiedDownload.sha256(input);
        Process process = launcher.launch(List.of(powershell(), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script.toString(),
                "-Mode", "Install", "-Request", input.toString(), "-RequestHash", hash), directory.resolve("worker.log"));
        long end = System.nanoTime() + TimeUnit.SECONDS.toNanos(70);
        Path ready = directory.resolve("ready.json");
        while (process.isAlive() && System.nanoTime() < end) {
            if (Files.isRegularFile(ready)) {
                var n = JSON.readTree(ready.toFile());
                if (n.path("operationId").asText().equals(op.id().toString()) && n.path("requestHash").asText().equals(hash)) return new Handshake(directory, op.id().toString(), hash);
                throw new IOException("安装协调握手身份不匹配。");
            }
            Thread.sleep(100);
        }
        // Worker cannot install without both this permit and parent exit; timeout leaves application running.
        throw new IOException("安装协调未就绪，原应用继续运行。");
    }
    public synchronized void permitExit(Handshake h) throws IOException {
        Path permit = h.directory.resolve("exit-permit.json");
        if (Files.exists(permit)) throw new IOException("退出许可已存在，不可覆盖。");
        Path temporary = Files.createTempFile(h.directory, "exit-permit-", ".tmp");
        try {
            JSON.writeValue(temporary.toFile(), Map.of("operationId", h.operationId, "requestHash", h.requestHash));
            Files.move(temporary, permit, StandardCopyOption.ATOMIC_MOVE);
        } finally { Files.deleteIfExists(temporary); }
    }
    public static String reconcileReceipts(Path root, InstalledAppIdentity app) throws IOException {
        return reconcileReceipts(root, app, WindowsUpdateInstaller::currentBootIdentity);
    }
    @FunctionalInterface public interface BootIdentity { String read() throws IOException; }
    private static String currentBootIdentity() throws IOException {
        Process process = new ProcessBuilder(powershell(), "-NoProfile", "-NonInteractive", "-Command",
                "(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().Ticks.ToString()")
                .redirectError(ProcessBuilder.Redirect.DISCARD).start();
        try {
            if (!process.waitFor(10, TimeUnit.SECONDS) || process.exitValue() != 0) return "";
            String value = new String(process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8).trim();
            return value.matches("[0-9]{15,20}") ? value : "";
        } catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new IOException(e); }
    }
    public static String reconcileReceipts(Path root, InstalledAppIdentity app, BootIdentity bootIdentity) throws IOException {
        return reconcileReceipts(root,app,bootIdentity,WindowsInstalledApplication::read);
    }
    public static String reconcileReceipts(Path root, InstalledAppIdentity app, BootIdentity bootIdentity, WindowsInstalledApplication.Locator installed) throws IOException {
        if (!Files.isDirectory(root)) return "";
        String message = "";
        try (var paths = Files.list(root)) {
            // Request file time is fixed before its bound hash/worker handshake; later confirmations do not reorder operations.
            for (Path dir : paths.filter(Files::isDirectory).sorted(Comparator.comparingLong(WindowsUpdateInstaller::requestTime).thenComparing(Path::toString)).toList()) {
                Path receipt = dir.resolve("receipt.json"), request = dir.resolve("request.json");
                Path pending=dir.resolve("pending.json");
                if(!Files.exists(receipt) && Files.isRegularFile(request) && Files.isRegularFile(pending)) {
                    var waiting=JSON.readTree(pending.toFile());var requested=JSON.readTree(request.toFile());
                    if(waiting.path("requestHash").asText().equals(VerifiedDownload.sha256(request)) && waiting.path("operationId").asText().equals(requested.path("operationId").asText()))
                        message="安装尚未返回最终结果，请勿重复安装；保留安装窗口和日志。";
                }
                if (!Files.isRegularFile(receipt) || !Files.isRegularFile(request)) continue;
                var r = JSON.readTree(receipt.toFile()); var q = JSON.readTree(request.toFile());
                if (!r.path("operationId").asText().equals(q.path("operationId").asText()) || !r.path("requestHash").asText().equals(VerifiedDownload.sha256(request))) continue;
                String state = r.path("state").asText();
                int code = r.path("exitCode").asInt(-1);
                boolean needsBoot = (state.equals("reboot-required") && code == 3010) || (state.equals("reboot-initiated") && code == 1641);
                boolean success = (state.equals("installed-unconfirmed") && code == 0) || needsBoot;
                boolean identityMatches = app.installed() && app.version().equals(q.path("version").asText())
                        && app.variant().equals(q.path("variant").asText()) && app.productId().equals(q.path("productId").asText())
                        && app.arch().equals(q.path("arch").asText()) && app.upgradeCode().equalsIgnoreCase(q.path("upgradeCode").asText())
                        && app.buildId().equals(q.path("targetBuildId").asText()) && q.path("targetMsiSha256").asText().matches("[a-f0-9]{64}")
                        && !q.path("source").path("productCode").asText().isBlank();
                if(success && identityMatches) {
                    try {
                        String launch=System.getProperty("jpackage.app-path","");
                        var actual=installed.read(Path.of(launch),dir);
                        identityMatches=actual.context()==4 && actual.productCode().equalsIgnoreCase(q.path("targetProductCode").asText())
                                && actual.version().equals(app.version()) && actual.variant().equals(app.variant()) && actual.arch().equals(app.arch())
                                && actual.upgradeCode().equalsIgnoreCase(app.upgradeCode()) && actual.buildId().equals(app.buildId())
                                && WindowsInstalledApplication.samePath(actual.directory(),q.path("source").path("directory").asText())
                                && WindowsInstalledApplication.samePath(actual.launcher(),launch);
                    } catch(Exception unavailable) {identityMatches=false;}
                }
                Path confirmation = dir.resolve("restart-confirmed.json");
                if (Files.isRegularFile(confirmation)) {
                    var confirmed = JSON.readTree(confirmation.toFile());
                    if (success && identityMatches && confirmed.path("operationId").asText().equals(r.path("operationId").asText())
                            && confirmed.path("requestHash").asText().equals(r.path("requestHash").asText())
                            && confirmed.path("productCode").asText().equals(q.path("targetProductCode").asText())
                            && confirmed.path("buildId").asText().equals(app.buildId())) {
                        message = "重启已确认：" + app.version(); continue;
                    }
                }
                String before = r.path("bootIdBefore").asText(), after = "";
                if (success && needsBoot && identityMatches && before.matches("[0-9]{15,20}")) {
                    try { after = bootIdentity.read(); } catch (IOException unavailable) { after = ""; }
                }
                boolean bootChanged = before.matches("[0-9]{15,20}") && after.matches("[0-9]{15,20}") && !before.equals(after);
                if (success && identityMatches && (!needsBoot || bootChanged)) {
                    Map<String,Object> confirmed = new LinkedHashMap<>();
                    confirmed.put("operationId", r.path("operationId").asText()); confirmed.put("requestHash", r.path("requestHash").asText());
                    confirmed.put("version", app.version()); confirmed.put("buildId", app.buildId()); confirmed.put("at", Instant.now().toString());
                    confirmed.put("productCode",q.path("targetProductCode").asText());confirmed.put("directory",q.path("source").path("directory").asText());
                    confirmed.put("exitCode", code); confirmed.put("systemRebootRequired", needsBoot); confirmed.put("systemRebootObserved", bootChanged);
                    confirmed.put("bootIdBefore", before); confirmed.put("bootIdAfter", after);
                    Path temporary = Files.createTempFile(dir, "restart-confirmed-", ".tmp");
                    try { JSON.writeValue(temporary.toFile(), confirmed); Files.move(temporary, confirmation, StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING); }
                    finally { Files.deleteIfExists(temporary); }
                    message = "重启已确认：" + app.version();
                } else message = "上次安装结果：" + state + "；" + (needsBoot && identityMatches ? "目标应用版本已匹配，尚未核实 Windows 系统重启。" : "尚未确认目标版本重启。");
            }
        }
        return message;
    }
    private static long requestTime(Path directory) {
        try { return Files.getLastModifiedTime(directory.resolve("request.json")).toMillis(); }
        catch (IOException missing) { return Long.MIN_VALUE; }
    }
}
