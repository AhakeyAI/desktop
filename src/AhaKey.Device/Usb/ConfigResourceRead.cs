using System.Collections.Immutable;
using AhaKey.Protocol;
namespace AhaKey.Device.Usb;

public sealed class ApprovedConfigRead
{
    private int used;
    public Guid Session {get;}
    public byte Resource {get;}
    public byte Index {get;}
    public byte Offset {get;}
    public ImmutableArray<byte> Frame {get;}
    public ImmutableArray<byte> Report=>StaticDisplayPlan.A1(Frame);
    internal ApprovedConfigRead(Guid session,byte resource,byte index,byte offset)
    {Session=session;Resource=resource;Index=index;Offset=offset;Frame=new WindowsContract32ProtocolAdapter().QueryConfig(resource,index,offset);}
    public void Consume(Guid session)
    {if(session!=Session||Interlocked.Exchange(ref used,1)!=0)throw new InvalidOperationException("Stale or consumed configuration query.");}
}
public sealed partial class UsbTransport
{
    public async Task<ImmutableArray<byte>> ReadConfigAsync(byte resource,byte index,Action<PhysicalCommandEvidence> record,CancellationToken ct)
    {
        await operations.WaitAsync(ct);
        try
        {
            var active=session??throw new InvalidOperationException("No live USB session.");
            var identity=FirmwareProtocols.Identify(Observation.Status,Observation.Capabilities);
            if(!Observation.IsLive||!new AhaKey.Core.DeviceFeatureCatalog(identity,AhaKey.Core.FeatureTransport.Usb,new()).CanReadConfigResource(resource).Available)throw new InvalidOperationException("Resource unavailable for this firmware.");
            int total=WindowsContract32ProtocolAdapter.ResourceLength(resource,index);var bytes=ImmutableArray.CreateBuilder<byte>(total);
            var adapter=new WindowsContract32ProtocolAdapter();
            while(bytes.Count<total)
            {
                using var timeout=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime!.Token);timeout.CancelAfter(QueryTimeout);
                var query=new ApprovedConfigRead(active.Id,resource,index,(byte)bytes.Count);
                var evidence=new PhysicalCommandEvidence(active.Id,PhysicalTransportKind.Usb,ControlCategory.ConfigurationRead,"9D partial live resource","User requested supported readback",DateTimeOffset.UtcNow,null,null,Convert.ToHexString(query.Frame.AsSpan()),Convert.ToHexString(query.Report.AsSpan()),null,null,null);
                record(evidence);
                var request=new Pending(active.Id,(ReadOnlyQuery)0x9D,evidence.StartedAt);lock(sync){accumulator.Clear();pending=request;}
                try
                {
                    var result=await active.WriteConfigAsync(query,timeout.Token);
                    evidence=evidence with{CompletedAt=DateTimeOffset.UtcNow,NativeResult=$"{result.Success}; {result.BytesWritten}; {result.Error}"};
                    if(!result.Success||result.BytesWritten!=65)throw new IOException("Incomplete read request.");
                    var response=await request.Response.Task.WaitAsync(timeout.Token);
                    evidence=evidence with{ResponseAt=response.At,Rx=Convert.ToHexString(response.Frame.AsSpan()),NativeInputReports=request.Reports.Select(x=>Convert.ToHexString(x.AsSpan())).ToArray()};
                    var slice=adapter.ParseConfig(response.Frame.AsSpan(),resource,index,query.Offset);bytes.AddRange(slice.Data);record(evidence);
                }
                catch(Exception ex){record(evidence with{Error=ex.GetType().Name});throw;}
            }
            return bytes.ToImmutable();
        }
        catch{await CloseCore();throw;}
        finally{lock(sync)pending=null;operations.Release();}
    }
}
