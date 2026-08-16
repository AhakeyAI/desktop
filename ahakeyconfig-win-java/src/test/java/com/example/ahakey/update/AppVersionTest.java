package com.example.ahakey.update;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class AppVersionTest {
    @AfterEach
    void clearVersion() {
        System.clearProperty("app.version");
    }

    @Test
    void systemPropertyOverridesBuildMetadata() {
        System.setProperty("app.version", "1.2.0");
        assertEquals(new SemanticVersion(1, 2, 0), AppVersion.current());
    }
}
