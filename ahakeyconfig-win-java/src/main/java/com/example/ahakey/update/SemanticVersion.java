package com.example.ahakey.update;

import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * A strict three-component application/firmware version.
 *
 * <p>The optional {@code v} prefix is accepted because GitHub release tags use
 * names such as {@code v1.1.0}. Pre-release and two-component versions are
 * intentionally rejected: the release contract for AhaKey is {@code X.Y.Z}.
 */
public record SemanticVersion(int major, int minor, int patch)
        implements Comparable<SemanticVersion> {

    private static final Pattern PATTERN = Pattern.compile(
            "^[vV]?(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)$");

    public SemanticVersion {
        if (major < 0 || minor < 0 || patch < 0) {
            throw new IllegalArgumentException("Version components must be non-negative");
        }
    }

    public static SemanticVersion parse(String value) {
        Objects.requireNonNull(value, "value");
        Matcher matcher = PATTERN.matcher(value.trim());
        if (!matcher.matches()) {
            throw new IllegalArgumentException(
                    "Version must use the three-component X.Y.Z format: " + value);
        }
        try {
            return new SemanticVersion(
                    Integer.parseInt(matcher.group(1)),
                    Integer.parseInt(matcher.group(2)),
                    Integer.parseInt(matcher.group(3)));
        } catch (NumberFormatException exception) {
            throw new IllegalArgumentException("Version component is too large: " + value, exception);
        }
    }

    @Override
    public int compareTo(SemanticVersion other) {
        Objects.requireNonNull(other, "other");
        int result = Integer.compare(major, other.major);
        if (result == 0) {
            result = Integer.compare(minor, other.minor);
        }
        if (result == 0) {
            result = Integer.compare(patch, other.patch);
        }
        return result;
    }

    public boolean isNewerThan(SemanticVersion other) {
        return compareTo(other) > 0;
    }

    @Override
    public String toString() {
        return major + "." + minor + "." + patch;
    }
}
