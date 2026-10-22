package com.example.ahakey.util;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Properties;

/** Persists UI onboarding flags independently from device configuration. */
public final class FirstRunState {
    private static final String HOOK_ONBOARDING = "hookOnboardingShown";
    private static final Path STATE_FILE = Path.of(
        System.getProperty("user.home"), ".ahakey", "ui-state.properties"
    );

    private FirstRunState() {
    }

    public static synchronized boolean shouldShowHookOnboarding() {
        return !Boolean.parseBoolean(load().getProperty(HOOK_ONBOARDING, "false"));
    }

    public static synchronized void markHookOnboardingShown() {
        Properties properties = load();
        properties.setProperty(HOOK_ONBOARDING, "true");
        try {
            Files.createDirectories(STATE_FILE.getParent());
            Path temporary = STATE_FILE.resolveSibling(STATE_FILE.getFileName() + ".tmp");
            try (OutputStream output = Files.newOutputStream(temporary)) {
                properties.store(output, "AhaKey Studio UI state");
            }
            try {
                Files.move(temporary, STATE_FILE,
                    StandardCopyOption.REPLACE_EXISTING,
                    StandardCopyOption.ATOMIC_MOVE);
            } catch (IOException atomicMoveUnsupported) {
                Files.move(temporary, STATE_FILE, StandardCopyOption.REPLACE_EXISTING);
            }
        } catch (IOException ignored) {
            // Persistence failure must never prevent the application from starting.
        }
    }

    private static Properties load() {
        Properties properties = new Properties();
        if (!Files.isRegularFile(STATE_FILE)) return properties;
        try (InputStream input = Files.newInputStream(STATE_FILE)) {
            properties.load(input);
        } catch (IOException ignored) {
            // An unreadable state file is treated as first run.
        }
        return properties;
    }
}
