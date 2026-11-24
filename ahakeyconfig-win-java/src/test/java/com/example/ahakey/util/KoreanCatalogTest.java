package com.example.ahakey.util;

import org.junit.jupiter.api.Test;

import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Properties;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;

/** The Korean build must not show Chinese or untranslated text. */
class KoreanCatalogTest {
    private static final Pattern FORMAT = Pattern.compile("%(?:\\d+\\$)?[-#+ 0,(]*\\d*(?:\\.\\d+)?[a-zA-Z%]");
    private static final Pattern HAN = Pattern.compile("[\\x{3400}-\\x{9fff}\\x{f900}-\\x{faff}]");
    private static final Pattern LOCALIZE = Pattern.compile("(?<![A-Za-z0-9_$])localize\\(");

    private Properties resource(String name) throws Exception {
        Properties p = new Properties();
        try (var reader = new InputStreamReader(Objects.requireNonNull(
            getClass().getResourceAsStream("/" + name), name), StandardCharsets.UTF_8)) {
            p.load(reader);
        }
        return p;
    }

    private static List<String> formats(String text) {
        return FORMAT.matcher(text).results().map(java.util.regex.MatchResult::group).toList();
    }

    private static long slf4jPlaceholders(String text) {
        return Pattern.compile("\\{\\}").matcher(text).results().count();
    }

    @Test void koreanCoversEveryEnglishKeyWithoutChinese() throws Exception {
        var english = resource("messages_en.properties");
        var korean = resource("messages_ko.properties");
        var problems = new ArrayList<String>();
        for (String key : new TreeSet<>(english.stringPropertyNames())) {
            String value = korean.getProperty(key);
            if (value == null || value.isBlank()) { problems.add("missing " + key); continue; }
            if (HAN.matcher(value).find()) problems.add("chinese " + key);
            if (!formats(english.getProperty(key)).equals(formats(value))) problems.add("format " + key);
        }
        assertEquals(List.of(), problems);
    }

    @Test void legacyKoreanKeepsPlaceholdersAndHasNoChinese() throws Exception {
        var catalog = resource("legacy_ko.properties");
        var problems = new ArrayList<String>();
        for (String source : new TreeSet<>(catalog.stringPropertyNames())) {
            String translated = catalog.getProperty(source);
            if (translated.isBlank()) problems.add("blank " + source);
            if (HAN.matcher(translated).find()) problems.add("chinese " + source);
            if (!formats(source).equals(formats(translated))) problems.add("format " + source);
            if (slf4jPlaceholders(source) != slf4jPlaceholders(translated)) problems.add("{} " + source);
        }
        assertEquals(List.of(), problems);
    }

    @Test void everyChineseLocalizeLiteralHasKorean() throws Exception {
        var catalog = resource("legacy_ko.properties");
        var missing = new TreeSet<String>();
        try (Stream<Path> files = Files.walk(Path.of("src/main/java"))) {
            for (Path file : files.filter(p -> p.toString().endsWith(".java")).toList()) {
                String source = Files.readString(file);
                Matcher matcher = LOCALIZE.matcher(source);
                while (matcher.find()) {
                    String literal = literalArgument(source, matcher.end());
                    if (literal != null && HAN.matcher(literal).find() && catalog.getProperty(literal) == null) {
                        missing.add(file.getFileName() + ": " + literal);
                    }
                }
            }
        }
        assertEquals(new TreeSet<String>(), missing);
    }

    @Test void koreanSelectionUsesKoreanCatalogs() {
        var ko = new LanguageManager("ko-KR");
        assertTrue(ko.isKorean());
        assertTrue(ko.usesChineseSourceText());
        assertEquals("ko", LanguageManager.normalizeLanguage("ko_KR"));
        assertFalse(HAN.matcher(ko.getString("button.connect")).find());
        assertFalse(HAN.matcher(ko.localizeText("固件管理（CH582）")).find());
        assertEquals("v1.4.8", ko.localizeText("v1.4.8"));
    }

    /** Concatenated string literals directly inside localize(...), or null when dynamic. */
    static String literalArgument(String source, int index) {
        StringBuilder value = new StringBuilder();
        int i = index;
        while (true) {
            i = skipSpace(source, i);
            if (i >= source.length() || source.charAt(i) != '"' || source.startsWith("\"\"\"", i)) return null;
            i++;
            while (i < source.length() && source.charAt(i) != '"') {
                char c = source.charAt(i);
                if (c == '\n') return null;
                if (c == '\\') {
                    char n = source.charAt(i + 1);
                    if (n == 'u') {
                        int k = i + 1;
                        while (source.charAt(k) == 'u') k++;
                        value.append((char) Integer.parseInt(source.substring(k, k + 4), 16));
                        i = k + 4;
                        continue;
                    }
                    if (n >= '0' && n <= '7') {
                        int k = i + 1;
                        StringBuilder digits = new StringBuilder();
                        while (k < source.length() && digits.length() < 3
                            && source.charAt(k) >= '0' && source.charAt(k) <= '7') digits.append(source.charAt(k++));
                        value.append((char) Integer.parseInt(digits.toString(), 8));
                        i = k;
                        continue;
                    }
                    value.append(switch (n) {
                        case 'n' -> '\n'; case 't' -> '\t'; case 'r' -> '\r'; case 'f' -> '\f';
                        case 'b' -> '\b'; case 's' -> ' '; default -> n;
                    });
                    i += 2;
                    continue;
                }
                value.append(c);
                i++;
            }
            i = skipSpace(source, i + 1);
            if (i < source.length() && source.charAt(i) == '+') { i++; continue; }
            return i < source.length() && source.charAt(i) == ')' ? value.toString() : null;
        }
    }

    private static int skipSpace(String source, int i) {
        while (i < source.length()) {
            char c = source.charAt(i);
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') i++;
            else if (source.startsWith("//", i)) { int end = source.indexOf('\n', i); i = end < 0 ? source.length() : end; }
            else if (source.startsWith("/*", i)) { int end = source.indexOf("*/", i); i = end < 0 ? source.length() : end + 2; }
            else break;
        }
        return i;
    }
}
