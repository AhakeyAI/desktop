package com.example.ahakey.util;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.service.ScreenAnimationAssetStore;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.*;

class ScreenAnimationAssetStoreTest {
    @Test
    void successfulAckStoresOnlyTheCommittedModeAndAsset() throws Exception {
        Path root = Files.createTempDirectory("screen-assets-");
        Path source = Files.write(root.resolve("chosen.gif"), new byte[]{'G', 'I', 'F', '1'});
        ScreenAnimationAssetStore store = new ScreenAnimationAssetStore(root.resolve("managed"));
        ScreenAnimationAssetStore.StoredAsset stored = store.store(
            source, ModeSlot.MODE1, 2, 7, 160, 80);

        StudioState state = new StudioState();
        state.setScreenAssetMetadata(ModeSlot.MODE1, 2, stored.metadata());
        assertNull(state.getScreenAssetMetadata(ModeSlot.MODE1, 1));
        assertNull(state.getScreenAssetMetadata(ModeSlot.MODE0, 2));
        assertTrue(ScreenAnimationAssetStore.isUsable(stored.metadata()));
        assertEquals("chosen.gif", stored.metadata().originalFileName);
        assertEquals("gif", stored.metadata().mediaType);
    }

    @Test
    void metadataSurvivesRestartAndManagedCopySurvivesSourceDeletion() throws Exception {
        Path root = Files.createTempDirectory("screen-assets-restart-");
        Path source = Files.write(root.resolve("source.gif"), new byte[]{'G', 'I', 'F', '2'});
        ScreenAnimationAssetStore.StoredAsset stored = new ScreenAnimationAssetStore(
            root.resolve("managed")).store(source, ModeSlot.MODE0, 0, 2, 160, 80);
        StudioState before = new StudioState();
        before.setScreenAssetMetadata(ModeSlot.MODE0, 0, stored.metadata());
        Path draft = root.resolve("studio-draft.json");
        assertTrue(StudioStore.save(draft, before.toPersisted()));
        Files.delete(source);

        StudioState after = new StudioState();
        after.loadFromPersisted(StudioStore.load(draft));
        StudioState.PersistedDraft.ScreenAssetMetadata metadata =
            after.getScreenAssetMetadata(ModeSlot.MODE0, 0);
        assertNotNull(metadata);
        assertTrue(ScreenAnimationAssetStore.isUsable(metadata));
        assertFalse(Files.exists(source));
    }

    @Test
    void failedUploadCannotCreateOrReplaceManagedMetadata() throws Exception {
        Path root = Files.createTempDirectory("screen-assets-failure-");
        ScreenAnimationAssetStore store = new ScreenAnimationAssetStore(root.resolve("managed"));
        assertThrows(java.io.IOException.class, () -> store.store(
            root.resolve("missing.gif"), ModeSlot.MODE2, 1, 1, 160, 80));
        assertFalse(Files.exists(root.resolve("managed")));
    }

    @Test
    void missingMetadataIsNeverReportedAsCurrentResource() {
        assertFalse(ScreenAnimationAssetStore.isUsable(null));
        var metadata = new StudioState.PersistedDraft.ScreenAssetMetadata();
        metadata.managedCachePath = "missing.gif";
        assertFalse(ScreenAnimationAssetStore.isUsable(metadata));
    }

    @Test
    void failedReplacementLeavesPreviousSlotUntouched() throws Exception {
        Path root = Files.createTempDirectory("screen-assets-replace-");
        Path source = Files.write(root.resolve("old.gif"), new byte[]{'G', 'I', 'F'});
        var store = new ScreenAnimationAssetStore(root.resolve("managed"));
        var old = store.store(source, ModeSlot.MODE3, 3, 1, 160, 80);
        var state = new StudioState();
        state.setScreenAssetMetadata(ModeSlot.MODE3, 3, old.metadata());
        assertThrows(java.io.IOException.class, () -> store.store(
            root.resolve("deleted.gif"), ModeSlot.MODE3, 3, 1, 160, 80));
        assertSame(old.metadata(), state.getScreenAssetMetadata(ModeSlot.MODE3, 3));
        assertTrue(ScreenAnimationAssetStore.isUsable(old.metadata()));
    }

    @Test
    void metadataIncludesIntegrityAndDisplayFields() throws Exception {
        Path root = Files.createTempDirectory("screen-assets-fields-");
        Path source = Files.write(root.resolve("field.gif"), new byte[]{9, 8, 7});
        var stored = new ScreenAnimationAssetStore(root.resolve("managed"))
            .store(source, ModeSlot.MODE2, 1, 9, 160, 80);
        assertEquals(3, stored.metadata().fileSize);
        assertEquals(64, stored.metadata().sha256.length());
        assertEquals(160, stored.metadata().width);
        assertEquals(80, stored.metadata().height);
        assertNotNull(stored.metadata().updatedAt);
    }

    @Test
    void staticImageIsTrackedAsStaticMedia() throws Exception {
        Path root = Files.createTempDirectory("screen-assets-static-");
        Path source = Files.write(root.resolve("image.png"), new byte[]{1, 2, 3});
        var stored = new ScreenAnimationAssetStore(root.resolve("managed"))
            .store(source, ModeSlot.MODE0, 3, 1, 160, 80);
        assertEquals("static", stored.metadata().mediaType);
        assertEquals(1, stored.metadata().frameCount);
    }
}
