package com.example.ahakey.service.connection;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;

/** A startup hint, never device identity, capability evidence, or an upload checkpoint. */
public record RememberedBleTarget(String name, String address) {
    private static Path path() { return Path.of(System.getProperty("user.home"), ".ahakey", "last-ble-target.json"); }
    public static RememberedBleTarget load() {
        try {
            var node = new ObjectMapper().readTree(Files.readAllBytes(path()));
            return new RememberedBleTarget(node.path("name").asText(), node.path("address").asText());
        } catch (IOException | RuntimeException e) { return new RememberedBleTarget("", ""); }
    }
    public void save() throws IOException {
        if (address == null || address.isBlank()) return;
        Path target = path(); Files.createDirectories(target.getParent());
        Path temporary = Files.createTempFile(target.getParent(), "ble-target-", ".tmp");
        try {
            new ObjectMapper().writeValue(temporary.toFile(), this);
            try { Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING); }
            catch (AtomicMoveNotSupportedException e) { Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING); }
        } finally { Files.deleteIfExists(temporary); }
    }
    public boolean matches(String candidateAddress) { return !address.isBlank() && address.equalsIgnoreCase(candidateAddress); }
}
