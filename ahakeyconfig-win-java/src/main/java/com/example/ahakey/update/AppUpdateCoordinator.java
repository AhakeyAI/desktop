package com.example.ahakey.update;

import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.scene.control.Alert;
import javafx.scene.control.ButtonBar;
import javafx.scene.control.ButtonType;
import javafx.scene.control.Label;
import javafx.scene.control.ProgressBar;
import javafx.scene.layout.VBox;
import javafx.stage.Stage;

import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.prefs.Preferences;

/** User-facing, optional Windows application update flow. */
public final class AppUpdateCoordinator {
    public static final SemanticVersion CURRENT = AppVersion.current();
    private static final Preferences PREFS =
        Preferences.userRoot().node("com/example/ahakey/update");
    private static final String LAST_CHECK = "lastCheck";
    private static final String REMIND_AFTER = "remindAfter";
    private static final String INSTALLED_NOTICE = "installedNotice";
    private static final AtomicBoolean CHECKING = new AtomicBoolean();

    private AppUpdateCoordinator() {}

    public static void onApplicationReady(Stage owner) {
        String installed = PREFS.get(INSTALLED_NOTICE, "");
        if (installed.equals(CURRENT.toString())) {
            PREFS.remove(INSTALLED_NOTICE);
            Alert done = alert(owner, Alert.AlertType.INFORMATION,
                text("更新完成", "Update Complete"),
                text("AhaKeyStudio 已更新到 ", "AhaKeyStudio was updated to ") + installed);
            done.show();
        }
        long now = Instant.now().toEpochMilli();
        long last = PREFS.getLong(LAST_CHECK, 0);
        long remindAfter = PREFS.getLong(REMIND_AFTER, 0);
        if (now - last >= Duration.ofDays(1).toMillis() && now >= remindAfter) {
            check(owner, false);
        }
    }

    public static void showAboutAndCheck(Stage owner) {
        Alert about = alert(owner, Alert.AlertType.INFORMATION,
            text("关于与软件更新", "About & Software Update"),
            "AhaKeyStudio " + CURRENT + "\nWindows 10/11 x64\n\n"
                + text("将通过 ahakey.com 检查稳定版本。",
                    "Checks the stable release through ahakey.com."));
        ButtonType check = new ButtonType(
            text("检查更新", "Check for Updates"), ButtonBar.ButtonData.OK_DONE);
        about.getButtonTypes().setAll(check, ButtonType.CLOSE);
        if (about.showAndWait().filter(check::equals).isPresent()) {
            check(owner, true);
        }
    }

    public static void check(Stage owner, boolean manual) {
        if (!CHECKING.compareAndSet(false, true)) {
            return;
        }
        PREFS.putLong(LAST_CHECK, Instant.now().toEpochMilli());
        daemon("app-update-check", () -> {
            try {
                Optional<StableRelease> optional =
                    new StableReleaseClient().fetchLatest();
                if (optional.isEmpty()
                    || !optional.get().appVersion().isNewerThan(CURRENT)) {
                    if (manual) {
                        Platform.runLater(() -> alert(owner, Alert.AlertType.INFORMATION,
                            text("已是最新版本", "Up to Date"),
                            text("当前已安装最新稳定版。", "The latest stable version is installed."))
                            .showAndWait());
                    }
                    return;
                }
                StableRelease release = optional.get();
                Platform.runLater(() -> prompt(owner, release));
            } catch (Exception exception) {
                if (manual) {
                    Platform.runLater(() -> alert(owner, Alert.AlertType.WARNING,
                        text("检查更新失败", "Update Check Failed"),
                        exception.getMessage()).showAndWait());
                }
            } finally {
                CHECKING.set(false);
            }
        });
    }

