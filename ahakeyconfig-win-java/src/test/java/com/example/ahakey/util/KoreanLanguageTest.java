package com.example.ahakey.util;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.regex.Pattern;
import static org.junit.jupiter.api.Assertions.*;

class KoreanLanguageTest {
    @TempDir Path home;
    private Properties resource(String name) throws Exception {
        var result = new Properties();
        try (var reader = new InputStreamReader(Objects.requireNonNull(
                getClass().getResourceAsStream("/" + name)), StandardCharsets.UTF_8)) {
            result.load(reader);
        }
        return result;
    }

    @Test void catalogsCoverExistingKeysAndPreserveFormatArguments() throws Exception {
        var format = Pattern.compile("%(?:\\d+\\$)?[-#+ 0,(]*\\d*(?:\\.\\d+)?[a-zA-Z%]");
        for (String catalog : List.of("messages", "legacy")) {
            var reference = resource(catalog + (catalog.equals("messages") ? "_en.properties" : "_ru.properties"));
            var korean = resource(catalog + "_ko.properties");
            for (String key : reference.stringPropertyNames()) {
                String translated = korean.getProperty(key);
                assertNotNull(translated, key);
                assertFalse(translated.isBlank(), key);
                assertFalse(translated.matches("(?s).*[\\p{IsHan}\\p{IsCyrillic}].*"), key);
                String original = catalog.equals("messages") ? reference.getProperty(key) : key;
                assertEquals(format.matcher(original).results().map(m -> m.group()).toList(),
                    format.matcher(translated).results().map(m -> m.group()).toList(), key);
            }
        }
    }

    @Test void everyLocalizedChineseLiteralHasAKoreanTranslation() throws Exception {
        var catalog = resource("legacy_ko.properties");
        String javaString = "\"(?:\\\\.|[^\"\\\\])*\"";
        var literal = Pattern.compile("\\blocalize\\(\\s*(" + javaString
                + "(?:\\s*\\+\\s*" + javaString + ")*)\\s*\\)");
        var fragment = Pattern.compile("\"((?:\\\\.|[^\"\\\\])*)\"");
        var missing = new TreeSet<String>();
        try (var files = Files.walk(Path.of("src/main/java"))) {
            for (Path file : files.filter(p -> p.toString().endsWith(".java")).toList()) {
                var matcher = literal.matcher(Files.readString(file));
                while (matcher.find()) {
                    var parts = fragment.matcher(matcher.group(1));
                    var sourceText = new StringBuilder();
                    while (parts.find()) sourceText.append(parts.group(1).translateEscapes());
                    String source = sourceText.toString();
                    if (source.matches("(?s).*[\\p{IsHan}].*") && !catalog.containsKey(source)) missing.add(source);
                }
            }
        }
        assertTrue(missing.isEmpty(), () -> "Missing Korean display literals: " + missing);
    }

    @Test void koreanLocaleSelectionPreservesOtherPreferencesAndTechnicalIdentifiers() throws Exception {
        assertEquals("ko", LanguageManager.normalizeLanguage("ko-KR"));
        assertEquals("ko", LanguageManager.normalizeLanguage("KO_kr"));
        var ko = new LanguageManager("ko-KR");
        assertTrue(ko.usesLocalizedLiterals());
        assertEquals("기기 연결", ko.getString("button.connect"));
        assertEquals("펌웨어 관리 (CH582)", ko.localizeText("固件管理（CH582）"));
        for (String identifier : List.of("F18", "0x9F", "AHAKEY_VOICE", "Win+H", "v1.4.8", "Record")) {
            assertEquals(identifier, ko.localizeText(identifier));
        }
        assertFalse(new LanguageManager("en").usesLocalizedLiterals());
        assertEquals("固件管理（CH582）", new LanguageManager("zh").localizeText("固件管理（CH582）"));
        String oldHome = System.getProperty("user.home");
        String oldLanguage = System.getProperty("AhaKeySelectedLanguage");
        try {
            System.setProperty("user.home", home.toString());
            Path file = home.resolve(".ahakey/preferences.properties");
            Files.createDirectories(file.getParent());
            Files.writeString(file, "existing.setting=keep\n");
            var manager = new LanguageManager("en");
            manager.switchLanguage("ko");
            var prefs = new Properties();
            try (var input = Files.newInputStream(file)) { prefs.load(input); }
            assertEquals("ko", prefs.getProperty("AhaKeySelectedLanguage"));
            assertEquals("keep", prefs.getProperty("existing.setting"));
            manager.switchLanguage("en");
            assertEquals("Connect Device", manager.getString("button.connect"));
        } finally {
            System.setProperty("user.home", oldHome);
            if (oldLanguage == null) System.clearProperty("AhaKeySelectedLanguage");
            else System.setProperty("AhaKeySelectedLanguage", oldLanguage);
        }
    }
}
