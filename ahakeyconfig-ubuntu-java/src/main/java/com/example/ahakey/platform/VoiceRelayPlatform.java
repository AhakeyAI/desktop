package com.example.ahakey.platform;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.VoicePreset;
import com.example.ahakey.platform.linux.LinuxVoiceRelayService;

import javafx.beans.property.BooleanProperty;
import javafx.beans.property.StringProperty;

import java.util.function.IntSupplier;
import java.util.function.Supplier;

/**
 * 跨平台语音桥门面
 * 根据操作系统自动选择对应的语音服务实现
 */
public final class VoiceRelayPlatform {

    private final VoiceRelayService service;
    private final boolean isLinux;
    
    // 内部引用，用于访问 Linux 特定方法
    private LinuxVoiceRelayService linuxService;

    public VoiceRelayPlatform() {
        String os = System.getProperty("os.name", "").toLowerCase();
        this.isLinux = os.contains("linux");
        
        if (isLinux) {
            linuxService = new LinuxVoiceRelayService();
            service = linuxService;
        } else if (os.contains("win")) {
            try {
                // 尝试加载 Windows 服务（用于跨平台场景）
                Class<?> winServiceClass = Class.forName("com.example.ahakey.platform.windows.WindowsVoiceRelayService");
                service = (VoiceRelayService) winServiceClass.getDeclaredConstructor().newInstance();
            } catch (Exception e) {
                throw new UnsupportedOperationException("Windows 服务未找到，请确保已添加 Windows 平台依赖", e);
            }
        } else {
            throw new UnsupportedOperationException("不支持的操作系统: " + os);
        }
    }
    
    /**
     * 设置语音键按下回调
     */
    public void setOnVoiceKeyDown(Runnable callback) {
        if (linuxService != null) {
            linuxService.setOnVoiceKeyDown(callback);
        }
    }
    
    /**
     * 设置语音键释放回调
     */
    public void setOnVoiceKeyUp(Runnable callback) {
        if (linuxService != null) {
            linuxService.setOnVoiceKeyUp(callback);
        }
    }
    
    /**
     * 设置模拟录音开始回调
     */
    public void setOnSimulateRecordStart(Runnable callback) {
        if (linuxService != null) {
            linuxService.setOnSimulateRecordStart(callback);
        }
    }
    
    /**
     * 设置模拟录音停止回调
     */
    public void setOnSimulateRecordStop(Runnable callback) {
        if (linuxService != null) {
            linuxService.setOnSimulateRecordStop(callback);
        }
    }
    
    /**
     * 获取讯飞语音快捷键
     */
    public String getVoiceShortcut() {
        if (linuxService != null) {
            return linuxService.getVoiceShortcut();
        }
        return "ctrl+alt+v";
    }
    
    /**
     * 设置讯飞语音快捷键
     */
    public void setVoiceShortcut(String shortcut) {
        if (linuxService != null) {
            linuxService.setVoiceShortcut(shortcut);
        }
    }
    
    /**
     * 处理来自 BLE 的语音键事件
     */
    public void handleVoiceKeyEvent(int hidCode, boolean isKeyDown) {
        if (linuxService != null) {
            linuxService.handleVoiceKeyEvent(hidCode, isKeyDown);
        }
    }

    public boolean isSupported() {
        return true;
    }

    public boolean isLinux() {
        return isLinux;
    }

    public boolean isWindows() {
        return !isLinux;
    }

    public void configure(Supplier<StudioState> studioState, IntSupplier workMode) {
        service.configure(studioState, workMode);
    }

    public void updateRoutes(StudioState state) {
        service.updateRoutes(state);
    }

    public void start() {
        service.start();
    }

    public void stop() {
        service.stop();
    }

    public void simulateVoiceKeyTap(ModeSlot mode) {
        service.simulateVoiceKeyTap(mode);
    }

    public void simulateVoiceKeyTap(ModeSlot mode, VoicePreset preset) {
        service.simulateVoiceKeyTap(mode, preset);
    }

    public void simulateKeyByHid(int hidCode) {
        service.simulateKeyByHid(hidCode);
    }

    public BooleanProperty listeningProperty() {
        return service.listeningProperty();
    }

    public StringProperty statusMessageProperty() {
        return service.statusMessageProperty();
    }

    public StringProperty activeRouteSummaryProperty() {
        return service.activeRouteSummaryProperty();
    }

    public StringProperty lastSimulateHintProperty() {
        return service.lastSimulateHintProperty();
    }
}
