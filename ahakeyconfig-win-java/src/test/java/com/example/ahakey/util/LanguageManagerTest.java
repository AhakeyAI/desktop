package com.example.ahakey.util;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.regex.Pattern;
import static org.junit.jupiter.api.Assertions.*;

class LanguageManagerTest {
    @TempDir Path home;

    private Properties resource(String name) throws Exception {
        Properties p = new Properties();
        try (var reader = new InputStreamReader(Objects.requireNonNull(
            getClass().getResourceAsStream("/" + name)), StandardCharsets.UTF_8)) {
            p.load(reader);
        }
        return p;
    }

    @Test void russianCoversEveryEnglishKeyAndPreservesFormatArguments() throws Exception {
        var english = resource("messages_en.properties");
        var russian = resource("messages_ru.properties");
        var format = Pattern.compile("%(?:\\d+\\$)?[-#+ 0,(]*\\d*(?:\\.\\d+)?[a-zA-Z%]");
        for (String key : english.stringPropertyNames()) {
            assertNotNull(russian.getProperty(key), key);
            assertFalse(russian.getProperty(key).isBlank(), key);
            assertEquals(format.matcher(english.getProperty(key)).results().map(m -> m.group()).toList(),
                format.matcher(russian.getProperty(key)).results().map(m -> m.group()).toList(), key);
        }
    }

    @Test void legacyCatalogPreservesFormattingAndHasNoUntranslatedChinese() throws Exception {
        var catalog = resource("legacy_ru.properties");
        var format = Pattern.compile("%(?:\\d+\\$)?[-#+ 0,(]*\\d*(?:\\.\\d+)?[a-zA-Z%]");
        for (String source : catalog.stringPropertyNames()) {
            String translated = catalog.getProperty(source);
            assertFalse(translated.matches("(?s).*[\\p{IsHan}].*"), source);
            assertEquals(format.matcher(source).results().map(m -> m.group()).toList(),
                format.matcher(translated).results().map(m -> m.group()).toList(), source);
        }
        var ru = new LanguageManager("ru-RU");
        assertEquals("Прошивка (CH582)", ru.localizeText("固件管理（CH582）"));
        assertEquals(" мин.", ru.localizeText(" 分钟"));
        assertEquals("v1.4.8", ru.localizeText("v1.4.8"));
    }

    @Test void languageSelectionPersistsWithoutDiscardingOtherPreferences() throws Exception {
        String oldHome = System.getProperty("user.home");
        String oldLanguage = System.getProperty("AhaKeySelectedLanguage");
        try {
            System.setProperty("user.home", home.toString());
            Path file = home.resolve(".ahakey/preferences.properties");
            Files.createDirectories(file.getParent());
            Files.writeString(file, "existing.setting=keep\n");
            var manager = new LanguageManager("en");
            manager.switchLanguage("ru");
            assertEquals("Подключить", manager.getString("button.connect"));
            var prefs = new Properties();
            try (var input = Files.newInputStream(file)) { prefs.load(input); }
            assertEquals("ru", prefs.getProperty("AhaKeySelectedLanguage"));
            assertEquals("keep", prefs.getProperty("existing.setting"));
            manager.switchLanguage("zh");
            assertTrue(manager.isChinese());
            manager.switchLanguage("unknown");
            assertEquals("Connect Device", manager.getString("button.connect"));
        } finally {
            System.setProperty("user.home", oldHome);
            if (oldLanguage == null) System.clearProperty("AhaKeySelectedLanguage");
            else System.setProperty("AhaKeySelectedLanguage", oldLanguage);
        }
    }

    @Test void localeVariantsAndUnknownLanguagesNormalize() {
        assertEquals("ru", LanguageManager.normalizeLanguage("ru_RU"));
        assertEquals("zh", LanguageManager.normalizeLanguage("zh-CN"));
        assertEquals("en", LanguageManager.normalizeLanguage("de"));
        assertEquals("en", LanguageManager.normalizeLanguage(null));
    }
}
