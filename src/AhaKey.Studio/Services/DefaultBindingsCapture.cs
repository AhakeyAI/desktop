using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using AhaKey.Device.Usb;
using AhaKey.Services;
namespace AhaKey.Studio.Services;

// Completion task only: status, four default bindings, status. No setters/retries.
public static class DefaultBindingsCapture
{
    public static async Task RunAsync(string output)
    {
        output=Path.GetFullPath(output);Directory.CreateDirectory(output);
        var settings=new SettingsStore();using var owner=new SingleInstanceOwner(settings.Root);
        if(!owner.IsPrimary)throw new InvalidOperationException("Close Studio before default binding characterization.");
        var factory=new WindowsHidSessionFactory(defaultBindings:true);
        var candidates=await factory.EnumerateAsync(default);
        var candidate=HidSelectionPolicy.Select(candidates).Candidate??throw new InvalidOperationException("No unique validated USB collection; no commands sent.");
        var acceptance=JsonSerializer.Deserialize<ControlAcceptance>(File.ReadAllText(Path.Combine(settings.Root,"physical-controls-acceptance.json")));
        var hash=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("Usb:"+candidate.Path)));
        if(acceptance?.DeviceHash!=hash)throw new InvalidOperationException("USB identity differs from accepted AD1E; no commands sent.");
        using(var once=new FileStream(Path.Combine(settings.Root,"phase4b-completion-default-bindings.lock"),FileMode.CreateNew,FileAccess.Write,FileShare.None))
        {JsonSerializer.Serialize(once,new{At=DateTimeOffset.UtcNow,Commands=new[]{"00","83 00","83 01","83 02","83 03","00"}});once.Flush(true);}
        var json=new JsonSerializerOptions{WriteIndented=true,Converters={new JsonStringEnumConverter()}};
        object sync=new();
        using var trace=new StreamWriter(new FileStream(Path.Combine(output,"physical-events.jsonl"),FileMode.CreateNew,FileAccess.Write,FileShare.Read)){AutoFlush=true};
        var runner=new DisplayCharacterization(factory){DefaultBindings=true,Trace=(name,value)=>{lock(sync)trace.WriteLine(JsonSerializer.Serialize(new{At=DateTimeOffset.UtcNow,Event=name,Data=value}));}};
        var result=await runner.RunAsync(candidate);
        File.WriteAllText(Path.Combine(output,"default-bindings-ledger.json"),JsonSerializer.Serialize(result,json));
    }
}
