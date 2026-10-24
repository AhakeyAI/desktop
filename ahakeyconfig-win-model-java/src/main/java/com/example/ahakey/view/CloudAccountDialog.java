package com.example.ahakey.view;

import com.example.ahakey.service.AhaTypeService;
import com.example.ahakey.service.CloudAccountManager;
import com.example.ahakey.service.CloudPaymentOrder;
import com.example.ahakey.service.CloudRechargePlan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.WriterException;
import com.google.zxing.client.j2se.MatrixToImageWriter;
import com.google.zxing.qrcode.QRCodeWriter;
import javafx.application.Platform;
import javafx.embed.swing.SwingFXUtils;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.CheckBox;
import javafx.scene.control.Label;
import javafx.scene.control.PasswordField;
import javafx.scene.control.TextField;
import javafx.scene.image.Image;
import javafx.scene.image.ImageView;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.stage.Modality;
import javafx.stage.Stage;

import java.awt.Desktop;
import java.awt.image.BufferedImage;
import java.net.URI;
import java.util.Map;

/**
 * AhaType 云端账号登录弹窗。
 * 参考 macOS 版 AhaKeyStudioView 的"云端账号 · AhaType"面板。
 * 功能:登录/注册、记住密码、退出登录、刷新配额、充值订阅、兑换码。
 */
public class CloudAccountDialog {

    private static final Logger logger = LoggerFactory.getLogger(CloudAccountDialog.class);

    private final Stage stage;
    private final AhaTypeService ahaType = AhaTypeService.getInstance();
    private final CloudAccountManager account = CloudAccountManager.getInstance();

    private final VBox content = new VBox(12);
    private final Label statusLabel = new Label();
    private TextField phoneField;
    private PasswordField passwordField;
    private CheckBox rememberCheckBox;
    private Button loginButton;
    private Button registerButton;
    private Label paymentStatusLabel;

    public CloudAccountDialog(Stage owner) {
        stage = new Stage();
        stage.setTitle("云端账号 · AhaType");
        stage.initModality(Modality.APPLICATION_MODAL);
        if (owner != null) stage.initOwner(owner);
        stage.setResizable(false);
        try {
            stage.getIcons().add(new Image(getClass().getResourceAsStream("/ahakey.jpg")));
        } catch (Exception ignored) {
        }

        content.setPadding(new Insets(18));
        content.setStyle("-fx-background-color: #f5f5f5;");
        content.setPrefWidth(420);

        render();

        Scene scene = new Scene(content);
        stage.setScene(scene);
    }

    public void show() {
        stage.show();
        Platform.runLater(() -> {
            if (phoneField != null) phoneField.requestFocus();
        });
    }

    private void render() {
        content.getChildren().clear();

        Label title = new Label("云端账号 · AhaType");
        title.setStyle("-fx-font-size: 16px; -fx-font-weight: bold;");

        Button closeButton = new Button("关闭");
        closeButton.setOnAction(e -> stage.close());

        HBox header = new HBox(12, title, closeButton);
        header.setAlignment(Pos.CENTER_LEFT);

        content.getChildren().add(header);

        if (ahaType.hasValidToken()) {
            content.getChildren().add(profileSection());
        } else {
            content.getChildren().add(loginSection());
        }

        content.getChildren().add(ahaTypeSection());

        statusLabel.setStyle("-fx-text-fill: #666; -fx-font-size: 12px;");
        statusLabel.setWrapText(true);
        content.getChildren().add(statusLabel);

        stage.sizeToScene();
    }

    // ==================== 登录区 ====================

