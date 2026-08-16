package com.example.ahakey.update;

import org.junit.jupiter.api.Test;

import java.time.Duration;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;

class CompatibleHttpClientTest {
    @Test
    void usesTls12AndRequestedConnectTimeout() {
        var client = CompatibleHttpClient.create(Duration.ofSeconds(7));

        assertArrayEquals(
            new String[]{"TLSv1.2"},
            client.sslParameters().getProtocols());
        assertEquals(Duration.ofSeconds(7), client.connectTimeout().orElseThrow());
    }
}
