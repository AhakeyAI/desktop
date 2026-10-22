package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import javafx.application.Platform;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import javax.net.ssl.SSLContext;

/**
 * AhaType 云端账号管理。
 * 移植自 macOS 版 CloudAccountManager.swift 的核心部分(登录/注册/登出/刷新配额/兑换码)。
 * <p>
 * token 通过 {@link AhaTypeService#patchCloudToken(String)} 写入 typeless_config.json,
 * 这样 AhaTypeService.processIfEnabled 能直接读取到。
 */
public class CloudAccountManager {

    private static final Logger logger = LoggerFactory.getLogger(CloudAccountManager.class);

    private static final CloudAccountManager INSTANCE = new CloudAccountManager();

    private static final String FALLBACK_API_BASE = "https://956798.xyz/prod-api";

    private final ObjectMapper mapper = new ObjectMapper();
    private final HttpClient httpClient = createHttpClient();

    private static HttpClient createHttpClient() {
        try {
            SSLContext ssl = SSLContext.getInstance("TLSv1.2");
            ssl.init(null, null, null);
            return HttpClient.newBuilder()
                    .connectTimeout(Duration.ofSeconds(15))
                    .sslContext(ssl)
                    .build();
        } catch (NoSuchAlgorithmException | KeyManagementException e) {
            return HttpClient.newBuilder()
                    .connectTimeout(Duration.ofSeconds(15))
                    .build();
        }
    }

    private volatile boolean loggedIn = false;
    private volatile String statusMessage = "尚未登录。";
    private volatile Map<String, Object> profile;
    private volatile CloudPaymentOrder paymentOrder;

    private CloudAccountManager() {
        loggedIn = !AhaTypeService.getInstance().getAccessToken().isEmpty();
        if (loggedIn) statusMessage = "已登录,等待刷新用户信息。";
    }

    public static CloudAccountManager getInstance() {
        return INSTANCE;
    }

    public boolean isLoggedIn() {
        return loggedIn;
    }

    public String getStatusMessage() {
        return statusMessage;
    }

    public Map<String, Object> getProfile() {
        return profile;
    }

    public CloudPaymentOrder getPaymentOrder() {
        return paymentOrder;
    }

    public void clearPaymentOrder() {
        this.paymentOrder = null;
        statusMessage = "已关闭支付订单。";
    }

    /**
     * 登录(同步阻塞,应在后台线程调用)。
     * @return 成功返回 null,失败返回错误消息
     */
    public String login(String phone, String password) {
        return authenticate("api/v1/auth/login", phone, password, "登录成功。", "登录失败。");
    }

    /**
     * 注册(同步阻塞,应在后台线程调用)。
     */
    public String register(String phone, String password) {
        return authenticate("api/v1/auth/register", phone, password, "注册成功。", "注册失败。");
    }

    public void logout() {
        AhaTypeService.getInstance().clearSessionKeepToggle();
        profile = null;
        loggedIn = false;
        statusMessage = "已退出登录。";
    }

    /**
     * 刷新用户信息与配额(同步阻塞)。
     * @return 成功返回 null,失败返回错误消息
     */
    public String refreshProfile() {
        String token = AhaTypeService.getInstance().getAccessToken();
        if (token.isEmpty()) {
            logout();
            return "尚未登录。";
        }
        statusMessage = "正在刷新用户信息…";
        try {
            JsonNode object = request("api/v1/auth/users/me", "GET", null, true);
            JsonNode data = payloadData(object, "获取用户信息失败");
            applyProfile(data);
            statusMessage = "用户信息已刷新。";
            return null;
        } catch (Exception e) {
            statusMessage = "刷新失败。";
            String msg = e.getMessage();
            if (msg != null && msg.contains("401")) logout();
            return msg;
        }
    }

