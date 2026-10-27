package com.example.ahakey.update;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;
import java.util.concurrent.TimeUnit;

/** Read-only MSI registration and launcher proof; no registry writes or repair calls. */
public final class WindowsInstalledApplication {
    public record Snapshot(String productCode, String upgradeCode, String version, String variant, String arch,
                           String directory, String launcher, String buildId, String msiSha256, int context) {}
    @FunctionalInterface public interface Locator { Snapshot read(Path launcher, Path work) throws Exception; }
    public static Snapshot read(Path launcher, Path work) throws Exception {
        Path directory=Files.createTempDirectory(work,"installed-");
        Path script=WindowsUpdateInstaller.worker(directory), result=directory.resolve("installed.json");
        Process process=new ProcessBuilder(WindowsUpdateInstaller.powershell(),"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
                "-File",script.toString(),"-Mode","Resolve","-Executable",launcher.toString(),"-Result",result.toString())
                .redirectErrorStream(true).redirectOutput(directory.resolve("resolve.log").toFile()).start();
        if(!process.waitFor(30,TimeUnit.SECONDS)) {
            process.destroyForcibly();process.waitFor(3,TimeUnit.SECONDS);
            throw new IOException("已安装实例检查超时，原应用继续运行。");
        }
        if(process.exitValue()!=0 || !Files.isRegularFile(result))throw new IOException("无法核实唯一 MSI 安装及原目录；请保留原应用并检查安装记录。");
        return new ObjectMapper().readValue(result.toFile(),Snapshot.class);
    }
    public static boolean samePath(String a,String b) {
        try{return Path.of(a).toAbsolutePath().normalize().equals(Path.of(b).toAbsolutePath().normalize());}
        catch(RuntimeException invalid){return false;}
    }
    private WindowsInstalledApplication() {}
}
