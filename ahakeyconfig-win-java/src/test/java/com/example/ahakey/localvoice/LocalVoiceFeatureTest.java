package com.example.ahakey.localvoice;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.net.URI;
import java.net.http.HttpClient;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LocalVoiceFeatureTest {
    @TempDir
    Path temp;

    private LocalVoiceFeature feature(URI manifest) {
        LocalVoiceAssets assets = new LocalVoiceAssets(temp.resolve("lv"));
        LocalVoiceInstaller installer = new LocalVoiceInstaller(
            HttpClient.newHttpClient(), assets, Duration.ofSeconds(20));
        // Run the download and UI updates inline so the test is deterministic.
        return new LocalVoiceFeature(temp.resolve("local-voice.json"), assets, installer,
            Runnable::run, Runnable::run, () -> manifest);
    }

    @Test
    void disablingBeforeQueuedCompletionDoesNotReenableVoice() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceAssets assets = new LocalVoiceAssets(temp.resolve("lv"));
            List<Runnable> queuedUi = new ArrayList<>();
            LocalVoiceFeature feature = new LocalVoiceFeature(temp.resolve("settings.json"), assets,
                new LocalVoiceInstaller(HttpClient.newHttpClient(), assets, Duration.ofSeconds(20)),
                Runnable::run, queuedUi::add, server::manifestUrl);
            feature.enable();
            assertFalse(queuedUi.isEmpty());
            feature.disable(false);
            queuedUi.forEach(Runnable::run);
            assertFalse(feature.enabledProperty().get());
            assertFalse(feature.isAvailable());
            assertEquals(LocalVoiceFeature.Phase.IDLE, feature.phaseProperty().get());
        }
    }

    @Test
    void oldFailureCannotOverwriteANewDownload() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            server.forcedSha256 = "0".repeat(64);
            LocalVoiceAssets assets = new LocalVoiceAssets(temp.resolve("lv"));
            List<Runnable> workers = new ArrayList<>();
            List<Runnable> queuedUi = new ArrayList<>();
            LocalVoiceFeature feature = new LocalVoiceFeature(temp.resolve("settings.json"), assets,
                new LocalVoiceInstaller(HttpClient.newHttpClient(), assets, Duration.ofSeconds(20)),
                workers::add, queuedUi::add, server::manifestUrl);
            feature.enable();
            workers.remove(0).run();
            feature.cancelDownload();
            feature.enable();
            queuedUi.forEach(Runnable::run);
            assertEquals(LocalVoiceFeature.Phase.CHECKING, feature.phaseProperty().get());
            assertFalse(feature.isAvailable());
        }
    }

    @Test
    void freshInstallIsTheLightClient() {
        LocalVoiceFeature feature = feature(URI.create("http://127.0.0.1:9/none"));
        assertFalse(feature.isAvailable());
        assertFalse(feature.enabledProperty().get());
        assertTrue(feature.modelDirectory().isEmpty());
        assertFalse(Files.exists(temp.resolve("local-voice.json")));
    }

    @Test
    void enableDownloadsThenBecomesAvailableAndSurvivesRestart() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceFeature feature = feature(server.manifestUrl());
            List<Boolean> events = new ArrayList<>();
            feature.addListener(events::add);

            feature.enable();

            assertTrue(feature.isAvailable());
            assertEquals(List.of(true), events);
            assertEquals(LocalVoiceFeature.Phase.IDLE, feature.phaseProperty().get());
            assertTrue(feature.modelDirectory().isPresent());
            assertTrue(feature.nativeDirectory().orElseThrow().endsWith(Path.of("native", "win-x64")));

            LocalVoiceFeature restarted = feature(server.manifestUrl());
            assertTrue(restarted.isAvailable());
        }
    }

    @Test
    void failedDownloadLeavesTheFeatureOff() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            server.forcedSha256 = "0".repeat(64);
            LocalVoiceFeature feature = feature(server.manifestUrl());
            feature.enable();
            assertFalse(feature.isAvailable());
            assertFalse(feature.enabledProperty().get());
            assertEquals(LocalVoiceFeature.Phase.FAILED, feature.phaseProperty().get());
            assertFalse(feature.messageProperty().get().isEmpty());
        }
    }

    @Test
    void disableKeepsFilesSoReEnablingDoesNotDownloadAgain() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceFeature feature = feature(server.manifestUrl());
            List<Boolean> events = new ArrayList<>();
            feature.addListener(events::add);
            feature.enable();
            int requests = server.fileRequests.get();

            feature.disable(false);
            assertFalse(feature.isAvailable());
            assertTrue(feature.installedProperty().get());

            feature.enable();
            assertTrue(feature.isAvailable());
            assertEquals(requests, server.fileRequests.get());
            assertEquals(List.of(true, false, true), events);
        }
    }

    @Test
    void disableWithDeleteRemovesTheDownload() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceFeature feature = feature(server.manifestUrl());
            feature.enable();
            feature.disable(true);
            assertFalse(feature.isAvailable());
            assertFalse(feature.installedProperty().get());
            assertTrue(feature.modelDirectory().isEmpty());
        }
    }

    @Test
    void enabledSettingWithMissingFilesIsNotAvailable() throws Exception {
        new LocalVoiceSettings(true, LocalVoiceSettings.ChineseScript.TRADITIONAL)
            .save(temp.resolve("local-voice.json"));
        LocalVoiceFeature feature = feature(URI.create("http://127.0.0.1:9/none"));
        assertTrue(feature.enabledProperty().get());
        assertFalse(feature.isAvailable());
        assertFalse(feature.messageProperty().get().isEmpty());
        assertEquals(LocalVoiceSettings.ChineseScript.TRADITIONAL, feature.getChineseScript());
    }

    @Test
    void chineseScriptChoiceIsSaved() {
        LocalVoiceFeature feature = feature(URI.create("http://127.0.0.1:9/none"));
        feature.setChineseScript(LocalVoiceSettings.ChineseScript.TRADITIONAL);
        assertEquals(LocalVoiceSettings.ChineseScript.TRADITIONAL,
            LocalVoiceSettings.load(temp.resolve("local-voice.json")).chineseScript());
    }
}
