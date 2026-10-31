package com.example.ahakey.firmware;

import com.example.ahakey.update.VerifiedDownload;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;

public final class DeviceBackupStore {
    private final Path directory;
    private final ObjectMapper json = new ObjectMapper();
    public record Saved(Path file, String hash) {}
    public DeviceBackupStore(Path directory) { this.directory = directory; }
    public Saved save(DeviceBackup backup) throws IOException {
        backup.validate(); Files.createDirectories(directory);
        Path temporary = Files.createTempFile(directory, "backup-", ".tmp");
        json.writeValue(temporary.toFile(), backup);
        String hash = VerifiedDownload.sha256(temporary);
        Path destination = directory.resolve(backup.operationId() + ".json");
        Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE);
        Saved saved = new Saved(destination, hash); load(saved).validate(); return saved;
    }
    public DeviceBackup load(Saved saved) throws IOException {
        if (Files.size(saved.file) > 16 * 1024 * 1024 || !VerifiedDownload.sha256(saved.file).equals(saved.hash)) throw new IOException("备份文件已损坏或改变。");
        DeviceBackup b = json.readValue(saved.file.toFile(), DeviceBackup.class); b.validate(); return b;
    }
    public static DeviceBackup.PcFile snapshot(Path file) throws IOException {
        if (Files.notExists(file)) return new DeviceBackup.PcFile(false, "");
        if (!Files.isRegularFile(file) || Files.size(file) > 8 * 1024 * 1024) throw new IOException("PC 配置文件不可读取。");
        byte[] bytes = Files.readAllBytes(file);
        var node = new ObjectMapper().readTree(bytes); if (node == null || !node.isObject()) throw new IOException("PC 配置损坏。");
        return new DeviceBackup.PcFile(true, java.util.Base64.getEncoder().encodeToString(bytes));
    }
}
