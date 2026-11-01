package com.example.ahakey.protocol;

import java.util.Set;

/** Offline identities whose configuration protocol has been checked against firmware evidence.
 * This is connection capability admission, not permission to flash an image across hardware. */
public final class FirmwareCapabilities {
    private FirmwareCapabilities() {}

    public static final String HW1_BASELINE = "x1-c582-hw1-p1-1.0.0-r001";
    private static final Set<String> CONFIGURATION_IDENTITIES = Set.of(
            HW1_BASELINE,
            "x1-c582-hw1-p1-1.0.1-r001",
            "x1-c582-hw2-p1-1.0.1-r001");

    public static Set<String> configurationIdentities() { return CONFIGURATION_IDENTITIES; }

    public static boolean supportsConfiguration(String identity) {
        return identity != null && CONFIGURATION_IDENTITIES.contains(identity);
    }
}
