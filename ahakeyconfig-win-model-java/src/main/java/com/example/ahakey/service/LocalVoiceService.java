package com.example.ahakey.service;

import java.util.function.Consumer;

/**
 * 本地语音服务抽象接口。
 *
 * <p>设计目的:让通用代码(<code>App.java</code> / <code>WindowsVoiceRelayService</code> 回调)能够以类型安全的方式
 * 引用"可选"的本地语音能力,而不必硬依赖具体实现类(<code>VoiceInputManager</code>)。
 *
 * <p>工作方式:
 * <ul>
 *   <li>通用代码用 <code>LocalVoiceService</code> 引用</li>
 *   <li>App.java 启动时用 <code>Class.forName</code> 探测 <code>VoiceInputManager</code> 是否存在
 *       (由 <code>with-local-model</code> Maven profile 决定 classpath 里有没有这个类)</li>
 *   <li>不存在:本地模型不可用,纯走 Win+H 系统语音</li>
 *   <li>存在:反射创建实例,转型为 <code>LocalVoiceService</code>,设置键盘钩子回调</li>
 * </ul>
 *
 * <p>实现类(<code>com.example.ahakey.service.VoiceInputManager</code>)在
 * <code>src/main/local-model/java/</code> 下,只在 <code>with-local-model</code> profile 激活时被编译。
 */
public interface LocalVoiceService {

    /** 初始化底层服务(加载模型、初始化音频设备等)。失败时抛异常。 */
    void initialize();

    /** 关闭并释放资源。 */
    void shutdown();

    /** 开始录音(由键盘钩子的 voiceKeyDown 回调触发)。 */
    void startRecording();

    /** 停止录音(由键盘钩子的 voiceKeyUp 回调触发)。 */
    void stopRecording();

    /**
     * 服务是否已"激活"(用户主动开启了本地识别开关)。
     * 未激活时按下语音键应降级到系统语音(Win+H)。
     */
    boolean isActivated();

    /** 是否正在录音。 */
    boolean isRecording();

    /** 本地模型是否可用(模型文件存在、依赖加载成功等)。 */
    boolean isEnabled();

    /**
     * 启动识别(全双工模式:同时回调 onFinal / onPartial)。
     *
     * @param onFinal    最终结果回调
     * @param onPartial  中间结果回调
     */
    void startVoiceInput(Consumer<String> onFinal, Consumer<String> onPartial);

    /** 停止识别(由 UI 按钮或外部事件触发)。 */
    void stopVoiceInput();

    /**
     * 设置状态变更回调(状态码:消息字符串)。
     * 用于更新 UI 状态指示灯/标签。
     */
    void setStatusCallback(Consumer<String> statusCallback);
}
