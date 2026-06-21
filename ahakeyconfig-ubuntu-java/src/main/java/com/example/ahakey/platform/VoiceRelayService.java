package com.example.ahakey.platform;

import javafx.beans.property.BooleanProperty;
import javafx.beans.property.StringProperty;

import java.util.function.IntSupplier;
import java.util.function.Supplier;

/**
 * 语音中继服务接口
 * 定义跨平台语音服务的标准接口
 */
public interface VoiceRelayService {

    /**
     * 初始化服务
     */
    void initialize();

    /**
     * 启动服务
     */
    void start();

    /**
     * 停止服务
     */
    void stop();

    /**
     * 配置服务
     */
    void configure(Supplier<?> studioState, IntSupplier workMode);

    /**
     * 更新路由配置
     */
    void updateRoutes(Object state);

    /**
     * 模拟语音按键点击
     */
    void simulateVoiceKeyTap(Object mode);

    /**
     * 模拟语音按键点击（带预设）
     */
    void simulateVoiceKeyTap(Object mode, Object preset);

    /**
     * 通过 HID 模拟按键
     */
    void simulateKeyByHid(int hidCode);

    /**
     * 获取监听状态属性
     */
    BooleanProperty listeningProperty();

    /**
     * 获取状态消息属性
     */
    StringProperty statusMessageProperty();

    /**
     * 获取活动路由摘要属性
     */
    StringProperty activeRouteSummaryProperty();

    /**
     * 获取最后模拟提示属性
     */
    StringProperty lastSimulateHintProperty();
}
