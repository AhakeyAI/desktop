package com.example.ahakey.firmware;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
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
import static org.junit.jupiter.api.Assertions.assertThrows;
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
        copyResource("/wchisp/wchisp-runtime.json",
            temporaryDirectory.resolve("wchisp-runtime.json"));
        copyResource("/wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH",
            temporaryDirectory.resolve("CONFIG_CH57X59X.WCH"));
        var report = new WindowsWchIspFlasher(tool).diagnoseEnvironment();

        assertTrue(report.ready());
        assertTrue(report.checks().stream().anyMatch(line ->
            line.contains("临时目录可读写")));
    }

    @Test
    void supportedLayoutContainsMultipleFixedPathSlots() throws Exception {
        byte[] bytes = baseline();
        for (int index = 0; index < WindowsWchIspFlasher.WCH_PATH_SLOT_OFFSETS.length; index++) {
            writeSlot(bytes, index, index == 0
                ? "C:\\firmware\\AhaKey-X1-firmware-1.4.7-ch582.hex"
                : "C:\\history\\slot-" + index + ".bin");
        }
        WindowsWchIspFlasher.WchConfigLayout layout =
            WindowsWchIspFlasher.inspectLayout(bytes);
        assertEquals(5, layout.slotValues().length);
        assertTrue(layout.slotValues()[0].contains("ch582"));
    }

    @Test
    void patchesOnlyCh582SlotAndPreservesAllOtherBytes() throws Exception {
        Path config = temporaryDirectory.resolve("CONFIG_CH57X59X.WCH");
        byte[] bytes = baseline();
        for (int index = 0; index < WindowsWchIspFlasher.WCH_PATH_SLOT_OFFSETS.length; index++) {
            writeSlot(bytes, index, index == 0
                ? "C:\\old\\AhaKey-ch582.hex"
                : "C:\\history\\slot-" + index + ".bin");
        }
        byte[] before = Arrays.copyOf(bytes, bytes.length);
        Files.write(config, bytes);

        Path firmware = temporaryDirectory.resolve("new-firmware.hex");
        WindowsWchIspFlasher.patchCh582FirmwarePath(config, firmware);

        byte[] updated = Files.readAllBytes(config);
        byte[] expected = firmware.toAbsolutePath().normalize()
            .toString().getBytes(StandardCharsets.UTF_16BE);
        int target = WindowsWchIspFlasher.WCH_PATH_SLOT_OFFSETS[0];
        assertTrue(indexOf(updated, expected) == target);
        for (int i = 0; i < updated.length; i++) {
            if (i < target || i >= target + WindowsWchIspFlasher.WCH_PATH_SLOT_BYTES) {
                assertEquals(before[i], updated[i], "unexpected byte change at " + i);
            }
        }
    }

    @Test
    void unknownLayoutFailsClosed() throws Exception {
        byte[] bytes = baseline();
        bytes[123] ^= 0x01;
        Path config = temporaryDirectory.resolve("unknown.WCH");
        Files.write(config, bytes);
        IOException failure = assertThrows(IOException.class, () ->
            WindowsWchIspFlasher.patchCh582FirmwarePath(config,
                temporaryDirectory.resolve("firmware.hex")));
        assertTrue(failure.getMessage().contains("Unsupported WCHISP configuration layout"));
    }

    @Test
    void pathOverCapacityFailsClosed() throws Exception {
        Path config = temporaryDirectory.resolve("CONFIG_CH57X59X.WCH");
        Files.write(config, baseline());
        Path longPath = temporaryDirectory.resolve("x".repeat(400) + ".hex");
        IOException failure = assertThrows(IOException.class, () ->
            WindowsWchIspFlasher.patchCh582FirmwarePath(config, longPath));
        assertTrue(failure.getMessage().contains("固件路径过长"));
    }

    @Test
    void malformedUtf16SlotFailsClosed() throws Exception {
        byte[] bytes = baseline();
        int offset = WindowsWchIspFlasher.WCH_PATH_SLOT_OFFSETS[0];
        bytes[offset] = 0x01;
        bytes[offset + 1] = 0x02;
        Path config = temporaryDirectory.resolve("malformed.WCH");
        Files.write(config, bytes);
        IOException failure = assertThrows(IOException.class, () ->
            WindowsWchIspFlasher.patchCh582FirmwarePath(config,
                temporaryDirectory.resolve("firmware.hex")));
        assertTrue(failure.getMessage().contains("Unsupported WCHISP configuration layout"));
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
        assertPowerShellSyntax(WindowsWchIspFlasher.captureWorkerScript());
    }

    @Test
    void runAsWrapperIsValidWindowsPowerShellSyntax() throws Exception {
        String javaSource = Files.readString(Path.of("src", "main", "java", "com",
            "example", "ahakey", "firmware", "WindowsWchIspFlasher.java"),
            StandardCharsets.UTF_8);
        var matcher = Pattern.compile(
            "String wrapperScript = \"\"\"\\R(?<script>[\\s\\S]*?)\\R\\s*\"\"\";"
        ).matcher(javaSource);
        assertTrue(matcher.find());
        assertPowerShellSyntax(matcher.group("script").replace("\\\\", "\\"));
    }

    private void assertPowerShellSyntax(String workerScript) throws Exception {
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

    @Test
    void adminAndNonAdminSelectTheSameCaptureWorkerWithoutWorkerRunAs() {
        assertEquals(WindowsWchIspFlasher.CaptureLaunchMode.DIRECT_WORKER,
            WindowsWchIspFlasher.captureLaunchMode(true));
        assertEquals(WindowsWchIspFlasher.CaptureLaunchMode.RUNAS_WORKER,
            WindowsWchIspFlasher.captureLaunchMode(false));
        String worker = WindowsWchIspFlasher.captureWorkerScript();
        assertTrue(worker.contains("GetBufferContents"));
        assertTrue(worker.contains("ReadAllText($Stdout)"));
        assertTrue(worker.contains("ReadAllText($Stderr)"));
        assertFalse(worker.contains("-Verb RunAs"));
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

    @Test
    void exit100WithEnumeratedDeviceUsesUidFailureMessage() {
        String detail = WindowsWchIspFlasher.detectionFailureDetail(
            100, true, "\nraw output");
        assertTrue(detail.contains("已检测到 WCH ISP 设备"));
        assertTrue(detail.contains("读取设备 UID 失败"));
        assertTrue(detail.contains("100"));
    }

    @Test
    void exit100WithoutEnumeratedDeviceUsesNotFoundMessage() {
        String detail = WindowsWchIspFlasher.detectionFailureDetail(100, false, "");
        assertTrue(detail.contains("未检测到 WCH ISP 设备"));
        assertFalse(detail.contains("读取设备 UID 失败"));
    }

    @Test
    void nonZeroResultRetainsAllWchIspDiagnosticArtifacts() throws Exception {
        Path runtime = temporaryDirectory.resolve("runtime");
        Files.createDirectories(runtime);
        Path executable = runtime.resolve("WCHISPTool_CH57x-59x.exe");
        Files.write(executable, new byte[]{1});
        copyResource("/wchisp/wchisp-runtime.json",
            runtime.resolve("wchisp-runtime.json"));
        Path config = temporaryDirectory.resolve("CONFIG_CH57X59X.WCH");
        copyResource("/wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH", config);
        Path destination = temporaryDirectory.resolve("wchisp-last-failure");

        String persisted = WindowsWchIspFlasher.persistDiagnosticsForTest(
            destination, executable, List.of("-c", config.toString(), "-u", "get"),
            "PROCESS_EXIT:100\nUID query failed", 100);

        assertEquals(destination.toString(), persisted);
        for (String name : List.of("command.txt", "stdout.txt", "stderr.txt",
            "console.txt", "result.txt", "runtime-version.txt", "config-fingerprint.txt")) {
            assertTrue(Files.isRegularFile(destination.resolve(name)), name);
        }
        assertTrue(Files.readString(destination.resolve("result.txt")).contains("100"));
        assertTrue(Files.readString(destination.resolve("runtime-version.txt")).contains("3.6.1"));
        assertEquals(WchIspRuntimeContract.EXPECTED_CONFIG_FINGERPRINT,
            Files.readString(destination.resolve("config-fingerprint.txt")).trim());
    }

    private byte[] baseline() throws Exception {
        try (var stream = WindowsWchIspFlasherTest.class.getResourceAsStream(
            WindowsWchIspFlasher.SANITIZED_CONFIG_RESOURCE)) {
            assertTrue(stream != null, "sanitized WCHISP fixture missing");
            return stream.readAllBytes();
        }
    }

    private void copyResource(String resource, Path destination) throws Exception {
        try (var stream = WindowsWchIspFlasherTest.class.getResourceAsStream(resource)) {
            assertTrue(stream != null, "resource missing: " + resource);
            Files.copy(stream, destination);
        }
    }

    private void writeSlot(byte[] bytes, int slot, String value) {
        int offset = WindowsWchIspFlasher.WCH_PATH_SLOT_OFFSETS[slot];
        byte[] encoded = value.getBytes(StandardCharsets.UTF_16BE);
        assertTrue(encoded.length + 2 <= WindowsWchIspFlasher.WCH_PATH_SLOT_BYTES);
        Arrays.fill(bytes, offset,
            offset + WindowsWchIspFlasher.WCH_PATH_SLOT_BYTES, (byte) 0);
        System.arraycopy(encoded, 0, bytes, offset, encoded.length);
    }
}
