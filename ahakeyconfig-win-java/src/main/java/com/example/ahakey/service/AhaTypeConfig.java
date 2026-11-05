package com.example.ahakey.service;

import com.example.ahakey.platform.windows.WindowsCredentialStore;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.file.*;
import java.util.*;

/** One atomic, DPAPI protected account document; legacy migration preserves unrelated keys. */
public final class AhaTypeConfig {
    private final Path path;
    private final WindowsCredentialStore credentials;
    private final ObjectMapper json = new ObjectMapper();
    public AhaTypeConfig() { this(Path.of(System.getProperty("user.home"), ".ahakey", "typeless_config.json"), new WindowsCredentialStore()); }
    public AhaTypeConfig(Path path, WindowsCredentialStore credentials) { this.path = path.toAbsolutePath(); this.credentials = credentials; }
    public synchronized Map<String,Object> load() throws IOException {
        if (!Files.exists(path)) return new LinkedHashMap<>();
        Map<String,Object> envelope = json.readValue(Files.readAllBytes(path), new TypeReference<>() {});
        if(envelope==null)throw new IOException("账号存储损坏");
        if (envelope.containsKey("protected_state")) {
            if (!Integer.valueOf(1).equals(envelope.get("schema"))) throw new IOException("账号存储版本不支持");
            if(!(envelope.get("protected_state") instanceof String encoded)||encoded.isBlank())throw new IOException("账号存储损坏");
            try {
                byte[] plain = credentials.unprotect(Base64.getDecoder().decode((String)envelope.get("protected_state")));
                try { Map<String,Object> decoded=json.readValue(plain,new TypeReference<>(){});if(decoded==null)throw new IOException("账号存储损坏");return decoded; }
                finally { Arrays.fill(plain, (byte)0); }
            } catch (IllegalArgumentException | ClassCastException e) { throw new IOException("账号存储损坏"); }
        }
        // Protect and atomically replace before exposing legacy secrets to the application.
        save(envelope);
        return envelope;
    }
    public synchronized void save(Map<String,Object> values) throws IOException {
        byte[] plain = json.writeValueAsBytes(values);
        byte[] encrypted;
        try { encrypted = credentials.protect(plain); }
        finally { Arrays.fill(plain, (byte)0); }
        byte[] bytes = json.writeValueAsBytes(Map.of("schema", 1, "protected_state", Base64.getEncoder().encodeToString(encrypted)));
        Files.createDirectories(path.getParent());
        Path temporary = Files.createTempFile(path.getParent(), "account-", ".tmp");
        try {
            Files.write(temporary, bytes);
            try (FileChannel channel = FileChannel.open(temporary, StandardOpenOption.WRITE)) { channel.force(true); }
            // No non-atomic fallback: retain the old document on unsupported filesystems.
            Files.move(temporary, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } finally { Files.deleteIfExists(temporary); }
    }
}
