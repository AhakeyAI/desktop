package com.example.ahakey.firmware;

import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.HashSet;
import java.util.jar.JarFile;

/** Runs at package time with only the application manifest supplying its dependencies. */
public final class PackagedRuntimeCheck {
    public static void main(String[] args) throws Exception {
        Path jar = Path.of(args[0]).toAbsolutePath();
        try (JarFile archive = new JarFile(jar.toFile())) {
            String classpath = archive.getManifest().getMainAttributes().getValue("Class-Path");
            if (classpath == null) throw new IllegalStateException("Manifest Class-Path is missing");
            var entries = new HashSet<>(Arrays.asList(classpath.trim().split("\\s+")));
            try (var dependencies = Files.list(jar.getParent().resolve("lib"))) {
                for (Path dependency : dependencies.filter(path -> path.toString().endsWith(".jar")).toList()) {
                    if (!entries.contains("lib/" + dependency.getFileName())) {
                        throw new IllegalStateException("Runtime dependency missing from manifest: " + dependency.getFileName());
                    }
                }
            }
        }
        // Platform parent prevents Maven's own dependency classpath hiding omissions.
        try (URLClassLoader loader = new URLClassLoader(new URL[]{jar.toUri().toURL()},
                ClassLoader.getPlatformClassLoader())) {
            Class<?> converter = loader.loadClass("com.example.ahakey.util.ChineseTextConverter");
            Object result = converter.getMethod("toTraditional", String.class).invoke(null, "汉语");
            if (!"漢語".equals(result)) throw new IllegalStateException("Packaged Chinese conversion failed: " + result);
            Class.forName("com.k2fsa.sherpa.onnx.OnlineRecognizer", false, loader);
        }
        System.out.println("PACKAGED_RUNTIME_CLASSPATH=OK");
    }
}
