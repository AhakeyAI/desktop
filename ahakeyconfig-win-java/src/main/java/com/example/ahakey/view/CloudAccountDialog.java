package com.example.ahakey.view;

import com.example.ahakey.service.AhaTypeService;
import com.example.ahakey.service.CloudAccountManager;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.CheckBox;
import javafx.scene.control.Alert;
import javafx.scene.control.ChoiceDialog;
import javafx.scene.control.Label;
import javafx.scene.control.PasswordField;
import javafx.scene.control.TextField;
import javafx.scene.control.TextInputDialog;
import javafx.scene.image.ImageView;
import javafx.scene.image.WritableImage;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.stage.Stage;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.qrcode.QRCodeWriter;

import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

/** Small, real account action surface used by the TopBar cloud-account menu. */
public class CloudAccountDialog {
    static final double INITIAL_WIDTH = 520;
    static final double INITIAL_HEIGHT = 400;
    static final double MIN_WIDTH = 500;
    static final double MIN_HEIGHT = 360;
    static final double ACCOUNT_ACTION_MIN_WIDTH = 90;

    private final Stage stage;
    private final CloudAccountManager account;
    private final AhaTypeService ahaType;
    private final Runnable stateChanged;
    private final VBox content = new VBox(10);
    private final Label statusLabel = new Label();
    private TextField phoneField;
    private PasswordField passwordField;
    private CheckBox rememberCheckBox;
    private final AtomicLong paymentGeneration = new AtomicLong();
    private Stage paymentStage;

    public CloudAccountDialog(Stage owner) {
        this(owner, CloudAccountManager.getInstance(), AhaTypeService.getInstance(), () -> { });
    }

    public CloudAccountDialog(Stage owner, CloudAccountManager account, Runnable stateChanged) {
        this(owner, account, AhaTypeService.getInstance(), stateChanged);
    }

    CloudAccountDialog(Stage owner, CloudAccountManager account, AhaTypeService ahaType,
                       Runnable stateChanged) {
        this.stage = new Stage();
        if (owner != null) {
            this.stage.initOwner(owner);
        }
        this.account = account;
        this.ahaType = ahaType;
        this.stateChanged = stateChanged == null ? () -> { } : stateChanged;
        this.stage.setTitle("云端账号 · AhaType");
        this.stage.setMinWidth(MIN_WIDTH);
        this.stage.setMinHeight(MIN_HEIGHT);
        this.stage.setWidth(INITIAL_WIDTH);
        this.stage.setHeight(INITIAL_HEIGHT);
        this.stage.setOnHidden(event -> {
            paymentGeneration.incrementAndGet();
            account.cancelPaymentPolling();
            if (paymentStage != null) {
                paymentStage.close();
                paymentStage = null;
            }
        });
    }

    public void show() {
        render();
        stage.show();
        stage.toFront();
    }

    private void render() {
        boolean preserveSize = stage.isShowing();
        double renderedWidth = renderDimension(stage.getWidth(), preserveSize, INITIAL_WIDTH);
        double renderedHeight = renderDimension(stage.getHeight(), preserveSize, INITIAL_HEIGHT);
        content.getChildren().clear();
        content.setPadding(new Insets(18));
        Label title = new Label("AhaType 云端账号");
        title.getStyleClass().add("section-title");
        content.getChildren().add(title);
        if (account.isLoggedIn()) {
            content.getChildren().add(profileSection());
        } else {
            content.getChildren().add(loginSection());
        }
        statusLabel.setText(account.getStatusMessage());
        content.getChildren().add(statusLabel);
        if (stage.getScene() == null) {
            stage.setScene(new Scene(content));
        }
        stage.setWidth(renderedWidth);
        stage.setHeight(renderedHeight);
    }

    static double renderDimension(double current, boolean preserveSize, double initial) {
        return preserveSize && Double.isFinite(current) && current > 0
            ? current : initial;
    }

