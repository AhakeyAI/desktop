using System.Collections.Immutable;
using System.Security.Cryptography;
using System.Buffers.Binary;
using AhaKey.Core;
namespace AhaKey.Protocol;

public sealed class Windows32DisplayUploadPlan
{
    public DisplayWritePlan Transfer {get;}
    public DisplayAllocation Allocation {get;}
    public string Sha256 {get;}
    public ImmutableArray<string> FrameHashes {get;}
    public ImmutableArray<byte> Verify {get;}
    private Windows32DisplayUploadPlan(DisplayWritePlan transfer,DisplayAllocation allocation,IReadOnlyList<byte[]> frames)
    {
        Transfer=transfer;Allocation=allocation;
        FrameHashes=[..frames.Select(x=>Convert.ToHexString(SHA256.HashData(x)))];
        using var hash=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);foreach(var frame in frames)hash.AppendData(frame);
        Sha256=Convert.ToHexString(hash.GetHashAndReset());
        Verify=transfer.Asset==DisplayState.Default?[0xAA,0xBB,0x83,(byte)transfer.Profile,0xCC,0xDD]:[0xAA,0xBB,0x94,(byte)transfer.Profile,(byte)transfer.Asset,0xCC,0xDD];
    }
    public static Windows32DisplayUploadPlan Create(HardwareProfileId profile,DisplayState state,IReadOnlyList<byte[]> frames,int interval)
    {
        var allocation=Windows32DisplayGeometry.Target(profile,state);
        if(frames.Count<1||frames.Count>allocation.Capacity)throw new ArgumentOutOfRangeException(nameof(frames));
        var transfer=DisplayWritePlan.Create(profile,state,frames,interval);
        if(transfer.StartSlot!=allocation.StartSlot || transfer.Blocks.Any(b=>!allocation.Contains(b.Address,b.Length)||!allocation.Contains(b.Sector*4096,4096)))throw new ArgumentException("Frame or erase crosses target allocation.");
        return new(transfer,allocation,frames);
    }
    public bool MatchesBinding(ReadOnlySpan<byte> f,bool exact)
    {
        bool defaults=Transfer.Asset==DisplayState.Default;int length=defaults?15:16,offset=defaults?5:6;
        if(f.Length!=length||f[0]!=0xAA||f[1]!=0xBB||f[2]!=Verify[2]||f[3]!=0||f[4]!=(byte)Transfer.Profile||!defaults&&f[5]!=(byte)Transfer.Asset||f[^2]!=0xCC||f[^1]!=0xDD)return false;
        ushort start=BinaryPrimitives.ReadUInt16LittleEndian(f[offset..]),count=BinaryPrimitives.ReadUInt16LittleEndian(f[(offset+2)..]),interval=BinaryPrimitives.ReadUInt16LittleEndian(f[(offset+4)..]),slots=BinaryPrimitives.ReadUInt16LittleEndian(f[(offset+6)..]);
        return slots>=Allocation.StartSlot+Allocation.Capacity && (long)start+count<=slots && (!exact||start==Allocation.StartSlot&&count==Transfer.FrameCount&&interval==Transfer.IntervalMs);
    }
}
