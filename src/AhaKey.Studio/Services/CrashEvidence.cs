using System.IO;
using System.Text.Json;
using AhaKey.Core;

namespace AhaKey.Studio.Services;
public static class CrashEvidence
{
    private static readonly object sync=new();
    private static string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"AhaKey","Studio2","Crashes");
    private static object context=new {Operation="Startup"};
    public static string? LastReport {get;private set;}
    public static void Configure(string settingsRoot)
    {root=Path.Combine(settingsRoot,"Crashes");if(Directory.Exists(root))LastReport=Directory.EnumerateFiles(root,"crash-*.json").Select(Path.GetFileName).OrderDescending().FirstOrDefault();}
    public static void Operation(string operation,HardwareProfileId? profile=null,Guid? project=null)
    {lock(sync)context=new {Operation=operation,Profile=profile,ProjectId=project};}
    public static void Record(Exception exception,string origin)
    {
        try
        {
            lock(sync)
            {
                Directory.CreateDirectory(root);string name=$"crash-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmssfff}-{Environment.ProcessId}.json";
                // Do not persist exception.Data (can contain payloads) or UI text. Keep full stack/inner chain.
                object Describe(Exception e)=>new {Type=e.GetType().FullName,e.HResult,Message=Redact(e.Message),Stack=Redact(e.StackTrace??""),Inner=e.InnerException is {} inner?Describe(inner):null};
                File.WriteAllText(Path.Combine(root,name),JsonSerializer.Serialize(new{At=DateTimeOffset.UtcNow,Origin=origin,Context=context,Exception=Describe(exception)},new JsonSerializerOptions{WriteIndented=true}));LastReport=name;
            }
        }
        catch(IOException){}catch(UnauthorizedAccessException){}
    }
    private static string Redact(string value)=>System.Text.RegularExpressions.Regex.Replace(value,@"(?:[A-Za-z]:\\|\\\\)[^\r\n""<>]*","[local path]");
}