    private VBox loginSection() {
        VBox section = new VBox(8);
        phoneField = new TextField(account.rememberedPhone());
        phoneField.setPromptText("手机号");
        passwordField = new PasswordField();
        passwordField.setText(account.rememberPassword() ? account.rememberedPassword() : "");
        passwordField.setPromptText("密码");
        rememberCheckBox = new CheckBox("记住密码");
        rememberCheckBox.setSelected(account.rememberPassword());
        Button login = new Button("登录");
        Button register = new Button("注册");
        login.setOnAction(event -> submit(false));
        register.setOnAction(event -> submit(true));
        section.getChildren().addAll(phoneField, passwordField, rememberCheckBox,
            new HBox(8, login, register));
        return section;
    }

    private VBox profileSection() {
        VBox section = new VBox(8);
        Map<String, Object> profile = account.getProfile();
        String phone = String.valueOf(profile.getOrDefault("phone", account.rememberedPhone()));
        Label accountLabel = new Label("手机号：" + (phone.isBlank() ? "未提供" : phone));
        String validUntil = account.getTokenValidUntil();
        Label validUntilLabel = new Label("有效期：" + (validUntil.isBlank() ? "无" : validUntil));
        VBox quotaBox = new VBox(4);
        for (CloudAccountManager.QuotaLine line : account.getVisibleQuotaLines()) {
            String title = switch (line.period()) {
                case "daily" -> "每日额度";
                case "weekly" -> "每周额度";
                default -> "每月额度";
            };
            String value = line.limit() <= 0
                ? "已用 " + line.used() + " · 无上限"
                : line.used() + " / " + line.limit();
            quotaBox.getChildren().add(new Label(title + "：" + value));
        }
        Button refresh = new Button("刷新账号");
        refresh.setMinWidth(ACCOUNT_ACTION_MIN_WIDTH);
        refresh.setOnAction(event -> runAsync(account::refreshProfile));
        Button recharge = new Button("微信充值");
        recharge.setMinWidth(ACCOUNT_ACTION_MIN_WIDTH);
        recharge.setOnAction(event -> chooseRechargePlan());
        Button coupon = new Button("兑换码");
        coupon.setMinWidth(ACCOUNT_ACTION_MIN_WIDTH);
        coupon.setOnAction(event -> redeemCoupon());
        Button logout = new Button("退出登录");
        logout.setMinWidth(ACCOUNT_ACTION_MIN_WIDTH);
        logout.setOnAction(event -> {
            String error = account.logout();
            if (error == null) {
                stateChanged.run();
                render();
            } else {
                setStatus(error);
            }
        });
        Label refreshHint = new Label("点击“刷新账号”，确认额度和套餐加载。");
        section.getChildren().addAll(accountLabel, validUntilLabel, quotaBox,
            new HBox(8, refresh, recharge, coupon, logout), refreshHint);
        return section;
    }

    private void chooseRechargePlan() {
        List<CloudAccountManager.RechargePlan> plans = account.getRechargePlans();
        if (plans.isEmpty()) {
            setStatus("服务端未下发可用的充值套餐");
            return;
        }
        ChoiceDialog<CloudAccountManager.RechargePlan> dialog =
            new ChoiceDialog<>(plans.get(0), plans);
        dialog.initOwner(stage);
        dialog.setTitle("微信充值");
        dialog.setHeaderText("请选择充值套餐");
        dialog.setContentText("套餐：");
        dialog.showAndWait().ifPresent(this::createPaymentOrder);
    }

    private void createPaymentOrder(CloudAccountManager.RechargePlan plan) {
        long generation = paymentGeneration.incrementAndGet();
        account.cancelPaymentPolling();
        if (paymentStage != null) {
            paymentStage.close();
            paymentStage = null;
        }
        setStatus("正在创建微信支付订单…");
        Thread request = new Thread(() -> {
            try {
                CloudAccountManager.PaymentOrder order = account.createWechatOrder(plan.id());
                Platform.runLater(() -> {
                    if (paymentGeneration.get() == generation) {
                        showPaymentOrder(order, generation);
                    }
                });
            } catch (CloudAccountManager.CloudAccountException exception) {
                Platform.runLater(() -> {
                    if (paymentGeneration.get() == generation) {
                        setStatus(exception.getMessage());
                    }
                });
            }
        }, "ahatype-payment-create");
        request.setDaemon(true);
        request.start();
    }

