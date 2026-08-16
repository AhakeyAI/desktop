package com.example.ahakey.update;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.List;

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
