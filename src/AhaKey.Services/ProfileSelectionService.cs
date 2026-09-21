using AhaKey.Core;
namespace AhaKey.Services;
public sealed class ProfileSelectionService(SettingsStore store)
{
    public StudioSettings Settings { get; private set; } = store.Load();
    public event Action? Changed;
    public string LocalKeyName(HardwareProfileId profile,PhysicalKey key)
    {
        var name=Settings.KeyLocalNames.GetValueOrDefault($"{(int)profile}:{(int)key}");
        return string.IsNullOrWhiteSpace(name)?key switch{PhysicalKey.K1=>"Record",PhysicalKey.K2=>"Accept",PhysicalKey.K3=>"Reject",PhysicalKey.K4=>"Backspace",_=>throw new ArgumentOutOfRangeException(nameof(key))}:name;
    }
    public void Update(Func<StudioSettings, StudioSettings> change)
    { var next = change(Settings); store.Save(next); Settings = next; Changed?.Invoke(); }
    public void Select(HardwareProfileId id)
    {
        if (!Enum.IsDefined(id)) throw new ArgumentOutOfRangeException(nameof(id));
        Update(s => s with { SelectedProfile = id });
    }
    public void RenameCustom(string name)
    { var renamed = Profile.Defaults[3].Rename(name); Update(s => s with { CustomProfileName = renamed.DisplayName }); }
}
