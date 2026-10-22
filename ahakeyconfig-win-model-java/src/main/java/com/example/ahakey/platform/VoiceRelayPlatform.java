package com.example.ahakey.platform;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.VoicePreset;
import com.example.ahakey.platform.windows.WindowsVoiceRelayService;
import com.example.ahakey.platform.windows.WindowsVoiceTyping;

import javafx.beans.property.BooleanProperty;
import javafx.beans.property.StringProperty;

import java.util.function.IntSupplier;
import java.util.function.Supplier;

/** 跨平台语音桥门面；当前 Windows 完整实现 Win+H。 */
public final class VoiceRelayPlatform {
    private final WindowsVoiceRelayService windows = WindowsVoiceRelayService.getInstance();

    public boolean isSupported() {
        return WindowsVoiceTyping.isWindows();
    }

    public void configure(Supplier<StudioState> studioState, IntSupplier workMode) {
        windows.configure(studioState, workMode);
    }

    public void updateRoutes(StudioState state) {
        windows.updateRoutes(state);
    }

    public void start() {
        windows.start();
    }

    public void stop() {
        windows.stop();
    }

    public void simulateVoiceKeyTap(ModeSlot mode) {
        windows.simulateVoiceKeyTap(mode);
    }
    
    public void simulateVoiceKeyTap(ModeSlot mode, VoicePreset preset) {
        windows.simulateVoiceKeyTap(mode, preset);
    }

    public void simulateKeyByHid(int hidCode) {
        windows.simulateKeyByHid(hidCode);
    }

    public BooleanProperty listeningProperty() {
        return windows.listeningProperty();
    }

    public StringProperty statusMessageProperty() {
        return windows.statusMessageProperty();
    }

    public StringProperty activeRouteSummaryProperty() {
        return windows.activeRouteSummaryProperty();
    }

    public StringProperty lastSimulateHintProperty() {
        return windows.lastSimulateHintProperty();
    }
}
