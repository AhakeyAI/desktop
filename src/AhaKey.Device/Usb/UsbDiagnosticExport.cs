using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;
namespace AhaKey.Device.Usb;
public static class UsbDiagnosticExport
{
    public static object Candidate(HidCandidate c) => new { Path="[redacted]",InstanceId="[redacted]",c.Vid,c.Pid,c.InterfaceNumber,c.Collection,c.UsagePage,c.Usage,c.InputLength,c.OutputLength,c.FeatureLength,c.InputIds,c.OutputIds,Manufacturer=c.Manufacturer is null?null:"[redacted]",Product=c.Product is null?null:"[redacted]",c.InspectionError,Accepted=HidSelectionPolicy.IsValid(c) };
    public static string Redacted(UsbDiagnostics d)
    {
        string? Safe(string? text)
        {
            if(text is null)return null;
            foreach(var c in d.Candidates.Concat(d.Selected is null?[]:new[]{d.Selected}))
                foreach(var id in new[]{c.Path,c.InstanceId,c.Manufacturer,c.Product})
                    if(!string.IsNullOrEmpty(id))text=text.Replace(id,"[redacted]",StringComparison.OrdinalIgnoreCase);
            return text;
        }
        return JsonSerializer.Serialize(new {Transport="USB",d.Stage,d.SessionId,Selected=d.Selected is null?null:Candidate(d.Selected),Candidates=d.Candidates.Select(Candidate),
            ReportIdPolicy="Unnumbered descriptor; Windows report ID 00; native length 65; no 64-byte fallback",
            d.IsLive,d.ReaderRunning,d.Status,d.Capabilities,d.StatusAt,d.LastQuery,d.LastStatusQuery,d.LastInput,d.LastOutput,d.LastWriteResult,d.ErrorKey,Error=Safe(d.Error),
            History=d.History.Select(h=>h with {Detail=Safe(h.Detail)??""}).ToImmutableArray()},new JsonSerializerOptions{WriteIndented=true,Converters={new JsonStringEnumConverter()}});
    }
}
