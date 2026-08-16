package com.example.ahakey.update;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.service.BleManager;
import javafx.application.Platform;
import javafx.beans.value.ChangeListener;
import javafx.scene.control.Alert;
import javafx.stage.Stage;

import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.prefs.Preferences;

/** Once-daily, non-blocking firmware availability notification. */
public final class FirmwareUpdateNotifier {
    private static final Preferences PREFS =
        Preferences.userRoot().node("com/example/ahakey/firmware-update");
    private static final AtomicBoolean STARTED = new AtomicBoolean();

    private FirmwareUpdateNotifier() {}

    public static void checkWhenConnected(
        Stage owner, BleManager manager, DeviceStatus status
    ) {
        if (!STARTED.compareAndSet(false, true)) {
            return;
        }
        long now = Instant.now().toEpochMilli();
        if (now - PREFS.getLong("lastCheck", 0) < Duration.ofDays(1).toMillis()) {
            return;
        }
        if (status.isConnected()) {
            check(owner, manager);
            return;
        }
        AtomicReference<ChangeListener<Boolean>> holder = new AtomicReference<>();
        ChangeListener<Boolean> listener = (observable, oldValue, connected) -> {
            if (connected) {
                status.isConnectedProperty().removeListener(holder.get());
                check(owner, manager);
            }
        };
        holder.set(listener);
        status.isConnectedProperty().addListener(listener);
    }

    private static void check(Stage owner, BleManager manager) {
        PREFS.putLong("lastCheck", Instant.now().toEpochMilli());
        Thread thread = new Thread(() -> {
            try {
                var release = new StableReleaseClient().fetchLatest().orElse(null);
                var firmware = release == null
                    ? null : release.ch582Firmware().orElse(null);
                var caps = manager.queryDeviceCapabilities();
                if (firmware == null || caps == null) {
                    return;
                }
                SemanticVersion current = new SemanticVersion(
                    caps.firmwareMajor(), caps.firmwareMinor(), caps.firmwarePatch()
                );
                if (!firmware.version().isNewerThan(current)) {
                    return;
                }
                Platform.runLater(() -> {
                    Alert alert = new Alert(Alert.AlertType.INFORMATION);
                    if (owner != null) alert.initOwner(owner);
                    alert.setTitle(text("发现新固件", "New Firmware Available"));
                    alert.setHeaderText(null);
                    alert.setContentText(text(
                        "当前固件 " + current + "，可更新到 " + firmware.version()
                            + "。请在“设备信息 → 固件管理”中手动开始；不会自动烧录。",
                        "Firmware " + firmware.version() + " is available (current "
                            + current + "). Open Device Info → Firmware Management. Flashing never starts automatically."
                    ));
                    alert.show();
                });
            } catch (Exception ignored) {
                // A failed background check must not affect device use.
            }
        }, "firmware-update-check");
        thread.setDaemon(true);
        thread.start();
    }

    private static String text(String zh, String en) {
        return Locale.getDefault().getLanguage().equalsIgnoreCase("zh") ? zh : en;
    }
}