    private VBox loginSection() {
        VBox box = new VBox(10);
        box.setStyle("-fx-padding: 12; -fx-background-color: white; -fx-border-radius: 6; -fx-background-radius: 6;");

        Label tip = new Label("登录后可使用 AhaType 云端大模型整理。");
        tip.setStyle("-fx-text-fill: #666; -fx-font-size: 12px;");
        tip.setWrapText(true);

        phoneField = new TextField();
        phoneField.setPromptText("手机号");
        phoneField.setText(ahaType.getRememberedPhone());

        passwordField = new PasswordField();
        passwordField.setPromptText("密码");
        if (ahaType.isRememberPassword()) {
            passwordField.setText(ahaType.getRememberedPassword());
        }

        rememberCheckBox = new CheckBox("记住密码");
        rememberCheckBox.setSelected(ahaType.isRememberPassword());

        loginButton = new Button("登录");
        loginButton.setDefaultButton(true);
        loginButton.setOnAction(e -> doLogin());

        registerButton = new Button("注册");
        registerButton.setOnAction(e -> doRegister());

        HBox btnRow = new HBox(10, loginButton, registerButton);
        passwordField.setOnAction(e -> doLogin());

        box.getChildren().addAll(tip, phoneField, passwordField, rememberCheckBox, btnRow);
        return box;
    }

    // ==================== 个人信息区(已登录) ====================

