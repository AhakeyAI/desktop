package com.example.ahakey.update;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;

public final class InstallerTrustPolicy {
    public record Evidence(String status, String certificateSha256, String productName, String version,
                           String upgradeCode, String variant, String arch, String productCode,String msiSha256, String buildId) {
        public Evidence {if(msiSha256!=null&&!msiSha256.matches("[a-f0-9]{64}"))throw new IllegalArgumentException("实际MSI摘要格式无效");}
        public Evidence(String status,String certificateSha256,String productName,String version,String upgradeCode,String variant,String arch,String productCode) {
            this(status,certificateSha256,productName,version,upgradeCode,variant,arch,productCode,null,null);
        }
        public Evidence(String status,String certificateSha256,String productName,String version,String upgradeCode,String variant,String arch,String productCode,String msiSha256) {
            this(status,certificateSha256,productName,version,upgradeCode,variant,arch,productCode,msiSha256,null);
        }
    }
    @FunctionalInterface public interface Inspector { Evidence inspect(Path executable) throws Exception; }
    private final Map<String, Set<String>> certificates;
    private final Inspector inspector;
    private final ReleaseSignature releaseSignature;
    public InstallerTrustPolicy(Map<String, Set<String>> certificates, Inspector inspector) {
        Map<String, Set<String>> copy = new HashMap<>(); certificates.forEach((k,v) -> copy.put(k, Set.copyOf(v))); this.certificates = Map.copyOf(copy); this.inspector = inspector;
        this.releaseSignature = null;
    }
    public InstallerTrustPolicy(ReleaseSignature signature, Inspector inspector) {
        this.certificates=Map.of(); this.inspector=inspector; this.releaseSignature=Objects.requireNonNull(signature);
    }
    public static InstallerTrustPolicy production(Path work) throws IOException {
        return new InstallerTrustPolicy(ReleaseSignature.production(), exe -> WindowsUpdateInstaller.inspect(exe, work));
    }
    public Set<String> certificates(String policy) throws IOException {
        var pins = certificates.get(policy);
        if (pins == null || pins.isEmpty()) throw new IOException("安装包可信发布配置尚未就绪。");
        return pins;
    }
    public Evidence verify(Path file, ReleaseManifest.WindowsRelease release, InstalledAppIdentity app) throws Exception {
        if(releaseSignature!=null){
            release.matches(app);var signature=releaseSignature.verify(file);var actual=inspector.inspect(file);
            if(!signature.version().equals(release.version())||!signature.variant().equals(release.variant())||!signature.arch().equals(release.arch())
                    ||!signature.productId().equals(release.productId())||!signature.upgradeCode().equalsIgnoreCase(release.upgradeCode())
                    ||!signature.version().equals(actual.version())||!signature.variant().equals(actual.variant())||!signature.arch().equals(actual.arch())
                    ||!signature.productId().equals(actual.productName())||!signature.upgradeCode().equalsIgnoreCase(actual.upgradeCode())
                    ||!signature.productCode().equalsIgnoreCase(actual.productCode()))throw new IOException("发行签名、实际MSI与更新目标身份不一致。");
            // MSI inspection is read-only; verify the file again before publishing READY.
            if(!signature.equals(releaseSignature.verify(file)))throw new IOException("安装包检查期间改变。");
            return actual;
        }
        release.matches(app); Set<String> pins = certificates(release.signerPolicyId());
        if (Files.size(file) != release.size() || !VerifiedDownload.sha256(file).equals(release.sha256())) throw new IOException("安装包已改变。");
        Evidence e = inspector.inspect(file);
        if (!"Valid".equals(e.status()) || e.certificateSha256() == null || !pins.contains(e.certificateSha256().toLowerCase(Locale.ROOT))) throw new IOException("安装包签名不可信。");
        if (!release.productId().equals(e.productName()) || !release.version().equals(e.version()) || !release.upgradeCode().equalsIgnoreCase(e.upgradeCode())
                || !release.variant().equals(e.variant()) || !release.arch().equals(e.arch()) || e.productCode() == null
                || !e.productCode().matches("\\{[A-Fa-f0-9-]{36}}")) throw new IOException("实际 MSI 身份与发布目录不一致。");
        return e;
    }
}
