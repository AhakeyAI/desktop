package com.example.ahakey.model;

import com.example.ahakey.util.LanguageManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javafx.beans.property.*;

public class DeviceStatus {
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
    public void setConnected(boolean value) { isConnected.set(value); }
    public void setScanning(boolean value) { isScanning.set(value); }
    public void setBatteryLevel(int value) { batteryLevel.set(value); }
    public void setSignal(int value) { signal.set(value); }
    public void setFirmwareMain(int value) { firmwareMain.set(value); }
    public void setFirmwareSub(int value) { firmwareSub.set(value); }
    public void setWorkMode(int value) { workMode.set(value); }
    public void setLightMode(int value) { lightMode.set(value); }
    public void setLightBrightness(int value) { lightBrightness.set(value); }
    public void setSwitchState(int value) { 
        logger.debug("[DeviceStatus] setSwitchState - 旧值: {}, 新值: {}", switchState.get(), value);
        switchState.set(value); 
    }
    public void setDeviceName(String value) { deviceName.set(value); }
    public void setFirmwareCatalogKey(String value) { firmwareCatalogKey.set(value == null ? "" : value); }
    public void clearFirmwareIdentity() {
        firmwareMain.set(-1);
        firmwareSub.set(-1);
        firmwareCatalogKey.set("");
        identityState.set(isConnected() ? IdentityState.UNKNOWN : IdentityState.DISCONNECTED);
    }
    
    // Convenience methods
    public boolean isAutoApproval() {
        // 仅当 switchState == 0 时为自动批准模式
        // 未连接时 switchState 为 -1，此时不自动批准（与 macOS 版本一致）
        return switchState.get() == 0;
    }
    
    public String getSwitchTitle() {
        return isAutoApproval() 
            ? LanguageManager.getInstance().getString("status.auto-approval")
            : LanguageManager.getInstance().getString("status.manual-approval");
    }
    
    public String getDisplayDeviceName() {
        String name = deviceName.get();
        if (name == null || name.isBlank()) {
            return LanguageManager.getInstance().getString("status.waiting-device");
        }
        return name;
    }

    public String getDisplayFirmwareVersion() {
        String catalogKey = firmwareCatalogKey.get();
        if (catalogKey != null && !catalogKey.isBlank()) {
            return catalogKey;
        }
        int main = firmwareMain.get();
        int sub = firmwareSub.get();
        if (main >= 0 && sub >= 0) {
            return "V" + main + "." + sub;
        }
        return "-";
    }
}