    private VBox profileSection() {
        VBox box = new VBox(10);
        box.setStyle("-fx-padding: 12; -fx-background-color: white; -fx-border-radius: 6; -fx-background-radius: 6;");

        Map<String, Object> profile = account.getProfile();
        String phone = profile != null ? String.valueOf(profile.getOrDefault("phone", "")) : "";
        Label profileLabel = new Label("已登录: " + phone);
        profileLabel.setStyle("-fx-font-size: 13px;");

        String quota = ahaType.getQuotaSummary();
        Label quotaLabel = new Label("配额: " + quota);
        quotaLabel.setStyle("-fx-font-size: 12px; -fx-text-fill: #555;");
        quotaLabel.setWrapText(true);

        Button refreshBtn = new Button("刷新");
        refreshBtn.setOnAction(e -> {
            refreshBtn.setDisable(true);
            setStatus("正在刷新…");
            new Thread(() -> {
                String err = account.refreshProfile();
                Platform.runLater(() -> {
                    refreshBtn.setDisable(false);
                    if (err == null) {
                        setStatus("已刷新。");
                        render();
                    } else {
                        setStatus(err);
                    }
                });
            }, "ahatype-refresh").start();
        });

        Button switchBtn = new Button("切换账号");
        switchBtn.setOnAction(e -> {
            account.logout();
            render();
        });

        Button logoutBtn = new Button("退出登录");
        logoutBtn.setOnAction(e -> {
            account.logout();
            setStatus("已退出登录。");
            render();
        });

        HBox btnRow = new HBox(10, refreshBtn, switchBtn, logoutBtn);

        // 充值订阅区
        VBox rechargeBox = new VBox(8);
        rechargeBox.setStyle("-fx-padding: 10; -fx-background-color: #f8f9fb; -fx-border-radius: 6; -fx-background-radius: 6;");

        Label rechargeTitle = new Label("充值订阅");
        rechargeTitle.setStyle("-fx-font-size: 13px; -fx-font-weight: bold;");

        HBox planRow = new HBox(8);
        planRow.setAlignment(Pos.CENTER);
        for (CloudRechargePlan plan : CloudRechargePlan.values()) {
            VBox planCard = new VBox(3);
            planCard.setAlignment(Pos.CENTER);
            planCard.setStyle(
                "-fx-background-color: white; -fx-padding: 8 12; -fx-background-radius: 6; " +
                "-fx-border-radius: 6; -fx-border-color: #d8dde8; -fx-border-width: 1; -fx-cursor: hand;");
            planCard.setOnMouseEntered(e ->
                planCard.setStyle("-fx-background-color: white; -fx-padding: 8 12; -fx-background-radius: 6; " +
                    "-fx-border-radius: 6; -fx-border-color: #07C160; -fx-border-width: 1; -fx-cursor: hand;"));
            planCard.setOnMouseExited(e ->
                planCard.setStyle("-fx-background-color: white; -fx-padding: 8 12; -fx-background-radius: 6; " +
                    "-fx-border-radius: 6; -fx-border-color: #d8dde8; -fx-border-width: 1; -fx-cursor: hand;"));

            Label planTitle = new Label(plan.title);
            planTitle.setStyle("-fx-font-size: 12px; -fx-font-weight: bold;");
            Label planPrice = new Label(account.priceText(plan));
            planPrice.setStyle("-fx-font-size: 11px; -fx-text-fill: #555;");
            Label planSub = new Label(plan.subtitle);
            planSub.setStyle("-fx-font-size: 10px; -fx-text-fill: #999;");

            planCard.getChildren().addAll(planTitle, planPrice, planSub);
            planCard.setOnMouseClicked(e -> doCreateOrder(plan));
            planRow.getChildren().add(planCard);
        }
        rechargeBox.getChildren().addAll(rechargeTitle, planRow);

        // 订单状态（有支付中的订单时显示）
        CloudPaymentOrder order = account.getPaymentOrder();
        if (order != null) {
            VBox orderBox = new VBox(8);
            orderBox.setStyle("-fx-padding: 10; -fx-background-color: #fff; -fx-border-radius: 6; -fx-background-radius: 6; -fx-border-color: #e0e0e0; -fx-border-width: 1;");

            Label orderTitle = new Label(order.plan.title + " \u00b7 " + order.amountText());
            orderTitle.setStyle("-fx-font-size: 12px; -fx-font-weight: bold;");

            // 二维码
            ImageView qrView = new ImageView();
            qrView.setFitWidth(132);
            qrView.setFitHeight(132);
            try {
                QRCodeWriter qrWriter = new QRCodeWriter();
                BufferedImage qrImage = MatrixToImageWriter.toBufferedImage(
                    qrWriter.encode(order.paymentURL(), BarcodeFormat.QR_CODE, 264, 264));
                qrView.setImage(SwingFXUtils.toFXImage(qrImage, null));
            } catch (WriterException ignored) {
            }

            Label qrHint = new Label("微信扫码完成支付，支付成功后会自动刷新额度。");
            qrHint.setStyle("-fx-font-size: 11px; -fx-text-fill: #666;");

            // 支付状态
            paymentStatusLabel = new Label("状态: " + order.status);
            paymentStatusLabel.setStyle("-fx-font-size: 10px; -fx-text-fill: #999;");

            // 操作按钮
            HBox orderBtnRow = new HBox(8);
            Button copyBtn = new Button("复制支付链接");
            copyBtn.setOnAction(e -> {
                try {
                    Desktop.getDesktop().browse(new URI(order.paymentURL()));
                    setStatus("已打开支付链接。");
                } catch (Exception ex) {
                    setStatus("打开支付链接失败。");
                }
            });
            Button refreshOrderBtn = new Button("刷新到账");
            refreshOrderBtn.setOnAction(e -> {
                refreshOrderBtn.setDisable(true);
                setStatus("正在查询订单状态…");
                new Thread(() -> {
                    if (order != null) {
                        String status = account.fetchPaymentStatus(order.outTradeNo);
                        Platform.runLater(() -> {
                            refreshOrderBtn.setDisable(false);
                            boolean finished = account.applyPaymentStatus(status, order.outTradeNo);
                            if (finished) {
                                render();
                            } else {
                                paymentStatusLabel.setText("状态: " + status);
                                setStatus("等待支付中…");
                            }
                        });
                    }
                }, "ahatype-payment-check").start();
            });
            Button closeOrderBtn = new Button("关闭订单");
            closeOrderBtn.setOnAction(e -> {
                account.clearPaymentOrder();
                render();
            });

            orderBtnRow.getChildren().addAll(copyBtn, refreshOrderBtn, closeOrderBtn);

            HBox qrRow = new HBox(12, qrView, new VBox(6, qrHint, paymentStatusLabel, orderBtnRow));
            qrRow.setAlignment(Pos.CENTER_LEFT);

            orderBox.getChildren().addAll(orderTitle, qrRow);
            rechargeBox.getChildren().add(orderBox);
        }

        // 兑换码
        TextField couponField = new TextField();
        couponField.setPromptText("免费券兑换码");
        Button redeemBtn = new Button("兑换");
        redeemBtn.setOnAction(e -> {
            String code = couponField.getText().trim();
            redeemBtn.setDisable(true);
            setStatus("正在兑换…");
            new Thread(() -> {
                String err = account.redeemCoupon(code);
                Platform.runLater(() -> {
                    redeemBtn.setDisable(false);
                    if (err == null) {
                        couponField.clear();
                        setStatus("兑换成功。");
                        render();
                    } else {
                        setStatus(err);
                    }
                });
            }, "ahatype-redeem").start();
        });
        HBox couponRow = new HBox(8, couponField, redeemBtn);
        HBox.setHgrow(couponField, javafx.scene.layout.Priority.ALWAYS);

        box.getChildren().addAll(profileLabel, quotaLabel, btnRow, rechargeBox, couponRow);
        return box;
    }

