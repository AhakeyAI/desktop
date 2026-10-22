package com.example.ahakey.service;

import com.example.ahakey.model.ModeSlot;

import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

/** Classpath-backed factory GIF set shipped with AhaKey Studio. */
public final class BundledGifLibrary {
    private static final String[] MODE_DIRS = {"claude", "cursor", "codex", "mode4"};
    private static final String[] ASSET_FILES = {
        "default.gif", "running.gif", "waiting-error.gif", "completed.gif"
    };

    private BundledGifLibrary() {}

    public static URL resource(ModeSlot mode, int asset) {
        validate(mode, asset);
        return BundledGifLibrary.class.getResource(resourceName(mode, asset));
    }

    public static Path extract(ModeSlot mode, int asset) throws IOException {
        validate(mode, asset);
        String resourceName = resourceName(mode, asset);
        try (InputStream input = BundledGifLibrary.class.getResourceAsStream(resourceName)) {
            if (input == null) throw new IOException("安装包缺少内置动画：" + resourceName);
            Path directory = Path.of(System.getProperty("java.io.tmpdir"), "ahakey-default-gifs");
            Files.createDirectories(directory);
            Path target = directory.resolve(MODE_DIRS[mode.getIndex()] + "-" + ASSET_FILES[asset]);
            Files.copy(input, target, StandardCopyOption.REPLACE_EXISTING);
            target.toFile().deleteOnExit();
            return target;
        }
    }

    private static String resourceName(ModeSlot mode, int asset) {
        return "/default-gifs/" + MODE_DIRS[mode.getIndex()] + "/" + ASSET_FILES[asset];
    }

    private static void validate(ModeSlot mode, int asset) {
        if (mode == null || asset < 0 || asset >= ASSET_FILES.length)
            throw new IllegalArgumentException("Invalid bundled GIF selection");
    }
}
