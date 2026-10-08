using AhaKey.Protocol;
namespace AhaKey.Device.Usb;
public sealed partial class UsbTransport
{
    public async Task<PhysicalCommandEvidence> SendControlAsync(ApprovedControl approved,CancellationToken ct)
    {
        await operations.WaitAsync(ct);
        var command=approved.Command;var report=command.UsbReport();
        var evidence=new PhysicalCommandEvidence(approved.Session,PhysicalTransportKind.Usb,command.Category,command.Operation,approved.Approval,DateTimeOffset.UtcNow,null,null,Convert.ToHexString(command.Frame.AsSpan()),Convert.ToHexString(report.AsSpan()),null,null,null);
        try
        {
            var active=session??throw new InvalidOperationException("No USB session.");
            if(active.Id!=approved.Session || !Observation.IsLive)throw new InvalidOperationException("Approval session no longer live.");
            using var bounded=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime!.Token);bounded.CancelAfter(TimeSpan.FromSeconds(5));
            var request=new Pending(active.Id,(ReadOnlyQuery)command.Opcode,evidence.StartedAt);
            lock(sync){accumulator.Clear();pending=request;}
            var native=await active.WriteControlAsync(approved,bounded.Token);
            evidence=evidence with{CompletedAt=DateTimeOffset.UtcNow,NativeResult=$"HID success={native.Success}; bytes={native.BytesWritten}; error={native.Error}"};
            if(!native.Success || native.BytesWritten!=report.Length)throw new IOException("Incomplete native HID write.");
            var response=await request.Response.Task.WaitAsync(bounded.Token);bounded.Token.ThrowIfCancellationRequested();
            if(session?.Id!=active.Id)throw new OperationCanceledException();
            evidence=evidence with{ResponseAt=response.At,Rx=Convert.ToHexString(response.Frame.AsSpan())};
            lock(sync)evidence=evidence with{NativeInputReports=request.Reports.Select(r=>Convert.ToHexString(r.AsSpan())).ToArray()};
            if(!command.AcceptsResponse(response.Frame.AsSpan()))throw new FormatException("Control ACK missing or rejected.");
            return evidence;
        }
        catch(Exception ex) when(ex is not OutOfMemoryException)
        {evidence=evidence with{Error=ex.GetType().Name};await CloseCore();throw new PhysicalControlException(evidence);}
        finally{lock(sync)pending=null;operations.Release();}
    }
}
