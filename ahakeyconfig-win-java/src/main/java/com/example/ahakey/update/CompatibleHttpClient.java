package com.example.ahakey.update;

import javax.net.ssl.SSLParameters;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.Objects;

/**
 * Creates HTTPS clients compatible with the mainland CloudBase download CDN.
 *
 * <p>The current {@code tcb.qcloud.la} endpoint aborts Java 17's initial
 * TLS 1.3 handshake instead of negotiating down to TLS 1.2. Restricting these
 * release/configuration requests to TLS 1.2 keeps certificate validation
 * enabled while allowing the stable manifest and its assets to be fetched.</p>
 */
final class CompatibleHttpClient {
    private CompatibleHttpClient() {
    }

    static HttpClient create(Duration connectTimeout) {
        Objects.requireNonNull(connectTimeout, "connectTimeout");
        SSLParameters sslParameters = new SSLParameters();
        sslParameters.setProtocols(new String[]{"TLSv1.2"});
        return HttpClient.newBuilder()
            .connectTimeout(connectTimeout)
            .sslParameters(sslParameters)
            .build();
    }
}