    private static void prompt(Stage owner, StableRelease release) {
        Alert prompt = alert(owner, Alert.AlertType.INFORMATION,
            text("发现新版本 ", "New Version ") + release.appVersion(),
            release.appName() + "\n\n" + release.appNotes());
        ButtonType install = new ButtonType(
            text("下载并安装", "Download & Install"), ButtonBar.ButtonData.OK_DONE);
        ButtonType later = new ButtonType(
            text("稍后提醒", "Remind Me Later"), ButtonBar.ButtonData.CANCEL_CLOSE);
        prompt.getButtonTypes().setAll(install, later);
        prompt.showAndWait().ifPresent(choice -> {
            if (choice == install) {
                downloadInstaller(
                    owner, release.appVersion(), release.windowsInstaller());
            } else {
                PREFS.putLong(REMIND_AFTER,
                    Instant.now().plus(Duration.ofHours(24)).toEpochMilli());
            }
        });
    }

    private static void downloadInstaller(
        Stage owner, SemanticVersion version, ReleaseAsset asset
    ) {
        Stage progressStage = new Stage();
        progressStage.initOwner(owner);
        progressStage.setTitle(text("下载更新", "Downloading Update"));
        Label detail = new Label(text("正在下载安装包…", "Downloading installer…"));
        ProgressBar progress = new ProgressBar(-1);
        progress.setPrefWidth(380);
        VBox root = new VBox(12, detail, progress);
        root.setPadding(new Insets(18));
        progressStage.setScene(new javafx.scene.Scene(root));
        progressStage.setResizable(false);
        progressStage.show();

        daemon("app-update-download", () -> {
            try {
                Path destination = Path.of(
                    System.getProperty("user.home"), ".ahakey", "updates", asset.name()
                );
                AssetDownloader.DownloadResult result = new AssetDownloader().download(
                    asset, destination,
                    (done, total) -> Platform.runLater(() -> {
                        progress.setProgress(total > 0 ? (double) done / total : -1);
                        detail.setText(text("已下载 ", "Downloaded ") + done
                            + (total > 0 ? " / " + total : "") + " bytes");
                    })
                );
                Platform.runLater(() -> {
                    progressStage.close();
                    Alert confirm = alert(owner, Alert.AlertType.CONFIRMATION,
                        text("准备安装", "Ready to Install"),
                        text(
                            "安装包已下载并通过基本格式检查。\n",
                            "The installer passed basic download validation.\n"
                        ) + text(
                            "确认后将退出 AhaKeyStudio 并启动安装程序。",
                            "AhaKeyStudio will quit and start the installer."
                        ));
                    if (confirm.showAndWait().filter(
                        button -> button == ButtonType.OK).isPresent()) {
                        try {
                            PREFS.put(INSTALLED_NOTICE, version.toString());
                            launchInstallerAndRestart(result.path(), version);
                            Platform.exit();
                        } catch (Exception exception) {
                            alert(owner, Alert.AlertType.ERROR,
                                text("无法启动安装程序", "Cannot Start Installer"),
                                exception.getMessage()).showAndWait();
                        }
                    }
                });
            } catch (Exception exception) {
                Platform.runLater(() -> {
                    progressStage.close();
                    alert(owner, Alert.AlertType.ERROR,
                        text("更新下载失败", "Update Download Failed"),
                        exception.getMessage()).showAndWait();
                });
            }
        });
    }

    private static void launchInstallerAndRestart(
        Path installer, SemanticVersion version
    ) throws Exception {
        String currentApp = System.getProperty("jpackage.app-path", "").trim();
        if (currentApp.isBlank()) {
            new ProcessBuilder(installer.toString()).start();
            return;
        }
        WindowsUpdateInstaller.launch(installer, Path.of(currentApp), version);
    }

    private static Alert alert(
        Stage owner, Alert.AlertType type, String title, String content
    ) {
        Alert alert = new Alert(type);
        if (owner != null) {
            alert.initOwner(owner);
        }
        alert.setTitle(title);
        alert.setHeaderText(null);
        alert.setContentText(content);
        return alert;
    }

    private static void daemon(String name, Runnable task) {
        Thread thread = new Thread(task, name);
        thread.setDaemon(true);
        thread.start();
    }

    private static String text(String zh, String en) {
        return Locale.getDefault().getLanguage().equalsIgnoreCase("zh") ? zh : en;
    }
}
