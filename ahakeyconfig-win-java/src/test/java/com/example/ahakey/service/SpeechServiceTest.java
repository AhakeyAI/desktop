package com.example.ahakey.service;

import com.example.ahakey.config.ModelConfig;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Contract tests for the restored Sherpa resource and lifecycle boundary. */
class SpeechServiceTest {
    @Test
    void bundledConfigurationUsesHistoricalSherpaContract() {
        ModelConfig config = ModelConfig.getInstance();
        assertTrue(config.isEnabled());
        assertEquals("models", config.getModelPath());
        assertEquals("STREAMING_PARAFORMER", config.getModelType());
        assertEquals("tokens.txt", config.getTokensPath());
        assertEquals(16000, config.getSampleRate());
        assertFalse(config.isVadEnabled());
    }

    @Test
    void resolverRequiresAllThreeParaformerResources() throws Exception {
        Path modelDir = Files.createTempDirectory("ahakey-sherpa-model-");
        Files.writeString(modelDir.resolve("tokens.txt"), "<blank> 0\n");
        Files.writeString(modelDir.resolve("encoder.int8.onnx"), "test encoder");
        Files.writeString(modelDir.resolve("decoder.int8.onnx"), "test decoder");

        assertEquals(modelDir.toAbsolutePath().normalize(),
            SpeechService.resolveModelDirectory(modelDir.toString()));
    }

    @Test
    void resolverRejectsSenseVoiceSingleFileLayout() throws Exception {
        Path modelDir = Files.createTempDirectory("ahakey-sherpa-incomplete-");
        Files.writeString(modelDir.resolve("model_q8.onnx"), "legacy");
        Files.writeString(modelDir.resolve("tokens.txt"), "<blank> 0\n");

        try {
            SpeechService.resolveModelDirectory(modelDir.toString());
        } catch (java.io.IOException expected) {
            assertTrue(expected.getMessage().contains("encoder.int8.onnx"));
            return;
        }
        throw new AssertionError("single-file SenseVoice layout must not be accepted");
    }

    @Test
    void resolverRejectsEmptySherpaResource() throws Exception {
        Path modelDir = Files.createTempDirectory("ahakey-sherpa-empty-");
        Files.writeString(modelDir.resolve("tokens.txt"), "<blank> 0\n");
        Files.writeString(modelDir.resolve("encoder.int8.onnx"), "");
        Files.writeString(modelDir.resolve("decoder.int8.onnx"), "valid");

        try {
            SpeechService.resolveModelDirectory(modelDir.toString());
        } catch (java.io.IOException expected) {
            assertTrue(expected.getMessage().contains("encoder.int8.onnx"));
            return;
        }
        throw new AssertionError("empty Sherpa model files must not be accepted");
    }
}
