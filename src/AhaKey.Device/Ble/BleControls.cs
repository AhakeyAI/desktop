using AhaKey.Protocol;
namespace AhaKey.Device.Ble;
public sealed partial class BleTransport
{
    public async Task<PhysicalCommandEvidence> SendControlAsync(ApprovedControl approved,CancellationToken ct)
    {
        await operations.WaitAsync(ct);
        var command=approved.Command;
        var evidence=new PhysicalCommandEvidence(approved.Session,PhysicalTransportKind.Bluetooth,command.Category,command.Operation,approved.Approval,DateTimeOffset.UtcNow,null,null,Convert.ToHexString(command.Frame.AsSpan()),null,null,null,null);
        try
        {
            var active=session??throw new InvalidOperationException("No BLE session.");
            if(active.Id!=approved.Session || !Observation.IsLive)throw new InvalidOperationException("Approval session no longer live.");
            using var bounded=CancellationTokenSource.CreateLinkedTokenSource(ct,sessionCancellation!.Token);bounded.CancelAfter(TimeSpan.FromSeconds(5));
            var ticket=generation;
            var request=new PendingQuery(active.Id,(ReadOnlyQuery)command.Opcode){StartedAt=evidence.StartedAt};
            lock(sync)pending=request;
            var native=await active.WriteControlAsync(contract.Service,contract.Command,approved,bounded.Token);
            evidence=evidence with{CompletedAt=DateTimeOffset.UtcNow,NativeResult=$"GATT {native.Status}; ATT={native.ProtocolError}"};
            native.RequireSuccess("Control WriteWithResponse");EnsureCurrent(ticket,bounded.Token);
            var response=await request.Response.Task.WaitAsync(bounded.Token);EnsureCurrent(ticket,bounded.Token);
            evidence=evidence with{ResponseAt=response.ArrivedAt,Rx=Convert.ToHexString(response.Bytes.AsSpan())};
            if(!command.AcceptsResponse(response.Bytes.AsSpan()))throw new FormatException("Control ACK missing or rejected.");
            return evidence;
        }
        catch(Exception ex) when(ex is not OutOfMemoryException)
        {evidence=evidence with{Error=ex.GetType().Name};await CloseCore();throw new PhysicalControlException(evidence);}
        finally{lock(sync)pending=null;operations.Release();}
    }
}
