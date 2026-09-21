namespace AhaKey.Device;
// Separate proof: accepting BLE runtime lighting never promotes keys, Display or other effects.
public sealed record BleRuntimeAcceptance(string DeviceHash,string Firmware,Guid Session,bool EffectObserved,bool NeutralObserved,string Evidence)
{
    public bool Matches(string? hash,string firmware)=>Session!=Guid.Empty && EffectObserved && NeutralObserved && DeviceHash==hash && Firmware==firmware;
}