    private void showPaymentOrder(CloudAccountManager.PaymentOrder order, long generation) {
        paymentStage = new Stage();
        paymentStage.initOwner(stage);
        paymentStage.setTitle("微信扫码支付");
        Label tip = new Label(String.format(java.util.Locale.ROOT,
            "请使用微信扫码支付 %.2f 元", order.amountFen() / 100.0));
        ImageView qr = new ImageView(createQrImage(order.paymentUrl(), 260));
        Button close = new Button("关闭");
        close.setOnAction(event -> paymentStage.close());
        VBox box = new VBox(12, tip, qr, close);
        box.setPadding(new Insets(18));
        paymentStage.setScene(new Scene(box));
        paymentStage.setOnHidden(event -> {
            if (paymentGeneration.compareAndSet(generation, generation + 1)) {
                account.cancelPaymentPolling();
            }
            paymentStage = null;
        });
        paymentStage.show();
        account.startPaymentPolling(order, result -> Platform.runLater(() -> {
            if (paymentGeneration.get() != generation
                || !result.outTradeNo().equals(order.outTradeNo())) return;
            paymentGeneration.incrementAndGet();
            paymentStage.close();
            String message = switch (result.outcome()) {
                case PAID -> "充值成功，账号额度已刷新。";
                case FAILED -> "订单支付失败，请重新发起充值。";
                case TIMED_OUT -> "等待支付超时，请检查微信支付状态后重试。";
            };
            Alert.AlertType type = result.outcome() == CloudAccountManager.PaymentPollOutcome.PAID
                ? Alert.AlertType.INFORMATION : Alert.AlertType.WARNING;
            Alert alert = new Alert(type, message);
            alert.initOwner(stage);
            alert.setHeaderText(null);
            alert.showAndWait();
            stateChanged.run();
            render();
        }));
    }

    private void redeemCoupon() {
        TextInputDialog dialog = new TextInputDialog();
        dialog.initOwner(stage);
        dialog.setTitle("兑换码");
        dialog.setHeaderText("输入兑换码");
        dialog.setContentText("兑换码：");
        dialog.showAndWait().ifPresent(code -> runAsync(() -> account.redeemCoupon(code)));
    }

    static WritableImage createQrImage(String value, int size) {
        try {
            var matrix = new QRCodeWriter().encode(value, BarcodeFormat.QR_CODE, size, size);
            WritableImage image = new WritableImage(size, size);
            var writer = image.getPixelWriter();
            for (int y = 0; y < size; y++) {
                for (int x = 0; x < size; x++) {
                    writer.setArgb(x, y, matrix.get(x, y) ? 0xFF000000 : 0xFFFFFFFF);
                }
            }
            return image;
        } catch (Exception exception) {
            throw new IllegalStateException("无法生成支付二维码", exception);
        }
    }

    private void submit(boolean register) {
        String phone = phoneField.getText();
        String password = passwordField.getText();
        boolean remember = rememberCheckBox.isSelected();
        setStatus("请求中…");
        new Thread(() -> {
            String error = register
                ? account.register(phone, password, remember)
                : account.login(phone, password, remember);
            Platform.runLater(() -> {
                if (error == null && account.isLoggedIn()) {
                    stateChanged.run();
                    render();
                } else {
                    setStatus(error == null ? account.getStatusMessage() : error);
                }
            });
        }, "ahatype-account-request").start();
    }

    private void runAsync(java.util.function.Supplier<String> action) {
        setStatus("请求中…");
        new Thread(() -> {
            String result = action.get();
            Platform.runLater(() -> {
                setStatus(result == null ? account.getStatusMessage() : result);
                stateChanged.run();
                render();
            });
        }, "ahatype-account-refresh").start();
    }

    private void setStatus(String text) {
        statusLabel.setText(text == null ? "" : text);
    }
}
