package com.example.ahakey.localvoice;

import javafx.application.Platform;
import javafx.beans.property.BooleanProperty;
import javafx.beans.property.DoubleProperty;
import javafx.beans.property.ObjectProperty;
import javafx.beans.property.ReadOnlyBooleanProperty;
import javafx.beans.property.ReadOnlyDoubleProperty;
import javafx.beans.property.ReadOnlyObjectProperty;
import javafx.beans.property.ReadOnlyStringProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.beans.property.SimpleDoubleProperty;
import javafx.beans.property.SimpleObjectProperty;
import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.concurrent.CancellationException;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

import static com.example.ahakey.util.LanguageManager.localize;

/**
 * Owns the optional local voice feature: the user's on/off choice, the
 * downloaded pack, and the download itself.
 *
 * <p>The feature is <em>available</em> only when the user turned it on
 * <em>and</em> a verified pack is installed. Everything that belongs to local
 * voice (TopBar voice controls, AhaType, the cloud account menu, the K1
 * "local voice" actions) is shown only while it is available.
 */
public final class LocalVoiceFeature {

    private static final Logger logger = LoggerFactory.getLogger(LocalVoiceFeature.class);
    private static LocalVoiceFeature instance;

    public enum Phase { IDLE, CHECKING, DOWNLOADING, INSTALLING, FAILED }

    /** Called on the UI thread when the feature becomes available or unavailable. */
    public interface Listener {
        void onAvailabilityChanged(boolean available);
    }

    private final Path settingsFile;
    private final LocalVoiceAssets assets;
    private final LocalVoiceInstaller installer;
    private final Executor worker;
    private final Consumer<Runnable> uiThread;
    private final java.util.function.Supplier<java.net.URI> manifestUrl;
    private final List<Listener> listeners = new ArrayList<>();

    private LocalVoiceSettings settings;
    private final BooleanProperty enabled = new SimpleBooleanProperty(false);
    private final BooleanProperty installed = new SimpleBooleanProperty(false);
    private final BooleanProperty available = new SimpleBooleanProperty(false);
    private final ObjectProperty<Phase> phase = new SimpleObjectProperty<>(Phase.IDLE);
    private final DoubleProperty progress = new SimpleDoubleProperty(0);
    private final StringProperty message = new SimpleStringProperty("");
    private final ObjectProperty<LocalVoiceSettings.ChineseScript> chineseScript =
        new SimpleObjectProperty<>(LocalVoiceSettings.ChineseScript.SIMPLIFIED);
    private volatile AtomicBoolean cancelFlag = new AtomicBoolean(false);

    public static synchronized LocalVoiceFeature getInstance() {
        if (instance == null) {
            LocalVoiceAssets assets = new LocalVoiceAssets(LocalVoiceAssets.defaultRoot());
            instance = new LocalVoiceFeature(LocalVoiceSettings.defaultPath(), assets,
                new LocalVoiceInstaller(assets),
                Executors.newSingleThreadExecutor(runnable -> {
                    Thread thread = new Thread(runnable, "local-voice-installer");
                    thread.setDaemon(true);
                    return thread;
                }),
                LocalVoiceFeature::runOnFxThread, LocalVoiceInstaller::manifestUrl);
        }
        return instance;
    }

    public LocalVoiceFeature(Path settingsFile, LocalVoiceAssets assets, LocalVoiceInstaller installer,
                             Executor worker, Consumer<Runnable> uiThread,
                             java.util.function.Supplier<java.net.URI> manifestUrl) {
        this.settingsFile = Objects.requireNonNull(settingsFile, "settingsFile");
        this.assets = Objects.requireNonNull(assets, "assets");
        this.installer = Objects.requireNonNull(installer, "installer");
        this.worker = Objects.requireNonNull(worker, "worker");
        this.uiThread = Objects.requireNonNull(uiThread, "uiThread");
        this.manifestUrl = Objects.requireNonNull(manifestUrl, "manifestUrl");
        this.settings = LocalVoiceSettings.load(settingsFile);
        Optional<LocalVoiceAssets.InstalledPack> pack = assets.installed();
        // Leftovers from an earlier uninstall could not be deleted while their
        // DLLs were loaded; this is the first chance to clean them up.
        assets.removeUnusedPacks(pack.map(LocalVoiceAssets.InstalledPack::packId).orElse(null));
        enabled.set(settings.enabled());
        installed.set(pack.isPresent());
        chineseScript.set(settings.chineseScript());
        available.set(enabled.get() && installed.get());
        if (enabled.get() && !installed.get()) {
            message.set(localize("本地语音文件不完整，请重新下载。"));
        }
    }

    private static void runOnFxThread(Runnable runnable) {
        try {
            if (Platform.isFxApplicationThread()) runnable.run();
            else Platform.runLater(runnable);
        } catch (IllegalStateException toolkitNotStarted) {
            runnable.run();
        }
    }

    // ---- State -------------------------------------------------------------

    /** User turned it on and the files are complete. */
    public boolean isAvailable() {
        return available.get();
    }

    public ReadOnlyBooleanProperty availableProperty() {
        return available;
    }

    public ReadOnlyBooleanProperty enabledProperty() {
        return enabled;
    }

    public ReadOnlyBooleanProperty installedProperty() {
        return installed;
    }

