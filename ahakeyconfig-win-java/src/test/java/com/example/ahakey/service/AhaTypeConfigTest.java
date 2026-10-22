package com.example.ahakey.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AhaTypeConfigTest {
    @TempDir
    Path tempDir;

    @Test
    void usesTheTypelessConfigSchemaAndRoundTripsUnknownFields() throws Exception {
        Path path = tempDir.resolve("typeless_config.json");
        AhaTypeConfig config = new AhaTypeConfig(path);
        Map<String, Object> values = AhaTypeConfig.defaults();
        values.put(AhaTypeConfig.ENABLED, true);
        values.put(AhaTypeConfig.REMEMBER_PASSWORD, true);
        values.put(AhaTypeConfig.REMEMBERED_PHONE, "13800000000");
        values.put("future_field", "preserved");

        config.save(values);
        Map<String, Object> loaded = config.load();

        assertTrue(Files.isRegularFile(path));
        assertTrue((Boolean) loaded.get(AhaTypeConfig.ENABLED));
        assertTrue((Boolean) loaded.get(AhaTypeConfig.REMEMBER_PASSWORD));
        assertEquals("13800000000", loaded.get(AhaTypeConfig.REMEMBERED_PHONE));
        assertEquals("preserved", loaded.get("future_field"));
        assertFalse(config.path().toString().contains("access_token="));
    }
}