    private void doCreateOrder(CloudRechargePlan plan) {
        setStatus("正在创建微信支付订单…");
        new Thread(() -> {
            String err = account.createWechatOrder(plan);
            Platform.runLater(() -> {
                if (err == null) {
                    setStatus("订单已创建，请使用微信扫码支付。");
                    render();
                } else {
                    setStatus(err);
                }
            });
        }, "ahatype-create-order").start();
    }

    // ==================== AhaType 开关区 ====================

    private VBox ahaTypeSection() {
        VBox box = new VBox(8);
        Label tip = new Label("开启后,本地语音转写完成后会先请求云端整理,再粘贴整理后的文本。未登录、过期或网络失败时自动回退原始转写。");
        tip.setStyle("-fx-text-fill: #666; -fx-font-size: 12px;");
        tip.setWrapText(true);

        String statusText = ahaType.isEnabled() ? "✓ 当前状态：已开启" : "○ 当前状态：已关闭";
        Label statusLabel = new Label(statusText);
        statusLabel.setStyle(ahaType.isEnabled()
            ? "-fx-text-fill: #28a745; -fx-font-size: 13px; -fx-font-weight: bold;"
            : "-fx-text-fill: #888; -fx-font-size: 13px;");
        Label hint = new Label("可在主界面工具栏上点击「开启 AhaType」/「关闭 AhaType」切换。");
        hint.setStyle("-fx-text-fill: #999; -fx-font-size: 11px;");

        box.getChildren().addAll(tip, statusLabel, hint);
        return box;
    }

    // ==================== 操作 ====================

    private void doLogin() {
        String phone = phoneField.getText().trim();
        String password = passwordField.getText();
        boolean remember = rememberCheckBox.isSelected();
        if (phone.isEmpty() || password.isEmpty()) {
            setStatus("请输入手机号和密码。");
            return;
        }
        ahaType.saveRememberedCredentials(phone, password, remember);

        loginButton.setDisable(true);
        registerButton.setDisable(true);
        setStatus("正在登录…");

        new Thread(() -> {
            logger.info("[ahatype-login] 开始登录, phone={}", phone);
            String err = account.login(phone, password);
            logger.info("[ahatype-login] 登录结果: {}", err == null ? "成功" : "失败 -> " + err);
            Platform.runLater(() -> {
                loginButton.setDisable(false);
                registerButton.setDisable(false);
                if (err == null) {
                    setStatus("登录成功。");
                    render();
                } else {
                    setStatus(err);
                }
            });
        }, "ahatype-login").start();
    }

    private void doRegister() {
        String phone = phoneField.getText().trim();
        String password = passwordField.getText();
        if (phone.isEmpty() || password.isEmpty()) {
            setStatus("请输入手机号和密码。");
            return;
        }
        ahaType.saveRememberedCredentials(phone, password, rememberCheckBox.isSelected());

        loginButton.setDisable(true);
        registerButton.setDisable(true);
        setStatus("正在注册…");

        new Thread(() -> {
            String err = account.register(phone, password);
            Platform.runLater(() -> {
                loginButton.setDisable(false);
                registerButton.setDisable(false);
                if (err == null) {
                    setStatus("注册成功,已自动登录。");
                    render();
                } else {
                    setStatus(err);
                }
            });
        }, "ahatype-register").start();
    }

    private void setStatus(String text) {
        statusLabel.setText(text);
    }
}