using System.Buffers.Binary;
using System.Collections.Immutable;
using AhaKey.Core;
namespace AhaKey.Protocol;

public static class DisplayPixelEncoder
{
    public const int Width=160,Height=80,FrameBytes=25600;
    // Canvas pixels are RGB24, row-major, after compositing and letterboxing.
    public static byte[] Rgb565(ReadOnlySpan<byte> rgb)
    {
        if(rgb.Length!=Width*Height*3)throw new ArgumentException("Expected one 160x80 RGB24 canvas.");
        var result=new byte[FrameBytes];
        for(int i=0,j=0;i<rgb.Length;i+=3,j+=2)
        {ushort value=(ushort)(((rgb[i]>>3)<<11)|((rgb[i+1]>>2)<<5)|(rgb[i+2]>>3));BinaryPrimitives.WriteUInt16BigEndian(result.AsSpan(j),value);}
        return result;
    }
}
public sealed record DisplayTiming(ImmutableArray<int> SourceIndices,int IntervalMs,long SourceDurationMs)
{
    // Retained Java GifUploadRules: uniform output timing with time-midpoint sampling.
    public static DisplayTiming Create(IReadOnlyList<int> delays,int limit)
    {
        if(delays.Count is <1 or >500 || limit is <1 or >292)throw new ArgumentOutOfRangeException(nameof(limit));
        var normalized=delays.Select(x=>x<=0?100:x).ToArray();
        long total=normalized.Sum(x=>(long)x);int count=Math.Min(delays.Count,limit);
        var indices=ImmutableArray.CreateBuilder<int>(count);long[] starts=new long[delays.Count];
        for(int i=1;i<starts.Length;i++)starts[i]=starts[i-1]+normalized[i-1];
        int previous=-1;
        for(int i=0;i<count;i++)
        {
            int selected=i;
            if(delays.Count>limit)
            {
                long target=(long)Math.Floor((i+0.5)*total/count+0.5);
                selected=Array.BinarySearch(starts,target);if(selected<0)selected=~selected-1;
                selected=Math.Clamp(selected,previous+1,delays.Count-(count-i));
            }
            indices.Add(selected);previous=selected;
        }
        return new(indices.ToImmutable(),(int)Math.Clamp((long)Math.Floor((double)total/count+0.5),1,65535),total);
    }
}
public sealed record DisplayFlashBlock(int Slot,int Address,int Sector,int Length,ImmutableArray<byte> Prepare,ImmutableArray<byte> Data)
{
    public IEnumerable<ImmutableArray<byte>> UsbA2Reports()
    {
        // Java hands each 1024-byte batch separately to UsbBridgeTransport.sendData.
        // Preserve those boundaries: a 4096-byte block is 4 * 17 reports, not 67.
        foreach(var batch in JavaBatches())for(int start=0;start<batch.Length;start+=62)
        {int count=Math.Min(62,batch.Length-start);var report=new byte[65];report[1]=0xA2;report[2]=(byte)count;batch.AsSpan(start,count).CopyTo(report.AsSpan(3));yield return [..report];}
    }
    public IEnumerable<ImmutableArray<byte>> JavaBatches()
    {for(int start=0;start<Data.Length;start+=1024)yield return Data.Slice(start,Math.Min(1024,Data.Length-start));}
}
public sealed record DisplayWritePlan(HardwareProfileId Profile,DisplayState Asset,int StartSlot,int FrameCount,int IntervalMs,
    ImmutableArray<DisplayFlashBlock> Blocks,ImmutableArray<byte> Binding)
{
    public const int SlotStride=28672,SectorBytes=4096,FlashBytes=8*1024*1024;
    public bool PhysicalUploadAllowed=>false;
    public bool PixelBackupAvailable=>false;
    public bool RollbackAvailable=>false;
    public string GateReason=>"NO-GO for this generic allocation: reserved and AI regions unknown; select an existing verified default binding and explicitly authorize that asset's loss. Pixel backup is not an absolute requirement.";
    public int TotalBytes=>checked(FrameCount*DisplayPixelEncoder.FrameBytes);
    public ImmutableArray<byte> Persistence=>[0xAA,0xBB,4,0xCC,0xDD];
    // A deterministic current-Java allocation proposal, never a measured free-space claim.
    public static DisplayWritePlan Create(HardwareProfileId profile,DisplayState asset,IReadOnlyList<byte[]> frames,int intervalMs)
    {
        if(!Enum.IsDefined(profile)||!Enum.IsDefined(asset))throw new ArgumentOutOfRangeException(nameof(profile));
        int state=(int)asset;var allocation=Windows32DisplayGeometry.Target(profile,asset);
        if(state>=4 || frames.Count<1 || frames.Count>allocation.Capacity || intervalMs is <1 or >65535)throw new ArgumentOutOfRangeException(nameof(frames));
        int start=allocation.StartSlot;
        var blocks=ImmutableArray.CreateBuilder<DisplayFlashBlock>();
        for(int frame=0;frame<frames.Count;frame++)
        {
            if(frames[frame].Length!=DisplayPixelEncoder.FrameBytes)throw new ArgumentException("Invalid frame byte length.");
            int slot=start+frame,baseAddress=checked(slot*SlotStride);
            if(baseAddress<0 || checked(baseAddress+SlotStride)>FlashBytes)throw new ArgumentOutOfRangeException(nameof(frames));
            for(int offset=0;offset<DisplayPixelEncoder.FrameBytes;offset+=SectorBytes)
            {
                int length=Math.Min(SectorBytes,DisplayPixelEncoder.FrameBytes-offset),address=baseAddress+offset;
                var prepare=new byte[]{0xAA,0xBB,0x80,0,0,0,0,0,0,0,0xCC,0xDD};
                BinaryPrimitives.WriteUInt16LittleEndian(prepare.AsSpan(4),(ushort)length);BinaryPrimitives.WriteUInt32LittleEndian(prepare.AsSpan(6),(uint)address);
                blocks.Add(new(slot,address,address/SectorBytes,length,[..prepare],[..frames[frame].AsSpan(offset,length)]));
            }
        }
        var binding=new List<byte>{0xAA,0xBB,(byte)(state==0?0x82:0x93),(byte)profile};if(state!=0)binding.Add((byte)state);
        foreach(int n in new[]{start,frames.Count,intervalMs}){binding.Add((byte)n);binding.Add((byte)(n>>8));}binding.AddRange([0xCC,0xDD]);
        return new(profile,asset,start,frames.Count,intervalMs,blocks.ToImmutable(),[..binding]);
    }
}
public sealed record BrightnessRestorePlan(byte Original,byte Temporary)
{
    public bool PhysicalAllowed=>false;
    public ImmutableArray<LegacyControlCommand> Commands=>[LegacyControlCommand.Brightness(Temporary),LegacyControlCommand.Brightness(Original)];
    public static BrightnessRestorePlan Create(byte original,byte temporary)
    {_=LegacyControlCommand.Brightness(original);_=LegacyControlCommand.Brightness(temporary);return new(original,temporary);}
}
