namespace AhaKey.Device;
public sealed record ProfileSwitchAcceptance(Guid Session,bool Baseline2,bool SwitchAck,bool Observed1,bool RestoreAck,bool Observed2)
{
    public bool Accepted=>Session!=Guid.Empty && Baseline2 && SwitchAck && Observed1 && RestoreAck && Observed2;
}
