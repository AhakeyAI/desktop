package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/** Login/profile state for the AhaType cloud account menu. */
public class CloudAccountManager {
    private static final Logger logger = LoggerFactory.getLogger(CloudAccountManager.class);
    private static final CloudAccountManager INSTANCE = new CloudAccountManager(
        AhaTypeService.getInstance(), HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build(),
        new ObjectMapper(), AhaTypeService.configuredApiBase(), Clock.systemUTC());

    private final AhaTypeService ahaType;
    private final HttpClient httpClient;
    private final ObjectMapper mapper;
    private final URI apiBase;
    private final Clock clock;
    private volatile boolean loggedIn;
    private volatile String statusMessage = "未登录";
    private volatile Map<String, Object> profile = Map.of();

    public CloudAccountManager() {
        this(AhaTypeService.getInstance(),
            HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build(),
            new ObjectMapper(), AhaTypeService.configuredApiBase(), Clock.systemUTC());
    }

    public CloudAccountManager(AhaTypeService ahaType, HttpClient httpClient,
                               ObjectMapper mapper, URI apiBase, Clock clock) {
        this.ahaType = ahaType;
        this.httpClient = httpClient;
        this.mapper = mapper;
        this.apiBase = normalizeApiBase(apiBase);
        this.clock = clock;
        refreshLocalState();
    }

    public static CloudAccountManager getInstance() {
        return INSTANCE;
    }

    public boolean isLoggedIn() {
        return loggedIn && ahaType.hasValidToken();
    }

    public String getStatusMessage() {
        return statusMessage;
    }

    public Map<String, Object> getProfile() {
        return Collections.unmodifiableMap(new LinkedHashMap<>(profile));
    }

    public String rememberedPhone() {
        return ahaType.getRememberedPhone();
    }

    public String rememberedPassword() {
        return ahaType.getRememberedPassword();
    }

    public boolean rememberPassword() {
        return ahaType.isRememberPassword();
    }

    public String login(String phone, String password) {
        return login(phone, password, false);
    }

    public String login(String phone, String password, boolean rememberPassword) {
        return authenticate("/api/v1/auth/login", phone, password, rememberPassword, true);
    }

    public String register(String phone, String password) {
        return register(phone, password, false);
    }

    public String register(String phone, String password, boolean rememberPassword) {
        return authenticate("/api/v1/auth/register", phone, password, rememberPassword, false);
    }

    public void logout() {
        ahaType.clearSessionKeepToggle();
        profile = Map.of();
        loggedIn = false;
        statusMessage = "已退出登录";
    }

    /** Refresh the snake_case/camelCase profile and quota fields from the server. */
    public String refreshProfile() {
        if (!ahaType.hasValidToken()) {
            loggedIn = false;
            statusMessage = "未登录或登录已过期";
            return statusMessage;
        }
        try {
            JsonNode root = request("/api/v1/users/me", "GET", null, true);
            JsonNode data = dataObject(root);
            applyProfile(data);
            loggedIn = true;
            statusMessage = "已登录";
            return null;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            statusMessage = "刷新账号已中断";
            return statusMessage;
        } catch (Exception exception) {
            statusMessage = "刷新账号失败";
            logger.warn("Cloud profile refresh failed ({})", exception.getClass().getSimpleName());
            return statusMessage;
        }
    }

    private String authenticate(String path, String phone, String password,
                                boolean rememberPassword, boolean requireToken) {
        String normalizedPhone = phone == null ? "" : phone.trim();
        if (normalizedPhone.isEmpty() || password == null || password.isEmpty()) {
            return "请输入手机号和密码";
        }
        try {
            JsonNode root = request(path, "POST", Map.of("phone", normalizedPhone, "password", password), false);
            JsonNode data = dataObject(root);
            String token = firstText(data, "access_token", "token");
            if (token.isEmpty()) token = firstText(root, "access_token", "token");
            if (requireToken && token.isEmpty()) {
                throw new IllegalStateException("账号响应缺少 token");
            }
            if (!token.isEmpty()) {
                ahaType.patchCloudToken(token);
                Object validUntil = tokenValidUntil(data, token);
                if (validUntil != null) ahaType.setTokenValidUntil(validUntil);
            }
            Map<String, Object> localProfile = profileMap(profileNode(data));
            localProfile.putIfAbsent("phone", normalizedPhone);
            ahaType.setUserProfile(localProfile);
            ahaType.saveRememberedCredentials(normalizedPhone, password, rememberPassword);
            profile = Collections.unmodifiableMap(new LinkedHashMap<>(localProfile));
            loggedIn = !token.isEmpty() && ahaType.hasValidToken();
            statusMessage = loggedIn ? "已登录" : "注册成功，请登录";
            if (loggedIn && localProfile.size() <= 1) {
                refreshProfile();
            }
            return null;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            statusMessage = "账号请求已中断";
            return statusMessage;
        } catch (Exception exception) {
            statusMessage = requireToken ? "登录失败" : "注册失败";
            logger.warn("Cloud account request failed ({})", exception.getClass().getSimpleName());
            return statusMessage;
        }
    }

