package com.example.ahakey.util;

import com.example.ahakey.model.AiRuntimeDisplayMode;
import com.example.ahakey.model.AiRuntimeSlotBinding;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

public final class AiRuntimeStore {
    private static final Logger logger = LoggerFactory.getLogger(AiRuntimeStore.class);
    private static final ObjectMapper MAPPER = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);
    private static final Path STORE_PATH = Path.of(System.getProperty("user.home"), ".ahakey", "ai-runtime.json");

    private AiRuntimeStore() {
    }

    public static Draft loadOrDefault() {
        File file = STORE_PATH.toFile();
        if (!file.exists()) {
            return Draft.defaults();
        }
        try {
            Draft saved = MAPPER.readValue(file, Draft.class);
            Draft defaults = Draft.defaults();
            if (saved.displayMode != null) {
                defaults.displayMode = saved.displayMode;
            }
            if (saved.codexDataDir != null && !saved.codexDataDir.isBlank()) {
                defaults.codexDataDir = saved.codexDataDir;
            }
            if (saved.cursorDataDir != null && !saved.cursorDataDir.isBlank()) {
                defaults.cursorDataDir = saved.cursorDataDir;
            }
            if (saved.primarySlotIndex >= 0 && saved.primarySlotIndex < 4) {
                defaults.primarySlotIndex = saved.primarySlotIndex;
            }
            if (saved.slots != null) {
                for (int i = 0; i < Math.min(saved.slots.length, defaults.slots.length); i++) {
                    if (saved.slots[i] != null) {
                        saved.slots[i].setSlotIndex(i);
                        defaults.slots[i] = saved.slots[i];
                    }
                }
            }
            return defaults;
        } catch (IOException e) {
            logger.warn("AiRuntimeStore.load failed, returning defaults: {}", e.getMessage());
            return Draft.defaults();
        }
    }

    public static void save(Draft draft) {
        try {
            Files.createDirectories(STORE_PATH.getParent());
            MAPPER.writeValue(STORE_PATH.toFile(), draft);
        } catch (IOException e) {
            logger.warn("AiRuntimeStore.save failed: {}", e.getMessage());
        }
    }

    public static class Draft {
        public String displayMode = AiRuntimeDisplayMode.SINGLE.name();
        public String codexDataDir = Path.of(System.getProperty("user.home"), ".codex").toString();
        public String cursorDataDir = defaultCursorDataDir();
        public int primarySlotIndex = -1;
        public AiRuntimeSlotBinding[] slots = new AiRuntimeSlotBinding[4];

        public static Draft defaults() {
            Draft draft = new Draft();
            for (int i = 0; i < draft.slots.length; i++) {
                draft.slots[i] = new AiRuntimeSlotBinding(i);
            }
            return draft;
        }

        public static String defaultCursorDataDir() {
            String appData = System.getenv("APPDATA");
            if (appData == null || appData.isBlank()) {
                return Path.of(System.getProperty("user.home"), "AppData", "Roaming", "Cursor", "User").toString();
            }
            return Path.of(appData, "Cursor", "User").toString();
        }
    }
}
