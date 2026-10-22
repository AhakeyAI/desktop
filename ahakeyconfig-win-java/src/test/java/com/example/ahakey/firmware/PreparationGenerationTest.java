package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PreparationGenerationTest {
    @Test
    void stalePreparationCannotReplaceLatestSession() {
        PreparationGeneration generations = new PreparationGeneration();
        long first = generations.begin();
        long second = generations.begin();

        assertFalse(generations.isCurrent(first));
        assertTrue(generations.isCurrent(second));
        generations.invalidate();
        assertFalse(generations.isCurrent(second));
    }
}
