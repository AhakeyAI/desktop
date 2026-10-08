namespace AhaKey.Core;
// Immutable snapshots keep edits made while a write is in flight independent of its result.
public sealed class ConfigurationChangeTracker
{
    private ConfigurationSnapshot? baseline;
    private bool hasDraft;
    public DeviceConfiguration Draft { get; private set; } = DeviceConfiguration.Default;
    public ConfigurationSnapshot? LastDeviceRead { get; private set; }
    public ConfigurationSnapshot? LastWritten { get; private set; }
    public ConfigurationSnapshot? PendingWrite { get; private set; }
    public SyncState State { get; private set; } = SyncState.Indeterminate;
    public DeviceConfiguration BaselineConfiguration => baseline?.Configuration ?? DeviceConfiguration.Default;
    public bool IsProfileDirty(HardwareProfileId id) => !(Draft with { Profiles = Draft.Profiles.SetItem(id, BaselineConfiguration.Profiles[id]) }).EquivalentTo(Draft);
    public bool IsDirty => baseline is null || !baseline.Configuration.EquivalentTo(Draft);
    public void Edit(DeviceConfiguration draft)
    {
        Draft = draft; hasDraft = true;
        if (State != SyncState.Writing) State = IsDirty ? SyncState.UnsavedChanges : baseline?.Source is SnapshotSource.MockWriteAccepted or SnapshotSource.DeviceWriteAccepted ? SyncState.WriteAccepted : baseline is not null ? SyncState.Synced : SyncState.Indeterminate;
    }
    public void Read(ConfigurationSnapshot snapshot)
    {
        if (State == SyncState.Writing) throw new InvalidOperationException("Cannot replace read evidence during a write.");
        var preserveDraft = hasDraft && IsDirty;
        LastDeviceRead = snapshot; baseline = snapshot; hasDraft = true;
        // New read supersedes ACK evidence, which stays available for inspection.
        if (!preserveDraft) Draft = snapshot.Configuration;
        State = Draft.EquivalentTo(snapshot.Configuration) ? SyncState.Synced : SyncState.UnsavedChanges;
    }
    public ConfigurationSnapshot BeginWrite(Guid session, DeviceIdentity identity, DateTimeOffset now)
    {
        if (PendingWrite is not null) throw new InvalidOperationException("A write is already in flight.");
        PendingWrite = new(Draft, identity.IsSimulation ? SnapshotSource.MockWriteAccepted : SnapshotSource.DeviceWriteAccepted, session, identity, now);
        State = SyncState.Writing;
        return PendingWrite;
    }
    public void AcceptWrite(Guid session)
    {
        if (PendingWrite is null || PendingWrite.SessionId != session) throw new InvalidOperationException("Write session mismatch.");
        LastWritten = PendingWrite; baseline = PendingWrite; PendingWrite = null;
        State = Draft.EquivalentTo(LastWritten.Configuration) ? SyncState.WriteAccepted : SyncState.UnsavedChanges;
    }
    public void FailWrite(bool indeterminate) { PendingWrite = null; State = indeterminate ? SyncState.Indeterminate : SyncState.WriteFailed; }
    public void InvalidateSession() { PendingWrite = null; State = SyncState.Indeterminate; }
}
