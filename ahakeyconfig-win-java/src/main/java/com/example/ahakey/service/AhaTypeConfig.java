package com.example.ahakey.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.LinkedHashMap;
import java.util.Map;

/** Persistent, user-scoped AhaType session/configuration storage. */
public final class AhaTypeConfig {
    public static final String ENABLED = "typeless_enabled";
    public static final String ACCESS_TOKEN = "access_token";
    public static final String USER = "user";
    public static final String TOKEN_VALID_UNTIL = "token_valid_until";
    public static final String REMEMBER_PASSWORD = "remember_password";
    public static final String REMEMBERED_PHONE = "remembered_phone";
    public static final String REMEMBERED_PASSWORD = "remembered_password";

    private static final String[] QUOTA_FIELDS = {
        "limit_daily", "limit_weekly", "limit_monthly",
        "used_daily", "used_weekly", "used_monthly"
    };

    private final Path path;
    private final ObjectMapper mapper;

    public AhaTypeConfig() {
        this(defaultPath(), new ObjectMapper());
    }

    public AhaTypeConfig(Path path) {
        this(path, new ObjectMapper());
    }

    AhaTypeConfig(Path path, ObjectMapper mapper) {
        this.path = path.toAbsolutePath().normalize();
        this.mapper = mapper;
    }

    public static Path defaultPath() {
        return Path.of(System.getProperty("user.home", "."), ".ahakey", "typeless_config.json");
    }

    public Path path() {
        return path;
    }

    public Map<String, Object> load() throws IOException {
        if (!Files.isRegularFile(path)) {
            return defaults();
        }
        Map<String, Object> loaded = mapper.readValue(
            Files.readString(path), new TypeReference<Map<String, Object>>() { });
        Map<String, Object> result = defaults();
        if (loaded != null) {
            result.putAll(loaded);
        }
        return result;
    }

    public void save(Map<String, Object> values) throws IOException {
        Map<String, Object> copy = defaults();
        if (values != null) {
            copy.putAll(values);
        }
        Path parent = path.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        Path temporary = Files.createTempFile(parent, "typeless_config", ".tmp");
        try {
            Files.writeString(temporary, mapper.writerWithDefaultPrettyPrinter().writeValueAsString(copy));
            Files.move(temporary, path, StandardCopyOption.REPLACE_EXISTING);
        } finally {
            Files.deleteIfExists(temporary);
        }
    }

    public static Map<String, Object> defaults() {
        Map<String, Object> defaults = new LinkedHashMap<>();
        defaults.put(ENABLED, false);
        defaults.put(ACCESS_TOKEN, "");
        defaults.put(USER, null);
        defaults.put(TOKEN_VALID_UNTIL, null);
        defaults.put(REMEMBER_PASSWORD, false);
        defaults.put(REMEMBERED_PHONE, "");
        defaults.put(REMEMBERED_PASSWORD, "");
        for (String field : QUOTA_FIELDS) {
            defaults.put(field, 0);
        }
        return defaults;
    }

    public static String[] quotaFields() {
        return QUOTA_FIELDS.clone();
    }
}
