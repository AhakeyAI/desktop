using AhaKey.Core;
namespace AhaKey.Device;
// Transport-independent draft operations; firmware capability is deliberately narrower than the action hierarchy.
public sealed class KeymapSession(DeviceManager manager)
{
    private readonly Dictionary<(HardwareProfileId,PhysicalKey),string> invalidLabels = [];
    private readonly Stack<DeviceConfiguration> undo = new();
    private DeviceConfiguration localResetPoint=manager.Tracker.Draft;
    public bool CanUndo=>undo.Count>0;
    public void Undo(){if(undo.TryPop(out var draft)){invalidLabels.Clear();manager.Edit(draft);}}
    public void AcceptLocalKey(HardwareProfileId profile,PhysicalKey key,KeyAction action,string label)
    {var p=localResetPoint.Profiles[profile];localResetPoint=localResetPoint with{Profiles=localResetPoint.Profiles.SetItem(profile,p with{Keys=p.Keys.SetItem(key,action),DeviceLabels=p.DeviceLabels.SetItem(key,label)})};}
    public void CopyFromProfile(HardwareProfileId source)
    {
        if(!Enum.IsDefined(source))throw new ArgumentOutOfRangeException(nameof(source));
        var from=manager.Tracker.Draft.Profiles[source];var target=Configuration;
        foreach(var key in new[]{PhysicalKey.K2,PhysicalKey.K3,PhysicalKey.K4})
        {invalidLabels.Remove((Profile,key));target=target with{Keys=target.Keys.SetItem(key,from.Keys[key]),DeviceLabels=target.DeviceLabels.SetItem(key,from.Label(key))};}
        Update(target);
    }
    public void CopyKeyToProfile(HardwareProfileId target)
    {
        EnsureEditable();if(!Enum.IsDefined(target)||!IsLabelValid)throw new ArgumentException();
        var destination=manager.Tracker.Draft.Profiles[target];undo.Push(manager.Tracker.Draft);
        manager.Edit(manager.Tracker.Draft with{Profiles=manager.Tracker.Draft.Profiles.SetItem(target,destination with{Keys=destination.Keys.SetItem(Key,Action),DeviceLabels=destination.DeviceLabels.SetItem(Key,DeviceLabel)})});
    }
    public HardwareProfileId Profile { get; set; } = HardwareProfileId.Codex;
    public PhysicalKey Key { get; private set; } = PhysicalKey.K2;
    public bool HasInvalidLabels => invalidLabels.Count>0;
    public bool IsLabelValid => !invalidLabels.ContainsKey((Profile,Key));
    public string DeviceLabel => invalidLabels.GetValueOrDefault((Profile,Key),Configuration.Label(Key));
    public ProfileConfiguration Configuration => manager.Tracker.Draft.Profiles[Profile];
    public KeyAction Action => Configuration.Keys[Key];
    public void SelectKey(PhysicalKey key) { if(!Enum.IsDefined(key)) throw new ArgumentOutOfRangeException(nameof(key)); Key=key; }
    private void EnsureEditable() { if(Key==PhysicalKey.K1) throw new InvalidOperationException("K1 is fixed Voice / F18."); }
    public void SetShortcut(ShortcutGesture gesture)
    {
        EnsureEditable(); if(!ShortcutGesture.TryParse(gesture.Canonical,out var valid) || valid!.Modifiers != gesture.Modifiers) throw new ArgumentException("Invalid shortcut.");
        Update(Configuration with { Keys=Configuration.Keys.SetItem(Key,new KeyboardShortcutAction(valid.Canonical)) });
    }
    public void SetDeviceLabel(string label)
    {
        EnsureEditable();
        if(!DeviceLabelRules.IsValid(label)) { invalidLabels[(Profile,Key)]=label; return; }
        invalidLabels.Remove((Profile,Key)); Update(Configuration with { DeviceLabels=Configuration.DeviceLabels.SetItem(Key,label) });
    }
    public bool IsDirty(HardwareProfileId profile) => manager.Tracker.IsProfileDirty(profile) || invalidLabels.Keys.Any(x=>x.Item1==profile);
    // Clearing is explicitly a simulator-only DisabledAction, never an asserted firmware command.
    public void ClearForSimulation() { EnsureEditable(); if(!manager.Device.Identity.IsSimulation) throw new InvalidOperationException("Simulation required."); Update(Configuration with { Keys=Configuration.Keys.SetItem(Key,new DisabledAction()) }); }
    public void ResetKey()
    {
        EnsureEditable(); invalidLabels.Remove((Profile,Key)); var baseline=localResetPoint.Profiles[Profile];
        Update(Configuration with { Keys=Configuration.Keys.SetItem(Key,baseline.Keys[Key]), DeviceLabels=Configuration.DeviceLabels.SetItem(Key,baseline.Label(Key)) });
    }
    private void Update(ProfileConfiguration profile) {undo.Push(manager.Tracker.Draft);manager.Edit(manager.Tracker.Draft with { Profiles=manager.Tracker.Draft.Profiles.SetItem(Profile,profile) });}
}
public sealed record SimulatedActionResult(KeyAction Action);
public interface IActionSimulator
{
    SimulatedActionResult TestAction(PhysicalKey key, KeyAction action);
}
