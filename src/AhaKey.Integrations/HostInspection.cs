using System.Diagnostics;
using System.Text.Json;

namespace AhaKey.Integrations;

public sealed record ApplicationInstallation(bool Installed, string? Version, string? Executable);
public sealed record CodexHookEvidence(EvidenceState Enabled, EvidenceState Trusted, EvidenceState Compatible);
public interface IHostInspection
{
    Task<ApplicationInstallation> FindAsync(AssistantId id, CancellationToken ct);
    Task<CodexHookEvidence> InspectCodexAsync(string executable, CodexIntegration adapter, CancellationToken ct);
}
public sealed class HostInspection : IHostInspection
{
    public async Task<ApplicationInstallation> FindAsync(AssistantId id, CancellationToken ct)
    {
        string name = id.ToString().ToLowerInvariant();
        var dirs = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator).ToList();
        dirs.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin"));
        dirs.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", name));
        var exe = ResolveExecutable(id, dirs, Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
        if (exe is null) return new(false, null, null);
        try
        {
            using var process = new Process { StartInfo = new(exe) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true } };
            process.StartInfo.ArgumentList.Add("--version"); process.Start();
            using var bound = CancellationTokenSource.CreateLinkedTokenSource(ct); bound.CancelAfter(TimeSpan.FromSeconds(3));
            try
            {
                var stdout = ReadBounded(process.StandardOutput, bound.Token);
                var stderr = ReadBounded(process.StandardError, bound.Token);
                await process.WaitForExitAsync(bound.Token);
                var output = await stdout; _ = await stderr;
                var version = System.Text.RegularExpressions.Regex.Match(output, @"\b\d+\.\d+\.\d+(?:[-.a-zA-Z0-9]+)?").Value;
                return new(true, string.IsNullOrEmpty(version) ? null : version, exe);
            }
            finally { if (!process.HasExited) process.Kill(true); }
        }
        catch (Exception ex) when (ex is not OutOfMemoryException) { return new(true, null, exe); }
    }
    public static string? ResolveExecutable(AssistantId id, IEnumerable<string> searchDirectories, string localAppData)
    {
        var name = id.ToString().ToLowerInvariant() + ".exe";
        var onPath = searchDirectories.Where(d => !string.IsNullOrWhiteSpace(d))
            .Select(d => Path.Combine(d.Trim('"'), name)).FirstOrDefault(File.Exists);
        if (onPath is not null || id != AssistantId.Codex) return onPath;
        // The desktop installer keeps its CLI here; Explorer need not inherit Codex's PATH.
        var root = Path.Combine(localAppData, "OpenAI", "Codex", "bin");
        try
        {
            return Directory.Exists(root) ? Directory.EnumerateDirectories(root)
                .Select(d => Path.Combine(d, name)).Where(File.Exists)
                .OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault() : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return null; }
    }
    private static async Task<string> ReadBounded(StreamReader reader, CancellationToken ct)
    {
        var chars = new char[65536]; int count = 0;
        while (count < chars.Length)
        {
            int n = await reader.ReadAsync(chars.AsMemory(count), ct); if (n == 0) return new(chars, 0, count); count += n;
        }
        throw new FormatException("Output limit.");
    }
    public async Task<CodexHookEvidence> InspectCodexAsync(string executable, CodexIntegration adapter, CancellationToken ct)
    {
        // Read-only native API from installed 0.155 schema; never invent trust hashes or modify TOML.
        using var process = new Process { StartInfo = new(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true } };
        process.StartInfo.ArgumentList.Add("app-server");
        using var bound = CancellationTokenSource.CreateLinkedTokenSource(ct); bound.CancelAfter(TimeSpan.FromSeconds(5));
        try
        {
            process.Start(); var stderr = ReadBounded(process.StandardError, bound.Token);
            async Task<JsonElement> Call(int id, string method, object parameters)
            {
                await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(new { id, method, @params = parameters }));
                await process.StandardInput.FlushAsync(bound.Token);
                for (int line = 0; line < 40; line++)
                {
                    var text = await ReadLineBounded(process.StandardOutput, bound.Token);
                    using var doc = JsonDocument.Parse(text);
                    if (doc.RootElement.TryGetProperty("id", out var value) && value.ValueKind == JsonValueKind.Number && value.GetInt32() == id)
                        return doc.RootElement.GetProperty("result").Clone();
                }
                throw new FormatException();
            }
            await Call(1, "initialize", new { clientInfo = new { name = "ahakey_studio_inspect", version = "1.0.0" }, capabilities = new { experimentalApi = true } });
            var response = await Call(2, "hooks/list", new { cwds = new[] { Path.GetDirectoryName(adapter.ConfigPath)! } });
            var entries = response.GetProperty("data").EnumerateArray().ToArray();
            if (entries.Any(e => e.GetProperty("errors").GetArrayLength() != 0)) return new(EvidenceState.Unknown, EvidenceState.Unknown, EvidenceState.No);
            var commands=adapter.RecognizedCommands;
            var hooks = entries.SelectMany(e => e.GetProperty("hooks").EnumerateArray()).Where(h => h.TryGetProperty("command", out var cmd) && commands.Values.Contains(cmd.GetString())).ToArray();
            if (commands.Count!=adapter.Events.Count() || commands.Values.Any(c=>!hooks.Any(h=>h.GetProperty("command").GetString()==c))) return new(EvidenceState.Unknown, EvidenceState.Unknown, EvidenceState.Yes);
            return new(hooks.All(h => h.GetProperty("enabled").GetBoolean()) ? EvidenceState.Yes : EvidenceState.No,
                hooks.All(h => h.GetProperty("trustStatus").GetString() is "trusted" or "managed") ? EvidenceState.Yes : EvidenceState.No, EvidenceState.Yes);
        }
        catch (Exception ex) when (ex is not OutOfMemoryException) { return new(EvidenceState.Unknown, EvidenceState.Unknown, EvidenceState.Unknown); }
        finally { try { if (!process.HasExited) process.Kill(true); } catch (InvalidOperationException) { } }
    }
    private static async Task<string> ReadLineBounded(StreamReader reader, CancellationToken ct)
    {
        var b = new char[262144]; int n = 0;
        while (n < b.Length)
        {
            int read = await reader.ReadAsync(b.AsMemory(n, 1), ct);
            if (read == 0) throw new EndOfStreamException();
            if (b[n] == '\n') return new(b, 0, n); n++;
        }
        throw new FormatException();
    }
}