    public ReadOnlyObjectProperty<Phase> phaseProperty() {
        return phase;
    }

    public ReadOnlyDoubleProperty progressProperty() {
        return progress;
    }

    public ReadOnlyStringProperty messageProperty() {
        return message;
    }

    public ReadOnlyObjectProperty<LocalVoiceSettings.ChineseScript> chineseScriptProperty() {
        return chineseScript;
    }

    public LocalVoiceSettings.ChineseScript getChineseScript() {
        return chineseScript.get();
    }

    public boolean isBusy() {
        Phase current = phase.get();
        return current == Phase.CHECKING || current == Phase.DOWNLOADING || current == Phase.INSTALLING;
    }

    /** Model directory of the installed pack, used by SpeechService. */
    public Optional<Path> modelDirectory() {
        return assets.installed().map(LocalVoiceAssets.InstalledPack::modelDirectory);
    }

    /** Native DLL directory of the installed pack, used by LibraryLoader. */
    public Optional<Path> nativeDirectory() {
        return assets.installed().map(LocalVoiceAssets.InstalledPack::nativeDirectory);
    }

    public Path storageRoot() {
        return assets.root();
    }

    public synchronized void addListener(Listener listener) {
        listeners.add(Objects.requireNonNull(listener, "listener"));
    }

    // ---- Actions -----------------------------------------------------------

    /**
     * Turns local voice on. Downloads the pack first when it is missing; the
     * feature only becomes available after the download is verified.
     */
    public void enable() {
        if (isBusy()) return;
        if (assets.installed().isPresent()) {
            installed.set(true);
            saveEnabled(true);
            phase.set(Phase.IDLE);
            message.set("");
            refreshAvailability();
            return;
        }
        AtomicBoolean cancel = new AtomicBoolean(false);
        cancelFlag = cancel;
        phase.set(Phase.CHECKING);
        progress.set(0);
        message.set(localize("正在获取本地语音下载信息…"));
        worker.execute(() -> runInstall(cancel));
    }

    private void runInstall(AtomicBoolean cancel) {
        try {
            LocalVoiceManifest manifest = installer.fetchManifest(manifestUrl.get());
            long total = manifest.totalBytes();
            uiThread.accept(() -> {
                phase.set(Phase.DOWNLOADING);
                message.set(localize("正在下载本地语音模型（共 ") + formatMegabytes(total) + "）…");
            });
            installer.install(manifest, (done, all, file) -> uiThread.accept(() -> {
                progress.set(all <= 0 ? 0 : (double) done / all);
                message.set(localize("正在下载本地语音模型 ")
                    + formatMegabytes(done) + " / " + formatMegabytes(all));
            }), cancel::get);
            uiThread.accept(() -> {
                phase.set(Phase.IDLE);
                progress.set(1);
                message.set("");
                installed.set(true);
                saveEnabled(true);
                refreshAvailability();
            });
        } catch (CancellationException e) {
            uiThread.accept(() -> {
                phase.set(Phase.IDLE);
                progress.set(0);
                message.set(localize("已取消下载，下次开启时会继续下载。"));
            });
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            fail(localize("下载被中断"));
        } catch (IOException | RuntimeException e) {
            logger.warn("Local voice download failed", e);
            fail(localize("下载失败：") + e.getMessage());
        }
    }

    private void fail(String text) {
        uiThread.accept(() -> {
            phase.set(Phase.FAILED);
            message.set(text);
        });
    }

    public void cancelDownload() {
        cancelFlag.set(true);
    }

    /**
     * Turns local voice off. With {@code deleteFiles} the downloaded pack is
     * removed as well (DLLs in use are cleaned up on the next start).
     */
    public void disable(boolean deleteFiles) {
        cancelDownload();
        saveEnabled(false);
        refreshAvailability();
        if (deleteFiles) {
            try {
                assets.uninstall();
            } catch (IOException e) {
                logger.warn("Could not remove local voice files: {}", e.getMessage());
            }
            installed.set(assets.installed().isPresent());
        }
        phase.set(Phase.IDLE);
        progress.set(0);
        message.set("");
    }

    public void setChineseScript(LocalVoiceSettings.ChineseScript script) {
        if (script == null || script == chineseScript.get()) return;
        chineseScript.set(script);
        settings = settings.withChineseScript(script);
        persist();
    }

    private void saveEnabled(boolean value) {
        enabled.set(value);
        settings = settings.withEnabled(value);
        persist();
    }

    private void persist() {
        try {
            settings.save(settingsFile);
        } catch (IOException e) {
            logger.warn("local-voice.json could not be saved: {}", e.getMessage());
        }
    }

    private void refreshAvailability() {
        boolean now = enabled.get() && installed.get();
        if (now == available.get()) return;
        available.set(now);
        List<Listener> snapshot;
        synchronized (this) {
            snapshot = List.copyOf(listeners);
        }
        for (Listener listener : snapshot) {
            try {
                listener.onAvailabilityChanged(now);
            } catch (RuntimeException e) {
                logger.error("Local voice listener failed", e);
            }
        }
    }

    static String formatMegabytes(long bytes) {
        return String.format(java.util.Locale.ROOT, "%.0f MB", bytes / (1024.0 * 1024.0));
    }
}
