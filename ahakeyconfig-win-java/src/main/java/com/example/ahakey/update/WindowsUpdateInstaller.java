package com.example.ahakey.update;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.List;
import java.util.Locale;

/** Launches the Windows installer outside the application process and restarts on success. */
final class WindowsUpdateInstaller {
    private static final String HELPER_NAME = "ahakey-install-update.ps1";
    private static final String SCRIPT = """
        param(
            [Parameter(Mandatory = $true)]
            [string]$InstallerPath,
            [Parameter(Mandatory = $true)]
            [string]$ApplicationPath,
            [Parameter(Mandatory = $true)]
            [string]$ExpectedVersion
        )

        $exitCode = 1
        try {
            $process = Start-Process -FilePath $InstallerPath -Wait -PassThru
            $exitCode = $process.ExitCode
            # Some jpackage/WiX combinations return a non-zero launcher code
            # even though the upgraded application was installed correctly.
            # The next application start verifies its embedded version.
            $deadline = (Get-Date).AddSeconds(120)
            $installedVersion = ''
            while ((Get-Date) -lt $deadline) {
                if (Test-Path -LiteralPath $ApplicationPath) {
                    $installedVersion = [string](
                        Get-Item -LiteralPath $ApplicationPath
                    ).VersionInfo.ProductVersion
                    if ($installedVersion.StartsWith($ExpectedVersion)) {
                        break
                    }
                }
                Start-Sleep -Milliseconds 500
            }
            if ($installedVersion.StartsWith($ExpectedVersion)) {
                Start-Sleep -Seconds 2
                Start-Process -FilePath $ApplicationPath
                $exitCode = 0
            }
        } finally {
            Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
        }
        exit $exitCode
        """;

    private WindowsUpdateInstaller() {}

    @FunctionalInterface
    interface SignatureVerifier {
        SignatureVerification verify(Path installer, String expectedPublisher)
            throws IOException;
    }

    record SignatureVerification(boolean valid, String signerSubject) {}

    private static final SignatureVerifier AUTHENTICODE_VERIFIER =
        WindowsUpdateInstaller::verifyWithPowerShell;

    static void verifyDownloadedInstaller(Path installer) throws IOException {
        String expectedPublisher = System.getProperty(
            "ahakey.update.expectedPublisher", "").trim();
        if (expectedPublisher.isBlank()) {
            throw new IOException(
                "Installer publisher policy is not configured; update aborted");
        }
        verifyDownloadedInstaller(installer, expectedPublisher, AUTHENTICODE_VERIFIER);
    }

    static void verifyDownloadedInstaller(
        Path installer, String expectedPublisher, SignatureVerifier verifier
    ) throws IOException {
        if (!java.nio.file.Files.isRegularFile(installer)) {
            throw new IOException("Downloaded installer is missing");
        }
        byte[] header = java.nio.file.Files.readAllBytes(installer);
        if (header.length < 2 || header[0] != 'M' || header[1] != 'Z') {
            throw new IOException("Downloaded installer is not a valid Windows executable");
        }
        SignatureVerification result = verifier.verify(installer, expectedPublisher);
        if (result == null || !result.valid()
            || result.signerSubject() == null
            || !result.signerSubject().toLowerCase(Locale.ROOT)
                .contains(expectedPublisher.toLowerCase(Locale.ROOT))) {
            throw new IOException("Installer Authenticode signature or publisher is invalid");
        }
    }

    private static SignatureVerification verifyWithPowerShell(
        Path installer, String ignoredExpectedPublisher
    ) throws IOException {
        String path = installer.toAbsolutePath().toString().replace("'", "''");
        List<String> command = List.of(
            "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive",
            "-ExecutionPolicy", "Bypass", "-Command",
            "$s=Get-AuthenticodeSignature -LiteralPath '" + path
                + "'; [Console]::Out.WriteLine([string]$s.Status);"
                + "[Console]::Out.WriteLine([string]$s.SignerCertificate.Subject)"
        );
        try {
            Process process = new ProcessBuilder(command)
                .redirectErrorStream(true).start();
            String output = new String(process.getInputStream().readAllBytes(),
                java.nio.charset.StandardCharsets.UTF_8).trim();
            int exit = process.waitFor();
            String[] lines = output.split("\\R", 2);
            return new SignatureVerification(exit == 0 && lines.length > 0
                && "Valid".equalsIgnoreCase(lines[0].trim()),
                lines.length > 1 ? lines[1].trim() : "");
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IOException("Authenticode verification interrupted", interrupted);
        } catch (IOException failure) {
            throw new IOException("Authenticode verification could not run", failure);
        }
    }

    static void launch(
        Path installer, Path currentApplication, SemanticVersion expectedVersion
    ) throws IOException {
        Path helper = installer.toAbsolutePath().getParent().resolve(HELPER_NAME);
        Path application = expectedInstalledApplication(
            currentApplication,
            System.getenv("ProgramFiles")
        );
        Files.writeString(
            helper,
            SCRIPT,
            StandardCharsets.UTF_8,
            StandardOpenOption.CREATE,
            StandardOpenOption.TRUNCATE_EXISTING
        );
        new ProcessBuilder(command(
            helper, installer, application, expectedVersion.toString())).start();
    }

    static List<String> command(
        Path helper, Path installer, Path application, String expectedVersion
    ) {
        return List.of(
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy", "Bypass",
            "-WindowStyle", "Hidden",
            "-File", helper.toAbsolutePath().toString(),
            "-InstallerPath", installer.toAbsolutePath().toString(),
            "-ApplicationPath", application.toAbsolutePath().toString(),
            "-ExpectedVersion", expectedVersion
        );
    }

    static Path expectedInstalledApplication(
        Path currentApplication, String programFiles
    ) {
        Path current = currentApplication.toAbsolutePath().normalize();
        if (programFiles == null || programFiles.isBlank()) {
            return current;
        }
        Path programFilesPath = Path.of(programFiles).toAbsolutePath().normalize();
        if (current.startsWith(programFilesPath)) {
            return current;
        }
        return programFilesPath.resolve("AhaKeyStudio").resolve("AhaKeyStudio.exe");
    }

    static String script() {
        return SCRIPT;
    }
}
