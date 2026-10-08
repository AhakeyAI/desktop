using System.Reflection;
using System.Runtime.InteropServices;

namespace AhaKey.Services;
public sealed class AppVersionService
{
    public static AppVersionService Current {get;}=new(Assembly.GetEntryAssembly()??typeof(AppVersionService).Assembly);
    public string ProductName {get;}
    public string Version {get;}
    public string InformationalVersion {get;}
    public string? Build {get;}
    public string BuildLabel=>Build is null?"":"Build "+Build[..Math.Min(12,Build.Length)]+(Build.EndsWith(".dirty",StringComparison.Ordinal)?" (modified)":"");
    public string Platform=>$"{RuntimeInformation.FrameworkDescription}\nWindows {RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant()}";
    public string SupportText=>$"{ProductName}\nVersion {Version}\n{BuildLabel}\n{Platform}";
    public AppVersionService(Assembly assembly)
    {
        ProductName=assembly.GetCustomAttribute<AssemblyProductAttribute>()?.Product??assembly.GetName().Name??"";
        InformationalVersion=assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion??assembly.GetName().Version?.ToString()??"";
        var parts=InformationalVersion.Split('+',2);Version=parts[0];Build=parts.Length==2?parts[1]:null;
    }
}
