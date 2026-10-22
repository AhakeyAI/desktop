using System.Buffers.Binary;
using System.Collections.Immutable;
using System.Security.Cryptography;
namespace AhaKey.Protocol;

// Proven candidate only. Never uses the generic profile*44 allocation or an unbound slot.
public sealed class StaticDisplayPlan
{
    public static DisplayBinding ExpectedBinding {get;}=new(2,null,9,1,100,292);
    public ImmutableArray<byte> Frame {get;}
    public string Sha256 {get;}
    public ImmutableArray<DisplayFlashBlock> Blocks {get;}
    public ImmutableArray<byte> Binding => [0xAA,0xBB,0x82,2,9,0,1,0,100,0,0xCC,0xDD];
    public ImmutableArray<byte> Verify => [0xAA,0xBB,0x83,2,0xCC,0xDD];
    public ImmutableArray<byte> Save => [0xAA,0xBB,4,0xCC,0xDD];
    public int StartAddress=>9*DisplayWritePlan.SlotStride;
    public int PixelEnd=>StartAddress+DisplayPixelEncoder.FrameBytes-1;
    public int EraseEnd=>StartAddress+DisplayWritePlan.SlotStride-1;
    public int A2ReportCount=>Blocks.Sum(b=>b.UsbA2Reports().Count());
    public bool MatchesBinding(ReadOnlySpan<byte> response)=>DisplayReadProtocol.Parse(0x83,response,2).Binding==ExpectedBinding;
    private StaticDisplayPlan(ReadOnlySpan<byte> frame)
    {
        if(frame.Length!=DisplayPixelEncoder.FrameBytes)throw new ArgumentException("Exactly one 160x80 RGB565 frame is required.");
        Frame=[..frame];Sha256=Convert.ToHexString(SHA256.HashData(frame));
        var blocks=ImmutableArray.CreateBuilder<DisplayFlashBlock>();
        for(int offset=0;offset<frame.Length;offset+=4096)
        {
            int length=Math.Min(4096,frame.Length-offset),address=StartAddress+offset;
            var prepare=new byte[]{0xAA,0xBB,0x80,0,0,0,0,0,0,0,0xCC,0xDD};
            BinaryPrimitives.WriteUInt16LittleEndian(prepare.AsSpan(4),(ushort)length);
            BinaryPrimitives.WriteUInt32LittleEndian(prepare.AsSpan(6),(uint)address);
            blocks.Add(new(9,address,address/4096,length,[..prepare],Frame.Slice(offset,length)));
        }
        Blocks=blocks.ToImmutable();
    }
    public static StaticDisplayPlan Create(DisplayBinding binding,IReadOnlyList<byte[]> frames)
    {
        if(binding!=ExpectedBinding)throw new ArgumentException("Only the observed profile 2 / Default / slot 9 binding is in scope.");
        if(frames.Count!=1)throw new ArgumentException("Animated/multi-frame physical upload is not accepted.");
        return new(frames[0]);
    }
    public static ImmutableArray<byte> A1(ImmutableArray<byte> command)
    {var report=new byte[65];report[1]=0xA1;report[2]=(byte)command.Length;command.CopyTo(report,3);return [..report];}
}
