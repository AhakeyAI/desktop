package com.example.ahakey.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CloudAccountFlowTest {
    @TempDir
    Path tempDir;

    @Test
    void preservesUserQuotaPolicyAndExpiryAcrossSnakeAndCamelCase() throws Exception {
        HttpServer server = server();
        try {
            server.createContext("/prod-api/api/v1/auth/login", exchange -> respond(exchange, 200,
                "{\"code\":0,\"data\":{\"access_token\":\"token-A\"," +
                    "\"tokenValidUntil\":\"2031-01-01T00:00:00Z\"," +
                    "\"user\":{\"userId\":\"u1\",\"phone\":\"13800000000\"}," +
                    "\"quota\":{\"limitDaily\":10,\"usedDaily\":2," +
                    "\"limitWeekly\":50,\"usedWeekly\":4," +
                    "\"limitMonthly\":200,\"usedMonthly\":9}," +
                    "\"policy\":{\"enableDaily\":true,\"enableWeekly\":false," +
                    "\"enableMonthly\":true,\"rechargePricesFen\":{" +
                    "\"monthly\":990,\"quarterly\":2490,\"yearly\":8990}}}}"));
            server.start();
            CloudAccountManager manager = manager(server, "account-fields.json",
                Duration.ofMillis(10), Duration.ofMillis(100));

            assertNull(manager.login("13800000000", "password", false));
            assertEquals("u1", manager.getProfile().get("user_id"));
            assertEquals(10, ((Number) manager.getQuota().get("limit_daily")).intValue());
            assertEquals(9, ((Number) manager.getQuota().get("used_monthly")).intValue());
            assertEquals(true, manager.getPolicy().get("enable_daily"));
            assertEquals(false, manager.getPolicy().get("enable_weekly"));
            assertEquals("2031-01-01T00:00:00Z", manager.getTokenValidUntil());
            assertEquals(2, manager.getVisibleQuotaLines().size());
            assertEquals(3, manager.getRechargePlans().size());
            assertTrue(manager.isLoggedIn());
        } finally {
            server.stop(0);
        }
    }

    @Test
    void registrationTokenAutoLogsInAndExpiredRefreshClearsTheSession() throws Exception {
        AtomicInteger profileCalls = new AtomicInteger();
        HttpServer server = server();
        try {
            server.createContext("/prod-api/api/v1/auth/register", exchange -> respond(exchange, 200,
                "{\"code\":0,\"data\":{\"token\":\"registered-token\"," +
                    "\"token_valid_until\":\"2031-01-01T00:00:00Z\"," +
                    "\"user\":{\"user_id\":\"new-user\"}}}"));
            server.createContext("/prod-api/api/v1/auth/users/me", exchange -> {
                profileCalls.incrementAndGet();
                respond(exchange, 401, "{\"code\":401,\"message\":\"expired\"}");
            });
            server.start();
            CloudAccountManager manager = manager(server, "registration.json",
                Duration.ofMillis(10), Duration.ofMillis(100));

            assertNull(manager.register("13800000000", "password", true));
            assertTrue(manager.isLoggedIn());
            assertEquals("new-user", manager.getProfile().get("user_id"));
            assertTrue(manager.refreshProfile().contains("重新登录"));
            assertFalse(manager.isLoggedIn());
            assertEquals(1, profileCalls.get());
        } finally {
            server.stop(0);
        }
    }

    @Test
    void createsWechatOrderPollsAllTerminalStatesAndCancelsOldOrder() throws Exception {
        AtomicReference<String> createBody = new AtomicReference<>();
        AtomicInteger paidRefreshes = new AtomicInteger();
        HttpServer server = server();
        try {
            server.createContext("/prod-api/api/v1/payment/wechat/native", exchange -> {
                createBody.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
                respond(exchange, 200, "{\"code\":0,\"data\":{" +
                    "\"out_trade_no\":\"paid-order\",\"code_url\":\"weixin://pay/test\"," +
                    "\"amount_fen\":990}}" );
            });
            server.createContext("/prod-api/api/v1/payment/wechat/order-status", exchange -> {
                String query = exchange.getRequestURI().getQuery();
                String status = query.contains("paid-order") ? "SUCCESS"
                    : query.contains("failed-order") ? "CLOSED" : "NOTPAY";
                respond(exchange, 200, "{\"code\":0,\"data\":{\"status\":\"" + status + "\"}}" );
            });
            server.createContext("/prod-api/api/v1/auth/users/me", exchange -> {
                paidRefreshes.incrementAndGet();
                respond(exchange, 200, profileResponse(7));
            });
            server.start();
            CloudAccountManager manager = loggedInManager(server, "payments.json",
                Duration.ofMillis(10), Duration.ofMillis(70));

            CloudAccountManager.PaymentOrder created = manager.createWechatOrder("monthly");
            assertEquals("paid-order", created.outTradeNo());
            assertEquals("weixin://pay/test", created.paymentUrl());
            assertEquals(990, created.amountFen());
            assertTrue(createBody.get().contains("\"plan\":\"monthly\""));

            CountDownLatch paid = new CountDownLatch(1);
            AtomicReference<CloudAccountManager.PaymentPollResult> paidResult = new AtomicReference<>();
            manager.startPaymentPolling(created, result -> {
                paidResult.set(result);
                paid.countDown();
            });
            assertTrue(paid.await(1, TimeUnit.SECONDS));
            assertEquals(CloudAccountManager.PaymentPollOutcome.PAID, paidResult.get().outcome());
            assertEquals(1, paidRefreshes.get());

            CountDownLatch failed = new CountDownLatch(1);
            AtomicReference<CloudAccountManager.PaymentPollResult> failedResult = new AtomicReference<>();
            manager.startPaymentPolling(new CloudAccountManager.PaymentOrder(
                "failed-order", "x", 1, "monthly"), result -> {
                    failedResult.set(result);
                    failed.countDown();
                });
            assertTrue(failed.await(1, TimeUnit.SECONDS));
            assertEquals(CloudAccountManager.PaymentPollOutcome.FAILED, failedResult.get().outcome());

            AtomicInteger cancelledCallbacks = new AtomicInteger();
            manager.startPaymentPolling(new CloudAccountManager.PaymentOrder(
                "pending-order", "x", 1, "monthly"), result -> cancelledCallbacks.incrementAndGet());
            manager.cancelPaymentPolling();
            Thread.sleep(120);
            assertEquals(0, cancelledCallbacks.get());

            CountDownLatch timeout = new CountDownLatch(1);
            AtomicReference<CloudAccountManager.PaymentPollResult> timeoutResult = new AtomicReference<>();
            manager.startPaymentPolling(new CloudAccountManager.PaymentOrder(
                "pending-order", "x", 1, "monthly"), result -> {
                    timeoutResult.set(result);
                    timeout.countDown();
                });
            assertTrue(timeout.await(1, TimeUnit.SECONDS));
            assertEquals(CloudAccountManager.PaymentPollOutcome.TIMED_OUT,
                timeoutResult.get().outcome());
        } finally {
            server.stop(0);
        }
    }

    @Test
    void couponRedeemSendsOnlyTheCodeThenRefreshesQuota() throws Exception {
        AtomicReference<String> couponBody = new AtomicReference<>();
        HttpServer server = server();
        try {
            server.createContext("/prod-api/api/v1/coupon/redeem", exchange -> {
                couponBody.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
                respond(exchange, 200, "{\"code\":0,\"data\":{}}" );
            });
            server.createContext("/prod-api/api/v1/auth/users/me",
                exchange -> respond(exchange, 200, profileResponse(11)));
            server.start();
            CloudAccountManager manager = loggedInManager(server, "coupon.json",
                Duration.ofMillis(10), Duration.ofMillis(100));

            assertNull(manager.redeemCoupon("  ABC-123  "));
            assertEquals("{\"code\":\"ABC-123\"}", couponBody.get());
            assertEquals(11, ((Number) manager.getQuota().get("used_monthly")).intValue());
        } finally {
            server.stop(0);
        }
    }

    private CloudAccountManager manager(HttpServer server, String file, Duration interval,
                                        Duration timeout) {
        AhaTypeService service = new AhaTypeService(
            new AhaTypeConfig(tempDir.resolve(file)), HttpClient.newHttpClient(),
            URI.create(baseUrl(server) + "/prod-api"), fixedClock());
        return new TestCloudAccountManager(service, HttpClient.newHttpClient(),
            new ObjectMapper(), URI.create(baseUrl(server) + "/prod-api"), fixedClock(),
            interval, timeout);
    }

    private CloudAccountManager loggedInManager(HttpServer server, String file,
                                                Duration interval, Duration timeout)
            throws Exception {
        AhaTypeConfig config = new AhaTypeConfig(tempDir.resolve(file));
        Map<String, Object> values = AhaTypeConfig.defaults();
        values.put(AhaTypeConfig.ACCESS_TOKEN, "test-token");
        values.put(AhaTypeConfig.TOKEN_VALID_UNTIL, "2031-01-01T00:00:00Z");
        values.put(AhaTypeConfig.USER, Map.of("user_id", "u1"));
        values.put(AhaTypeConfig.POLICY, Map.of(
            "recharge_prices_fen", Map.of("monthly", 990)));
        config.save(values);
        AhaTypeService service = new AhaTypeService(config, HttpClient.newHttpClient(),
            URI.create(baseUrl(server) + "/prod-api"), fixedClock());
        return new TestCloudAccountManager(service, HttpClient.newHttpClient(),
            new ObjectMapper(), URI.create(baseUrl(server) + "/prod-api"), fixedClock(),
            interval, timeout);
    }

    private static String profileResponse(int usedMonthly) {
        return "{\"code\":0,\"data\":{\"user\":{\"user_id\":\"u1\"}," +
            "\"quota\":{\"limit_monthly\":100,\"used_monthly\":" + usedMonthly + "}," +
            "\"policy\":{\"enable_monthly\":true,\"recharge_prices_fen\":{\"monthly\":990}}," +
            "\"token_valid_until\":\"2031-01-01T00:00:00Z\"}}";
    }

    private static HttpServer server() throws IOException {
        return HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    }

    private static String baseUrl(HttpServer server) {
        return "http://127.0.0.1:" + server.getAddress().getPort();
    }

    private static Clock fixedClock() {
        return Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC);
    }

    private static void respond(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(status, bytes.length);
        try (var output = exchange.getResponseBody()) {
            output.write(bytes);
        }
    }

    private static final class TestCloudAccountManager extends CloudAccountManager {
        TestCloudAccountManager(AhaTypeService service, HttpClient client, ObjectMapper mapper,
                                URI apiBase, Clock clock, Duration interval, Duration timeout) {
            super(service, client, mapper, apiBase, clock, interval, timeout);
        }
    }
}
