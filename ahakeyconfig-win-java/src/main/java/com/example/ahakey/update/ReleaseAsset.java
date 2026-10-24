package com.example.ahakey.update;

import java.net.URI;
import java.util.Objects;

/** A downloadable release asset validated by transport and file format. */
public record ReleaseAsset(String name, URI downloadUrl) {

    public ReleaseAsset {
        name = Objects.requireNonNull(name, "name");
        downloadUrl = Objects.requireNonNull(downloadUrl, "downloadUrl");
        boolean localTestEndpoint = "http".equalsIgnoreCase(downloadUrl.getScheme())
                && downloadUrl.getHost() != null
                && (downloadUrl.getHost().equalsIgnoreCase("localhost")
                || downloadUrl.getHost().equals("127.0.0.1")
                || downloadUrl.getHost().equals("::1"));
        if (!"https".equalsIgnoreCase(downloadUrl.getScheme()) && !localTestEndpoint) {
            throw new IllegalArgumentException("Release asset URL must use HTTPS");
        }
    }

}
