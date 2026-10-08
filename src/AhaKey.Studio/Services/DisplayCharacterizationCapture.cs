using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using AhaKey.Device.Usb;
using AhaKey.Protocol;
using AhaKey.Services;
namespace AhaKey.Studio.Services;

public static class DisplayCharacterizationCapture
{
    public static async Task RunAsync(string output)
    {
        output=Path.GetFullPath(output);Directory.CreateDirectory(output);
        var json=new JsonSerializerOptions{WriteIndented=true,Converters={new JsonStringEnumConverter()}};
        void Save(string file,object value)=>File.WriteAllText(Path.Combine(output,file),JsonSerializer.Serialize(value,json));
        using var owner=new SingleInstanceOwner(new SettingsStore().Root);
        if(!owner.IsPrimary)throw new InvalidOperationException("Close normal Studio before USB characterization.");
        var factory=new WindowsHidSessionFactory(displayCharacterization:true);
        var candidates=await factory.EnumerateAsync(default);
        File.WriteAllText(Path.Combine(output,"hid-candidates.json"),UsbDiagnosticExport.Redacted(new(){Candidates=candidates}));
        var candidate=HidSelectionPolicy.Select(candidates).Candidate??throw new InvalidOperationException("No unique validated USB collection; zero commands.");
        var marker=Path.Combine(new SettingsStore().Root,"phase35-ad1e-attempted.lock");
        using(var once=new FileStream(marker,FileMode.CreateNew,FileAccess.Write,FileShare.None))
        {var bytes=System.Text.Encoding.UTF8.GetBytes(DateTimeOffset.UtcNow.ToString("O"));once.Write(bytes);once.Flush(true);}
        // Marker is deliberately never deleted, including after errors; not a retry loop.
        object traceLock=new();
        using var trace=new StreamWriter(new FileStream(Path.Combine(output,"physical-events.jsonl"),FileMode.CreateNew,FileAccess.Write,FileShare.Read)){AutoFlush=true};
        var runner=new DisplayCharacterization(factory){Trace=(name,value)=>{lock(traceLock)trace.WriteLine(JsonSerializer.Serialize(new{At=DateTimeOffset.UtcNow,Event=name,Data=value}));}};
        var result=await runner.RunAsync(candidate);
        var commands=result.Queries.Select(q=>Convert.FromHexString(q.LogicalTx)[2]).ToArray();
        Save("physical-command-ledger.json",new{SourceVersion=Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion,
            result.PhysicalUnit,result.SessionId,Status00Count=commands.Count(c=>c==0),Layout9CCount=commands.Count(c=>c==0x9C),Binding83Count=commands.Count(c=>c==0x83),Binding94Count=commands.Count(c=>c==0x94),
            A1Count=commands.Length,A2Count=0,OtherCommandCount=commands.Count(c=>c is not (0 or 0x9C or 0x83 or 0x94)),PersistentSetterCount=0,Queries=result.Queries,result.TeardownCompleted,result.ReaderStopped,result.ClosedAt,result.RunError});
        var layout=result.Queries.FirstOrDefault(q=>q.Sequence==1)?.Response;
        Save("display-layout.json",new{
            PhysicalBoardEvidence=new{Source="User-confirmed AD1E photographs; Phase 3.4 board-photo-manifest",Panel="0.96-inch color IPS",FlashMarking="PY25Q64HA",RawFlashBytes=8_388_608},
            ClientExpectation=new{Width=160,Height=80,PixelFormat="RGB565",HistoricalSlotStrideBytes=28672,Source="Windows client/source expectation, not response defaults"},
            FirmwareEvidence=new{Session=result.SessionId,LayoutQuery=layout,DefaultBinding=result.Queries.FirstOrDefault(q=>q.Sequence==2)?.Response,AiBinding=result.Queries.FirstOrDefault(q=>q.Sequence==3)?.Response},
            CapacityComparison=layout?.Layout?.CapacityComparison??EvidenceComparison.NOT_REPORTED,DimensionsComparison=layout?.Layout?.DimensionsComparison??EvidenceComparison.NOT_REPORTED,
            BaselineStatus=result.Queries.FirstOrDefault(q=>q.Sequence==0)?.Response.Telemetry,FinalStatus=result.Queries.FirstOrDefault(q=>q.Sequence==4)?.Response.Telemetry,
            PersistentMemoryUnchangedProven=false,PhysicalUploadAvailable=false,FutureDisplayWriteDecision="NO-GO pending complete verified layout/bounds/migration contract"});
    }
}
