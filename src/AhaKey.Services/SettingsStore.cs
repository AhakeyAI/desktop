using System.Text.Json;
using System.Text.Json.Serialization;
using AhaKey.Core;
namespace AhaKey.Services;
public enum LanguageChoice { System, English, Russian, Chinese }
public enum ThemeChoice { System, Light, Dark }
public enum BackendChoice { Mock, Real }
public sealed record StudioSettings(int SchemaVersion = 1, LanguageChoice Language = LanguageChoice.System,
    ThemeChoice Theme = ThemeChoice.System, BackendChoice Backend = BackendChoice.Real,
    HardwareProfileId? SelectedProfile = null, string? CustomProfileName = null)
{
    public bool DeveloperMode {get;init;}
    public bool IntegrationAutoStart {get;init;}
    public bool ActivateHardwareProfile {get;init;}
    public bool AdvancedLightingMapping {get;init;}
    public System.Collections.Immutable.ImmutableHashSet<string> PhysicalFeedback {get;init;} = [];
    public System.Collections.Immutable.ImmutableDictionary<string,DisplaySourcePreference> DisplaySources {get;init;} = System.Collections.Immutable.ImmutableDictionary<string,DisplaySourcePreference>.Empty;
    public BackendChoice EffectiveBackend => DeveloperMode ? Backend : BackendChoice.Real;
    public string? BleDeviceId {get;init;}
    public string? BleDeviceName {get;init;}
    public string? BleDeviceAddress {get;init;}
    public System.Collections.Immutable.ImmutableDictionary<string,string> KeyLocalNames { get; init; } = System.Collections.Immutable.ImmutableDictionary<string,string>.Empty;
}
public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };
    public string Root { get; }
    public string FilePath => Path.Combine(Root, "settings.v1.json");
    public string? LoadErrorKey { get; private set; }
    public bool IsReadOnly { get; private set; }
    public SettingsStore(string? root = null) => Root = root ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AhaKey", "Studio2");
    public StudioSettings Load()
    {
        if (!File.Exists(FilePath)) return new();
        try { var value = JsonSerializer.Deserialize<StudioSettings>(File.ReadAllText(FilePath), Json) ?? throw new JsonException(); Validate(value); return value; }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException or ArgumentException)
        { LoadErrorKey = "SettingsLoadError"; IsReadOnly = true; return new(); }
    }
    public void Save(StudioSettings settings)
    {
        if (IsReadOnly) throw new IOException("Unreadable settings preserved. Store is read-only for this session.");
        Validate(settings); Directory.CreateDirectory(Root);
        var temporary = Path.Combine(Root, $"settings.{Guid.NewGuid():N}.tmp");
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { JsonSerializer.Serialize(file, settings, Json); file.Flush(true); }
            File.Move(temporary, FilePath, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    private static void Validate(StudioSettings value)
    {
        if(value.PhysicalFeedback is null || value.PhysicalFeedback.Any(x=>!System.Text.RegularExpressions.Regex.IsMatch(x,"^[0-3]:(Codex|Claude|Cursor)$")) || value.DisplaySources is null || value.DisplaySources.Any(x=>!System.Text.RegularExpressions.Regex.IsMatch(x.Key,"^[0-3]:[0-3]$") || x.Value is null || string.IsNullOrWhiteSpace(x.Value.CachedPath) || x.Value.Fit is not ("Fit" or "Crop")))throw new ArgumentException("Invalid product preferences.");
        if (value.KeyLocalNames is null || value.KeyLocalNames.Any(x => !System.Text.RegularExpressions.Regex.IsMatch(x.Key, "^[0-3]:[0-3]$") || x.Value is null || x.Value.Length > 80)) throw new ArgumentException("Invalid local key names.");
        if (value.SchemaVersion != 1 || !Enum.IsDefined(value.Language) || !Enum.IsDefined(value.Theme) || !Enum.IsDefined(value.Backend) ||
            value.SelectedProfile is { } id && !Enum.IsDefined(id) ||
            value.CustomProfileName is { } name && (string.IsNullOrWhiteSpace(name) || name.Length > 48)) throw new ArgumentException("Invalid settings schema or values.");
    }
}
public sealed record DisplaySourcePreference(string CachedPath,string Name,string Fit,string? FrameSha256=null);
