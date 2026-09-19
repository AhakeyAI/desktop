package com.example.ahakey.util;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.MissingResourceException;
import java.util.Properties;

public class LanguageManager {
    
    private static LanguageManager instance;
    
    private Properties currentProperties;
    private String currentLanguage;
    private final Properties legacyRussian = readProperties("/legacy_ru.properties");
    private static final String PREFERENCE_KEY = "AhaKeySelectedLanguage";
    
    private LanguageManager() {
        currentLanguage = normalizeLanguage(loadUserPreference());
        loadResources(currentLanguage);
    }

    LanguageManager(String language) {
        currentLanguage = normalizeLanguage(language);
        loadResources(currentLanguage);
    }

    static String normalizeLanguage(String language) {
        String code = language == null ? "en" : language.toLowerCase(Locale.ROOT).split("[-_]", 2)[0];
        return switch (code) { case "zh", "ru" -> code; default -> "en"; };
    }
    
    public static synchronized LanguageManager getInstance() {
        if (instance == null) {
            instance = new LanguageManager();
        }
        return instance;
    }
    
    private String loadUserPreference() {
        try {
            String saved = System.getProperty(PREFERENCE_KEY);
            if (saved != null && !saved.isEmpty()) {
                return saved;
            }
        } catch (Exception e) {
            // ignore
        }
        
        try {
            java.io.File prefsDir = new java.io.File(
                System.getProperty("user.home"), ".ahakey"
            );
            java.io.File prefsFile = new java.io.File(prefsDir, "preferences.properties");
            if (prefsFile.exists()) {
                Properties prefs = new Properties();
                try (java.io.FileInputStream fis = new java.io.FileInputStream(prefsFile)) {
                    prefs.load(fis);
                    String savedLang = prefs.getProperty(PREFERENCE_KEY);
                    if (savedLang != null && !savedLang.isEmpty()) {
                        return savedLang;
                    }
                }
            }
        } catch (Exception e) {
            // ignore
        }
        
        return System.getProperty("ahakey.defaultLanguage", detectSystemLanguage());
    }
    
    private String detectSystemLanguage() {
        return normalizeLanguage(Locale.getDefault().getLanguage());
    }
    
    private void loadResources(String language) {
        currentProperties = readProperties("/messages_en.properties");
        currentProperties.putAll(readProperties("/messages_" + language + ".properties"));
    }

    private static Properties readProperties(String resourceName) {
        Properties properties = new Properties();
        try (InputStream is = LanguageManager.class.getResourceAsStream(resourceName)) {
            if (is != null) properties.load(new InputStreamReader(is, StandardCharsets.UTF_8));
        } catch (java.io.IOException e) {
            throw new IllegalStateException("Cannot read language resource: " + resourceName, e);
        }
        return properties;
    }

    /** Localizes legacy display literals without changing protocol or stored identifiers. */
    public static String localize(String source) {
        return getInstance().localizeText(source);
    }

    String localizeText(String source) {
        return isRussian() ? legacyRussian.getProperty(source, source) : source;
    }
    
    public String getString(String key) {
        try {
            String value = currentProperties.getProperty(key);
            if (value != null) {
                return value;
            }
        } catch (MissingResourceException e) {
            // ignore
        }
        return key;
    }
    
    public String getString(String key, Object... args) {
        String pattern = getString(key);
        if (args != null && args.length > 0) {
            return String.format(pattern, args);
        }
        return pattern;
    }
    
    public void switchLanguage(String language) {
        language = normalizeLanguage(language);
        if (!language.equalsIgnoreCase(currentLanguage)) {
            currentLanguage = language;
            saveUserPreference(language);
            loadResources(language);
            notifyLanguageChanged();
        }
    }
    
    private void saveUserPreference(String language) {
        try {
            System.setProperty(PREFERENCE_KEY, language);
            java.io.File prefsDir = new java.io.File(
                System.getProperty("user.home"), ".ahakey"
            );
            if (!prefsDir.exists()) {
                prefsDir.mkdirs();
            }
            java.io.File prefsFile = new java.io.File(prefsDir, "preferences.properties");
            Properties prefs = new Properties();
            if (prefsFile.exists()) {
                try (java.io.FileInputStream fis = new java.io.FileInputStream(prefsFile)) {
                    prefs.load(fis);
                }
            }
            prefs.setProperty(PREFERENCE_KEY, language);
            try (java.io.FileOutputStream fos = new java.io.FileOutputStream(prefsFile)) {
                prefs.store(fos, "AhaKey Studio Preferences");
            }
        } catch (Exception e) {
            // ignore
        }
    }
    
    private void notifyLanguageChanged() {
        LanguageChangeNotifier.notifyListeners();
    }
    
    public String getCurrentLanguage() {
        return currentLanguage;
    }
    
    public boolean isChinese() {
        return "zh".equalsIgnoreCase(currentLanguage);
    }

    public boolean isRussian() {
        return "ru".equals(currentLanguage);
    }
    
    public String getLanguageToggleText() {
        return getString("menu.switch-language");
    }
    
    public interface LanguageChangeListener {
        void onLanguageChanged();
    }
    
    public static class LanguageChangeNotifier {
        private static java.util.List<LanguageChangeListener> listeners = 
            new java.util.ArrayList<>();
        
        public static void addListener(LanguageChangeListener listener) {
            listeners.add(listener);
        }
        
        public static void removeListener(LanguageChangeListener listener) {
            listeners.remove(listener);
        }
        
        public static void notifyListeners() {
            for (LanguageChangeListener listener : listeners) {
                listener.onLanguageChanged();
            }
        }
    }
}
