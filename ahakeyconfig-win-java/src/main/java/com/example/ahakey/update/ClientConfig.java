package com.example.ahakey.update;

import java.net.URI;
import java.util.Optional;

/** Remotely changeable, non-secret client configuration. */
public record ClientConfig(Optional<URI> supportUrl) {

    public static final ClientConfig EMPTY = new ClientConfig(Optional.empty());

    public ClientConfig {
        supportUrl = supportUrl == null ? Optional.empty() : supportUrl;
        supportUrl.ifPresent(ClientConfig::requireHttps);
    }

    public static ClientConfig ofSupportUrl(String value) {
        if (value == null || value.isBlank()) {
            return EMPTY;
        }
        try {
            return new ClientConfig(Optional.of(URI.create(value.trim())));
        } catch (IllegalArgumentException exception) {
            throw new IllegalArgumentException("Invalid support URL", exception);
        }
    }

    private static void requireHttps(URI uri) {
        if (!uri.isAbsolute()
                || !"https".equalsIgnoreCase(uri.getScheme())
                || uri.getHost() == null
                || uri.getHost().isBlank()
                || uri.getUserInfo() != null) {
            throw new IllegalArgumentException("Support URL must be an absolute HTTPS URL");
        }
    }
}
