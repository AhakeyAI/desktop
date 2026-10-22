package com.example.ahakey.localvoice;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.net.http.HttpClient;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.concurrent.CancellationException;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LocalVoiceInstallerTest {
    @TempDir
    Path temp;

    private LocalVoiceInstaller installer(LocalVoiceAssets assets) {
        return new LocalVoiceInstaller(HttpClient.newHttpClient(), assets, Duration.ofSeconds(20));
    }

    @Test
    void manifestAcceptsOnlyTheFilesTheClientLoads() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceManifest manifest = LocalVoiceManifest.parse(server.manifestJson());
            assertEquals("test-pack-1", manifest.packId());
            assertEquals(LocalVoiceManifest.REQUIRED_PATHS.size(), manifest.files().size());

            String json = server.manifestJson();
            assertThrows(IOException.class, () -> LocalVoiceManifest.parse(
                json.replace("models/tokens.txt", "../../evil.dll")));
            assertThrows(IOException.class, () -> LocalVoiceManifest.parse(
                json.replace("models/tokens.txt", "models/other.onnx")));
            assertThrows(IOException.class, () -> LocalVoiceManifest.parse(
                json.replace("\"schema\":1", "\"schema\":2")));
            assertThrows(IOException.class, () -> LocalVoiceManifest.parse(
                json.replace("http://127.0.0.1", "http://example.com")));
            assertThrows(IOException.class, () -> LocalVoiceManifest.parse(
                json.replace("\"packId\":\"test-pack-1\"", "\"packId\":\"../x\"")));
        }
        assertThrows(IOException.class, () -> LocalVoiceManifest.parse(
            "{\"schema\":1,\"packId\":\"p\",\"files\":[{\"path\":\"models/tokens.txt\","
                + "\"url\":\"https://ahakey.com/t\",\"size\":1,\"sha256\":\"" + "a".repeat(64) + "\"}]}"),
            "a manifest missing required files is rejected");
    }

    @Test
    void installVerifiesFilesAndRecordsThePackLast() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceAssets assets = new LocalVoiceAssets(temp.resolve("lv"));
            LocalVoiceInstaller installer = installer(assets);
            LocalVoiceManifest manifest = installer.fetchManifest(server.manifestUrl());
            AtomicLong lastDone = new AtomicLong();
            LocalVoiceAssets.InstalledPack pack = installer.install(manifest,
                (done, total, file) -> lastDone.set(done), () -> false);

            assertEquals(manifest.totalBytes(), lastDone.get());
            assertEquals("test-pack-1", pack.packId());
            assertArrayEquals(server.files.get("models/encoder.int8.onnx"),
                Files.readAllBytes(pack.modelDirectory().resolve("encoder.int8.onnx")));
            assertTrue(Files.isRegularFile(pack.nativeDirectory().resolve("sherpa-onnx-jni.dll")));
            assertTrue(assets.isInstalled(manifest));

            // Installing the same pack again does not download anything.
            int requests = server.fileRequests.get();
            installer.install(manifest, null, null);
            assertEquals(requests, server.fileRequests.get());
        }
    }

    @Test
    void checksumMismatchInstallsNothing() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            server.forcedSha256 = "0".repeat(64);
            LocalVoiceAssets assets = new LocalVoiceAssets(temp.resolve("lv"));
            LocalVoiceInstaller installer = installer(assets);
            LocalVoiceManifest manifest = installer.fetchManifest(server.manifestUrl());
            IOException failure = assertThrows(IOException.class,
                () -> installer.install(manifest, null, null));
            assertTrue(failure.getMessage().contains("checksum"));
            assertTrue(assets.installed().isEmpty());
        }
    }

    @Test
    void cancelledDownloadInstallsNothing() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceAssets assets = new LocalVoiceAssets(temp.resolve("lv"));
            LocalVoiceInstaller installer = installer(assets);
            LocalVoiceManifest manifest = installer.fetchManifest(server.manifestUrl());
            AtomicInteger callbacks = new AtomicInteger();
            assertThrows(CancellationException.class, () -> installer.install(manifest,
                (done, total, file) -> callbacks.incrementAndGet(),
                () -> callbacks.get() > 1));
            assertTrue(assets.installed().isEmpty());
        }
    }

    @Test
    void partialFileFromAnEarlierAttemptIsResumedWithARangeRequest() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceAssets assets = new LocalVoiceAssets(temp.resolve("lv"));
            LocalVoiceInstaller installer = installer(assets);
            LocalVoiceManifest manifest = installer.fetchManifest(server.manifestUrl());
            byte[] encoder = server.files.get("models/encoder.int8.onnx");
            Path part = assets.stagingDir(manifest.packId()).resolve("models/encoder.int8.onnx.part");
            Files.createDirectories(part.getParent());
            Files.write(part, java.util.Arrays.copyOf(encoder, encoder.length / 2));

            installer.install(manifest, null, () -> false);

            assertEquals(1, server.rangeRequests.get(), "the partial file is resumed");
            assertArrayEquals(encoder, Files.readAllBytes(assets.installed().orElseThrow()
                .modelDirectory().resolve("encoder.int8.onnx")));
        }
    }

    @Test
    void uninstallForgetsThePackAndDeletesItsFiles() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceAssets assets = new LocalVoiceAssets(temp.resolve("lv"));
            LocalVoiceInstaller installer = installer(assets);
            LocalVoiceAssets.InstalledPack pack =
                installer.install(installer.fetchManifest(server.manifestUrl()), null, null);
            assets.uninstall();
            assertTrue(assets.installed().isEmpty());
            assertFalse(Files.exists(pack.directory()));
        }
    }

    @Test
    void aDamagedInstalledFileMakesThePackUnavailable() throws Exception {
        try (FakePackServer server = new FakePackServer()) {
            LocalVoiceAssets assets = new LocalVoiceAssets(temp.resolve("lv"));
            LocalVoiceInstaller installer = installer(assets);
            LocalVoiceAssets.InstalledPack pack =
                installer.install(installer.fetchManifest(server.manifestUrl()), null, null);
            Files.writeString(pack.modelDirectory().resolve("tokens.txt"), "truncated");
            assertTrue(assets.installed().isEmpty());
        }
    }
}
