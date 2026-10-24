package com.example.ahakey.localvoice;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Locale;

/**
 * User choices for the optional local voice feature, stored separately from
 * the key draft in {@code ~/.ahakey/local-voice.json}.
 *
 * <p>Local voice is off by default: a fresh install behaves like the light
 * client and never loads models or native libraries until the user turns it
 * on in settings.
 */
public final class LocalVoiceSettings {

    private static final Logger logger = LoggerFactory.getLogger(LocalVoiceSettings.class);
    private static final ObjectMapper MAPPER = new ObjectMapper()
        .enable(SerializationFeature.INDENT_OUTPUT);

    public static Path defaultPath() {
        return Path.of(System.getProperty("user.home"), ".ahakey", "local-voice.json");
    }

    /** Output script for recognized Chinese text. */
    public enum ChineseScript {
        SIMPLIFIED,
        TRADITIONAL;

        static ChineseScript parse(String value) {
            if (value == null) return SIMPLIFIED;
            try {
                return valueOf(value.trim().toUpperCase(Locale.ROOT));
            } catch (IllegalArgumentException ignored) {
                return SIMPLIFIED;
            }
        }
    }

    private final boolean enabled;
    private final ChineseScript chineseScript;

    public LocalVoiceSettings(boolean enabled, ChineseScript chineseScript) {
        this.enabled = enabled;
        this.chineseScript = chineseScript == null ? ChineseScript.SIMPLIFIED : chineseScript;
    }

    public static LocalVoiceSettings defaults() {
        return new LocalVoiceSettings(false, ChineseScript.SIMPLIFIED);
    }

    public boolean enabled() {
        return enabled;
    }

    public ChineseScript chineseScript() {
        return chineseScript;
    }

    public LocalVoiceSettings withEnabled(boolean value) {
        return new LocalVoiceSettings(value, chineseScript);
    }

    public LocalVoiceSettings withChineseScript(ChineseScript value) {
        return new LocalVoiceSettings(enabled, value);
    }

    /** Missing or unreadable files fall back to defaults (feature off). */
    public static LocalVoiceSettings load(Path file) {
        if (file == null || !Files.isRegularFile(file)) return defaults();
        try {
            Stored stored = MAPPER.readValue(file.toFile(), Stored.class);
            return new LocalVoiceSettings(stored.enabled, ChineseScript.parse(stored.chineseScript));
        } catch (IOException | RuntimeException e) {
            logger.warn("local-voice.json could not be read, using defaults: {}", e.getMessage());
            return defaults();
        }
    }

    public void save(Path file) throws IOException {
        Path absolute = file.toAbsolutePath();
        if (absolute.getParent() != null) Files.createDirectories(absolute.getParent());
        Stored stored = new Stored();
        stored.enabled = enabled;
        stored.chineseScript = chineseScript.name();
        Path temporary = absolute.resolveSibling(absolute.getFileName() + ".tmp");
        MAPPER.writeValue(temporary.toFile(), stored);
        try {
            Files.move(temporary, absolute, StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE);
        } catch (AtomicMoveNotSupportedException e) {
            Files.move(temporary, absolute, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    static final class Stored {
        public boolean enabled;
        public String chineseScript = ChineseScript.SIMPLIFIED.name();
    }
}
