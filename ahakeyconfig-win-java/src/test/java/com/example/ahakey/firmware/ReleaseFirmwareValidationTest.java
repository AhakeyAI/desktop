package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.io.TempDir;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ReleaseFirmwareValidationTest {
    @TempDir
    Path temporary;

    @Test
    void releaseRequiresExplicitFirmwareVersion() throws Exception {
        Path hex = hex("AhaKey-X1-firmware-1.4.7-ch582.hex", "1.4.7");
        Result result = run("-FirmwareHex", hex.toString(), "-PrepareOnly");
        assertFalse(result.success());
        assertTrue(result.output().contains("FirmwareVersion"));
    }

    @Test
    void releaseRejectsVersionDifferentFromBundledVersion() throws Exception {
        Result result = run("-FirmwareVersion", "1.4.3", "-PrepareOnly");
        assertFalse(result.success());
        assertTrue(result.output().contains("expectedBundledVersion 1.4.7"));
        Result newer = run("-FirmwareVersion", "1.4.8", "-PrepareOnly");
        assertFalse(newer.success());
        assertTrue(newer.output().contains("expectedBundledVersion 1.4.7"));
    }

    @Test
    void releaseRejectsFirmwareFilenameVersionMismatch() throws Exception {
        Path hex = hex("AhaKey-X1-firmware-1.4.3-ch582.hex", "1.4.7");
        Result result = run(
            "-FirmwareVersion", "1.4.7", "-FirmwareHex", hex.toString(),
            "-PrepareOnly");
        assertFalse(result.success());
        assertTrue(result.output().contains("must be named exactly"));
    }

    @Test
    void validFirmwareInputReachesLaterReleasePrerequisite() throws Exception {
        Path hex = hex("AhaKey-X1-firmware-1.4.7-ch582.hex", "1.4.7");
        Result result = run(
            "-FirmwareVersion", "1.4.7", "-FirmwareHex", hex.toString(),
            "-BaselineInstallDir", temporary.resolve("missing-baseline").toString(),
            "-PrepareOnly");
        assertFalse(result.success());
        assertTrue(result.output().contains("Release baseline icon is missing"), result.output());
        assertFalse(result.output().contains("Firmware filename version"));
    }

    @Test
    void formalReleaseRejectsMissingHexBeforePackaging() throws Exception {
        Result result = run("-FirmwareVersion", "1.4.7");
        assertFalse(result.success());
        assertTrue(result.output().contains("requires -FirmwareHex"));
    }

    @Test
    void compatibilityInstallerAllowsPrepareOnlyWithoutFirmwareArguments() throws Exception {
        Result result = runScript("build-installer.ps1",
            "-AppVersion", "1.5.3",
            "-BaselineInstallDir", temporary.resolve("missing-baseline").toString(),
            "-PrepareOnly");
        assertFalse(result.success());
        assertTrue(result.output().contains("Release baseline icon is missing"));
        assertFalse(result.output().contains("Mandatory"));
        assertFalse(result.output().contains("requires -FirmwareHex"));
    }

    @Test
    void releaseRejectsMissingOrMismatchedProvenance() throws Exception {
        Path hex = temporary.resolve("AhaKey-X1-firmware-1.4.7-ch582.hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n",
            StandardCharsets.US_ASCII);
        Result missing = run("-FirmwareVersion", "1.4.7", "-FirmwareHex",
            hex.toString(), "-PrepareOnly");
        assertFalse(missing.success());
        assertTrue(missing.output().contains("provenance is missing"), missing.output());

        Files.writeString(temporary.resolve(
            "AhaKey-X1-firmware-1.4.7-ch582.provenance.json"),
            provenance("1.4.3"), StandardCharsets.UTF_8);
        Result mismatch = run("-FirmwareVersion", "1.4.7", "-FirmwareHex",
            hex.toString(), "-PrepareOnly");
        assertFalse(mismatch.success());
        assertTrue(mismatch.output().contains("must exactly match 1.4.7"));
    }

    @Test
    void releaseRejectsInvalidIntelHexEvenWhenRenamedToBundledName() throws Exception {
        Path hex = temporary.resolve("AhaKey-X1-firmware-1.4.7-ch582.hex");
        Files.writeString(hex, ":0400000001020304F3\n:00000001FF\n",
            StandardCharsets.US_ASCII);
        Files.writeString(temporary.resolve(
            "AhaKey-X1-firmware-1.4.7-ch582.provenance.json"),
            provenance("1.4.7"), StandardCharsets.UTF_8);
        Result result = run("-FirmwareVersion", "1.4.7", "-FirmwareHex",
            hex.toString(), "-PrepareOnly");
        assertFalse(result.success());
        assertTrue(result.output().contains("checksum is invalid"));
    }

    @Test
    void releaseRejectsIntelHexOutsideLinkerAddressContract() throws Exception {
        Path hex = temporary.resolve("AhaKey-X1-firmware-1.4.7-ch582.hex");
        Files.writeString(hex,
            ":020000040007F3\n:01000000AA55\n:00000001FF\n",
            StandardCharsets.US_ASCII);
        Files.writeString(temporary.resolve(
            "AhaKey-X1-firmware-1.4.7-ch582.provenance.json"),
            provenance("1.4.7"), StandardCharsets.UTF_8);
        Result result = run("-FirmwareVersion", "1.4.7", "-FirmwareHex",
            hex.toString(), "-PrepareOnly");
        assertFalse(result.success());
        assertTrue(result.output().contains("address exceeds"), result.output());
    }

    private Path hex(String name, String provenanceVersion) throws Exception {
        Path path = temporary.resolve(name);
        Files.writeString(path, ":0400000001020304F2\n:00000001FF\n",
            StandardCharsets.US_ASCII);
        Files.writeString(temporary.resolve(name.replace(".hex", ".provenance.json")),
            provenance(provenanceVersion),
            StandardCharsets.UTF_8);
        return path;
    }

    @Test
    void releaseRequiresCompleteCrossEndProvenanceContract() throws Exception {
        Path hex = temporary.resolve("AhaKey-X1-firmware-1.4.7-ch582.hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n",
            StandardCharsets.US_ASCII);
        Path provenance = temporary.resolve(
            "AhaKey-X1-firmware-1.4.7-ch582.provenance.json");
        Files.writeString(provenance,
            provenance("1.4.7").replace("\"protocolVersion\":\"3.2\"",
                "\"protocolVersion\":\"3.1\""), StandardCharsets.UTF_8);
        Result wrongProtocol = run("-FirmwareVersion", "1.4.7", "-FirmwareHex",
            hex.toString(), "-PrepareOnly");
        assertFalse(wrongProtocol.success());
        assertTrue(wrongProtocol.output().contains(
            "protocolVersion must exactly match 3.2"), wrongProtocol.output());

        Files.writeString(provenance,
            provenance("1.4.7").replace("\"sourceCommit\":\"1234567\"",
                "\"sourceCommit\":\"not-a-commit\""), StandardCharsets.UTF_8);
        Result invalidSource = run("-FirmwareVersion", "1.4.7", "-FirmwareHex",
            hex.toString(), "-PrepareOnly");
        assertFalse(invalidSource.success());
        assertTrue(invalidSource.output().contains("sourceCommit"));
    }

    @Test
    void powershell7AcceptsCanonicalProvenanceAndRejectsFractionalTimestamp() throws Exception {
        Path pwsh = findPwsh();
        Assumptions.assumeTrue(pwsh != null, "pwsh 7 is not installed");
        Path hex = temporary.resolve("AhaKey-X1-firmware-1.4.7-ch582.hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n",
            StandardCharsets.US_ASCII);
        Path provenance = temporary.resolve(
            "AhaKey-X1-firmware-1.4.7-ch582.provenance.json");
        Files.writeString(provenance, provenance("1.4.7"), StandardCharsets.UTF_8);
        Result valid = runScript(pwsh, "build-release-installer.ps1",
            "-AppVersion", "1.5.3", "-FirmwareVersion", "1.4.7",
            "-FirmwareHex", hex.toString(),
            "-BaselineInstallDir", temporary.resolve("missing-baseline").toString(),
            "-PrepareOnly");
        assertFalse(valid.success());
        assertTrue(valid.output().contains("Release baseline icon is missing"), valid.output());

        Files.writeString(provenance,
            provenance("1.4.7").replace("2026-08-26T00:00:00Z",
                "2026-08-26T00:00:00.123Z"), StandardCharsets.UTF_8);
        Result fractional = runScript(pwsh, "build-release-installer.ps1",
            "-AppVersion", "1.5.3", "-FirmwareVersion", "1.4.7",
            "-FirmwareHex", hex.toString(), "-PrepareOnly");
        assertFalse(fractional.success());
        assertTrue(fractional.output().contains("builtAtUtc"));
    }

    private static String provenance(String version) {
        return "{\"firmwareVersion\":\"" + version + "\","
            + "\"deviceModel\":\"AhaKey-X1\","
            + "\"protocolVersion\":\"3.2\","
            + "\"capabilityMask\":\"0x7FF\","
            + "\"sourceCommit\":\"1234567\","
            + "\"buildCommand\":\"make release\","
            + "\"builtAtUtc\":\"2026-08-26T00:00:00Z\"}\n";
    }

    private Result run(String... arguments) throws Exception {
        List<String> allArguments = new ArrayList<>();
        allArguments.add("-AppVersion");
        allArguments.add("1.5.3");
        allArguments.addAll(List.of(arguments));
        return runScript("build-release-installer.ps1",
            allArguments.toArray(String[]::new));
    }

    private Result runScript(String script, String... arguments) throws Exception {
        String systemRoot = System.getenv("SystemRoot");
        Path powershell = Path.of(systemRoot, "System32", "WindowsPowerShell",
            "v1.0", "powershell.exe");
        return runScript(powershell, script, arguments);
    }

    private Result runScript(Path powershell, String script, String... arguments) throws Exception {
        List<String> command = new ArrayList<>();
        command.add(powershell.toString());
        command.add("-NoLogo");
        command.add("-NoProfile");
        command.add("-NonInteractive");
        command.add("-ExecutionPolicy");
        command.add("Bypass");
        command.add("-File");
        command.add(Path.of(script).toAbsolutePath().toString());
        command.addAll(List.of(arguments));
        Process process = new ProcessBuilder(command)
            .redirectErrorStream(true)
            .start();
        String output = new String(process.getInputStream().readAllBytes(),
            StandardCharsets.UTF_8);
        int exit = process.waitFor();
        return new Result(exit == 0, output);
    }

    private static Path findPwsh() throws Exception {
        Process process = new ProcessBuilder("where.exe", "pwsh")
            .redirectErrorStream(true).start();
        String output = new String(process.getInputStream().readAllBytes(),
            StandardCharsets.UTF_8).trim();
        process.waitFor();
        if (output.isBlank()) return null;
        Path candidate = Path.of(output.lines().findFirst().orElse("").trim());
        return Files.isRegularFile(candidate) ? candidate : null;
    }

    private record Result(boolean success, String output) {}
}
