package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.Map;

/** AhaType text processing client and its persisted session state. */
public class AhaTypeService {
    public static final String DEFAULT_API_BASE = "https://956798.xyz/prod-api";

    private static final Logger logger = LoggerFactory.getLogger(AhaTypeService.class);
    private static final AhaTypeService INSTANCE = new AhaTypeService();
    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(20);

    private final AhaTypeConfig config;
    private final ObjectMapper mapper;
    private final HttpClient httpClient;
    private final URI apiBase;
    private final Clock clock;
    private volatile boolean enabled;
    private volatile String statusMessage = "AhaType 未启用";

    public AhaTypeService() {
        this(new AhaTypeConfig(), createHttpClient(), configuredApiBase(), Clock.systemUTC());
    }

    public AhaTypeService(AhaTypeConfig config, HttpClient httpClient, URI apiBase, Clock clock) {
        this.config = config;
        this.mapper = new ObjectMapper();
        this.httpClient = httpClient;
        this.apiBase = normalizeApiBase(apiBase);
        this.clock = clock;
        refreshFromDisk();
    }

    public static AhaTypeService getInstance() {
        return INSTANCE;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public String getStatusMessage() {
        return statusMessage;
    }

    public String getAccessToken() {
        return stringValue(readConfig().get(AhaTypeConfig.ACCESS_TOKEN)).trim();
    }

    public boolean hasValidToken() {
        Map<String, Object> values = readConfig();
        String token = stringValue(values.get(AhaTypeConfig.ACCESS_TOKEN)).trim();
        return !token.isEmpty() && tokenIsStillValid(values.get(AhaTypeConfig.TOKEN_VALID_UNTIL));
    }

    public Map<String, Object> getUserProfile() {
        Object value = readConfig().get(AhaTypeConfig.USER);
        if (!(value instanceof Map<?, ?> map)) {
            return Map.of();
        }
        Map<String, Object> copy = new LinkedHashMap<>();
        map.forEach((key, item) -> copy.put(String.valueOf(key), item));
        return copy;
    }

    public void refreshFromDisk() {
        Map<String, Object> values = readConfig();
        enabled = boolValue(values.get(AhaTypeConfig.ENABLED));
        updateStatus(values);
    }

    /** Persist an enabled request only when a current cloud token exists. */
    public void setEnabled(boolean requested) {
        Map<String, Object> values = readConfig();
        boolean effective = requested && hasValidToken(values);
        values.put(AhaTypeConfig.ENABLED, effective);
        writeConfig(values);
        enabled = effective;
        if (requested && !effective) {
            statusMessage = "AhaType 未登录或登录已过期";
        } else {
            updateStatus(values);
        }
    }

    public void patchCloudToken(String token) {
        Map<String, Object> values = readConfig();
        values.put(AhaTypeConfig.ACCESS_TOKEN, token == null ? "" : token.trim());
        writeConfig(values);
        refreshFromDisk();
    }

    public void setTokenValidUntil(Object validUntil) {
        Map<String, Object> values = readConfig();
        values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, validUntil);
        writeConfig(values);
        refreshFromDisk();
    }

