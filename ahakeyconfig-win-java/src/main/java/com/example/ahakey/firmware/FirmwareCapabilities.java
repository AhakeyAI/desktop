package com.example.ahakey.firmware;

import com.example.ahakey.update.SemanticVersion;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

/** Shared firmware versions and capability gates exposed by the Windows client. */
public final class FirmwareCapabilities {
    private static final Properties VALUES = load();
    public static final SemanticVersion MINIMUM_GIF_VERSION = SemanticVersion.parse(
        required("minimumGifVersion"));
    public static final SemanticVersion MINIMUM_STABILIZED_VERSION = SemanticVersion.parse(
        required("minimumStabilizedFirmwareVersion"));
    /** Minimum 0x9F-reported firmware that emits raw F18 DOWN/UP events. */
    public static final SemanticVersion MINIMUM_RAW_F18_DESKTOP_VERSION = SemanticVersion.parse(
        required("minimumRawF18DesktopVersion"));
    /** Publisher-declared version expected when a real HEX is supplied. */
    public static final SemanticVersion BUNDLED_VERSION = SemanticVersion.parse(
        required("expectedBundledVersion"));
    public static final String BUNDLED_FIRMWARE_NAME =
        "AhaKey-X1-firmware-" + BUNDLED_VERSION + "-ch582.hex";
    /** Stable filename used by the installed application's firmware directory. */
    public static final String INSTALLED_BUNDLED_FIRMWARE_NAME =
        "AhaKey-X1-firmware.hex";
    public static final int REQUIRED_PROTOCOL_MAJOR;
    public static final int REQUIRED_PROTOCOL_MINOR;
    public static final long REQUIRED_CAPABILITY_MASK =
        Long.decode(required("requiredCapabilityMask"));
    public static final int REQUIRED_DEVICE_MODEL =
        Integer.parseInt(required("requiredDeviceModel"));
    public static final String REQUIRED_DEVICE_MODEL_NAME =
        required("requiredDeviceModelName");
    /** Inclusive absolute address ceiling from the CH582 release linker contract. */
    public static final long MAX_FIRMWARE_ADDRESS =
        Long.decode(required("maxFirmwareAddress"));

    static {
        String[] protocol = required("requiredProtocolVersion").split("\\.", -1);
        if (protocol.length != 2) {
            throw new IllegalStateException("requiredProtocolVersion must be MAJOR.MINOR");
        }
        REQUIRED_PROTOCOL_MAJOR = Integer.parseInt(protocol[0]);
        REQUIRED_PROTOCOL_MINOR = Integer.parseInt(protocol[1]);
        if (REQUIRED_CAPABILITY_MASK != AhaKeyProtocol.REQUIRED_STABILIZED_CAPABILITY_MASK) {
            throw new IllegalStateException("Firmware capability mask disagrees with protocol constants");
        }
    }

    private FirmwareCapabilities() {}

    private static Properties load() {
        try (InputStream input = FirmwareCapabilities.class.getResourceAsStream(
            "/firmware-capabilities.properties")) {
            if (input == null) {
                throw new IllegalStateException("firmware-capabilities.properties is missing");
            }
            Properties values = new Properties();
            values.load(input);
            return values;
        } catch (IOException exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }

    private static String required(String name) {
        String value = VALUES.getProperty(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing firmware capability property: " + name);
        }
        return value.trim();
    }

    public static boolean supportsGif(SemanticVersion version) {
        return version != null && version.compareTo(MINIMUM_GIF_VERSION) >= 0;
    }

    /**
     * The desktop F18 press/hold state machine is only safe for firmware that
     * reports the raw F18 key. Unknown versions deliberately fail closed.
     */
    public static boolean supportsRawF18DesktopRouting(SemanticVersion version) {
        return version != null && version.compareTo(MINIMUM_RAW_F18_DESKTOP_VERSION) >= 0;
    }

    public static void requireStabilizedContract(
        AhaKeyResponseParser.DeviceCapabilities capabilities
    ) {
        if (capabilities == null) {
            throw new IllegalStateException("Device did not return the 0x9F capability contract");
        }
        SemanticVersion firmware = new SemanticVersion(
            capabilities.firmwareMajor(), capabilities.firmwareMinor(),
            capabilities.firmwarePatch());
        if (capabilities.deviceModel() != REQUIRED_DEVICE_MODEL) {
            throw new IllegalStateException("Unsupported device model: "
                + capabilities.deviceModel());
        }
        if (capabilities.protocolMajor() != REQUIRED_PROTOCOL_MAJOR
            || capabilities.protocolMinor() != REQUIRED_PROTOCOL_MINOR) {
            throw new IllegalStateException("Protocol contract must be "
                + REQUIRED_PROTOCOL_MAJOR + "." + REQUIRED_PROTOCOL_MINOR);
        }
        if (firmware.compareTo(MINIMUM_STABILIZED_VERSION) < 0) {
            throw new IllegalStateException("Firmware " + firmware
                + " is below stabilized minimum " + MINIMUM_STABILIZED_VERSION);
        }
        if ((capabilities.capabilityBits() & REQUIRED_CAPABILITY_MASK)
            != REQUIRED_CAPABILITY_MASK) {
            throw new IllegalStateException(String.format(
                "Capability mask 0x%X does not satisfy required 0x%X",
                capabilities.capabilityBits(), REQUIRED_CAPABILITY_MASK));
        }
    }
}
