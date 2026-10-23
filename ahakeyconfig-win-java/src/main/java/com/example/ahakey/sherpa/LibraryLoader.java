package com.example.ahakey.sherpa;

import com.k2fsa.sherpa.onnx.OnlineStream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/** Delegates loading to the matching official API/native resource JAR pair. */
public final class LibraryLoader {
    private static final Logger logger = LoggerFactory.getLogger(LibraryLoader.class);
    private static volatile boolean loaded;
    private LibraryLoader() { }

    public static synchronized void load() {
        if (loaded) return;
        try {
            // In 1.13.3 the empty stream constructor calls the official once-only loader,
            // leaves its native pointer at zero and allocates no recognizer/model.
            // Do not System.load the same DLL through a second application class loader.
            OnlineStream probe = new OnlineStream();
            probe.release();
            loaded = true;
        } catch (LinkageError | RuntimeException e) {
            logger.error("Sherpa 本地库加载失败，请检查配套 native-lib-win-x64-v1.13.3.jar", e);
            throw e;
        }
    }
    public static boolean isLoaded() { return loaded; }
}
