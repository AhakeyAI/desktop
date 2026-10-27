package com.example.ahakey.update;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.core.JsonParser;
import java.io.IOException;
import java.net.URI;
import java.time.Instant;
import java.util.*;

public record ReleaseManifest(Map<String, WindowsRelease> windows, List<FirmwareRelease> firmware) {
    public record WindowsRelease(String variant, String version, String arch, String installerKind, URI url,
                                 long size, String sha256, String productId, String upgradeCode, String signerPolicyId) {
        public void matches(InstalledAppIdentity app) throws IOException {
            app.validate();
            if (!variant.equals(app.variant()) || !arch.equals(app.arch()) || !productId.equals(app.productId())
                    || !upgradeCode.equalsIgnoreCase(app.upgradeCode()) || !installerKind.equals("jpackage-exe"))
                throw new IOException("发布包的产品、形态或升级身份不匹配。");
            if (InstalledAppIdentity.compareVersions(version, app.version()) <= 0) throw new IOException("不允许安装相同或更早的软件版本。");
        }
    }
    public record FirmwareRelease(String releaseId, String catalogKey, String hardwareModel, String protocolProfile,
                                  URI hexUrl, long size, String sha256, List<String> recommendedFor,
                                  Set<String> capabilities, long releaseOrder) {}
    public ReleaseManifest { windows = Map.copyOf(windows); firmware = List.copyOf(firmware); }
    public static ReleaseManifest parse(byte[] data) throws IOException {
        JsonNode root = new ObjectMapper().enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION).readTree(data);
        if (root == null || !root.path("schema").isInt() || !Set.of(2,3).contains(root.path("schema").asInt()) || !text(root, "channel").equals("stable"))
            throw new IOException("不支持的更新目录格式。");
        if(root.path("schema").asInt()==3){
            String version=text(root,"version");InstalledAppIdentity.compareVersions(version,version);
            JsonNode windows=root.get("windows");if(windows==null||!windows.isObject())throw new IOException("更新目录缺少Windows形态");
            Map<String,WindowsRelease> releases=new LinkedHashMap<>();var fields=windows.fields();
            while(fields.hasNext()){
                var field=fields.next();String variant=field.getKey();
                if(!Set.of("lite","local-model").contains(variant))throw new IOException("未知软件形态");
                releases.put(variant,new WindowsRelease(variant,version,"x64","jpackage-exe",url(field.getValue(),"url"),-1,"",InstalledAppIdentity.PRODUCT,InstalledAppIdentity.UPGRADE_CODE,"release-rsa3072-v1"));
            }
            return new ReleaseManifest(releases,List.of());
        }
        try { Instant.parse(text(root, "generatedAt")); } catch (RuntimeException e) { throw new IOException("目录日期无效。", e); }
        JsonNode win = root.get("windows"), fw = root.path("firmware").get("entries");
        if (win == null || !win.isObject() || fw == null || !fw.isArray()) throw new IOException("目录缺少软件或固件列表。");
        Map<String, WindowsRelease> software = new LinkedHashMap<>();
        var fields = win.fields();
        while (fields.hasNext()) {
            var field = fields.next(); String variant = field.getKey(); JsonNode n = field.getValue();
            if (!Set.of("lite", "local-model").contains(variant)) throw new IOException("未知软件形态。");
            String version = text(n, "version"); InstalledAppIdentity.compareVersions(version, version);
            var release = new WindowsRelease(variant, version, text(n, "arch"), text(n, "installerKind"), url(n, "url"),
                    size(n, 2L * 1024 * 1024 * 1024), hash(n), text(n, "productId"), text(n, "upgradeCode"), text(n, "signerPolicyId"));
            if (!release.arch.equals("x64") || !release.installerKind.equals("jpackage-exe") || !release.productId.equals(InstalledAppIdentity.PRODUCT)
                    || !release.upgradeCode.equalsIgnoreCase(InstalledAppIdentity.UPGRADE_CODE)) throw new IOException("目录安装身份不受支持。");
            software.put(variant, release);
        }
        List<FirmwareRelease> firmware = new ArrayList<>(); Set<String> ids = new HashSet<>();
        for (JsonNode n : fw) {
            String id = text(n, "releaseId");
            if (!ids.add(id)) throw new IOException("固件 releaseId 重复。");
            long order = n.path("releaseOrder").isIntegralNumber() ? n.path("releaseOrder").asLong(-1) : -1;
            if (order < 0) throw new IOException("固件排序缺失。");
            firmware.add(new FirmwareRelease(id, text(n, "catalogKey"), text(n, "hardwareModel"), text(n, "protocolProfile"),
                    url(n, "hexUrl"), size(n, 4 * 1024 * 1024), hash(n), strings(n, "recommendedFor"), Set.copyOf(strings(n, "capabilities")), order));
        }
        return new ReleaseManifest(software, firmware);
    }
    private static List<String> strings(JsonNode n, String key) throws IOException {
        if (!n.path(key).isArray()) throw new IOException("目录缺少 " + key);
        List<String> out = new ArrayList<>();
        for (JsonNode item : n.get(key)) { if (!item.isTextual() || item.asText().isBlank()) throw new IOException("目录列表无效。"); out.add(item.asText()); }
        return List.copyOf(out);
    }
    private static URI url(JsonNode n, String key) throws IOException {
        try { URI uri = URI.create(text(n, key)); ReleaseManifestClient.requireAllowedUrl(uri); return uri; }
        catch (IllegalArgumentException e) { throw new IOException("更新链接无效。", e); }
    }
    private static long size(JsonNode n, long max) throws IOException {
        JsonNode v = n.get("size");
        if (v == null || !v.isIntegralNumber() || !v.canConvertToLong() || v.asLong() <= 0 || v.asLong() > max) throw new IOException("发布文件大小无效。");
        return v.asLong();
    }
    private static String hash(JsonNode n) throws IOException { String h = text(n, "sha256").toLowerCase(Locale.ROOT); if (!h.matches("[a-f0-9]{64}")) throw new IOException("发布 hash 无效。"); return h; }
    private static String text(JsonNode n, String k) throws IOException { JsonNode v = n.get(k); if (v == null || !v.isTextual() || v.asText().isBlank()) throw new IOException("目录缺少 " + k); return v.asText(); }
}
