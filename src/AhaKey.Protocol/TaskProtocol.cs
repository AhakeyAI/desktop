namespace AhaKey.Protocol;
public sealed record FirmwareTaskSlot(byte Profile,byte State,byte Flags);
public sealed record FirmwareTaskStatus(byte Mode,byte HeartbeatSeconds,IReadOnlyList<FirmwareTaskSlot> Slots);
public static class TaskProtocol
{
    public static bool IsStatus(ReadOnlySpan<byte> f)
    {try{ParseStatus(f);return true;}catch(FormatException){return false;}}
    public static FirmwareTaskStatus ParseStatus(ReadOnlySpan<byte> f)
    {
        if(f.Length!=20||f[0]!=0xAA||f[1]!=0xBB||f[2]!=0x9A||f[3]!=0||f[^2]!=0xCC||f[^1]!=0xDD||f[4]>1||f[5]>30)throw new FormatException("Invalid task status.");
        var slots=new List<FirmwareTaskSlot>();for(int i=6;i<18;i+=3){if(f[i]>3||f[i+1]>4||f[i+2]>1)throw new FormatException("Invalid task slot.");slots.Add(new(f[i],f[i+1],f[i+2]));}
        return new(f[4],f[5],slots);
    }
    public static ushort ParseStandby(ReadOnlySpan<byte> f)
    {
        if(!AhaKeyProtocol.IsFrame(f,ReadOnlyQuery.Standby)||f.Length!=8||f[3]!=0)throw new FormatException("Invalid sleep response.");
        ushort minutes=System.Buffers.Binary.BinaryPrimitives.ReadUInt16LittleEndian(f[4..6]);
        if(minutes is not (0 or 5 or 10 or 15 or 30))throw new FormatException("Unsupported sleep minutes.");return minutes;
    }
}
