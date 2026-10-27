package com.example.ahakey.firmware;

import com.example.ahakey.update.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;

public final class FirmwareCatalog {
    private final Map<String,Set<String>> trustedCapabilities = new HashMap<>();
    public FirmwareCatalog() { trustedCapabilities.put(CATALOG, ALL); }
    /** Only the fixed HTTPS manifest client may supply this catalog; unknown identities remain unknown. */
    public synchronized void acceptOfficial(List<ReleaseManifest.FirmwareRelease> releases) throws IOException {
        Map<String,Set<String>> candidate = new HashMap<>(trustedCapabilities);
        for (var release : releases) {
            if (!release.hardwareModel().equals("x1-c582-hw1") || !release.protocolProfile().equals("p1")) continue;
            if (!release.catalogKey().startsWith("x1-c582-hw1-p1-") || release.capabilities().isEmpty() || !ALL.containsAll(release.capabilities()))
                throw new IOException("官方固件能力不能由当前协议执行。");
            Set<String> caps = Set.copyOf(release.capabilities()), previous = candidate.putIfAbsent(release.catalogKey(), caps);
            if (previous != null && !previous.equals(caps)) throw new IOException("同一固件 catalog 的能力声明冲突。");
        }
        trustedCapabilities.clear(); trustedCapabilities.putAll(candidate);
    }
    public synchronized Map<String,Set<String>> knownCapabilities() { return Map.copyOf(trustedCapabilities); }
    public static final Set<String> ALL = Set.of("keys", "side", "lights");
    public static final String CATALOG = "x1-c582-hw1-p1-1.0.0-r001";
    public static final String HEX_NAME = "x1-c582-hw1-p1-r001-cp2-memory-safety-20261018.hex";
    public static final String HEX_HASH = "ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539";
    public enum Source { BUILTIN, OFFICIAL, LOCAL }
    public record Target(Source source, String releaseId, String catalog, String hardware, String protocol, String hash,
                         Set<String> capabilities, long order, Path file) {
        public Target { capabilities = Set.copyOf(capabilities); }
        public boolean unknownLocal() { return source == Source.LOCAL && catalog.isBlank(); }
        public Set<String> requiredBackup() { return unknownLocal() ? ALL : capabilities; }
    }
    public Target builtin(Path directory) throws IOException {
        Files.createDirectories(directory); Path path = directory.resolve(HEX_NAME);
        if (!Files.exists(path)) try (var in = getClass().getResourceAsStream("/firmware/" + HEX_NAME)) {
            if (in == null) throw new IOException("内置固件缺失。"); Files.copy(in, path);
        }
        if (!VerifiedDownload.sha256(path).equals(HEX_HASH)) throw new IOException("内置固件 hash 不匹配。");
        IntelHexValidator.validate(path);
        return new Target(Source.BUILTIN, "cp2-memory-safety-20261018", CATALOG, "x1-c582-hw1", "p1", HEX_HASH, ALL, 20261018, path);
    }
    public Target local(Path path) throws IOException {
        IntelHexValidator.validate(path); String hash = VerifiedDownload.sha256(path);
        return new Target(Source.LOCAL, hash.equals(HEX_HASH) ? "cp2-memory-safety-20261018" : "local-" + hash.substring(0, 12),
                hash.equals(HEX_HASH) ? CATALOG : "", hash.equals(HEX_HASH) ? "x1-c582-hw1" : "", hash.equals(HEX_HASH) ? "p1" : "", hash, ALL, 0, path);
    }
    public Target official(ReleaseManifest.FirmwareRelease r, Path file) throws IOException {
        if (!ALL.containsAll(r.capabilities()) || r.capabilities().isEmpty()) throw new IOException("固件能力目录不受支持。");
        if (Files.size(file) != r.size() || !VerifiedDownload.sha256(file).equals(r.sha256())) throw new IOException("官方固件校验失败。");
        IntelHexValidator.validate(file);
        acceptOfficial(List.of(r));
        return new Target(Source.OFFICIAL, r.releaseId(), r.catalogKey(), r.hardwareModel(), r.protocolProfile(), r.sha256(), r.capabilities(), r.releaseOrder(), file);
    }
    public void compatible(Target t, String sourceCatalog) throws IOException {
        if (t.unknownLocal()) return;
        if (!t.hardware.equals("x1-c582-hw1") || !t.protocol.equals("p1") || !sourceCatalog.startsWith("x1-c582-hw1-p1-")) throw new IOException("所选固件与键盘型号或协议不兼容。");
    }
    public synchronized Set<String> capabilities(String observedCatalog) { return trustedCapabilities.getOrDefault(observedCatalog, Set.of()); }
    // No reliable old-firmware identity has been supplied. Numeric 1.0 / timeout is never evidence.
    public boolean reliableLegacy(String observedCatalog) { return false; }
}
