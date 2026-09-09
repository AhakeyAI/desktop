package com.example.ahakey.platform;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.VoicePreset;
import com.example.ahakey.platform.voice.VoiceAction;
import com.example.ahakey.platform.windows.WindowsVoiceRelayService;
import com.example.ahakey.platform.windows.WindowsVoiceTyping;

import javafx.beans.property.BooleanProperty;
import javafx.beans.property.StringProperty;

import java.util.function.IntSupplier;
import java.util.function.Supplier;

/** Cross-platform voice facade; Windows consumes physical F18 and routes actions. */
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

    public void configureVoiceActions(VoiceAction shortAction, VoiceAction longAction,
                                      int thresholdMs) {
        windows.configureVoiceActions(shortAction, longAction, thresholdMs);
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

    public void simulateMacro(KeyConfig config) { windows.simulateMacro(config); }

    public void pressKeyByHid(int hidCode) {
        windows.pressKeyByHid(hidCode);
    }

    public void releaseKeyByHid(int hidCode) {
        windows.releaseKeyByHid(hidCode);
    }

    public void releaseAllSimulatedKeys() {
        windows.releaseAllSimulatedKeys();
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
