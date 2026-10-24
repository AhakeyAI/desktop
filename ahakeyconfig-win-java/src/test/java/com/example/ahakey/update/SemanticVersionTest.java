package com.example.ahakey.update;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SemanticVersionTest {

    @Test
    void parsesReleaseTagsAndComparesAllThreeComponents() {
        assertEquals(new SemanticVersion(1, 2, 3), SemanticVersion.parse("v1.2.3"));
        assertTrue(SemanticVersion.parse("1.10.0").isNewerThan(SemanticVersion.parse("1.9.99")));
        assertTrue(SemanticVersion.parse("2.0.0").isNewerThan(SemanticVersion.parse("1.99.99")));
        assertTrue(SemanticVersion.parse("1.2.4").isNewerThan(SemanticVersion.parse("1.2.3")));
    }

    @Test
    void rejectsNonContractVersions() {
        assertThrows(IllegalArgumentException.class, () -> SemanticVersion.parse("1.2"));
        assertThrows(IllegalArgumentException.class, () -> SemanticVersion.parse("1.2.3-beta"));
        assertThrows(IllegalArgumentException.class, () -> SemanticVersion.parse("01.2.3"));
    }
}
