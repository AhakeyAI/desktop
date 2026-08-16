package com.example.ahakey.view;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;

class SupportPaneTest {

    @Test
    void packagedSupportQrCodeExists() {
        assertNotNull(
            SupportPane.class.getResource("/images/support-service-qr.png")
        );
    }
}
