using AhaKey.Protocol;
namespace AhaKey.Device.Usb;

public sealed partial class UsbTransport
{
    public async Task UploadDisplayAsync(ApprovedDisplayUpload approval,Action<DisplayTransferEvidence> record,
        Action<DisplayResponseEvidence> responseRecord,CancellationToken ct)
    {
        await operations.WaitAsync(ct);
        try
        {
            var active=session??throw new InvalidOperationException("No USB session.");
            if(!Observation.IsLive || active.Id!=approval.Session || approval.Modern is null && Observation.Status?.WorkMode!=2)throw new InvalidOperationException("Live accepted USB profile 2 required.");
            var reports=approval.Begin(active.Id);int cursor=0;
            using var bounded=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime!.Token);bounded.CancelAfter(TimeSpan.FromSeconds(45+15*(approval.Modern?.Transfer.FrameCount??0)));
            Pending Expect(byte opcode)
            {var p=new Pending(active.Id,(ReadOnlyQuery)opcode,DateTimeOffset.UtcNow);lock(sync){accumulator.Clear();pending=p;}return p;}
            async Task Send(string stage)
            {
                int index=cursor++;var report=reports[index];
                var evidence=new DisplayTransferEvidence(active.Id,index,stage,DateTimeOffset.UtcNow,null,Convert.ToHexString(report.Report.AsSpan()),null,null);
                // Journal intent before native write, including A2 bytes; incomplete attempts remain visible.
                record(evidence);
                try
                {
                    var result=await active.WriteDisplayAsync(report,bounded.Token);
                    evidence=evidence with{CompletedAt=DateTimeOffset.UtcNow,NativeResult=$"HID success={result.Success}; bytes={result.BytesWritten}; error={result.Error}"};
                    if(!result.Success || result.BytesWritten!=65)throw new IOException("Incomplete HID Display write.");
                    record(evidence);
                }
                catch(Exception ex){record(evidence with{Error=ex.GetType().Name});throw;}
            }
            async Task<byte[]> Response(Pending p,string stage,bool binding=false)
            {
                var result=await p.Response.Task.WaitAsync(TimeSpan.FromSeconds(5),bounded.Token);
                var frame=result.Frame.ToArray();
                string[] native;lock(sync)native=p.Reports.Select(r=>Convert.ToHexString(r.AsSpan())).ToArray();
                if(session?.Id!=active.Id)throw new IOException("USB session changed.");
                if(binding ? !approval.MatchesBinding(frame,stage.Contains("verify")) : frame.Length!=6 || frame[3]!=0)
                {responseRecord(new(active.Id,"REJECTED "+stage,result.At,Convert.ToHexString(frame),native));throw new FormatException("Display response rejected or binding mismatch.");}
                responseRecord(new(active.Id,stage,result.At,Convert.ToHexString(frame),native));
                return frame;
            }
            var check=Expect(approval.Verify[2]);await Send("preflight binding");await Response(check,"preflight binding",true);
            foreach(var block in approval.Blocks)
            {
                var prepare=Expect(0x80);await Send($"80 sector {block.Sector}");await Response(prepare,$"80 sector {block.Sector}");
                var result=Expect(0x81);int count=block.UsbA2Reports().Count();
                for(int index=0;index<count;index++)
                {
                    await Send($"A2 sector {block.Sector} chunk {index}");await Task.Delay(2,bounded.Token);
                    if((index+1)%17==0 && index+1<count)await Task.Delay(12,bounded.Token);
                }
                await Response(result,$"81 sector {block.Sector} / 0x{block.Address:X6}");
            }
            await Task.Delay(25,bounded.Token);
            var bind=Expect(approval.Binding[2]);await Send($"{approval.Binding[2]:X2} binding");await Response(bind,$"{approval.Binding[2]:X2} binding");
            var save=Expect(4);await Send("04 global save");await Response(save,"04 save");
            await Task.Delay(250,bounded.Token);
            var verify=Expect(approval.Verify[2]);await Send($"{approval.Verify[2]:X2} verify");await Response(verify,$"{approval.Verify[2]:X2} verify",true);
        }
        catch {await CloseCore();throw;}
        finally{lock(sync)pending=null;operations.Release();}
    }
}