    public void setUserProfile(Map<String, Object> profile) {
        Map<String, Object> values = readConfig();
        Map<String, Object> stored = new LinkedHashMap<>();
        if (profile != null) {
            stored.putAll(profile);
        }
        String userId = firstString(stored, "user_id", "userId", "id");
        if (!userId.isEmpty()) {
            stored.put("user_id", userId);
        }
        values.put(AhaTypeConfig.USER, stored);
        Object validUntil = firstValue(stored, "token_valid_until", "tokenValidUntil",
            "expires_at", "expiresAt");
        if (validUntil != null) {
            values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, validUntil);
        }
        for (String field : AhaTypeConfig.quotaFields()) {
            Object quota = firstValue(stored, field);
            if (quota == null && stored.get("quota") instanceof Map<?, ?> nestedQuota) {
                quota = nestedQuota.get(field);
            }
            if (quota != null) {
                values.put(field, quota);
            }
        }
        writeConfig(values);
        refreshFromDisk();
    }

    /** Clear session/quota while retaining the toggle and remembered credentials. */
    public void clearSessionKeepToggle() {
        Map<String, Object> values = readConfig();
        Object toggle = values.get(AhaTypeConfig.ENABLED);
        values.put(AhaTypeConfig.ACCESS_TOKEN, "");
        values.put(AhaTypeConfig.USER, null);
        values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, null);
        for (String field : AhaTypeConfig.quotaFields()) {
            values.put(field, 0);
        }
        values.put(AhaTypeConfig.ENABLED, boolValue(toggle));
        writeConfig(values);
        refreshFromDisk();
    }

    public boolean isRememberPassword() {
        return boolValue(readConfig().get(AhaTypeConfig.REMEMBER_PASSWORD));
    }

    public String getRememberedPhone() {
        return stringValue(readConfig().get(AhaTypeConfig.REMEMBERED_PHONE));
    }

    public String getRememberedPassword() {
        return stringValue(readConfig().get(AhaTypeConfig.REMEMBERED_PASSWORD));
    }

    public void saveRememberedCredentials(String phone, String password, boolean remember) {
        Map<String, Object> values = readConfig();
        values.put(AhaTypeConfig.REMEMBER_PASSWORD, remember);
        values.put(AhaTypeConfig.REMEMBERED_PHONE, remember ? stringValue(phone) : "");
        values.put(AhaTypeConfig.REMEMBERED_PASSWORD, remember ? stringValue(password) : "");
        writeConfig(values);
    }

    public String getQuotaSummary() {
        Map<String, Object> values = readConfig();
        return "日 " + intValue(values.get("used_daily")) + "/" + intValue(values.get("limit_daily"))
            + " · 周 " + intValue(values.get("used_weekly")) + "/" + intValue(values.get("limit_weekly"));
    }

    /** Process one final speech segment; every failure returns the original text. */
    public String processIfEnabled(String text) {
        if (text == null || text.trim().isEmpty()) {
            return text;
        }
        String original = text;
        Map<String, Object> values = readConfig();
        enabled = boolValue(values.get(AhaTypeConfig.ENABLED));
        if (!enabled) {
            statusMessage = "AhaType 未启用，直接粘贴原文";
            return original;
        }
        if (!hasValidToken(values)) {
            statusMessage = "AhaType 未登录或登录已过期，直接粘贴原文";
            return original;
        }
        String token = stringValue(values.get(AhaTypeConfig.ACCESS_TOKEN)).trim();
        try {
            URI endpoint = endpoint("/api/v1/typeless/process");
            String body = mapper.writeValueAsString(Map.of("text", text));
            HttpRequest request = HttpRequest.newBuilder(endpoint)
                .timeout(REQUEST_TIMEOUT)
                .header("Authorization", "Bearer " + token)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            JsonNode root = requireSuccess(response);
            JsonNode data = root.get("data");
            if (data == null || !data.isObject()) {
                throw new IOException("AhaType data is not an object");
            }
            String result = firstText(data, "text", "result");
            if (result.isBlank()) {
                throw new IOException("AhaType result is empty");
            }
            mergeQuota(root, values);
            writeConfig(values);
            statusMessage = "AhaType 处理完成";
            return result;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            statusMessage = "AhaType 处理已中断，直接粘贴原文";
            return original;
        } catch (Exception exception) {
            statusMessage = "AhaType 请求失败，直接粘贴原文";
            logger.warn("AhaType request failed ({})", exception.getClass().getSimpleName());
            return original;
        }
    }

    URI apiBase() {
        return apiBase;
    }

    private URI endpoint(String path) {
        return URI.create(apiBase.toString().replaceAll("/+$", "") + path);
    }

    AhaTypeConfig config() {
        return config;
    }

    private JsonNode requireSuccess(HttpResponse<String> response) throws IOException {
        if (response.statusCode() != 200) {
            throw new IOException("AhaType HTTP status was not 200");
        }
        JsonNode root = mapper.readTree(response.body());
        if (root == null || !root.isObject() || !isSuccessCode(root.get("code"))) {
            throw new IOException("AhaType response envelope was not successful");
        }
        return root;
    }

    private void mergeQuota(JsonNode root, Map<String, Object> values) {
        JsonNode data = root.path("data");
        for (String field : AhaTypeConfig.quotaFields()) {
            JsonNode value = firstNode(data, field);
            if (value == null && data != null && data.isObject()) {
                value = firstNode(data.get("quota"), field);
            }
            if (value == null) {
                value = firstNode(root, field);
            }
            if (value != null && value.isValueNode()) {
                values.put(field, value.isNumber() ? value.numberValue() : value.asText());
            }
        }
    }

    private void updateStatus(Map<String, Object> values) {
        if (!boolValue(values.get(AhaTypeConfig.ENABLED))) {
            statusMessage = "AhaType 未启用，直接粘贴原文";
        } else if (!hasValidToken(values)) {
            statusMessage = "AhaType 未登录或登录已过期";
        } else {
            statusMessage = "AhaType 已启用";
        }
    }

    private Map<String, Object> readConfig() {
        try {
            return config.load();
        } catch (Exception exception) {
            logger.warn("AhaType configuration could not be read ({})", exception.getClass().getSimpleName());
            return AhaTypeConfig.defaults();
        }
    }

    private void writeConfig(Map<String, Object> values) {
        try {
            config.save(values);
        } catch (Exception exception) {
            logger.warn("AhaType configuration could not be saved ({})", exception.getClass().getSimpleName());
        }
    }

    private boolean hasValidToken(Map<String, Object> values) {
        String token = stringValue(values.get(AhaTypeConfig.ACCESS_TOKEN)).trim();
        return !token.isEmpty() && tokenIsStillValid(values.get(AhaTypeConfig.TOKEN_VALID_UNTIL));
    }

    private boolean tokenIsStillValid(Object value) {
        if (value == null || stringValue(value).isBlank()) {
            return true;
        }
        Instant expiry = parseDate(value);
        return expiry != null && expiry.isAfter(clock.instant());
    }

    private Instant parseDate(Object value) {
        if (value instanceof Number number) {
            long raw = number.longValue();
            return Instant.ofEpochMilli(raw < 10_000_000_000L ? raw * 1000L : raw);
        }
        String text = stringValue(value).trim();
        if (text.isEmpty()) {
            return null;
        }
        try {
            return Instant.parse(text);
        } catch (DateTimeParseException ignored) {
            try {
                long raw = Long.parseLong(text);
                return Instant.ofEpochMilli(raw < 10_000_000_000L ? raw * 1000L : raw);
            } catch (NumberFormatException ignoredAgain) {
                return null;
            }
        }
    }

    private static HttpClient createHttpClient() {
        return HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build();
    }

    static URI configuredApiBase() {
        String value = System.getenv("VIBE_TYPELESS_API_BASE");
        if (value == null || value.isBlank()) value = System.getenv("VIBE_API_BASE");
        if (value == null || value.isBlank()) value = DEFAULT_API_BASE;
        return normalizeApiBase(URI.create(value));
    }

    private static URI normalizeApiBase(URI value) {
        String text = value.toString().replaceAll("/+$", "");
        return URI.create(text + "/");
    }

    static boolean isSuccessCode(JsonNode code) {
        if (code == null || code.isNull()) return false;
        String value = code.asText().trim();
        return "0".equals(value) || "200".equals(value);
    }

    static String firstText(JsonNode node, String... names) {
        for (String name : names) {
            JsonNode value = firstNode(node, name);
            if (value != null && !value.isNull() && value.isValueNode()) {
                String text = value.asText();
                if (!text.isBlank()) return text;
            }
        }
        return "";
    }

    static JsonNode firstNode(JsonNode node, String name) {
        if (node == null || !node.isObject()) return null;
        JsonNode value = node.get(name);
        return value == null || value.isNull() ? null : value;
    }

    static Object firstValue(Map<String, Object> values, String... names) {
        if (values == null) return null;
        for (String name : names) {
            if (values.containsKey(name) && values.get(name) != null) return values.get(name);
        }
        return null;
    }

    static String firstString(Map<String, Object> values, String... names) {
        return stringValue(firstValue(values, names));
    }

    static String stringValue(Object value) {
        return value == null ? "" : String.valueOf(value);
    }

    static boolean boolValue(Object value) {
        if (value instanceof Boolean bool) return bool;
        return "true".equalsIgnoreCase(stringValue(value).trim()) || "1".equals(stringValue(value).trim());
    }

    static int intValue(Object value) {
        if (value instanceof Number number) return number.intValue();
        try {
            return Integer.parseInt(stringValue(value).trim());
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }
}
