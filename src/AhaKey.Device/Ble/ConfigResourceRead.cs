using System.Collections.Immutable;
using AhaKey.Protocol;
using AhaKey.Core;
namespace AhaKey.Device.Ble;
public sealed partial class BleTransport
{
    public async Task<ImmutableArray<byte>> ReadConfigAsync(byte resource,byte index,Action<PhysicalCommandEvidence> record,CancellationToken ct)
    {
        await operations.WaitAsync(ct);
        try
        {
            var active=session??throw new InvalidOperationException("No live BLE session.");
            var identity=FirmwareProtocols.Identify(Observation.Status,Observation.Capabilities);
            if(!Observation.IsLive||!new DeviceFeatureCatalog(identity,FeatureTransport.Bluetooth,new()).CanReadConfigResource(resource).Available)throw new InvalidOperationException("Resource unavailable for this firmware.");
            int total=WindowsContract32ProtocolAdapter.ResourceLength(resource,index);var bytes=ImmutableArray.CreateBuilder<byte>(total);
            var adapter=new WindowsContract32ProtocolAdapter();var ticket=generation;
            while(bytes.Count<total)
            {
                using var timeout=CancellationTokenSource.CreateLinkedTokenSource(ct,sessionCancellation!.Token);timeout.CancelAfter(QueryTimeout);
                var query=new Usb.ApprovedConfigRead(active.Id,resource,index,(byte)bytes.Count);
                var evidence=new PhysicalCommandEvidence(active.Id,PhysicalTransportKind.Bluetooth,ControlCategory.ConfigurationRead,"9D partial live resource","User requested supported readback",DateTimeOffset.UtcNow,null,null,Convert.ToHexString(query.Frame.AsSpan()),null,null,null,null);
                record(evidence);
                var request=new PendingQuery(active.Id,(ReadOnlyQuery)0x9D){StartedAt=evidence.StartedAt};lock(sync)pending=request;
                try
                {
                    var result=await active.WriteConfigAsync(contract.Service,contract.Command,query,timeout.Token);
                    evidence=evidence with{CompletedAt=DateTimeOffset.UtcNow,NativeResult=$"GATT {result.Status}; ATT={result.ProtocolError}"};result.RequireSuccess("9D query");
                    var response=await request.Response.Task.WaitAsync(timeout.Token);EnsureCurrent(ticket,timeout.Token);
                    evidence=evidence with{ResponseAt=response.ArrivedAt,Rx=Convert.ToHexString(response.Bytes.AsSpan())};
                    var slice=adapter.ParseConfig(response.Bytes.AsSpan(),resource,index,query.Offset);
                    if(slice.Data.IsEmpty||bytes.Count+slice.Data.Length>total)throw new FormatException("Invalid readback progress.");
                    bytes.AddRange(slice.Data);record(evidence);
                }
                catch(Exception ex){record(evidence with{Error=ex.GetType().Name});throw;}
            }
            return bytes.ToImmutable();
        }
        catch{await CloseCore();throw;}
        finally{lock(sync)pending=null;operations.Release();}
    }
}
