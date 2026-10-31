package com.example.ahakey.firmware;

import com.example.ahakey.update.VerifiedDownload;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;

public final class WchRuntimeLocator {
    public static Path installedApp() throws IOException {
        try {
            Path jar=Path.of(WchRuntimeLocator.class.getProtectionDomain().getCodeSource().getLocation().toURI()).toAbsolutePath();
            if(!Files.isRegularFile(jar)||!jar.getFileName().toString().endsWith(".jar"))throw new IOException("请使用已安装应用的随包工具。");
            return jar.getParent().toRealPath();
        }catch(java.net.URISyntaxException e){throw new IOException(e);}
    }
    public record Runtime(String profile, Path directory, Path executable, Map<String,String> hashes) {
        public Runtime { hashes = Map.copyOf(hashes); }
    }
    private final String profile;
    private final Map<String,String> hashes;
    private final Map<String,String> drivers;
    public WchRuntimeLocator() throws IOException {
        try (var in = getClass().getResourceAsStream("/firmware/wch-runtime-profiles.json")) {
            if (in == null) throw new IOException("工具 profile 缺失。");
            var root = new ObjectMapper().readTree(in); profile = root.path("profile").asText();
            if(root.path("schema").asInt()!=2)throw new IOException("随包工具清单版本无效。");
            Map<String,String> files = new LinkedHashMap<>(); root.path("files").fields().forEachRemaining(e -> files.put(e.getKey(), e.getValue().asText())); hashes = Map.copyOf(files);
            Map<String,String> driverFiles=new LinkedHashMap<>();root.path("drivers").fields().forEachRemaining(e->driverFiles.put(e.getKey(),e.getValue().asText()));drivers=Map.copyOf(driverFiles);
        }
    }
    public Runtime locate(Path selected) throws IOException {
        Path dir = (selected == null ? installedApp().resolve("tools/wchisp") : selected).toRealPath();
        if (hashes.size() != 6) throw new IOException("工具 profile 不完整。");
        for (var entry : hashes.entrySet()) {
            Path file = dir.resolve(entry.getKey()).normalize();
            if (!file.startsWith(dir) || !VerifiedDownload.sha256(file).equals(entry.getValue())) throw new IOException("WCH 工具缺失或版本不匹配：" + entry.getKey());
        }
        return new Runtime(profile, dir, dir.resolve("WCHISPTool_CH57x-59x.exe"), hashes);
    }
    public void recheck(Runtime runtime) throws IOException {
        Runtime actual = locate(runtime.directory()); if (!actual.equals(runtime)) throw new IOException("WCH 工具身份已改变。");
    }
    public Path driverDirectory()throws IOException {
        Path dir=installedApp().resolve("drivers/wch-ch375");verifyDrivers(dir);return dir;
    }
    public void verifyDrivers(Path directory)throws IOException {
        if(drivers.size()!=7)throw new IOException("驱动清单不完整");
        Path dir=directory.toRealPath();for(var entry:drivers.entrySet()){
            Path file=dir.resolve(entry.getKey()).normalize();
            if(!file.startsWith(dir)||!VerifiedDownload.sha256(file).equals(entry.getValue()))throw new IOException("随包驱动缺失或改变："+entry.getKey());
        }
    }
    public Runtime copyForOperation(Runtime source,Path destination)throws IOException {
        recheck(source);Files.createDirectory(destination);
        for(String name:hashes.keySet()){Path target=destination.resolve(name);Files.createDirectories(target.getParent());Files.copy(source.directory().resolve(name),target);}
        return locate(destination);
    }
}
