using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace AhaKey.Integrations;

// Read-only recognition of the reviewed Windows adapter. Ownership for removal stays Studio-only.
public static class LegacyCodexHooks
{
    public static IReadOnlyDictionary<string,string> Commands(string home, IEnumerable<HookEvent> events)
    {
        try
        {
            var scripts=Path.Combine(home,".ahakey","hooks");
            bool Matches(string file,string hash)=>File.Exists(file) && Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(File.ReadAllText(file).Replace("\r\n","\n"))))==hash;
            if(!Matches(Path.Combine(scripts,"ahakey-core.ps1"),"9AA3216AFF9A34A51E79C2CC79E25B5CED464AB0F84BB63C7D5D655E6DBF2CA5") ||
               !Matches(Path.Combine(scripts,"ahakey-codex.ps1"),"BC9D9F0B85E094F2C7347652ADC9E9EE3537C7D63891839CECE49746F1433EB0"))return new Dictionary<string,string>();
            var root=SafeJson.Parse(File.ReadAllBytes(Path.Combine(home,".codex","hooks.json")));
            var result=new Dictionary<string,string>();
            foreach(var ev in events)
            {
                string expected=$"powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"{Path.Combine(scripts,"ahakey-codex.ps1").Replace('\\','/')}\" {ev.NativeEvent}";
                if(root["hooks"]?[ev.Event.ToString()] is not JsonArray wrappers || !wrappers.Any(w=>w?["hooks"] is JsonArray hooks && hooks.Any(h=>h?["type"]?.GetValue<string>()=="command" && h?["command"]?.GetValue<string>()==expected)))return new Dictionary<string,string>();
                result.Add(ev.Event.ToString(),expected);
            }
            return result;
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){return new Dictionary<string,string>();}
    }
}
