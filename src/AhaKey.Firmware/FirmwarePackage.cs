using System.Security.Cryptography;
using System.Text.Json;
using AhaKey.Core;
namespace AhaKey.Firmware;

public sealed record FirmwarePackage(string Product,string Target,string Version,string Protocol,string ImagePath,
    string Sha256,string SourceCommit,string ProvenancePath,string HardwareCompatibility)
{
    public string MinimumStudioVersion {get;init;}="2.0.0-alpha.9";
    public string HardwareFamily {get;init;}="AhaKey X1 / CH582M";
    public uint ExpectedCapabilities {get;init;}=0x7FF;
    public string MigrationNotes {get;init;}="MCU code flash only; preserve DataFlash and external Display flash. Existing configuration is not a verified backup.";
}
public sealed record PackageValidation(string Sha256,int DataBytes,uint FirstAddress,uint EndExclusive,bool ProvenanceVerified);
public static class FirmwarePackageValidator
{
    public static async Task<PackageValidation> ValidateAsync(FirmwarePackage package,CancellationToken ct=default)
    {
        if(package.Product!="AhaKey-X1"||package.Target!="CH582"||package.Protocol!="3.2"||package.Version!="1.4.8")throw new ArgumentException("Unapproved package identity.");
        if(package.MinimumStudioVersion!="2.0.0-alpha.9"||package.HardwareFamily!="AhaKey X1 / CH582M"||package.ExpectedCapabilities!=0x7FF||string.IsNullOrWhiteSpace(package.MigrationNotes))throw new ArgumentException("Unsupported package requirements or hardware contract.");
        if(!System.Text.RegularExpressions.Regex.IsMatch(package.Sha256,"^[0-9A-Fa-f]{64}$")||!System.Text.RegularExpressions.Regex.IsMatch(package.SourceCommit,"^[0-9a-f]{40}$"))throw new ArgumentException("Missing package provenance.");
        if(new FileInfo(package.ImagePath).Length>2*1024*1024)throw new FormatException("HEX exceeds package limit.");
        byte[] bytes=await File.ReadAllBytesAsync(package.ImagePath,ct).ConfigureAwait(false);
        string hash=Convert.ToHexString(SHA256.HashData(bytes));if(!hash.Equals(package.Sha256,StringComparison.OrdinalIgnoreCase))throw new FormatException("Package SHA-256 mismatch.");
        using var provenance=JsonDocument.Parse(await File.ReadAllTextAsync(package.ProvenancePath,ct).ConfigureAwait(false));var p=provenance.RootElement;
        if(p.GetProperty("sourceCommit").GetString()!=package.SourceCommit||p.GetProperty("firmwareVersion").GetString()!=package.Version||p.GetProperty("protocolVersion").GetString()!=package.Protocol||p.GetProperty("deviceModel").GetString()!=package.Product||p.GetProperty("mcu").GetString()!=package.Target||!p.GetProperty("sourceTreeClean").GetBoolean())throw new FormatException("Provenance mismatch.");
        var image=ValidateHex(System.Text.Encoding.ASCII.GetString(bytes));return image with{Sha256=hash,ProvenanceVerified=true};
    }
    public static PackageValidation ValidateHex(string text)
    {
        uint addressBase=0;bool eof=false;var addresses=new HashSet<uint>();uint first=uint.MaxValue,end=0;
        foreach(string line in text.Split(['\r','\n'],StringSplitOptions.RemoveEmptyEntries))
        {
            if(eof||!line.StartsWith(':')||line.Length%2!=1)throw new FormatException("Invalid HEX record or data after EOF.");
            byte[] r;try{r=Convert.FromHexString(line[1..]);}catch(FormatException){throw new FormatException("Non-hexadecimal record.");}
            if(r.Length<5||r.Length!=r[0]+5||r.Sum(x=>(int)x)%256!=0)throw new FormatException("HEX length/checksum mismatch.");
            uint offset=(uint)(r[1]*256+r[2]);var data=r.AsSpan(4,r[0]);
            switch(r[3])
            {
                case 0:
                    if(data.IsEmpty||offset+data.Length>0x10000)throw new FormatException("Invalid data range.");
                    for(uint i=0;i<data.Length;i++)
                    {ulong full=(ulong)addressBase+offset+i;if(full>=0x70000)throw new FormatException("Outside CH582 code flash; ISP/data flash must be preserved.");uint a=(uint)full;if(!addresses.Add(a))throw new FormatException("Overlapping HEX data.");first=Math.Min(first,a);end=Math.Max(end,a+1);}break;
                case 1: if(r[0]!=0||offset!=0)throw new FormatException("Invalid EOF.");eof=true;break;
                case 2: if(r[0]!=2||offset!=0)throw new FormatException("Invalid segment.");addressBase=(uint)(data[0]*256+data[1])<<4;break;
                case 4: if(r[0]!=2||offset!=0)throw new FormatException("Invalid extended address.");addressBase=(uint)(data[0]*256+data[1])<<16;break;
                case 3: case 5: if(r[0]!=4||offset!=0)throw new FormatException("Invalid entry address.");break;
                default:throw new FormatException("Unknown HEX record type.");
            }
        }
        if(!eof||addresses.Count==0||first!=0)throw new FormatException("Missing EOF or reset vector.");
        return new("",addresses.Count,first,end,false);
    }
}
public interface IFlashTransport
{
    string AvailabilityReason {get;}
    Task EnterUpdateModeAsync(CancellationToken ct);
    Task ProgramAndVerifyAsync(FirmwarePackage package,PackageValidation validation,IProgress<string> progress,CancellationToken ct);
    Task<FirmwareIdentity> RebootAndReadIdentityAsync(CancellationToken ct);
}
// Unavailable until the exact vendor runtime and driver pass feature-specific preflight.
public sealed class PreparedWchIspTransport:IFlashTransport
{
    public string AvailabilityReason=>"FirmwareTransportPrepared";
    public Task EnterUpdateModeAsync(CancellationToken ct)=>Task.FromException(new NotSupportedException(AvailabilityReason));
    public Task ProgramAndVerifyAsync(FirmwarePackage p,PackageValidation v,IProgress<string> progress,CancellationToken ct)=>Task.FromException(new NotSupportedException(AvailabilityReason));
    public Task<FirmwareIdentity> RebootAndReadIdentityAsync(CancellationToken ct)=>Task.FromException<FirmwareIdentity>(new NotSupportedException(AvailabilityReason));
}
