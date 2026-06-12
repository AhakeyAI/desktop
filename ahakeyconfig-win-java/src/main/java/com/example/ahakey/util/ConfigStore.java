package com.example.ahakey.util;

import com.example.ahakey.model.KeyConfig;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.List;

public class ConfigStore {
    private static final ObjectMapper mapper = new ObjectMapper();
    private static final String CONFIG_DIR = System.getProperty("user.home") + 
                                           File.separator + ".ahakey";
    private static final String KEY_MAPPING_FILE = CONFIG_DIR + File.separator + "key_mapping.json";
    
    public static void saveKeyMappings(List<KeyConfig> keys) {
        try {
            File dir = new File(CONFIG_DIR);
            if (!dir.exists()) {
                dir.mkdirs();
            }
            
            mapper.writerWithDefaultPrettyPrinter().writeValue(new File(KEY_MAPPING_FILE), keys);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
    
    public static List<KeyConfig> loadKeyMappings() {
        File file = new File(KEY_MAPPING_FILE);
        if (!file.exists()) {
            return getDefaultKeyMappings();
        }
        
        try {
            List<KeyConfig> configs = mapper.readValue(file, new TypeReference<List<KeyConfig>>() {});
            if (configs.size() == 4) {
                return configs;
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        
        return getDefaultKeyMappings();
    }
    
    private static List<KeyConfig> getDefaultKeyMappings() {
        return Arrays.asList(
            new KeyConfig(0x6D, "Record"),      // F18
            new KeyConfig(0x28, "Enter"),       // Enter
            new KeyConfig(0x29, "Escape"),      // Escape
            new KeyConfig(0x28, "Enter")        // Enter
        );
    }
    
    public static void save(String key, Object value) {
        try {
            File dir = new File(CONFIG_DIR);
            if (!dir.exists()) {
                dir.mkdirs();
            }
            
            String filePath = CONFIG_DIR + File.separator + key + ".json";
            mapper.writerWithDefaultPrettyPrinter().writeValue(new File(filePath), value);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
    
    public static <T> T load(String key, Class<T> type) {
        File file = new File(CONFIG_DIR + File.separator + key + ".json");
        if (!file.exists()) {
            return null;
        }
        
        try {
            return mapper.readValue(file, type);
        } catch (IOException e) {
            e.printStackTrace();
            return null;
        }
    }
}