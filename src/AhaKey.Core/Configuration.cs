using System.Collections.Immutable;
using System.Text.Json.Serialization;
namespace AhaKey.Core;
public enum PhysicalKey { K1, K2, K3, K4 }
[JsonPolymorphic(TypeDiscriminatorPropertyName = "$action")]
[JsonDerivedType(typeof(KeyboardShortcutAction), "shortcut")]
[JsonDerivedType(typeof(VoiceInputAction), "voice")]
[JsonDerivedType(typeof(IntegrationAction), "integration")]
[JsonDerivedType(typeof(MacroAction), "macro")]
[JsonDerivedType(typeof(DisabledAction), "disabled")]
public abstract record KeyAction;
public sealed record KeyboardShortcutAction(string Shortcut) : KeyAction;
public sealed record VoiceInputAction(string Binding = "F18") : KeyAction;
public sealed record IntegrationAction(string IntegrationId, string ActionId) : KeyAction;
public sealed record MacroAction(ImmutableArray<string> Steps) : KeyAction;
public sealed record DisabledAction : KeyAction;
public enum DisplayState { Default, Working, WaitingError, Completed }
public enum OptimizationState { NotRequired, Pending, Optimized }
public sealed record DisplayAsset(int FrameCount = 0, string? SourceFile = null, int DurationMs = 0,
    OptimizationState Optimization = OptimizationState.NotRequired);
public static class DisplayLimits
{
    public const int Width = 160, Height = 80;
    public static int MaximumFrames(DisplayState state) => state switch
    {
        DisplayState.Default => 8,
        DisplayState.Working or DisplayState.WaitingError or DisplayState.Completed => 12,
        _ => throw new ArgumentOutOfRangeException(nameof(state))
    };
}
public enum IdeEventState { Notification = 0, PermissionRequest = 1, PostToolUse = 2, PreToolUse = 3, SessionStart = 4, Stop = 5, TaskCompleted = 6, UserPromptSubmit = 7, SessionEnd = 8 }
public sealed record LightingConfiguration(ImmutableDictionary<IdeEventState, byte> Mapping)
{
    public static LightingConfiguration Default => new(Enum.GetValues<IdeEventState>().ToImmutableDictionary(x => x, _ => (byte)0));
}
public sealed record ProfileConfiguration(ImmutableDictionary<PhysicalKey, KeyAction> Keys,
    [property: JsonPropertyName("Oled")] ImmutableDictionary<DisplayState, DisplayAsset> Display, LightingConfiguration Lighting)
{
    public ImmutableDictionary<PhysicalKey, string> DeviceLabels { get; init; } = ImmutableDictionary<PhysicalKey,string>.Empty;
    public string Label(PhysicalKey key) => DeviceLabels.GetValueOrDefault(key, "");
    public static ProfileConfiguration Default => new(new Dictionary<PhysicalKey, KeyAction>
    {
        [PhysicalKey.K1] = new VoiceInputAction(), [PhysicalKey.K2] = new DisabledAction(),
        [PhysicalKey.K3] = new DisabledAction(), [PhysicalKey.K4] = new DisabledAction()
    }.ToImmutableDictionary(), Enum.GetValues<DisplayState>().ToImmutableDictionary(x => x, _ => new DisplayAsset()), LightingConfiguration.Default);
}
public sealed record DeviceConfiguration(ImmutableDictionary<HardwareProfileId, ProfileConfiguration> Profiles, int GlobalBrightness)
{
    public static DeviceConfiguration Default => new(Profile.Defaults.ToImmutableDictionary(p => p.HardwareProfileId, p => p.Configuration), 75);
    public bool EquivalentTo(DeviceConfiguration other) => GlobalBrightness == other.GlobalBrightness &&
        Profiles.Count == other.Profiles.Count && Profiles.All(p => other.Profiles.TryGetValue(p.Key, out var q) &&
            p.Value.Keys.Count == q.Keys.Count && p.Value.Keys.All(k => q.Keys.TryGetValue(k.Key, out var a) && ActionEquals(k.Value, a)) &&
            Enum.GetValues<PhysicalKey>().All(k => p.Value.Label(k) == q.Label(k)) &&
            p.Value.Display.Count == q.Display.Count && p.Value.Display.All(o => q.Display.TryGetValue(o.Key, out var a) && a == o.Value) &&
            p.Value.Lighting.Mapping.Count == q.Lighting.Mapping.Count && p.Value.Lighting.Mapping.All(l => q.Lighting.Mapping.TryGetValue(l.Key, out var a) && a == l.Value));
    private static bool ActionEquals(KeyAction a, KeyAction b) => a is MacroAction ma && b is MacroAction mb ? ma.Steps.SequenceEqual(mb.Steps) : a == b;
}
