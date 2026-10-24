package com.example.ahakey.update;

import org.junit.jupiter.api.Test;

import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;

class WindowsUpdateInstallerTest {
    @Test
    void passesInstallerAndApplicationAsNamedFileParameters() {
        Path helper = Path.of("C:/Temp/update helper.ps1");
        Path installer = Path.of("C:/Temp/AhaKeyStudio 1.2.1.exe");
        Path application = Path.of("C:/Program Files/AhaKeyStudio/AhaKeyStudio.exe");

        List<String> command =
            WindowsUpdateInstaller.command(helper, installer, application, "1.2.5");

        assertEquals("powershell.exe", command.get(0));
        assertEquals("-File", command.get(7));
        assertEquals(helper.toAbsolutePath().toString(), command.get(8));
        assertEquals("-InstallerPath", command.get(9));
        assertEquals(installer.toAbsolutePath().toString(), command.get(10));
        assertEquals("-ApplicationPath", command.get(11));
        assertEquals(application.toAbsolutePath().toString(), command.get(12));
        assertEquals("-ExpectedVersion", command.get(13));
        assertEquals("1.2.5", command.get(14));
        assertFalse(command.get(10).contains(application.toString()));
    }

    @Test
    void restartsWhenInstalledApplicationExistsEvenIfLauncherCodeIsOdd() {
        String script = WindowsUpdateInstaller.script();

        assertTrue(script.contains(
            "Start-Process -FilePath $InstallerPath -Wait -PassThru"));
        assertTrue(script.contains("Test-Path -LiteralPath $ApplicationPath"));
        assertTrue(script.contains("VersionInfo.ProductVersion"));
        assertTrue(script.contains("StartsWith($ExpectedVersion)"));
        assertTrue(script.contains("$exitCode = 0"));
        assertTrue(script.contains("Start-Process -FilePath $ApplicationPath"));
    }

    @Test
    void legacyCustomInstallRestartsTheSafeProgramFilesApplication() {
        Path expected = WindowsUpdateInstaller.expectedInstalledApplication(
            Path.of("C:/app/AhaKeyStudio.exe"),
            "C:/Program Files"
        );

        assertEquals(
            Path.of("C:/Program Files/AhaKeyStudio/AhaKeyStudio.exe")
                .toAbsolutePath().normalize(),
            expected
        );
    }

    @Test
    void requiresValidSignatureAndExpectedPublisherBeforeLaunch() throws Exception {
        Path installer = java.nio.file.Files.createTempFile("signed", ".exe");
        java.nio.file.Files.write(installer, new byte[]{'M', 'Z', 0, 0});
        var valid = (WindowsUpdateInstaller.SignatureVerifier)
            (path, publisher) -> new WindowsUpdateInstaller.SignatureVerification(
                true, "CN=AhaKey Software, O=AhaKey");
        WindowsUpdateInstaller.verifyDownloadedInstaller(installer, "AhaKey", valid);
        assertThrows(java.io.IOException.class, () ->
            WindowsUpdateInstaller.verifyDownloadedInstaller(installer, "AhaKey",
                (path, publisher) -> new WindowsUpdateInstaller.SignatureVerification(
                    false, "CN=AhaKey Software")));
        assertThrows(java.io.IOException.class, () ->
            WindowsUpdateInstaller.verifyDownloadedInstaller(installer, "AhaKey",
                (path, publisher) -> new WindowsUpdateInstaller.SignatureVerification(
                    true, "CN=Untrusted")));
        assertThrows(java.io.IOException.class, () ->
            WindowsUpdateInstaller.verifyDownloadedInstaller(installer, "AhaKey",
                (path, publisher) -> null));
    }

    @Test
    void rejectsMalformedExecutableBeforeSignatureVerifier() throws Exception {
        Path installer = java.nio.file.Files.createTempFile("malformed", ".exe");
        java.nio.file.Files.write(installer, new byte[]{'N', 'O'});
        assertThrows(java.io.IOException.class, () ->
            WindowsUpdateInstaller.verifyDownloadedInstaller(installer, "AhaKey",
                (path, publisher) -> new WindowsUpdateInstaller.SignatureVerification(
                    true, "CN=AhaKey")));
    }
}
