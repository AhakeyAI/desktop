package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Consumer;

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
    private final Duration paymentPollInterval;
    private final Duration paymentPollTimeout;
    private final ExecutorService paymentPollExecutor;
    private final AtomicLong paymentPollGeneration = new AtomicLong();
    private final Object stateMutationLock = new Object();
    private volatile boolean loggedIn;
    private volatile String statusMessage = "未登录";
    private volatile Map<String, Object> profile = Map.of();

    public record RechargePlan(String id, int amountFen) {
        public String displayText() {
            String title = switch (id) {
                case "monthly" -> "包月";
                case "quarterly" -> "包季";
                case "yearly" -> "包年";
                default -> id;
            };
            return String.format(Locale.ROOT, "%s  %.2f 元", title, amountFen / 100.0);
        }

        @Override
        public String toString() {
            return displayText();
        }
    }

    public record PaymentOrder(String outTradeNo, String paymentUrl,
                               int amountFen, String plan) {}

    public enum PaymentState { PENDING, PAID, FAILED }
    public enum PaymentPollOutcome { PAID, FAILED, TIMED_OUT }
    public record PaymentPollResult(String outTradeNo, PaymentPollOutcome outcome) {}

    public record QuotaLine(String period, int used, int limit) {}

    public CloudAccountManager() {
        this(AhaTypeService.getInstance(),
            HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build(),
            new ObjectMapper(), AhaTypeService.configuredApiBase(), Clock.systemUTC());
    }

    public CloudAccountManager(AhaTypeService ahaType, HttpClient httpClient,
                               ObjectMapper mapper, URI apiBase, Clock clock) {
        this(ahaType, httpClient, mapper, apiBase, clock,
            Duration.ofSeconds(2), Duration.ofMinutes(3));
    }

    CloudAccountManager(AhaTypeService ahaType, HttpClient httpClient,
                        ObjectMapper mapper, URI apiBase, Clock clock,
                        Duration paymentPollInterval, Duration paymentPollTimeout) {
        this.ahaType = ahaType;
        this.httpClient = httpClient;
        this.mapper = mapper;
        this.apiBase = normalizeApiBase(apiBase);
        this.clock = clock;
        this.paymentPollInterval = paymentPollInterval;
        this.paymentPollTimeout = paymentPollTimeout;
        this.paymentPollExecutor = Executors.newSingleThreadExecutor(runnable -> {
            Thread thread = new Thread(runnable, "ahatype-payment-poll");
            thread.setDaemon(true);
            return thread;
        });
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

    public Map<String, Object> getQuota() {
        return Collections.unmodifiableMap(ahaType.getQuota());
    }

    public Map<String, Object> getPolicy() {
        return Collections.unmodifiableMap(ahaType.getPolicy());
    }

    public String getTokenValidUntil() {
        return AhaTypeService.stringValue(ahaType.getTokenValidUntil());
    }

    public List<QuotaLine> getVisibleQuotaLines() {
        Map<String, Object> quota = ahaType.getQuota();
        Map<String, Object> policy = ahaType.getPolicy();
        boolean hasVisibility = policy.containsKey("enable_daily")
            || policy.containsKey("enable_weekly") || policy.containsKey("enable_monthly");
        List<QuotaLine> lines = new ArrayList<>();
        addQuotaLine(lines, "daily", quota, policy, hasVisibility);
        addQuotaLine(lines, "weekly", quota, policy, hasVisibility);
        addQuotaLine(lines, "monthly", quota, policy, hasVisibility);
        return List.copyOf(lines);
    }

    public List<RechargePlan> getRechargePlans() {
        Map<String, Object> prices = mapValue(ahaType.getPolicy().get("recharge_prices_fen"));
        List<RechargePlan> plans = new ArrayList<>();
        addRechargePlan(plans, prices, "monthly");
        addRechargePlan(plans, prices, "quarterly");
        addRechargePlan(plans, prices, "yearly");
        return List.copyOf(plans);
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

    public String logout() {
        synchronized (stateMutationLock) {
            if (!ahaType.clearSessionKeepToggle()) {
                statusMessage = "退出登录保存失败";
                return statusMessage;
            }
            profile = Map.of();
            loggedIn = false;
            statusMessage = "已退出登录";
            return null;
        }
    }

    /** Refresh the snake_case/camelCase profile and quota fields from the server. */
    public String refreshProfile() {
        String requestToken = ahaType.getValidAccessToken();
        if (requestToken.isEmpty()) {
            synchronized (stateMutationLock) {
                if (!ahaType.getValidAccessToken().isEmpty()) return null;
                loggedIn = false;
                statusMessage = "未登录或登录已过期";
                return statusMessage;
            }
        }
        try {
            JsonNode root = request("/api/v1/auth/users/me", "GET", null, requestToken);
            JsonNode data = dataObject(root);
            AccountPayload payload = accountPayload(data, requestToken);
            synchronized (stateMutationLock) {
                AhaTypeService.CloudStatePersistenceResult persistence =
                    ahaType.persistCloudStateIfTokenCurrent(requestToken, payload.user(),
                        payload.quota(), payload.policy(), payload.validUntil());
                if (persistence == AhaTypeService.CloudStatePersistenceResult.STALE_TOKEN) {
                    return null;
                }
                if (persistence == AhaTypeService.CloudStatePersistenceResult.FAILED) {
                    statusMessage = "账号刷新成功，但本地保存失败";
                    return statusMessage;
                }
                profile = Collections.unmodifiableMap(new LinkedHashMap<>(payload.user()));
                loggedIn = true;
                statusMessage = "已登录";
                return null;
            }
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            synchronized (stateMutationLock) {
                if (!requestToken.equals(ahaType.getAccessToken())) return null;
                statusMessage = "刷新账号已中断";
                return statusMessage;
            }
        } catch (CloudAccountException exception) {
            synchronized (stateMutationLock) {
                if (!requestToken.equals(ahaType.getAccessToken())) return null;
                if (exception.statusCode() == 401 || exception.statusCode() == 403) {
                    ahaType.clearSessionKeepToggle();
                    profile = Map.of();
                    loggedIn = false;
                    statusMessage = "登录已过期，请重新登录";
                } else {
                    statusMessage = exception.getMessage();
                }
                return statusMessage;
            }
        } catch (Exception exception) {
            synchronized (stateMutationLock) {
                if (!requestToken.equals(ahaType.getAccessToken())) return null;
                statusMessage = "刷新账号失败";
                logger.warn("Cloud profile refresh failed ({})", exception.getClass().getSimpleName());
                return statusMessage;
            }
        }
    }

    public String redeemCoupon(String code) {
        String normalized = code == null ? "" : code.trim();
        if (normalized.isEmpty()) return "请输入兑换码";
        String token = ahaType.getValidAccessToken();
        if (token.isEmpty()) return "请重新登录后再兑换";
        try {
            request("/api/v1/coupon/redeem", "POST", Map.of("code", normalized), token);
            String refreshError = refreshProfile();
            if (refreshError != null) return "兑换成功，但账号信息刷新失败";
            statusMessage = "兑换成功";
            return null;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return "兑换已中断";
        } catch (CloudAccountException exception) {
            return exception.getMessage();
        } catch (Exception exception) {
            logger.warn("Coupon redemption failed ({})", exception.getClass().getSimpleName());
            return "兑换失败，请稍后重试";
        }
    }

    public PaymentOrder createWechatOrder(String planId) throws CloudAccountException {
        String token = ahaType.getValidAccessToken();
        if (token.isEmpty()) throw new CloudAccountException(401, "请重新登录后再充值");
        RechargePlan selected = getRechargePlans().stream()
            .filter(plan -> plan.id().equals(planId)).findFirst()
            .orElseThrow(() -> new CloudAccountException(0, "请选择有效的充值套餐"));
        try {
            JsonNode data = dataObject(request("/api/v1/payment/wechat/native", "POST",
                Map.of("plan", selected.id()), token));
            String codeUrl = firstText(data, "code_url", "codeUrl");
            String h5Url = firstText(data, "h5_url", "h5Url", "mweb_url", "mwebUrl");
            String orderNo = firstText(data, "out_trade_no", "outTradeNo");
            if (orderNo.isEmpty()) throw new CloudAccountException(0, "云端未返回订单号");
            String paymentUrl = codeUrl.isEmpty() ? h5Url : codeUrl;
            if (paymentUrl.isEmpty()) throw new CloudAccountException(0, "云端未返回可支付链接");
            JsonNode amountNode = AhaTypeService.firstNode(data, "amount_fen");
            if (amountNode == null) amountNode = AhaTypeService.firstNode(data, "amountFen");
            int amount = amountNode == null ? selected.amountFen() : amountNode.asInt(selected.amountFen());
            return new PaymentOrder(orderNo, paymentUrl, amount, selected.id());
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new CloudAccountException(0, "创建支付订单已中断");
        } catch (CloudAccountException exception) {
            throw exception;
        } catch (Exception exception) {
            logger.warn("Payment order creation failed ({})", exception.getClass().getSimpleName());
            throw new CloudAccountException(0, "创建支付订单失败，请稍后重试");
        }
    }

    public PaymentState fetchPaymentState(String outTradeNo) throws CloudAccountException {
        String token = ahaType.getValidAccessToken();
        if (token.isEmpty()) throw new CloudAccountException(401, "登录已过期，请重新登录");
        try {
            String encoded = java.net.URLEncoder.encode(outTradeNo, StandardCharsets.UTF_8);
            JsonNode data = dataObject(request(
                "/api/v1/payment/wechat/order-status?outTradeNo=" + encoded,
                "GET", null, token));
            String status = firstText(data, "status", "tradeState", "trade_state",
                "payStatus", "pay_status", "orderStatus", "order_status")
                .toLowerCase(Locale.ROOT).replace('-', '_');
            if (isPaidStatus(status)) return PaymentState.PAID;
            if (isFailedStatus(status)) return PaymentState.FAILED;
            return PaymentState.PENDING;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new CloudAccountException(0, "订单状态查询已中断");
        } catch (CloudAccountException exception) {
            throw exception;
        } catch (Exception exception) {
            logger.warn("Payment status request failed ({})", exception.getClass().getSimpleName());
            throw new CloudAccountException(0, "订单状态查询失败");
        }
    }

    public void startPaymentPolling(PaymentOrder order, Consumer<PaymentPollResult> completion) {
        long generation = paymentPollGeneration.incrementAndGet();
        paymentPollExecutor.execute(() -> {
            long deadline = System.nanoTime() + paymentPollTimeout.toNanos();
            while (generation == paymentPollGeneration.get() && System.nanoTime() < deadline) {
                try {
                    TimeUnit.NANOSECONDS.sleep(paymentPollInterval.toNanos());
                    if (generation != paymentPollGeneration.get()) return;
                    PaymentState state = fetchPaymentState(order.outTradeNo());
                    if (state == PaymentState.PAID) {
                        refreshProfile();
                        completePaymentPoll(generation, completion,
                            new PaymentPollResult(order.outTradeNo(), PaymentPollOutcome.PAID));
                        return;
                    }
                    if (state == PaymentState.FAILED) {
                        completePaymentPoll(generation, completion,
                            new PaymentPollResult(order.outTradeNo(), PaymentPollOutcome.FAILED));
                        return;
                    }
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                    return;
                } catch (Exception ignored) {
                    // A transient poll failure does not cancel a still-payable order.
                }
            }
            completePaymentPoll(generation, completion,
                new PaymentPollResult(order.outTradeNo(), PaymentPollOutcome.TIMED_OUT));
        });
    }

    public void cancelPaymentPolling() {
        paymentPollGeneration.incrementAndGet();
    }

    private void completePaymentPoll(long generation, Consumer<PaymentPollResult> completion,
                                     PaymentPollResult result) {
        if (generation == paymentPollGeneration.get() && completion != null) {
            completion.accept(result);
        }
    }

    private String authenticate(String path, String phone, String password,
                                boolean rememberPassword, boolean requireToken) {
        String normalizedPhone = phone == null ? "" : phone.trim();
        if (normalizedPhone.isEmpty() || password == null || password.isEmpty()) {
            return "请输入手机号和密码";
        }
        try {
            JsonNode root = request(path, "POST", Map.of("phone", normalizedPhone, "password", password), null);
            JsonNode data = dataObject(root);
            String token = firstText(data, "access_token", "token");
            if (token.isEmpty()) token = firstText(root, "access_token", "token");
            if (requireToken && token.isEmpty()) {
                throw new IllegalStateException("账号响应缺少 token");
            }
            AccountPayload payload = accountPayload(data, token);
            Map<String, Object> localProfile = new LinkedHashMap<>(payload.user());
            localProfile.putIfAbsent("phone", normalizedPhone);
            boolean refreshAfterLogin;
            synchronized (stateMutationLock) {
                if (!ahaType.persistSession(token, payload.validUntil(), localProfile,
                    payload.quota(), payload.policy(), normalizedPhone, password,
                    rememberPassword)) {
                    statusMessage = requireToken ? "登录成功，但本地保存失败" : "注册成功，但本地保存失败";
                    return statusMessage;
                }
                profile = Collections.unmodifiableMap(new LinkedHashMap<>(localProfile));
                loggedIn = !token.isEmpty() && ahaType.hasValidToken();
                statusMessage = loggedIn ? "已登录" : "注册成功，请登录";
                refreshAfterLogin = loggedIn && localProfile.size() <= 1;
            }
            if (refreshAfterLogin) {
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

    private JsonNode request(String path, String method, Map<String, Object> payload, String authenticatedToken)
            throws Exception {
        HttpRequest.Builder builder = HttpRequest.newBuilder(endpoint(path))
            .timeout(Duration.ofSeconds(20))
            .header("Content-Type", "application/json; charset=utf-8");
        if (authenticatedToken != null) {
            if (authenticatedToken.isBlank()) throw new IllegalStateException("missing token");
            builder.header("Authorization", "Bearer " + authenticatedToken);
        }
        if ("GET".equals(method)) {
            builder.GET();
        } else {
            String body = mapper.writeValueAsString(payload == null ? Map.of() : payload);
            builder.method(method, HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8));
        }
        HttpResponse<String> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
        JsonNode root;
        try {
            root = mapper.readTree(response.body());
        } catch (Exception exception) {
            throw new CloudAccountException(response.statusCode(), "服务器返回异常");
        }
        if (response.statusCode() != 200 || root == null || !root.isObject()
            || !AhaTypeService.isSuccessCode(root.get("code"))) {
            throw new CloudAccountException(response.statusCode(), safeResponseMessage(root,
                response.statusCode() == 401 || response.statusCode() == 403
                    ? "登录已过期，请重新登录" : "请求失败"));
        }
        return root;
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

    private AccountPayload accountPayload(JsonNode data, String token) {
        return new AccountPayload(
            profileMap(profileNode(data)),
            quotaMap(data),
            policyMap(data),
            tokenValidUntil(data, token)
        );
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
        JsonNode user = data == null ? null : data.get("user");
        JsonNode quota = data == null ? null : data.get("quota");
        String value = firstText(data, "token_valid_until", "tokenValidUntil", "expires_at", "expiresAt");
        if (value.isEmpty()) {
            value = firstText(user, "token_valid_until", "tokenValidUntil", "expires_at", "expiresAt");
        }
        if (value.isEmpty()) {
            value = firstText(quota, "token_valid_until", "tokenValidUntil", "expires_at", "expiresAt");
        }
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

    private Map<String, Object> quotaMap(JsonNode data) {
        Map<String, Object> quota = new LinkedHashMap<>();
        JsonNode nested = data == null ? null : data.get("quota");
        for (String field : AhaTypeConfig.quotaFields()) {
            String camel = toCamelCase(field);
            JsonNode value = AhaTypeService.firstNode(data, field);
            if (value == null) value = AhaTypeService.firstNode(data, camel);
            if (value == null) value = AhaTypeService.firstNode(nested, field);
            if (value == null) value = AhaTypeService.firstNode(nested, camel);
            if (value != null && value.isValueNode()) {
                quota.put(field, mapper.convertValue(value, Object.class));
            }
        }
        return quota;
    }

    private Map<String, Object> policyMap(JsonNode data) {
        JsonNode node = data == null ? null : data.get("policy");
        if ((node == null || !node.isObject()) && profileNode(data) != null) {
            node = profileNode(data).get("policy");
        }
        Map<String, Object> policy = new LinkedHashMap<>();
        if (node != null && node.isObject()) {
            node.fields().forEachRemaining(entry ->
                policy.put(entry.getKey(), mapper.convertValue(entry.getValue(), Object.class)));
        }
        copyAlias(policy, "recharge_prices_fen", "rechargePricesFen");
        copyAlias(policy, "default_limit_daily", "defaultLimitDaily");
        copyAlias(policy, "default_limit_weekly", "defaultLimitWeekly");
        copyAlias(policy, "default_limit_monthly", "defaultLimitMonthly");
        copyAlias(policy, "enable_daily", "enableDaily");
        copyAlias(policy, "enable_weekly", "enableWeekly");
        copyAlias(policy, "enable_monthly", "enableMonthly");
        return policy;
    }

    private void addQuotaLine(List<QuotaLine> lines, String period,
                              Map<String, Object> quota, Map<String, Object> policy,
                              boolean hasVisibility) {
        if (hasVisibility && !AhaTypeService.boolValue(policy.get("enable_" + period))) return;
        lines.add(new QuotaLine(period,
            AhaTypeService.intValue(quota.get("used_" + period)),
            AhaTypeService.intValue(quota.get("limit_" + period))));
    }

    private static void addRechargePlan(List<RechargePlan> plans,
                                        Map<String, Object> prices, String id) {
        int amount = AhaTypeService.intValue(prices.get(id));
        if (amount > 0) plans.add(new RechargePlan(id, amount));
    }

    private static boolean isPaidStatus(String value) {
        return List.of("paid", "success", "succeeded", "complete", "completed",
            "pay_success", "trade_success", "wechat_success", "finished", "done", "1")
            .contains(value);
    }

    private static boolean isFailedStatus(String value) {
        return List.of("failed", "failure", "fail", "closed", "cancelled", "canceled",
            "expired", "timeout", "trade_closed", "pay_error", "2").contains(value);
    }

    private static String safeResponseMessage(JsonNode root, String fallback) {
        String message = firstText(root, "errorMsg", "msg", "message", "error")
            .replaceAll("[\\r\\n\\t]", " ").trim();
        if (message.isEmpty() || message.length() > 160
            || message.toLowerCase(Locale.ROOT).contains("token")
            || message.toLowerCase(Locale.ROOT).contains("password")) {
            return fallback;
        }
        return message;
    }

    private static Map<String, Object> mapValue(Object value) {
        Map<String, Object> result = new LinkedHashMap<>();
        if (value instanceof Map<?, ?> map) {
            map.forEach((key, item) -> result.put(String.valueOf(key), item));
        }
        return result;
    }

    private static void copyAlias(Map<String, Object> values, String snake, String camel) {
        if (!values.containsKey(snake) && values.containsKey(camel)) {
            values.put(snake, values.get(camel));
        }
    }

    private static String toCamelCase(String snake) {
        StringBuilder result = new StringBuilder();
        boolean upper = false;
        for (char character : snake.toCharArray()) {
            if (character == '_') upper = true;
            else {
                result.append(upper ? Character.toUpperCase(character) : character);
                upper = false;
            }
        }
        return result.toString();
    }

    private record AccountPayload(Map<String, Object> user, Map<String, Object> quota,
                                  Map<String, Object> policy, Object validUntil) {}

    public static final class CloudAccountException extends Exception {
        private final int statusCode;

        CloudAccountException(int statusCode, String message) {
            super(message);
            this.statusCode = statusCode;
        }

        public int statusCode() {
            return statusCode;
        }
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
