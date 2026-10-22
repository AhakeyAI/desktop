namespace AhaKey.Protocol;
public sealed record ModeSync(byte Mode,byte Source,byte Sequence);
public static class ModeSyncProtocol
{
    public static ModeSync Parse(ReadOnlySpan<byte> frame)
    {
        if(!AhaKeyProtocol.IsFrame(frame,ReadOnlyQuery.ModeSync)||frame.Length!=9||frame[3]!=0||frame[4]>3||frame[5]>2)
            throw new FormatException("Invalid hardware profile frame.");
        return new(frame[4],frame[5],frame[6]);
    }
}
// Serial-number arithmetic: duplicate and older half-window values are discarded.
// Session IDs come from the owning native transport, never from payload bytes.
public sealed class ModeSyncTracker
{
    private Guid session;private byte? sequence;
    public void Reset(Guid value){session=value;sequence=null;}
    public bool Accept(Guid value,ReadOnlySpan<byte> frame,out ModeSync mode)
    {
        mode=null!;if(value!=session||session==Guid.Empty||frame.Length<3||frame[2]!=0x9B)return false;
        try{mode=ModeSyncProtocol.Parse(frame);}catch(FormatException){return false;}
        if(sequence is {} last){int delta=(mode.Sequence-last)&255;if(delta==0||delta>=128)return false;}
        sequence=mode.Sequence;return true;
    }
}
