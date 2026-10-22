package com.example.ahakey.sherpa;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.Set;

/** Loads the version-pinned Sherpa native libraries exactly once. */
public final class LibraryLoader {
    private static final Logger logger = LoggerFactory.getLogger(LibraryLoader.class);
    private static final String RESOURCE_ROOT = "/sherpa-onnx/native/win-x64/";
    private static final String NATIVE_PATH_PROPERTY = "sherpa_onnx.native.path";
    private static final String NATIVE_PATH_ENV = "SHERPA_ONNX_NATIVE_PATH";
    private static boolean loaded;
    private static Path loadedDirectory;

    private LibraryLoader() { }

    public static synchronized void load() {
        if (loaded) return;
        try {
            Path directory = findNativeDirectory();
            loadRequired(directory.resolve("onnxruntime.dll"));
            Path providers = directory.resolve("onnxruntime_providers_shared.dll");
            if (Files.isRegularFile(providers)) loadRequired(providers);
            loadRequired(directory.resolve("sherpa-onnx-jni.dll"));
            loadedDirectory = directory;
            loaded = true;
            logger.info("Sherpa native libraries loaded from {}", directory);
        } catch (Throwable failure) {
            logger.error("Sherpa native library load failed", failure);
            throw new IllegalStateException("加载 Sherpa-ONNX 原生库失败", failure);
        }
    }

    private static Path findNativeDirectory() throws Exception {
        Set<Path> candidates = new LinkedHashSet<>();
        addConfigured(candidates, System.getProperty(NATIVE_PATH_PROPERTY));
        addConfigured(candidates, System.getenv(NATIVE_PATH_ENV));
        Path codeLocation;
        try {
            codeLocation = Path.of(LibraryLoader.class.getProtectionDomain().getCodeSource()
                .getLocation().toURI());
        } catch (Exception e) {
            codeLocation = Path.of(System.getProperty("user.dir", "."));
        }
        Path codeDir = Files.isDirectory(codeLocation) ? codeLocation : codeLocation.getParent();
        if (codeDir != null) {
            candidates.add(codeDir.resolve("sherpa-onnx/native/win-x64"));
            candidates.add(codeDir.resolve("native/win-x64"));
            candidates.add(codeDir.resolve("lib/sherpa-onnx/native/win-x64"));
            candidates.add(codeDir.resolve("lib"));
            if (codeDir.getParent() != null) {
                candidates.add(codeDir.getParent().resolve("sherpa-onnx/native/win-x64"));
                candidates.add(codeDir.getParent().resolve("lib/sherpa-onnx/native/win-x64"));
            }
        }
        for (Path candidate : candidates) {
            Path normalized = candidate.toAbsolutePath().normalize();
            if (hasNativeLibraries(normalized)) return normalized;
        }
        return extractNativeLibraries();
    }

    private static void addConfigured(Set<Path> candidates, String value) {
        if (value != null && !value.isBlank()) candidates.add(Path.of(value));
    }

    private static boolean hasNativeLibraries(Path directory) {
        return Files.isRegularFile(directory.resolve("onnxruntime.dll"))
            && Files.isRegularFile(directory.resolve("sherpa-onnx-jni.dll"));
    }

    private static Path extractNativeLibraries() throws IOException {
        Path directory = Files.createTempDirectory("ahakey-sherpa-native-");
        directory.toFile().deleteOnExit();
        for (String name : new String[] {
            "onnxruntime.dll", "onnxruntime_providers_shared.dll", "sherpa-onnx-jni.dll"
        }) {
            String resource = RESOURCE_ROOT + name;
            try (InputStream input = LibraryLoader.class.getResourceAsStream(resource)) {
                if (input == null) throw new IOException("缺少原生库资源: " + resource);
                Path output = directory.resolve(name);
                Files.copy(input, output);
                output.toFile().deleteOnExit();
            }
        }
        return directory;
    }

    private static void loadRequired(Path path) throws IOException {
        if (!Files.isRegularFile(path)) throw new IOException("原生库不存在: " + path);
        System.load(path.toAbsolutePath().toString());
    }

    public static synchronized boolean isLoaded() { return loaded; }
    public static synchronized String getLoadedNativeLibDir() {
        return loadedDirectory == null ? null : loadedDirectory.toString();
    }
}
