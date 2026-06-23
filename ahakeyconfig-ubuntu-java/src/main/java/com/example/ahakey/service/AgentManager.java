package com.example.ahakey.service;

import javafx.beans.property.BooleanProperty;
import javafx.beans.property.ObjectProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.beans.property.SimpleObjectProperty;
import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

/**
 * Hook 管理器 - 参考 Windows Python 版本设计。
 * 负责安装/管理各种 AI 应用的 Hook 文件。
 */
public class AgentManager {
    public enum BluetoothOwner {
        AHAKEY_STUDIO,
        KEYBOARD_DEVICE
    }

    private final ObjectProperty<BluetoothOwner> bluetoothOwner =
        new SimpleObjectProperty<>(BluetoothOwner.KEYBOARD_DEVICE);
    private final BooleanProperty installed = new SimpleBooleanProperty(true);
    private final BooleanProperty hooksInstalled = new SimpleBooleanProperty(false);
    private final BooleanProperty operationInProgress = new SimpleBooleanProperty(false);
    private final StringProperty userAlert = new SimpleStringProperty(null);

    public ObjectProperty<BluetoothOwner> bluetoothOwnerProperty() {
        return bluetoothOwner;
    }

    public BluetoothOwner getBluetoothOwner() {
        return bluetoothOwner.get();
    }

    public void setBluetoothOwner(BluetoothOwner owner) {
        bluetoothOwner.set(owner);
    }

    public boolean isEditingConfiguration() {
        return bluetoothOwner.get() == BluetoothOwner.AHAKEY_STUDIO;
    }

    public BooleanProperty installedProperty() {
        return installed;
    }

    public BooleanProperty hooksInstalledProperty() {
        return hooksInstalled;
    }

    public boolean shouldShowInstallStart() {
        return !installed.get() || !hooksInstalled.get();
    }

    public BooleanProperty operationInProgressProperty() {
        return operationInProgress;
    }

    public StringProperty userAlertProperty() {
        return userAlert;
    }

    public void installHooks() {
        operationInProgress.set(true);
        // TODO: 调用真实的 Hook 安装逻辑
        // 安装位置：
        // - Claude Hook → ~/.claude/
        // - Cursor Hook → ~/.cursor/
        // - Codex Hook → 相应配置目录
        // - Kimi Hook → 相应配置目录
        installed.set(true);
        hooksInstalled.set(true);
        operationInProgress.set(false);
        userAlert.set("Hooks 安装成功！AI 应用重启后生效。");
    }
}