    private JsonNode request(String path, String method, Map<String, Object> payload, boolean authenticated)
            throws Exception {
        HttpRequest.Builder builder = HttpRequest.newBuilder(endpoint(path))
            .timeout(Duration.ofSeconds(20))
            .header("Content-Type", "application/json");
        if (authenticated) {
            String token = ahaType.getAccessToken();
            if (token.isBlank()) throw new IllegalStateException("missing token");
            builder.header("Authorization", "Bearer " + token);
        }
        if ("GET".equals(method)) {
            builder.GET();
        } else {
            String body = mapper.writeValueAsString(payload == null ? Map.of() : payload);
            builder.method(method, HttpRequest.BodyPublishers.ofString(body));
        }
        HttpResponse<String> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) throw new IllegalStateException("unexpected HTTP status");
        JsonNode root = mapper.readTree(response.body());
        if (root == null || !root.isObject() || !AhaTypeService.isSuccessCode(root.get("code"))) {
            throw new IllegalStateException("unsuccessful response envelope");
        }
        return root;
    }

    private void applyProfile(JsonNode node) {
        Map<String, Object> values = profileMap(node);
        profile = Collections.unmodifiableMap(new LinkedHashMap<>(values));
        ahaType.setUserProfile(values);
    }

    private void refreshLocalState() {
        profile = Collections.unmodifiableMap(new LinkedHashMap<>(ahaType.getUserProfile()));
        loggedIn = ahaType.hasValidToken() && !profile.isEmpty();
        if (loggedIn) statusMessage = "已登录";
    }

    private JsonNode dataObject(JsonNode root) {
        JsonNode data = root.get("data");
        return data != null && data.isObject() ? data : root;
    }

    private JsonNode profileNode(JsonNode data) {
        if (data == null || !data.isObject()) return data;
        JsonNode nested = data.get("user");
        if (nested != null && nested.isObject()) return nested;
        nested = data.get("profile");
        return nested != null && nested.isObject() ? nested : data;
    }

    private Map<String, Object> profileMap(JsonNode node) {
        Map<String, Object> values = new LinkedHashMap<>();
        if (node != null && node.isObject()) {
            node.fields().forEachRemaining(entry -> values.put(entry.getKey(), mapper.convertValue(entry.getValue(), Object.class)));
        }
        String userId = firstText(node, "user_id", "userId", "id");
        if (!userId.isEmpty()) values.put("user_id", userId);
        String validUntil = firstText(node, "token_valid_until", "tokenValidUntil", "expires_at", "expiresAt");
        if (!validUntil.isEmpty()) values.put("token_valid_until", validUntil);
        return values;
    }

    private Object tokenValidUntil(JsonNode data, String token) {
        String value = firstText(data, "token_valid_until", "tokenValidUntil", "expires_at", "expiresAt");
        if (!value.isEmpty()) return value;
        JsonNode expiresIn = AhaTypeService.firstNode(data, "expires_in");
        if (expiresIn != null && expiresIn.canConvertToLong()) {
            return clock.instant().plusSeconds(expiresIn.asLong()).toString();
        }
        int dot = token.indexOf('.');
        if (dot >= 0) {
            try {
                String payload = token.substring(dot + 1, token.indexOf('.', dot + 1));
                JsonNode jwt = mapper.readTree(new String(java.util.Base64.getUrlDecoder().decode(payload)));
                JsonNode exp = jwt.get("exp");
                if (exp != null && exp.canConvertToLong()) return Instant.ofEpochSecond(exp.asLong()).toString();
            } catch (Exception ignored) {
                // A non-JWT token is valid as long as the server did not provide an expiry.
            }
        }
        return null;
    }

    private static String firstText(JsonNode node, String... names) {
        return AhaTypeService.firstText(node, names);
    }

    private URI endpoint(String path) {
        return URI.create(apiBase.toString().replaceAll("/+$", "") + path);
    }

    private static URI normalizeApiBase(URI value) {
        return URI.create(value.toString().replaceAll("/+$", "") + "/");
    }
}
