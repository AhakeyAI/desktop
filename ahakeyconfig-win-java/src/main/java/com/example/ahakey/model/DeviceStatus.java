package com.example.ahakey.model;

import com.example.ahakey.util.LanguageManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javafx.beans.property.*;

public class DeviceStatus {
    private final IntegerProperty factorySleepMinutes=new SimpleIntegerProperty(-1);
    public IntegerProperty factorySleepMinutesProperty(){return factorySleepMinutes;}
    public void setFactorySleepMinutes(int minutes){factorySleepMinutes.set(minutes);}
    public enum IdentityState { DISCONNECTED, UNKNOWN, READING, SUPPORTED, UNSUPPORTED, FAILED }
    private final ObjectProperty<IdentityState> identityState = new SimpleObjectProperty<>(IdentityState.DISCONNECTED);
    public IdentityState getIdentityState() { return identityState.get(); }
    public ObjectProperty<IdentityState> identityStateProperty() { return identityState; }
    public void setIdentityState(IdentityState value) { identityState.set(value); }
    
    private static final Logger logger = LoggerFactory.getLogger(DeviceStatus.class);
    private final BooleanProperty isConnected = new SimpleBooleanProperty(false);
    private final BooleanProperty isScanning = new SimpleBooleanProperty(false);
    private final IntegerProperty batteryLevel = new SimpleIntegerProperty(-1);
    private final IntegerProperty signal = new SimpleIntegerProperty(-1);
    private final IntegerProperty firmwareMain = new SimpleIntegerProperty(-1);
    private final IntegerProperty firmwareSub = new SimpleIntegerProperty(-1);
    private final IntegerProperty workMode = new SimpleIntegerProperty(0);
    private final IntegerProperty lightMode = new SimpleIntegerProperty(0);
    private final IntegerProperty lightBrightness = new SimpleIntegerProperty(35);
    private final IntegerProperty switchState = new SimpleIntegerProperty(-1);
    private final StringProperty deviceName = new SimpleStringProperty("");
    private final StringProperty firmwareCatalogKey = new SimpleStringProperty("");
    
    // Getters
    public boolean isConnected() { return isConnected.get(); }
    public boolean isScanning() { return isScanning.get(); }
    public int getBatteryLevel() { return batteryLevel.get(); }
    public int getSignal() { return signal.get(); }
    public int getFirmwareMain() { return firmwareMain.get(); }
    public int getFirmwareSub() { return firmwareSub.get(); }
    public int getWorkMode() { return workMode.get(); }
    public int getLightMode() { return lightMode.get(); }
    public int getLightBrightness() { return lightBrightness.get(); }
    public int getSwitchState() { return switchState.get(); }
    public String getDeviceName() { return deviceName.get(); }
    public String getFirmwareCatalogKey() { return firmwareCatalogKey.get(); }
    
    // Property getters
    public BooleanProperty isConnectedProperty() { return isConnected; }
    public BooleanProperty isScanningProperty() { return isScanning; }
    public IntegerProperty batteryLevelProperty() { return batteryLevel; }
    public IntegerProperty signalProperty() { return signal; }
    public IntegerProperty firmwareMainProperty() { return firmwareMain; }
    public IntegerProperty firmwareSubProperty() { return firmwareSub; }
    public IntegerProperty workModeProperty() { return workMode; }
    public IntegerProperty lightModeProperty() { return lightMode; }
    public IntegerProperty lightBrightnessProperty() { return lightBrightness; }
    public IntegerProperty switchStateProperty() { return switchState; }
    public StringProperty deviceNameProperty() { return deviceName; }
    public StringProperty firmwareCatalogKeyProperty() { return firmwareCatalogKey; }
    
