using System.Collections.Immutable;
namespace AhaKey.Core;
public enum HardwareProfileId { Claude = 0, Cursor = 1, Codex = 2, Custom = 3 }
public enum ProfileType { Claude, Cursor, Codex, Custom }
public sealed record Profile(HardwareProfileId HardwareProfileId, string DisplayName, ProfileType ProfileType,
    string? IntegrationId, ProfileConfiguration Configuration)
{
    public Profile Rename(string name) => ProfileType != ProfileType.Custom
        ? throw new InvalidOperationException("Only the custom profile has a local display name.")
        : this with { DisplayName = ValidateName(name) };
    private static string ValidateName(string name) => !string.IsNullOrWhiteSpace(name) && name.Trim().Length <= 48
        ? name.Trim() : throw new ArgumentException("Profile name must contain 1–48 characters.", nameof(name));
    public static ImmutableArray<Profile> Defaults => [
        new(HardwareProfileId.Claude, "Claude", ProfileType.Claude, "claude", ProfileConfiguration.Default),
        new(HardwareProfileId.Cursor, "Cursor", ProfileType.Cursor, "cursor", ProfileConfiguration.Default),
        new(HardwareProfileId.Codex, "Codex", ProfileType.Codex, "codex", ProfileConfiguration.Default),
        new(HardwareProfileId.Custom, "Custom", ProfileType.Custom, null, ProfileConfiguration.Default)];
}
