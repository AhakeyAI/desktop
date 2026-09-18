package com.example.ahakey.view;

import com.example.ahakey.service.AhaTypeService;
import com.example.ahakey.service.CloudAccountManager;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.CheckBox;
import javafx.scene.control.Label;
import javafx.scene.control.PasswordField;
import javafx.scene.control.TextField;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.stage.Stage;

import java.util.Map;

/** Small, real account action surface used by the TopBar cloud-account menu. */
public class CloudAccountDialog {
    private final Stage stage;
    private final CloudAccountManager account;
    private final AhaTypeService ahaType;
    private final Runnable stateChanged;
    private final VBox content = new VBox(10);
    private final Label statusLabel = new Label();
    private TextField phoneField;
    private PasswordField passwordField;
    private CheckBox rememberCheckBox;

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
        this.stage.setMinWidth(420);
        this.stage.setMinHeight(300);
    }

    public void show() {
        render();
        stage.show();
        stage.toFront();
    }

    private void render() {
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
        stage.setScene(new Scene(content));
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
        String phone = String.valueOf(profile.getOrDefault("phone", "已登录账号"));
        Label accountLabel = new Label(phone);
        Label quotaLabel = new Label("额度：" + ahaType.getQuotaSummary());
        Button refresh = new Button("刷新账号");
        refresh.setOnAction(event -> runAsync(account::refreshProfile));
        Button logout = new Button("退出登录");
        logout.setOnAction(event -> {
            account.logout();
            stateChanged.run();
            render();
        });
        section.getChildren().addAll(accountLabel, quotaLabel, new HBox(8, refresh, logout));
        return section;
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