    // Setters
    public void setConnected(boolean value) { if (!value) clearSavedBindings(); isConnected.set(value); }
    public void setScanning(boolean value) { isScanning.set(value); }
    public void setBatteryLevel(int value) { batteryLevel.set(value); }
    public void setSignal(int value) { signal.set(value); }
    public void setFirmwareMain(int value) { firmwareMain.set(value); }
    public void setFirmwareSub(int value) { firmwareSub.set(value); }
    public void setWorkMode(int value) { if (workMode.get() != value) clearSavedBindings(); workMode.set(value); }
    public void setLightMode(int value) { lightMode.set(value); }
    public void setLightBrightness(int value) { lightBrightness.set(value); }
    public void setSwitchState(int value) { 
        logger.debug("[DeviceStatus] setSwitchState - 旧值: {}, 新值: {}", switchState.get(), value);
        switchState.set(value); 
    }
    public void setDeviceName(String value) { deviceName.set(value); }
    public void setFirmwareCatalogKey(String value) { firmwareCatalogKey.set(value == null ? "" : value); }
    public void clearFirmwareIdentity() {
        clearSavedBindings();
        firmwareMain.set(-1);
        firmwareSub.set(-1);
        firmwareCatalogKey.set("");
        identityState.set(isConnected() ? IdentityState.UNKNOWN : IdentityState.DISCONNECTED);
    }
    
    // Convenience methods
    private final ObjectProperty<com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchConfig> savedBindings = new SimpleObjectProperty<>();
    public ObjectProperty<com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchConfig> savedBindingsProperty() { return savedBindings; }
    public com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchConfig getSavedBindings() { return copyBindings(savedBindings.get()); }
    public static com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchConfig copyBindings(com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchConfig config) {
        if (config == null) return null;
        return new com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchConfig(config.physicalPosition(),
            new com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchPositionConfig(config.up().binding(), config.up().actionPayload().clone()),
            new com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchPositionConfig(config.down().binding(), config.down().actionPayload().clone()));
    }
    public void setSavedBindings(com.example.ahakey.protocol.AhaKeyResponseParser.SideSwitchConfig config) { savedBindings.set(copyBindings(config)); }
    public void clearSavedBindings() { savedBindings.set(null); }
    public boolean isAutoApproval() {
        var config = savedBindings.get();
        int position = getSwitchState();
        return isConnected() && config != null && getWorkMode() >= 0 && getWorkMode() <= 3 && (position == 0 || position == 1)
            && (position == 0 ? config.up() : config.down()).binding() == com.example.ahakey.protocol.AhaKeyProtocol.SIDE_SWITCH_BINDING_AUTO;
    }
    public String getSwitchTitle() {
        if (!isConnected()) return "未连接 · 动作未知";
        int position = getSwitchState();
        if (position != 0 && position != 1) return "位置未知 · 动作未知";
        String prefix = position == 0 ? "上拨 · " : "下拨 · ";
        var config = savedBindings.get();
        if (config == null) return prefix + "动作未知";
        var action = position == 0 ? config.up() : config.down();
        return prefix + switch (action.binding()) {
            case com.example.ahakey.protocol.AhaKeyProtocol.SIDE_SWITCH_BINDING_AUTO -> "自动批准";
            case com.example.ahakey.protocol.AhaKeyProtocol.SIDE_SWITCH_BINDING_MANUAL -> "手动批准";
            case com.example.ahakey.protocol.AhaKeyProtocol.SIDE_SWITCH_BINDING_DISABLED -> "无动作";
            case com.example.ahakey.protocol.AhaKeyProtocol.SIDE_SWITCH_BINDING_CUSTOM ->
                com.example.ahakey.service.DeviceSyncService.sideSwitchActionSummary(action.actionPayload());
            default -> "动作未知";
        };
    }

    public String getDisplayDeviceName() {
        String name = deviceName.get();
        if (name == null || name.isBlank()) {
            return LanguageManager.getInstance().getString("status.waiting-device");
        }
        return name;
    }

    public String getDisplayFirmwareVersion() {
        if (!isConnected()) return "未知（未连接）";
        String catalogKey = firmwareCatalogKey.get();
        if (catalogKey != null && !catalogKey.isBlank()) {
            return catalogKey;
        }
        int main = firmwareMain.get();
        int sub = firmwareSub.get();
        if (main >= 0 && sub >= 0) {
            return "V" + main + "." + sub + "（完整标识未读到）";
        }
        return "未知（未读到）";
    }
}
