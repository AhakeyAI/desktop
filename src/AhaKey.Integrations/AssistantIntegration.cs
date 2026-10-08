using System.Text;
using System.Text.Json.Nodes;

namespace AhaKey.Integrations;

public abstract class AssistantIntegration(AssistantId id, string home, string relativeConfig, string scriptRoot)
{
    public AssistantId Id { get; } = id;
    public string ConfigPath { get; } = Path.GetFullPath(Path.Combine(home, relativeConfig));
    public string ScriptPath { get; } = Path.Combine(scriptRoot, $"ahakey-studio2-{id.ToString().ToLowerInvariant()}-v1.ps1");
    public string SanitizedPath => ConfigPath.Replace(home, "%USERPROFILE%", StringComparison.OrdinalIgnoreCase);
    public virtual bool Supported => true;
    public EvidenceState EnabledState
    {
        get
        {
            if (!Inspect().Configured) return EvidenceState.No;
            try
            {
                var root = Read(File.ReadAllBytes(ConfigPath));
                if (Id == AssistantId.Claude && root["disableAllHooks"] is {} disabled)
                    return disabled.GetValue<bool>() ? EvidenceState.No : EvidenceState.Yes;
                return EvidenceState.Yes;
            }
            catch (Exception ex) when (ex is not OutOfMemoryException) { return EvidenceState.Unknown; }
        }
    }
    public IEnumerable<HookEvent> Events => HookContract.Events.Values.Where(e => e.Integration == Id && !(Id == AssistantId.Codex && e.Event == IdeEvent.SessionEnd));
    private bool Nested => Id != AssistantId.Cursor;
    public string Command(HookEvent ev) => $"powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{ScriptPath}\" {ev.NativeEvent}";
    private bool Owned(JsonNode? node) => node is JsonObject obj && obj["type"]?.GetValue<string>() is null or "command" &&
        obj["command"] is JsonValue value && value.TryGetValue<string>(out var command) && Events.Any(e => command == Command(e));
    private JsonObject Read(byte[]? bytes)
    {
        var root = SafeJson.Parse(bytes);
        if (root["version"] is {} version && (!version.AsValue().TryGetValue<int>(out int n) || n != 1)) throw new FormatException("Unknown configuration version.");
        if (root["hooks"] is not null && root["hooks"] is not JsonObject) throw new FormatException("Unknown hooks schema.");
        if (Id == AssistantId.Claude && root["disableAllHooks"] is {} disabled && !disabled.AsValue().TryGetValue<bool>(out _)) throw new FormatException("Unknown enablement schema.");
        if (root["hooks"] is JsonObject hooks)
            foreach (var (_, entry) in hooks)
            {
                if (entry is not JsonArray array) throw new FormatException("Unknown event schema.");
                foreach (var item in array)
                    if (item is not JsonObject || Nested && item["hooks"] is not JsonArray) throw new FormatException("Unknown command schema.");
            }
        return root;
    }
    public (bool Configured, bool Compatible) Inspect()
    {
        if (!Supported) return (false, false);
        try
        {
            var root = Read(File.Exists(ConfigPath) ? File.ReadAllBytes(ConfigPath) : null);
            bool configured = Events.All(e => root["hooks"]?[ConfigEvent(e)] is JsonArray a &&
                a.Any(n => Nested ? n?["hooks"] is JsonArray inner && inner.Any(Owned) : Owned(n)));
            return (configured && File.Exists(ScriptPath) && File.ReadAllText(ScriptPath) == HookScript.Create(Id), true);
        }
        catch (Exception ex) when (ex is not OutOfMemoryException) { return (false, false); }
    }
    private string ConfigEvent(HookEvent ev) => Id == AssistantId.Codex ? ev.Event.ToString() : ev.NativeEvent;
    private Dictionary<(string Event, string Command, string Matcher, int? Timeout), int> OwnedEntries(JsonObject root)
    {
        var result = new Dictionary<(string, string, string, int?), int>();
        if (root["hooks"] is not JsonObject hooks) return result;
        foreach (var (name, value) in hooks)
        foreach (var item in value!.AsArray())
        {
            var commands = Nested ? item!["hooks"]!.AsArray().ToArray() : new[] { item };
            foreach (var command in commands.Where(Owned))
            {
                var key = (name, command!["command"]!.GetValue<string>(), Nested ? item!["matcher"]?.GetValue<string>() ?? "" : "", command["timeout"]?.GetValue<int>());
                result[key] = result.GetValueOrDefault(key) + 1;
            }
        }
        return result;
    }
    public ConfigurationPlan Preview(ConfigurationAction action)
    {
        if (!Supported) throw new InvalidOperationException("Integration contract unavailable.");
        byte[]? before = File.Exists(ConfigPath) ? File.ReadAllBytes(ConfigPath) : null;
        if (before is null && action == ConfigurationAction.Remove) return new(Id, action, [], "No owned configuration");
        var root = Read(before);
        var originalEntries = OwnedEntries(root);
        var hooks = root["hooks"] as JsonObject ?? new JsonObject();
        // Remove only exact Studio 2 commands, even inside a mixed user-owned wrapper.
        foreach (var (_, node) in hooks.ToArray())
        {
            var array = (JsonArray)node!;
            for (int i = array.Count - 1; i >= 0; i--)
            {
                if (!Nested) { if (Owned(array[i])) array.RemoveAt(i); continue; }
                var commands = (JsonArray)array[i]!["hooks"]!;
                bool removed = false;
                for (int j = commands.Count - 1; j >= 0; j--) if (Owned(commands[j])) { commands.RemoveAt(j); removed = true; }
                if (removed && commands.Count == 0) array.RemoveAt(i);
            }
        }
        if (action != ConfigurationAction.Remove)
        {
            foreach (var ev in Events)
            {
                string key = ConfigEvent(ev);
                var array = hooks[key] as JsonArray;
                if (array is null) { array = new(); hooks[key] = array; }
                var command = new JsonObject { ["command"] = Command(ev), ["timeout"] = HookContract.RequiresApproval(ev) ? 20 : 10 };
                if (Nested)
                {
                    command["type"] = "command";
                    var wrapper = new JsonObject { ["hooks"] = new JsonArray(command) };
                    if (Id == AssistantId.Claude) wrapper["matcher"] = "";
                    else if (ev.Event == IdeEvent.SessionStart) wrapper["matcher"] = "startup|resume|clear";
                    else if (ev.Event is not (IdeEvent.Stop or IdeEvent.UserPromptSubmit)) wrapper["matcher"] = "*";
                    array.Add(wrapper);
                }
                else array.Add(command);
            }
            if (Id == AssistantId.Cursor) root["version"] = 1;
        }
        if (root["hooks"] is null) root["hooks"] = hooks;
        var after = SafeJson.Encode(root); _ = Read(after);
        var changes = new List<FileChange>();
        if (action != ConfigurationAction.Remove)
        {
            var script = Encoding.UTF8.GetBytes(HookScript.Create(Id));
            var oldScript = File.Exists(ScriptPath) ? File.ReadAllBytes(ScriptPath) : null;
            if (oldScript is not null && !HookScript.IsOwned(Encoding.UTF8.GetString(oldScript)))
                throw new IOException("Script path contains an unowned file.");
            if (oldScript is null || !oldScript.AsSpan().SequenceEqual(script)) changes.Add(new(ScriptPath, oldScript, script, "IntegrationOwnedScript"));
        }
        if (before is null || !before.AsSpan().SequenceEqual(after)) changes.Add(new(ConfigPath, before, after, action == ConfigurationAction.Remove ? "IntegrationRemoveEntries" : "IntegrationAddEntries"));
        var updatedEntries = OwnedEntries(root);
        return new(Id, action, changes, Id == AssistantId.Cursor ? "Windows Cursor hooks v1" : "Windows nested command hooks v1")
        {
            HookChanges = originalEntries.Keys.Union(updatedEntries.Keys)
                .Where(k => originalEntries.GetValueOrDefault(k) != updatedEntries.GetValueOrDefault(k))
                .Select(k => new OwnedHookChange(k.Event, k.Command, k.Matcher, k.Timeout, originalEntries.GetValueOrDefault(k), updatedEntries.GetValueOrDefault(k))).ToArray()
        };
    }
}
public sealed class ClaudeIntegration(string home, string scripts) : AssistantIntegration(AssistantId.Claude, home, ".claude/settings.json", scripts);
public sealed class CursorIntegration(string home, string scripts) : AssistantIntegration(AssistantId.Cursor, home, ".cursor/hooks.json", scripts);
public sealed class CodexIntegration(string home, string scripts) : AssistantIntegration(AssistantId.Codex, home, ".codex/hooks.json", scripts)
{
    public IReadOnlyDictionary<string,string> RecognizedCommands => Inspect().Configured
        ? Events.ToDictionary(e=>e.Event.ToString(),Command) : LegacyCodexHooks.Commands(Path.GetDirectoryName(Path.GetDirectoryName(ConfigPath)!)!,Events);
}
public sealed class KimiIntegration(string home, string scripts) : AssistantIntegration(AssistantId.Kimi, home, ".config/kimi-cli/hooks.json", scripts)
{ public override bool Supported => false; }
