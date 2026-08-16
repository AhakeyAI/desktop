package com.example.ahakey.firmware;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WindowsWchIspFlasherTest {
    @TempDir
    Path temporaryDirectory;

    @AfterEach
    void clearOverrides() {
        System.clearProperty("ahakey.wchisp.path");
        System.clearProperty("jpackage.app-path");
    }

    @Test
    void locatesToolInsideJpackageAppDirectory() throws Exception {
        Path launcher = temporaryDirectory.resolve("AhaKeyStudio.exe");
        Path tool = temporaryDirectory.resolve("app")
            .resolve("tools")
            .resolve("wchisp")
            .resolve("WCHISPTool_CH57x-59x.exe");
        Files.createDirectories(tool.getParent());
        Files.write(tool, new byte[]{0});
        System.setProperty("jpackage.app-path", launcher.toString());

        assertEquals(
            tool.toAbsolutePath().normalize(),
            WindowsWchIspFlasher.locateExecutable()
        );
    }

    @Test
    void diagnosesCompleteBundledToolWithoutMachineSpecificPaths() throws Exception {
        Path tool = temporaryDirectory.resolve("WCHISPTool_CH57x-59x.exe");
        Files.write(tool, new byte[]{1});
        Files.write(temporaryDirectory.resolve("CH343PT.DLL"), new byte[]{1});
        Files.write(temporaryDirectory.resolve("WCH55xISPDLL.dll"), new byte[]{1});
        Files.write(temporaryDirectory.resolve("CONFIG_CH57X59X.WCH.excluded"),
            new byte[2048]);

        var report = new WindowsWchIspFlasher(tool).diagnoseEnvironment();

        assertTrue(report.ready());
        assertTrue(report.checks().stream().anyMatch(line ->
            line.contains("临时目录可读写")));
    }

    @Test
    void patchesSingleFirmwarePathInBinaryWchConfig() throws Exception {
        Path config = temporaryDirectory.resolve("CONFIG_CH57X59X.WCH");
        byte[] bytes = new byte[700];
        Arrays.fill(bytes, (byte) 0);
        int fieldOffset = 17;
        byte[] oldPath = "C:\\old\\firmware.hex".getBytes(StandardCharsets.UTF_16LE);
        System.arraycopy(oldPath, 0, bytes, fieldOffset, oldPath.length);
        Files.write(config, bytes);

        Path firmware = temporaryDirectory.resolve("new-firmware.hex");
        WindowsWchIspFlasher.patchCh582FirmwarePath(config, firmware);

        byte[] updated = Files.readAllBytes(config);
        byte[] expected = firmware.toAbsolutePath().normalize()
            .toString()
            .getBytes(StandardCharsets.UTF_16LE);
        assertTrue(indexOf(updated, expected) == fieldOffset);
        assertEquals(0, updated[fieldOffset + expected.length]);
        assertEquals(0, updated[fieldOffset + expected.length + 1]);
    }

    @Test
    void waitsUntilWchIspReturnsItsRealTerminalResult() {
        String progressOnly = """
            {"Device":"CH582","Status":"Ready programming"}
            {"Device":"CH582","Status":"Programming","Progress":100%}
            """;
        String success = progressOnly
            + "{\"Device\":\"CH582\",\"Status\":\"Finished\",\"Code\":0,"
            + "\"Message\":\"Succeed\"}";
        String failure = """
            {"Device":"CH582","Status":"Fail","Code":5,
            "Message":"Fail to find any valid device"}
            """;

        assertNull(WindowsWchIspFlasher.terminalExitCode(progressOnly, false));
        assertEquals(0, WindowsWchIspFlasher.terminalExitCode(success, false));
        assertEquals(5, WindowsWchIspFlasher.terminalExitCode(failure, false));
    }

    @Test
    void deviceUidCompletesOnlyTheDetectionCommand() {
        String output = "Device UID:23-DF-93-5A-04-DC-BA-15";

        assertEquals(0, WindowsWchIspFlasher.terminalExitCode(output, true));
        assertNull(WindowsWchIspFlasher.terminalExitCode(output, false));
    }

    @Test
    void elevatedWorkerMarkerRequiresAnExplicitTerminalState() {
        assertEquals(0, WindowsWchIspFlasher.elevatedResultCode(
            "SUCCESS", false));
        assertEquals(5, WindowsWchIspFlasher.elevatedResultCode(
            "FAIL:5", false));
        assertEquals(124, WindowsWchIspFlasher.elevatedResultCode(
            "TIMEOUT", false));
        assertNull(WindowsWchIspFlasher.elevatedResultCode(
            "DEVICE_UID", false));
        assertEquals(0, WindowsWchIspFlasher.elevatedResultCode(
            "DEVICE_UID", true));
        assertNull(WindowsWchIspFlasher.elevatedResultCode("", false));
    }

    @Test
    void encodesPowerShellUnsafeSwitchesAsOnePositionalArgument() {
        List<String> arguments = List.of(
            "-c",
            "C:\\Temp Folder\\ch582.ini",
            "-o",
            "download",
            "-f",
            "C:\\固件\\AhaKey 1.1.1.hex"
        );

        String encoded = WindowsWchIspFlasher.encodeArguments(arguments);
        String decoded = new String(
            Base64.getDecoder().decode(encoded),
            StandardCharsets.UTF_8
        );

        assertFalse(encoded.startsWith("-"));
        assertEquals(String.join("\u0000", arguments), decoded);
    }

    @Test
    void decodesPowerShellUtf16AndUtf8ResultFiles() {
        String result =
            "{\"Status\":\"Finished\",\"Code\":0,\"Message\":\"Succeed\"}";
        byte[] utf16Body = result.getBytes(StandardCharsets.UTF_16LE);
        byte[] utf16WithBom = new byte[utf16Body.length + 2];
        utf16WithBom[0] = (byte) 0xFF;
        utf16WithBom[1] = (byte) 0xFE;
        System.arraycopy(
            utf16Body,
            0,
            utf16WithBom,
            2,
            utf16Body.length
        );
        byte[] utf8Body = result.getBytes(StandardCharsets.UTF_8);
        byte[] utf8WithBom = new byte[utf8Body.length + 3];
        utf8WithBom[0] = (byte) 0xEF;
        utf8WithBom[1] = (byte) 0xBB;
        utf8WithBom[2] = (byte) 0xBF;
        System.arraycopy(utf8Body, 0, utf8WithBom, 3, utf8Body.length);

        assertEquals(result, WindowsWchIspFlasher.decodeOutput(utf16WithBom));
        assertEquals(result, WindowsWchIspFlasher.decodeOutput(utf8WithBom));
        assertEquals(
            result,
            WindowsWchIspFlasher.decodeOutput(utf16Body)
        );
    }

    @Test
    void elevatedWorkerIsValidWindowsPowerShellSyntax() throws Exception {
        Path source = Path.of(
            "src",
            "main",
            "java",
            "com",
            "example",
            "ahakey",
            "firmware",
            "WindowsWchIspFlasher.java"
        );
        String javaSource = Files.readString(source, StandardCharsets.UTF_8);
        var matcher = Pattern.compile(
            "String workerScript = \"\"\"\\R(?<script>[\\s\\S]*?)\\R\\s*\"\"\";"
        ).matcher(javaSource);
        assertTrue(matcher.find());
        String workerScript = matcher.group("script").replace("\\\\", "\\");
        String parserCommand = """
            $source = [Console]::In.ReadToEnd()
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput(
                $source, [ref]$tokens, [ref]$errors
            )
            if ($errors.Count -gt 0) {
                $errors | ForEach-Object { $_.Message }
                exit 1
            }
            """;
        Process process = new ProcessBuilder(
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            parserCommand
        ).redirectErrorStream(true).start();
        try (var input = process.getOutputStream()) {
            input.write(workerScript.getBytes(StandardCharsets.UTF_8));
        }
        String output = new String(
            process.getInputStream().readAllBytes(),
            StandardCharsets.UTF_8
        );

        assertEquals(0, process.waitFor(), output);
    }

    private int indexOf(byte[] haystack, byte[] needle) {
        outer:
        for (int index = 0; index <= haystack.length - needle.length; index++) {
            for (int offset = 0; offset < needle.length; offset++) {
                if (haystack[index + offset] != needle[offset]) {
                    continue outer;
                }
            }
            return index;
        }
        return -1;
    }
}
