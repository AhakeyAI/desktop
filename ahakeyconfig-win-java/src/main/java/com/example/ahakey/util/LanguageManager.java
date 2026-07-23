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
    private static final String PREFERENCE_KEY = "AhaKeySelectedLanguage";
    
    private LanguageManager() {
        currentLanguage = loadUserPreference();
        loadResources(currentLanguage);
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
        
        return detectSystemLanguage();
    }
    
    private String detectSystemLanguage() {
        Locale locale = Locale.getDefault();
        String language = locale.getLanguage();
        if (language.equalsIgnoreCase("zh") || language.equalsIgnoreCase("zh_CN")) {
            return "zh";
        }
        return "en";
    }
    
    private void loadResources(String language) {
        currentProperties = new Properties();
        String resourceName = "/messages_" + language + ".properties";
        try (InputStream is = getClass().getResourceAsStream(resourceName)) {
            if (is != null) {
                currentProperties.load(new InputStreamReader(is, StandardCharsets.UTF_8));
            } else {
                loadResources("en");
            }
        } catch (Exception e) {
            loadResources("en");
        }
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