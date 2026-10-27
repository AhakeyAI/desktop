package com.example.ahakey.update;

import java.io.IOException;
import java.util.Properties;

/** productId is the stable application family, not the per-version MSI ProductCode. */
public record InstalledAppIdentity(String version, String variant, String arch, String productId,
                                   String upgradeCode, String buildId, boolean installed) {
    public static final String PRODUCT = "AhaKeyStudio";
    public static final String UPGRADE_CODE = "{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}";
    public static InstalledAppIdentity load() {
        Properties p = new Properties();
        try (var in = InstalledAppIdentity.class.getResourceAsStream("/update/app-release.properties")) {
            if (in != null) p.load(in);
            var result = new InstalledAppIdentity(p.getProperty("version", "0.0.0"), p.getProperty("variant", "development"),
                    p.getProperty("arch", "unknown"), p.getProperty("productId", PRODUCT), p.getProperty("upgradeCode", ""),
                    p.getProperty("buildId", "development"), Boolean.parseBoolean(p.getProperty("installed", "false")));
            if (result.installed) result.validate();
            return result;
        } catch (Exception e) { return new InstalledAppIdentity("0.0.0", "development", "unknown", PRODUCT, "", "invalid-metadata", false); }
    }
    public void validate() throws IOException {
        versionParts(version);
        if (!installed || !(variant.equals("lite") || variant.equals("local-model")) || !arch.equals("x64")
                || !productId.equals(PRODUCT) || !upgradeCode.equalsIgnoreCase(UPGRADE_CODE) || buildId.isBlank())
            throw new IOException("安装身份缺失或不匹配；开发版不执行软件更新。");
    }
    private static int[] versionParts(String v) throws IOException {
        if (v == null || !v.matches("(0|[1-9][0-9]{0,4})\\.(0|[1-9][0-9]{0,4})\\.(0|[1-9][0-9]{0,4})")) throw new IOException("版本格式无效。");
        return java.util.Arrays.stream(v.split("\\.")).mapToInt(Integer::parseInt).toArray();
    }
    public static int compareVersions(String a, String b) throws IOException {
        int[] x = versionParts(a), y = versionParts(b);
        for (int i = 0; i < 3; i++) if (x[i] != y[i]) return Integer.compare(x[i], y[i]);
        return 0;
    }
}
