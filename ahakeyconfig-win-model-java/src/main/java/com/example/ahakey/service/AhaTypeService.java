package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * AhaType 云端文本整理服务。
 * 移植自 macOS 版 AhaTypeTextOptimizer.swift。
 * <p>
 * 行为:语音识别出的文本先发到云端整理(纠错/润色/加标点),再注入光标。
 * 任何失败(未启用/token 失效/网络错误/返回空)都优雅降级为返回原始文本,不阻塞用户。
 */
public class AhaTypeService {

    private static final Logger logger = LoggerFactory.getLogger(AhaTypeService.class);

    private static final AhaTypeService INSTANCE = new AhaTypeService();

    private static final String FALLBACK_API_BASE = "https://956798.xyz/prod-api";
    private static final String CONFIG_FILE_NAME = "typeless_config.json";

    private final ObjectMapper mapper = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(15))
            .build();

    private volatile boolean enabled = false;
    private volatile String statusMessage = "AhaType 未启用。";

    private AhaTypeService() {
        refreshFromDisk();
    }

    public static AhaTypeService getInstance() {
        return INSTANCE;
    }

    // ==================== 状态查询 ====================

    public boolean isEnabled() {
        return enabled;
    }

    public String getStatusMessage() {
        return statusMessage;
    }

    /** 返回当前 access_token(供 CloudAccountManager 判断登录态/拼 Authorization 头)。 */
    public String getAccessToken() {
        return stringValue(loadConfig().get("access_token")).trim();
    }

    /** 是否已有有效的登录 token(用于 UI 判断"是否已登录")。 */
    public boolean hasValidToken() {
        Map<String, Object> config = loadConfig();
        String token = stringValue(config.get("access_token")).trim();
        return !token.isEmpty() && tokenIsStillValid(config.get("token_valid_until"));
    }

    public void refreshFromDisk() {
        Map<String, Object> config = loadConfig();
        enabled = boolValue(config.get("typeless_enabled"));
        updateStatus(config);
    }

    public void setEnabled(boolean enabled) {
        Map<String, Object> config = loadConfig();
        config.put("typeless_enabled", enabled);
        saveConfig(config);
        this.enabled = enabled;
        updateStatus(config);
    }

    /**
     * 从云端拉取的 token 写入配置(由 CloudAccountManager 登录成功后调用)。
     */
    public void patchCloudToken(String token) {
        Map<String, Object> config = loadConfig();
        config.put("access_token", token);
        saveConfig(config);
        refreshFromDisk();
    }

    /**
     * 写入用户资料与配额(由 CloudAccountManager 调用)。
     */
    @SuppressWarnings("unchecked")
    public void setUserProfile(Map<String, Object> profile) {
        Map<String, Object> config = loadConfig();
        Map<String, Object> user = new LinkedHashMap<>();
        user.put("phone", stringValue(profile.get("phone")));
        String uid = stringValue(profile.get("user_id"));
        if (uid.isEmpty()) uid = stringValue(profile.get("id"));
        user.put("user_id", uid);
        config.put("user", user);
        Object validUntil = profile.get("token_valid_until");
        if (validUntil != null) config.put("token_valid_until", validUntil);
        for (String key : new String[]{"limit_daily", "limit_weekly", "limit_monthly",
                "used_daily", "used_weekly", "used_monthly"}) {
            config.put(key, intValue(profile.get(key)));
        }
        saveConfig(config);
        refreshFromDisk();
    }

    public void clearSessionKeepToggle() {
        Map<String, Object> config = loadConfig();
        boolean keep = boolValue(config.get("typeless_enabled"));
        config.put("access_token", "");
        config.put("user", null);
        config.put("token_valid_until", null);
        for (String key : new String[]{"limit_daily", "limit_weekly", "limit_monthly",
                "used_daily", "used_weekly", "used_monthly"}) {
            config.put(key, 0);
        }
        config.put("typeless_enabled", keep);
        saveConfig(config);
        refreshFromDisk();
    }

    // ==================== 核心:整理文本 ====================

    /**
     * 如果 AhaType 启用且 token 有效,把 text 发到云端整理并返回整理后文本。
     * 否则直接返回原文。此方法为同步阻塞调用,应在后台线程执行。
     */
    public String processIfEnabled(String text) {
        String source = text == null ? "" : text.trim();
        if (source.isEmpty()) return text;

        Map<String, Object> config = loadConfig();
        enabled = boolValue(config.get("typeless_enabled"));
        if (!enabled) {
            statusMessage = "AhaType 未启用,直接写入原始转写。";
            return text;
        }

        if (!tokenIsStillValid(config.get("token_valid_until"))) {
            statusMessage = "AhaType 登录已过期,直接写入原始转写。";
            return text;
        }

        String token = stringValue(config.get("access_token")).trim();
        if (token.isEmpty()) {
            statusMessage = "AhaType 缺少登录令牌,直接写入原始转写。";
            return text;
        }

        String base = resolveAPIBase(stringValue(config.get("api_base")));
        String url = base + "/api/v1/typeless/process";
        statusMessage = "AhaType 整理中…";

        try {
            String body = mapper.writeValueAsString(Map.of("text", source));
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(120))
                    .header("Content-Type", "application/json; charset=utf-8")
                    .header("Authorization", "Bearer " + token)
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            int statusCode = response.statusCode();
            if (statusCode != 200) {
                statusMessage = "AhaType 请求失败(HTTP " + statusCode + "),已写入原始转写。";
                return text;
            }

            JsonNode root = mapper.readTree(response.body());
            int code = intValue(root.get("code"));
            if (code != 0 && code != 200) {
                String msg = responseMessage(root);
                statusMessage = msg.isEmpty() ? "AhaType 处理失败,已写入原始转写。" : "AhaType 处理失败:" + msg;
                return text;
            }

            JsonNode data = root.get("data");
            if (data == null || !data.isObject()) {
                statusMessage = "AhaType 返回缺少 data,已写入原始转写。";
                return text;
            }

            // 更新配额(如果有)
            JsonNode quota = data.get("quota");
            if (quota != null && quota.isObject()) {
                mergeQuota(quota, config);
                saveConfig(config);
                updateStatus(config);
            }

            String output = stringValue(data.get("text"));
            if (output.isEmpty()) output = stringValue(data.get("result"));
            String polished = output.trim();
            if (polished.isEmpty()) {
                statusMessage = "AhaType 返回空文本,已写入原始转写。";
                return text;
            }

            statusMessage = "AhaType 已整理,准备粘贴。";
            return polished;
        } catch (IOException | InterruptedException e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            statusMessage = "AhaType 网络错误,已写入原始转写。";
            logger.warn("AhaType process failed: {}", e.getMessage());
            return text;
        }
    }

    // ==================== 配置读写 ====================

    private Path configPath() {
        return Paths.get(System.getProperty("user.home"), ".ahakey", CONFIG_FILE_NAME);
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> loadConfig() {
        ensureConfigFileExists();
        try {
            Map<String, Object> object = mapper.readValue(configPath().toFile(), Map.class);
            Map<String, Object> merged = defaultPayload();
            merged.putAll(object);
            sanitize(merged);
            return merged;
        } catch (IOException e) {
            logger.warn("读取 AhaType 配置失败,使用默认配置: {}", e.getMessage());
            return defaultPayload();
        }
    }

    private void saveConfig(Map<String, Object> config) {
        Map<String, Object> sanitized = defaultPayload();
        sanitized.putAll(config);
        sanitize(sanitized);
        try {
            Files.createDirectories(configPath().getParent());
            File tmp = configPath().resolveSibling(CONFIG_FILE_NAME + ".tmp").toFile();
            mapper.writeValue(tmp, sanitized);
            File target = configPath().toFile();
            if (target.exists()) target.delete();
            tmp.renameTo(target);
        } catch (IOException e) {
            statusMessage = "AhaType 配置写入失败。";
            logger.error("保存 AhaType 配置失败: {}", e.getMessage());
        }
    }

    private void ensureConfigFileExists() {
        if (Files.exists(configPath())) return;
        saveConfig(defaultPayload());
    }

    private void sanitize(Map<String, Object> config) {
        for (String key : new String[]{"api_base", "token_balance", "typeless_balance"}) {
            config.remove(key);
        }
        Object user = config.get("user");
        if (user instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> u = (Map<String, Object>) user;
            u.remove("is_admin");
        }
    }

    private Map<String, Object> defaultPayload() {
        Map<String, Object> d = new LinkedHashMap<>();
        d.put("schema_version", 1);
        d.put("access_token", "");
        d.put("typeless_enabled", false);
        d.put("token_valid_until", null);
        d.put("limit_daily", 0);
        d.put("limit_weekly", 0);
        d.put("limit_monthly", 0);
        d.put("used_daily", 0);
        d.put("used_weekly", 0);
        d.put("used_monthly", 0);
        d.put("user", null);
        // 记住密码
        d.put("remember_password", false);
        d.put("remembered_phone", "");
        d.put("remembered_password", "");
        return d;
    }

    // ==================== 账号密码记忆 ====================

    public boolean isRememberPassword() {
        return boolValue(loadConfig().get("remember_password"));
    }

    public String getRememberedPhone() {
        return stringValue(loadConfig().get("remembered_phone"));
    }

    public String getRememberedPassword() {
        return stringValue(loadConfig().get("remembered_password"));
    }

    /**
     * 保存/清除记住的账号密码。
     * @param remember true:记住并保存 phone/password;false:清除已保存的密码(保留手机号)
     */
    public void saveRememberedCredentials(String phone, String password, boolean remember) {
        Map<String, Object> config = loadConfig();
        config.put("remember_password", remember);
        config.put("remembered_phone", remember ? (phone == null ? "" : phone.trim()) : (phone == null ? "" : phone.trim()));
        config.put("remembered_password", remember ? (password == null ? "" : password) : "");
        saveConfig(config);
    }

    // ==================== 状态/配额展示 ====================

    private void updateStatus(Map<String, Object> config) {
        boolean en = boolValue(config.get("typeless_enabled"));
        String token = stringValue(config.get("access_token")).trim();
        boolean valid = tokenIsStillValid(config.get("token_valid_until"));

        if (!en) statusMessage = "AhaType 未启用。";
        else if (token.isEmpty()) statusMessage = "AhaType 已开启,但尚未登录。";
        else if (!valid) statusMessage = "AhaType 已开启,但登录已过期。";
        else statusMessage = "AhaType 已开启,语音结果会先经云端整理。";
    }

    @SuppressWarnings("unused")
    public String getQuotaSummary() {
        Map<String, Object> config = loadConfig();
        StringBuilder sb = new StringBuilder();
        String daily = quotaLine("日", config.get("used_daily"), config.get("limit_daily"));
        String weekly = quotaLine("周", config.get("used_weekly"), config.get("limit_weekly"));
        String monthly = quotaLine("月", config.get("used_monthly"), config.get("limit_monthly"));
        String sep = "";
        if (!daily.isEmpty()) { sb.append(daily); sep = " · "; }
        if (!weekly.isEmpty()) { sb.append(sep).append(weekly); sep = " · "; }
        if (!monthly.isEmpty()) { sb.append(sep).append(monthly); sep = " · "; }
        String validUntil = stringValue(config.get("token_valid_until"));
        if (!validUntil.isEmpty()) {
            sb.append(sep).append("有效期 ").append(validUntil);
        }
        return sb.length() == 0 ? "暂无配额信息。" : sb.toString();
    }

    private String quotaLine(String title, Object used, Object limit) {
        int u = intValue(used);
        int l = intValue(limit);
        if (u <= 0 && l <= 0) return "";
        return title + " " + u + "/" + l;
    }

    private void mergeQuota(JsonNode quota, Map<String, Object> config) {
        JsonNode validUntil = quota.get("token_valid_until");
        if (validUntil != null && !validUntil.isNull()) {
            config.put("token_valid_until", validUntil.asText());
        }
        for (String key : new String[]{"limit_daily", "limit_weekly", "limit_monthly",
                "used_daily", "used_weekly", "used_monthly"}) {
            JsonNode v = quota.get(key);
            if (v != null) config.put(key, v.asInt());
        }
        config.put("quota_updated_at", Instant.now().getEpochSecond());
    }

    // ==================== API 地址 / Token 校验 ====================

    private String resolveAPIBase(String legacyAPIBase) {
        for (String key : new String[]{"VIBE_TYPELESS_API_BASE", "VIBE_API_BASE"}) {
            String v = normalizeAPIBase(System.getenv(key));
            if (!v.isEmpty()) return v;
        }
        String fallback = normalizeAPIBase(FALLBACK_API_BASE);
        if (!fallback.isEmpty()) return fallback;
        return normalizeAPIBase(legacyAPIBase);
    }

    private String normalizeAPIBase(String raw) {
        if (raw == null) return "";
        String value = raw.trim();
        while (value.endsWith("/")) {
            value = value.substring(0, value.length() - 1);
        }
        if (!value.isEmpty() && !value.contains("://")) {
            value = "https://" + value;
        }
        return value;
    }

    private boolean tokenIsStillValid(Object raw) {
        Instant date = parseDate(raw);
        return date != null && Instant.now().isBefore(date);
    }

    private Instant parseDate(Object raw) {
        String value = stringValue(raw).trim();
        if (value.isEmpty()) return null;
        for (DateTimeFormatter f : new DateTimeFormatter[]{
                DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"),
                DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")}) {
            try {
                return Instant.from(f.withZone(java.time.ZoneOffset.UTC).parse(value));
            } catch (DateTimeParseException ignored) {
            }
        }
        try {
            return Instant.parse(value);
        } catch (DateTimeParseException e) {
            return null;
        }
    }

    // ==================== 工具方法 ====================

    private String stringValue(Object value) {
        if (value == null) return "";
        if (value instanceof String) return (String) value;
        if (value instanceof Number) return value.toString();
        if (value instanceof JsonNode) {
            JsonNode n = (JsonNode) value;
            return n.isNull() ? "" : n.asText();
        }
        return "";
    }

    private String responseMessage(JsonNode object) {
        for (String key : new String[]{"errorMsg", "msg", "message", "error"}) {
            JsonNode v = object.get(key);
            if (v != null) {
                String s = v.asText("").trim();
                if (!s.isEmpty()) return s;
            }
        }
        return "";
    }

    private int intValue(Object value) {
        if (value == null) return 0;
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Number) return ((Number) value).intValue();
        if (value instanceof String) {
            try { return Integer.parseInt(((String) value).trim()); } catch (NumberFormatException e) { return 0; }
        }
        if (value instanceof JsonNode) {
            JsonNode n = (JsonNode) value;
            return n.isNull() ? 0 : n.asInt();
        }
        return 0;
    }

    private boolean boolValue(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return (Boolean) value;
        if (value instanceof Number) return ((Number) value).intValue() != 0;
        if (value instanceof String) {
            String s = ((String) value).toLowerCase();
            return s.equals("1") || s.equals("true") || s.equals("yes") || s.equals("on");
        }
        if (value instanceof JsonNode) {
            JsonNode n = (JsonNode) value;
            return !n.isNull() && n.asBoolean(false);
        }
        return false;
    }
}
