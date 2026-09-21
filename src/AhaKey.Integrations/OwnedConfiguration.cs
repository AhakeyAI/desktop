using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace AhaKey.Integrations;

public enum ConfigurationAction { Install, Configure, Repair, Remove }
public sealed record FileChange(string Path, byte[]? Before, byte[] After, string Purpose)
{
    public string BeforeHash => Before is null ? "ABSENT" : Convert.ToHexString(SHA256.HashData(Before));
    public string AfterHash => Convert.ToHexString(SHA256.HashData(After));
}
public sealed record OwnedHookChange(string Event, string Command, string Matcher, int? Timeout, int BeforeCount, int AfterCount);
public sealed record ConfigurationPlan(AssistantId Integration, ConfigurationAction Action, IReadOnlyList<FileChange> Files, string Schema)
{
    public IReadOnlyList<OwnedHookChange> HookChanges { get; init; } = [];
}
public sealed record ConfigurationReceipt(string BackupDirectory, IReadOnlyList<FileChange> Files);

public static class SafeJson
{
    public static JsonObject Parse(byte[]? bytes)
    {
        if (bytes is null) return new();
        var text = new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF');
        using var document = JsonDocument.Parse(text, new() { MaxDepth = 32 });
        void Check(JsonElement element)
        {
            if (element.ValueKind == JsonValueKind.Object)
            {
                var keys = new HashSet<string>(StringComparer.Ordinal);
                foreach (var p in element.EnumerateObject()) { if (!keys.Add(p.Name)) throw new FormatException("Duplicate JSON key."); Check(p.Value); }
            }
            else if (element.ValueKind == JsonValueKind.Array) foreach (var item in element.EnumerateArray()) Check(item);
        }
        Check(document.RootElement);
        return JsonNode.Parse(text)?.AsObject() ?? throw new FormatException("Object required.");
    }
    public static byte[] Encode(JsonObject value) => Encoding.UTF8.GetBytes(value.ToJsonString(new() { WriteIndented = true }) + "\n");
}

public sealed class OwnedConfiguration(string backupRoot)
{
    private readonly SemaphoreSlim gate = new(1, 1);
    public Action<string>? BeforeReplace { get; init; } // Fault-injection seam; no alternate write path.
    public async Task<ConfigurationReceipt> ApplyAsync(ConfigurationPlan plan, CancellationToken ct = default)
    {
        await gate.WaitAsync(ct);
        var written = new List<FileChange>();
        var backup = Path.Combine(backupRoot, DateTimeOffset.UtcNow.ToString("yyyyMMddTHHmmssfff") + "-" + Guid.NewGuid().ToString("N"));
        try
        {
            foreach (var file in plan.Files) ValidateUnchanged(file);
            Directory.CreateDirectory(backup);
            for (int i = 0; i < plan.Files.Count; i++)
                if (plan.Files[i].Before is { } original) await File.WriteAllBytesAsync(Path.Combine(backup, $"{i}.original"), original, ct);
            await File.WriteAllTextAsync(Path.Combine(backup, "manifest.json"), JsonSerializer.Serialize(new
            {
                Integration = plan.Integration.ToString(), Action = plan.Action.ToString(), At = DateTimeOffset.UtcNow, plan.Schema,
                Files = plan.Files.Select((f, i) => new { OriginalPath = f.Path, f.BeforeHash, f.AfterHash, Backup = f.Before is null ? null : $"{i}.original" })
            }, new JsonSerializerOptions { WriteIndented = true }), ct);
            // Scripts first; config last. A failure rolls back only bytes still matching our own write.
            foreach (var file in plan.Files)
            {
                ct.ThrowIfCancellationRequested(); ValidateUnchanged(file);
                if (Path.GetExtension(file.Path) == ".json") _ = SafeJson.Parse(file.After);
                BeforeReplace?.Invoke(file.Path);
                AtomicWrite(file.Path, file.After); written.Add(file);
                if (!File.ReadAllBytes(file.Path).AsSpan().SequenceEqual(file.After)) throw new IOException("Post-write verification failed.");
                if (Path.GetExtension(file.Path) == ".json") _ = SafeJson.Parse(File.ReadAllBytes(file.Path));
            }
            return new(backup, plan.Files);
        }
        catch
        {
            foreach (var file in written.AsEnumerable().Reverse())
            {
                if (!File.Exists(file.Path) || !File.ReadAllBytes(file.Path).AsSpan().SequenceEqual(file.After)) continue;
                if (file.Before is null) File.Delete(file.Path); else AtomicWrite(file.Path, file.Before);
            }
            throw;
        }
        finally { gate.Release(); }
    }
    private static void ValidateUnchanged(FileChange file)
    {
        // Do not follow config/script symlinks, including parent junctions, into another target.
        for (var p = new FileInfo(file.Path) as FileSystemInfo; p is not null; p = p is FileInfo f ? f.Directory : ((DirectoryInfo)p).Parent)
            if (p.Exists && (p.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Linked configuration path is not editable.");
        var now = File.Exists(file.Path) ? File.ReadAllBytes(file.Path) : null;
        if ((now is null) != (file.Before is null) || now is not null && !now.AsSpan().SequenceEqual(file.Before))
            throw new IOException("Configuration changed after preview; review again.");
    }
    private static void AtomicWrite(string path, byte[] data)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + ".ahakey-" + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(data); stream.Flush(true); }
            if (File.Exists(path)) File.Replace(temp, path, null); else File.Move(temp, path);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
