package com.example.ahakey.service;

import java.io.File;
import java.nio.file.Path;
import java.util.prefs.Preferences;

/** One global recent GIF selection shared by all animation entry points. */
public final class GifSelectionHistory {
    private static final Preferences PREFERENCES =
        Preferences.userNodeForPackage(GifSelectionHistory.class);
    private static final String KEY = "lastSelectedGif";

    private GifSelectionHistory() {}

    public static void remember(Path path) {
        if (path != null) PREFERENCES.put(KEY, path.toAbsolutePath().normalize().toString());
    }

    public static File initialLocation() {
        String stored = PREFERENCES.get(KEY, "");
        if (stored.isBlank()) return null;
        File file = new File(stored);
        if (file.exists()) return file;
        File parent = file.getParentFile();
        return parent != null && parent.isDirectory() ? parent : null;
    }
}
