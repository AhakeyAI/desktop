package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class HookInstallerTest {
    private static final ObjectMapper JSON = new ObjectMapper();

    @TempDir
    Path home;

    @Test
    void claudeInstallAndUninstallPreserveThirdPartyHooks() throws Exception {
        Path settings = home.resolve(".claude").resolve("settings.json");
        write(settings, """
            {
              "theme": "dark",
              "hooks": {
                "PermissionRequest": [{
                  "matcher": "*",
                  "hooks": [{"type":"command","command":"third-party-claude","timeout":5}]
                }]
              }
            }
            """);
        HookInstaller installer = installer();

        assertTrue(installer.install("Claude"));
        assertTrue(hasCommand(settings, "third-party-claude"));
        assertEquals(9, commandCount(settings, "ahakey-claude.ps1"));
        assertEquals("dark", JSON.readTree(settings.toFile()).path("theme").asText());

        assertTrue(installer.uninstall("Claude"));
        assertTrue(hasCommand(settings, "third-party-claude"));
        assertEquals(0, commandCount(settings, "ahakey-claude.ps1"));
        assertEquals("dark", JSON.readTree(settings.toFile()).path("theme").asText());
    }

    @Test
    void cursorInstallIsIdempotentAndUninstallPreservesThirdPartyHooks() throws Exception {
        Path settings = home.resolve(".cursor").resolve("hooks.json");
        write(settings, """
            {
              "version": 1,
              "custom": true,
              "hooks": {
                "preToolUse": [{"command":"third-party-cursor","timeout":7}]
              }
            }
            """);
        HookInstaller installer = installer();

        assertTrue(installer.install("Cursor"));
        assertTrue(installer.install("Cursor"));
        assertTrue(hasCommand(settings, "third-party-cursor"));
        assertEquals(5, commandCount(settings, "ahakey-cursor.ps1"));

        assertTrue(installer.uninstall("Cursor"));
        assertTrue(hasCommand(settings, "third-party-cursor"));
        assertEquals(0, commandCount(settings, "ahakey-cursor.ps1"));
        assertTrue(JSON.readTree(settings.toFile()).path("custom").asBoolean());
    }

    @Test
    void codexInstallAndUninstallPreserveThirdPartyHooksAndToml() throws Exception {
        Path hooks = home.resolve(".codex").resolve("hooks.json");
        Path config = home.resolve(".codex").resolve("config.toml");
        write(hooks, """
            {
              "owner": "user",
              "hooks": {
                "PreToolUse": [{
                  "matcher": "third-party",
                  "hooks": [{"type":"command","command":"third-party-codex","timeout":9}]
                }]
              }
            }
            """);
        write(config, "model = \"custom\"\n\n[features]\nother_hooks = false\n");
        HookInstaller installer = installer();

        assertTrue(installer.install("Codex"));
        assertTrue(hasCommand(hooks, "third-party-codex"));
        assertEquals(6, commandCount(hooks, "ahakey-codex.ps1"));
        assertTrue(Files.readString(config).contains("model = \"custom\""));
        assertTrue(Files.readString(config).contains("other_hooks = false"));

        assertTrue(installer.uninstall("Codex"));
        assertTrue(hasCommand(hooks, "third-party-codex"));
        assertEquals(0, commandCount(hooks, "ahakey-codex.ps1"));
        String toml = Files.readString(config);
        assertTrue(toml.contains("model = \"custom\""));
        assertFalse(toml.contains(HookInstaller.CODEX_HOOK_BLOCK_START));
    }

    @Test
    void cursorScriptFailsClosedWhenDesktopDoesNotRespond() throws Exception {
        HookInstaller installer = installer();
        installer.generateAllScripts();

        String script = Files.readString(
            home.resolve(".ahakey/hooks/ahakey-cursor.ps1"),
            StandardCharsets.UTF_8
        );

        assertTrue(script.contains("manual approval is required"));
        assertTrue(script.contains("exit 1"));
        assertTrue(script.contains("Test-AhaKeyCanonicalAllow"));
        assertFalse(script.contains("-match"));
    }

    @Test
    void kimiPreToolUseFailsClosedWhenDesktopDoesNotRespond() throws Exception {
        HookInstaller installer = installer();
        installer.generateAllScripts();

        String script = Files.readString(
            home.resolve(".ahakey/hooks/ahakey-kimi.ps1"),
            StandardCharsets.UTF_8
        );

        assertTrue(script.contains("KimiPreToolUse"));
        assertTrue(script.contains("approval state is unavailable"));
        assertTrue(script.contains("exit 1"));
        assertTrue(script.contains("Test-AhaKeyCanonicalAllow"));
        assertFalse(script.contains("-match"));
    }

    @Test
    void canonicalValidatorRejectsMalformedAndAmbiguousAllowResponses()
            throws Exception {
        HookInstaller installer = installer();
        installer.generateAllScripts();
        Path core = home.resolve(".ahakey/hooks/ahakey-core.ps1");
        Path validation = home.resolve("validate-envelope.ps1");
        String canonical = "{\"schemaVersion\":1,\"platform\":\"claude\","
            + "\"event\":\"PermissionRequest\",\"allow\":true,"
            + "\"approvalSource\":\"hardware-auto\"}";
        List<String> rejected = List.of(
            "", "{}", " " + canonical, canonical + " ", canonical + "junk",
            canonical.substring(0, canonical.length() - 1),
            canonical.replace("\"allow\":true", "\"allow\":\"true\""),
            canonical.replace("\"allow\":true", "\"allow\":1"),
            canonical.replace("\"allow\":true", "\"allow\":null"),
            "[" + canonical + "]",
            canonical.replace("\"allow\":true", "\"allow\":{\"value\":true}"),
            canonical.replace("\"event\":\"PermissionRequest\"",
                "\"event\":\"PreToolUse\""),
            canonical.replace("\"platform\":\"claude\"",
                "\"platform\":\"codex\""),
            canonical.replace("\"approvalSource\":\"hardware-auto\"",
                "\"approvalSource\":\"hardware-auto\",\"extra\":1"),
            canonical.replace("\"allow\":true", "\"allow\":false,\"allow\":true")
        );
        StringBuilder script = new StringBuilder()
            .append("$EventName='NoServer'; . '")
            .append(core.toString().replace("'", "''"))
            .append("'\n");
        script.append("if (-not (Test-AhaKeyCanonicalAllow '")
            .append(canonical).append("' 'claude' 'PermissionRequest')) { exit 10 }\n");
        int code = 20;
        for (String response : rejected) {
            script.append("if (Test-AhaKeyCanonicalAllow '")
                .append(response.replace("'", "''"))
                .append("' 'claude' 'PermissionRequest') { exit ")
                .append(code++).append(" }\n");
        }
        script.append("exit 0\n");
        Files.writeString(validation, script, StandardCharsets.UTF_8);
        Path emptyInput = home.resolve("empty-input.txt");
        Files.writeString(emptyInput, "", StandardCharsets.UTF_8);
        Path powershell = Path.of(System.getenv("SystemRoot"), "System32",
            "WindowsPowerShell", "v1.0", "powershell.exe");
        Process process = new ProcessBuilder(powershell.toString(), "-NoLogo",
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-File", validation.toString()).redirectInput(emptyInput.toFile())
            .redirectErrorStream(true).start();
        String output = new String(process.getInputStream().readAllBytes(),
            StandardCharsets.UTF_8);
        assertEquals(0, process.waitFor(), output);
    }

    @Test
    void generatedScriptsUseBoundedReadAndNoRegexAllowDecision() throws Exception {
        HookInstaller installer = installer();
        installer.generateAllScripts();
        Path hooks = home.resolve(".ahakey/hooks");
        String core = Files.readString(hooks.resolve("ahakey-core.ps1"));
        assertTrue(core.contains("New-Object byte[] 512"));
        assertTrue(core.contains("ReadTimeout = 17000"));
        assertTrue(core.contains("StringComparison]::Ordinal"));
        for (String name : List.of("ahakey-claude.ps1", "ahakey-codex.ps1",
                "ahakey-kimi.ps1", "ahakey-cursor.ps1")) {
            String script = Files.readString(hooks.resolve(name));
            assertFalse(script.contains("-match"), name);
        }
    }

    @Test
    void validNonObjectJsonIsNotReplacedDuringInstall() throws Exception {
        Path settings = home.resolve(".claude").resolve("settings.json");
        write(settings, "[\"user-owned\",\"configuration\"]\n");
        HookInstaller installer = installer();

        assertFalse(installer.install("Claude"));
        assertEquals("[\"user-owned\",\"configuration\"]\n",
            Files.readString(settings, StandardCharsets.UTF_8));
    }

    @Test
    void everyGeneratedPowerShellHookParses() throws Exception {
        HookInstaller installer = installer();
        installer.generateAllScripts();
        Path hooks = home.resolve(".ahakey").resolve("hooks");
        String parser = "$failed=$false; Get-ChildItem -LiteralPath $env:AHAKEY_TEST_HOOK_DIR -Filter '*.ps1' | "
            + "ForEach-Object {$t=$null;$e=$null;"
            + "[System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$t,[ref]$e)|Out-Null;"
            + "if($e.Count){$failed=$true;$e|ForEach-Object {$_.Message}}};"
            + "if($failed){exit 1}";
        Path powershell = Path.of(System.getenv("SystemRoot"), "System32",
            "WindowsPowerShell", "v1.0", "powershell.exe");
        ProcessBuilder builder = new ProcessBuilder(
            powershell.toString(), "-NoLogo", "-NoProfile", "-NonInteractive",
            "-Command", parser)
            .redirectErrorStream(true);
        builder.environment().put("AHAKEY_TEST_HOOK_DIR", hooks.toString());
        Process process = builder.start();
        String output = new String(process.getInputStream().readAllBytes(),
            StandardCharsets.UTF_8);
        assertEquals(0, process.waitFor(), output);
    }

    private HookInstaller installer() {
        return new HookInstaller(home, () -> 8765, ignored -> {});
    }

    private void write(Path path, String content) throws Exception {
        Files.createDirectories(path.getParent());
        Files.writeString(path, content, StandardCharsets.UTF_8);
    }

    private boolean hasCommand(Path path, String command) throws Exception {
        return commandCount(path, command) > 0;
    }

    private int commandCount(Path path, String fragment) throws Exception {
        List<String> commands = new ArrayList<>();
        collectCommands(JSON.readTree(path.toFile()), commands);
        return (int) commands.stream().filter(value -> value.contains(fragment)).count();
    }

    private void collectCommands(JsonNode node, List<String> commands) {
        if (node == null) return;
        if (node.isObject() && node.path("command").isTextual()) {
            commands.add(node.path("command").asText());
        }
        if (node.isContainerNode()) {
            node.forEach(child -> collectCommands(child, commands));
        }
    }
}
