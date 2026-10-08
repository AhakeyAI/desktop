using System.Text.Json;
using System.Text.Json.Serialization;
using System.Collections.Immutable;
namespace AhaKey.Device.Ble;
public static class BleDiagnosticExport
{
    public static string Redacted(BleDiagnostics d)
    {
        string? Safe(string? value)
        {
            if(value is null)return null;
            foreach(var identifier in new[]{d.Device?.Id,d.Device?.Address})
                if(!string.IsNullOrEmpty(identifier))value=value.Replace(identifier,"[redacted]",StringComparison.OrdinalIgnoreCase);
            return value;
        }
        return JsonSerializer.Serialize(d with {
        Device=d.Device is null?null:new("[redacted]","[redacted]",d.Device.Address is null?null:"[redacted]"),
        Adapter=d.Adapter with{Name=d.Adapter.Name is null?null:"[redacted]"},Error=Safe(d.Error),
        History=d.History.Select(h=>h with{Detail=Safe(h.Detail)??""}).ToImmutableArray()
        },new JsonSerializerOptions{WriteIndented=true,Converters={new JsonStringEnumConverter()}});
    }
}