    /**
     * 兑换免费券(同步阻塞)。
     */
    public String redeemCoupon(String code) {
        if (code == null || code.trim().isEmpty()) return "请输入兑换码。";
        statusMessage = "正在兑换免费券…";
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("code", code.trim());
            JsonNode object = request("api/v1/coupon/redeem", "POST", body, true);
            JsonNode data = payloadData(object, "兑换失败");
            applyProfile(data);
            statusMessage = "兑换成功。";
            return null;
        } catch (Exception e) {
            statusMessage = "兑换失败。";
            return e.getMessage();
        }
    }

    // ==================== 充值 ====================

    /**
     * 创建微信支付订单（同步阻塞）。
     * @return 成功返回 null，失败返回错误消息
     */
    public String createWechatOrder(CloudRechargePlan plan) {
        if (!loggedIn) return "请先登录后再充值。";
        statusMessage = "正在创建微信支付订单…";
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("plan", plan.rawValue);
            body.put("description", plan.orderDescription);
            JsonNode object = request("api/v1/payment/wechat/native", "POST", body, true);
            JsonNode data = payloadData(object, "创建支付订单失败");
            String codeURL = firstString(data, "code_url", "codeUrl");
            String h5URL = firstString(data, "h5_url", "h5Url", "mweb_url", "mwebUrl");
            String outTradeNo = firstString(data, "out_trade_no", "outTradeNo");
            if (outTradeNo.isEmpty()) return "云端未返回订单号，无法查询支付状态。";
            if (codeURL.isEmpty() && h5URL.isEmpty()) return "云端未返回可支付链接。";
            int amountFen = firstInt(data, "amount_fen", "amountFen");
            this.paymentOrder = new CloudPaymentOrder(plan, amountFen, outTradeNo, codeURL, h5URL, "pending");
            statusMessage = "订单已创建，请使用微信扫码支付。";
            pollPaymentStatus(outTradeNo);
            return null;
        } catch (Exception e) {
            statusMessage = "创建支付订单失败。";
            return e.getMessage();
        }
    }

    /** 查询订单状态（同步阻塞）。 */
    public String fetchPaymentStatus(String outTradeNo) {
        try {
            String encoded = java.net.URLEncoder.encode(outTradeNo, "UTF-8");
            JsonNode object = request("api/v1/payment/wechat/order-status?outTradeNo=" + encoded, "GET", null, true);
            JsonNode data = payloadData(object, "查询订单状态失败");
            return normalizedPaymentStatus(data);
        } catch (Exception e) {
            return "pending";
        }
    }

    /** 应用支付状态到当前订单，返回是否已支付完成。 */
    public boolean applyPaymentStatus(String status, String outTradeNo) {
        String normalized = status.isEmpty() ? "pending" : status;
        if (paymentOrder != null && paymentOrder.outTradeNo.equals(outTradeNo)) {
            paymentOrder = new CloudPaymentOrder(
                paymentOrder.plan, paymentOrder.amountFen, outTradeNo,
                paymentOrder.codeURL, paymentOrder.h5URL, normalized);
        }
        if ("success".equals(normalized) || "paid".equals(normalized)) {
            statusMessage = "充值成功，正在刷新额度。";
            paymentOrder = null;
            refreshProfile();
            return true;
        }
        if ("failed".equals(normalized) || "closed".equals(normalized)) {
            statusMessage = "订单已标记为失败，请重新发起充值。";
            paymentOrder = null;
            return true;
        }
        return false;
    }

    /** 获取套餐价格文本。 */
    public String priceText(CloudRechargePlan plan) {
        int fallback = plan.fallbackAmountFen;
        if (profile == null) return formatFen(fallback);
        Object policy = profile.get("policy");
        if (policy instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> policyMap = (Map<String, Object>) policy;
            Object prices = policyMap.get("recharge_prices_fen");
            if (prices instanceof Map) {
                @SuppressWarnings("unchecked")
                Map<String, Object> priceMap = (Map<String, Object>) prices;
                int amount = intValue(priceMap.get(plan.rawValue));
                return formatFen(amount > 0 ? amount : fallback);
            }
        }
        return formatFen(fallback);
    }

    /** 刷新当前支付订单状态。 */
    public void refreshCurrentPaymentOrder() {
        if (paymentOrder == null) {
            refreshProfile();
            return;
        }
        statusMessage = "正在查询订单状态…";
        new Thread(() -> {
            String status = fetchPaymentStatus(paymentOrder.outTradeNo);
            Platform.runLater(() -> applyPaymentStatus(status, paymentOrder.outTradeNo));
        }, "ahatype-payment-check").start();
    }

    // ==================== 内部 ====================

    private String authenticate(String path, String phone, String password,
                                String successMessage, String fallbackError) {
        String p = phone == null ? "" : phone.trim();
        if (p.isEmpty() || password == null || password.isEmpty()) {
            return "请输入手机号和密码。";
        }
        statusMessage = "正在请求云端账号…";
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("phone", p);
            body.put("password", password);
            JsonNode object = request(path, "POST", body, false);
            JsonNode data = payloadData(object, fallbackError);
            String token = firstString(data, "access_token", "token");
            if (token.isEmpty()) throw new RuntimeException("云端未返回 access_token。");

            AhaTypeService.getInstance().patchCloudToken(token);
            seedLocalProfile(token, data, p);
            statusMessage = successMessage;
            loggedIn = true;
            new Thread(this::refreshProfile, "ahatype-refresh-profile").start();
            return null;
        } catch (Exception e) {
            statusMessage = "账号请求失败。";
            logger.error("[ahatype-login] 登录失败: {}", e.getMessage());
            return e.getMessage();
        }
    }

    @SuppressWarnings("unchecked")
    private void applyProfile(JsonNode data) {
        Map<String, Object> normalized = normalizedProfile(data);
        this.profile = normalized;
        loggedIn = true;
        AhaTypeService.getInstance().patchCloudToken(AhaTypeService.getInstance().getAccessToken());
        AhaTypeService.getInstance().setUserProfile(normalized);
    }

    @SuppressWarnings("unchecked")
    private void seedLocalProfile(String token, JsonNode authData, String phone) {
        Map<String, Object> profile = normalizedProfile(authData);
        String phoneValue = firstString(authData, "phone", "mobile", "username");
        profile.put("phone", phoneValue.isEmpty() ? phone : phoneValue);
        String userID = firstString(authData, "id", "user_id", "userId");
        if (!userID.isEmpty()) {
            profile.put("user_id", userID);
            profile.put("id", userID);
        }
        String validUntil = jwtExpirationString(token);
        if (validUntil != null) profile.put("token_valid_until", validUntil);
        for (String[] pair : new String[][]{
                {"limit_daily", "limitDaily"}, {"limit_weekly", "limitWeekly"}, {"limit_monthly", "limitMonthly"},
                {"used_daily", "usedDaily"}, {"used_weekly", "usedWeekly"}, {"used_monthly", "usedMonthly"}}) {
            profile.put(pair[0], firstInt(authData, pair[0], pair[1]));
        }
        this.profile = profile;
        AhaTypeService.getInstance().setUserProfile(profile);
    }

    private Map<String, Object> normalizedProfile(JsonNode raw) {
        Map<String, Object> profile = new LinkedHashMap<>();
        if (raw == null || !raw.isObject()) return profile;
        raw.fields().forEachRemaining(e -> profile.put(e.getKey(), nodeToValue(e.getValue())));
        // 别名归一
        String[][] aliases = {
                {"id", "userId"}, {"user_id", "userId"},
                {"token_valid_until", "tokenValidUntil"},
                {"limit_daily", "limitDaily"}, {"limit_weekly", "limitWeekly"}, {"limit_monthly", "limitMonthly"},
                {"used_daily", "usedDaily"}, {"used_weekly", "usedWeekly"}, {"used_monthly", "usedMonthly"}};
        for (String[] a : aliases) {
            if (profile.containsKey(a[1]) && !profile.containsKey(a[0])) {
                profile.put(a[0], profile.get(a[1]));
            }
        }
        return profile;
    }

    private Object nodeToValue(JsonNode n) {
        if (n == null || n.isNull()) return null;
        if (n.isInt() || n.isLong()) return n.asLong();
        if (n.isNumber()) return n.asDouble();
        if (n.isBoolean()) return n.asBoolean();
        return n.asText();
    }

    private JsonNode request(String path, String method, Map<String, Object> body, boolean authorized) throws Exception {
        String baseUrl = apiBase();
        String url = baseUrl + "/" + path;
        logger.info("[ahatype-request] method={} url={} baseUrl={} path={}", method, url, baseUrl, path);
        HttpRequest.Builder builder = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .timeout(Duration.ofSeconds(90))
                .header("Content-Type", "application/json");
        if (authorized) {
            String token = AhaTypeService.getInstance().getAccessToken();
            builder.header("Authorization", "Bearer " + token);
        }
        if ("POST".equalsIgnoreCase(method)) {
            String json = body == null ? "{}" : mapper.writeValueAsString(body);
            builder.POST(HttpRequest.BodyPublishers.ofString(json));
        } else {
            builder.GET();
        }
        HttpResponse<String> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
        int statusCode = response.statusCode();
        JsonNode object;
        try {
            object = mapper.readTree(response.body());
        } catch (Exception e) {
            throw new RuntimeException("服务器返回非 JSON。(HTTP " + statusCode + ")");
        }
        if (statusCode != 200) {
            String msg = responseMessage(object);
            throw new RuntimeException(msg.isEmpty() ? "请求失败(HTTP " + statusCode + ")。" : msg);
        }
        return object;
    }

    private JsonNode payloadData(JsonNode object, String fallbackError) throws Exception {
        int code = object.has("code") ? object.get("code").asInt() : 0;
        if (code != 0 && code != 200) {
            String msg = responseMessage(object);
            throw new RuntimeException(msg.isEmpty() ? fallbackError : msg);
        }
        JsonNode data = object.get("data");
        return (data != null && data.isObject()) ? data : mapper.createObjectNode();
    }

    private String apiBase() {
        for (String key : new String[]{"VIBE_TYPELESS_API_BASE", "VIBE_API_BASE"}) {
            String v = normalizeAPIBase(System.getenv(key));
            if (!v.isEmpty()) {
                logger.info("[ahatype-apiBase] 使用环境变量 {} = {}", key, v);
                return v;
            }
        }
        logger.info("[ahatype-apiBase] 未找到环境变量, 使用默认地址: {}", FALLBACK_API_BASE);
        return normalizeAPIBase(FALLBACK_API_BASE);
    }

    private String normalizeAPIBase(String raw) {
        if (raw == null) return "";
        String value = raw.trim();
        while (value.endsWith("/")) value = value.substring(0, value.length() - 1);
        if (!value.isEmpty() && !value.contains("://")) value = "https://" + value;
        return value;
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

    private String firstString(JsonNode node, String... keys) {
        if (node == null) return "";
        for (String key : keys) {
            JsonNode v = node.get(key);
            if (v != null && !v.isNull()) {
                String s = v.asText("").trim();
                if (!s.isEmpty()) return s;
            }
        }
        return "";
    }

    private int firstInt(JsonNode node, String... keys) {
        if (node == null) return 0;
        for (String key : keys) {
            JsonNode v = node.get(key);
            if (v != null && !v.isNull()) return v.asInt();
        }
        return 0;
    }

    /** 从 JWT token 解析过期时间(简单实现,取 payload 的 exp)。 */
    private String jwtExpirationString(String token) {
        try {
            String[] parts = token.split("\\.");
            if (parts.length < 2) return null;
            String payload = new String(java.util.Base64.getUrlDecoder().decode(parts[1]));
            JsonNode node = mapper.readTree(payload);
            JsonNode exp = node.get("exp");
            if (exp == null || exp.isNull()) return null;
            long epoch = exp.asLong();
            return java.time.Instant.ofEpochSecond(epoch)
                    .atZone(java.time.ZoneOffset.UTC)
                    .toLocalDateTime()
                    .format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        } catch (Exception e) {
            return null;
        }
    }

    // ==================== 支付轮询与工具 ====================

    private void pollPaymentStatus(String outTradeNo) {
        new Thread(() -> {
            long deadline = System.currentTimeMillis() + 180_000; // 3 分钟超时
            while (System.currentTimeMillis() < deadline) {
                try { Thread.sleep(2000); } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    return;
                }
                if (paymentOrder == null || !paymentOrder.outTradeNo.equals(outTradeNo)) return;
                String status = fetchPaymentStatus(outTradeNo);
                String normalized = normalizedPaymentStatusFromString(status);
                // 在 UI 线程更新订单状态
                Platform.runLater(() -> applyPaymentStatus(status, outTradeNo));
                // 支付完成/失败则结束轮询
                if ("success".equals(normalized) || "paid".equals(normalized) ||
                    "failed".equals(normalized) || "closed".equals(normalized)) {
                    return;
                }
            }
            Platform.runLater(() -> {
                if (paymentOrder != null && paymentOrder.outTradeNo.equals(outTradeNo)) {
                    statusMessage = "等待支付超时，可稍后刷新用户信息确认到账。";
                }
            });
        }, "ahatype-payment-poll").start();
    }

    private String normalizedPaymentStatus(JsonNode data) {
        String raw = firstString(data, "status", "trade_status", "state");
        return normalizedPaymentStatusFromString(raw);
    }

    private String normalizedPaymentStatusFromString(String raw) {
        if (raw == null || raw.isEmpty()) return "pending";
        String lower = raw.toLowerCase();
        if (lower.contains("success") || lower.contains("paid") || lower.contains("succeed")) return "success";
        if (lower.contains("fail") || lower.contains("closed") || lower.contains("cancelled")) return "failed";
        if (lower.contains("pending") || lower.contains("wait") || lower.contains("processing")) return "pending";
        return "pending";
    }

    private String formatFen(int fen) {
        return String.format("%.2f 元", Math.max(0, fen) / 100.0);
    }

private int intValue(Object value) {
        if (value == null) return 0;
        if (value instanceof Number) return ((Number) value).intValue();
        if (value instanceof String) {
            try { return Integer.parseInt(((String) value).trim()); } catch (NumberFormatException e) { return 0; }
        }
        return 0;
    }
}
