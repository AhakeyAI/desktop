package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.List;
import java.util.jar.JarEntry;
import java.util.jar.JarOutputStream;
import java.nio.file.Files;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ReleaseArtifactContentsTest {
    private static final List<String> REQUIRED = List.of(
        "com/example/ahakey/protocol/AhaKeyProtocol.class",
        "com/example/ahakey/protocol/AhaKeyResponseParser.class",
        "com/example/ahakey/app/WorkModeSynchronizer.class",
        "com/example/ahakey/app/ManualApprovalGate.class",
        "com/example/ahakey/service/ApprovalService.class",
        "com/example/ahakey/service/ApprovalSnapshot.class",
        "com/example/ahakey/service/ApprovalState.class",
        "com/example/ahakey/service/PhysicalStatusFreshness.class",
        "com/example/ahakey/service/BleManager.class",
        "com/example/ahakey/service/KimiAhaKeyBridge.class",
        "com/example/ahakey/service/UsbHidTransport.class",
        "com/example/ahakey/service/GifUploadRules.class",
        "com/example/ahakey/service/LightOperationCoordinator.class",
        "com/example/ahakey/service/BleBridgeProcessOwner.class",
        "com/example/ahakey/service/ScreenAnimationAssetStore.class",
        "com/example/ahakey/service/BleDriverLocator.class",
        "com/example/ahakey/app/ApplicationLifecycle.class",
        "com/example/ahakey/SingleInstanceChecker.class",
        "com/example/ahakey/firmware/IntelHexValidator.class",
        "com/example/ahakey/firmware/FirmwareUpdateService.class",
        "com/example/ahakey/firmware/FirmwareUpdateState.class",
        "com/example/ahakey/firmware/FirmwareUpdateError.class",
        "com/example/ahakey/firmware/FirmwareOperationHandle.class",
        "com/example/ahakey/firmware/FirmwareUpdateRequest.class",
        "com/example/ahakey/firmware/FirmwareUpdateResult.class",
        "com/example/ahakey/firmware/FirmwareUpdateStatus.class",
        "com/example/ahakey/firmware/RuntimeBundle.class",
        "com/example/ahakey/firmware/RuntimeIdentity.class",
        "com/example/ahakey/firmware/RuntimeProvider.class",
        "com/example/ahakey/firmware/WchIspRuntimeProvider.class",
        "com/example/ahakey/firmware/WchIspWorkspace.class",
        "com/example/ahakey/firmware/WchIspRunner.class",
        "com/example/ahakey/firmware/WchIspResultParser.class",
        "com/example/ahakey/firmware/IspDeviceProbe.class",
        "com/example/ahakey/firmware/ChipMatched.class",
        "com/example/ahakey/firmware/FirmwareUpdateDiagnostics.class",
        "com/example/ahakey/firmware/FirmwarePostVerifier.class",
        "com/example/ahakey/firmware/WchIspConfigLayout.class",
        "com/example/ahakey/firmware/OfficialWchIspAdapter.class",
        "com/example/ahakey/firmware/DefaultOfficialWchIspAdapter.class",
        "com/example/ahakey/firmware/RuntimeLocator.class",
        "com/example/ahakey/firmware/InstalledRuntimeLocator.class",
        "com/example/ahakey/firmware/WchIspRuntimeContract.class",
        "com/example/ahakey/update/WindowsUpdateInstaller.class",
        "com/example/ahakey/platform/windows/VoiceKeyPressState.class",
        "firmware-capabilities.properties",
        "wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH",
        "wchisp/baseline.properties",
        "wchisp/wchisp-runtime.json"
    );

    @TempDir
    Path temporary;

    @Test
    void verifierAcceptsArtifactContainingEveryP0Entry() throws Exception {
        Result result = verify(jar("complete.jar", REQUIRED));
        assertTrue(result.success(), result.output());
        assertTrue(result.output().contains("RELEASE_ARTIFACT_CONTENTS=OK"));
    }

    @Test
    void verifierRejectsArtifactMissingAProductionClass() throws Exception {
        Result result = verify(jar("incomplete.jar", REQUIRED.subList(1, REQUIRED.size())));
        assertFalse(result.success());
        assertTrue(result.output().contains("AhaKeyProtocol.class"));
    }

    private Path jar(String name, List<String> entries) throws Exception {
        Path jar = temporary.resolve(name);
        try (JarOutputStream output = new JarOutputStream(Files.newOutputStream(jar))) {
            for (String nameInJar : entries) {
                output.putNextEntry(new JarEntry(nameInJar));
                output.write("test".getBytes(StandardCharsets.US_ASCII));
                output.closeEntry();
            }
        }
        return jar;
    }

    private Result verify(Path jar) throws Exception {
        Path powershell = Path.of(System.getenv("SystemRoot"), "System32",
            "WindowsPowerShell", "v1.0", "powershell.exe");
        Process process = new ProcessBuilder(
            powershell.toString(), "-NoLogo", "-NoProfile", "-NonInteractive",
            "-ExecutionPolicy", "Bypass", "-File",
            Path.of("Test-ReleaseArtifactContents.ps1").toAbsolutePath().toString(),
            "-JarPath", jar.toString())
            .redirectErrorStream(true)
            .start();
        String output = new String(process.getInputStream().readAllBytes(),
            StandardCharsets.UTF_8);
        return new Result(process.waitFor() == 0, output);
    }

    private record Result(boolean success, String output) {}
}
