using System.Text.Json;
namespace AhaKey.Services;

// Local receipts, never a device configuration read or Synced snapshot.
public sealed record ProductWriteReceipt(string DeviceHash,string Firmware,string Target,string ValueHash,DateTimeOffset WrittenAt,bool BehaviorVerified=false);
public sealed class ProductWriteHistory(SettingsStore settings)
{
    private readonly object sync=new();
    private string PathName=>Path.Combine(settings.Root,"written-items.v1.json");
    private List<ProductWriteReceipt> Load()
    {
        if(!File.Exists(PathName))return [];
        return JsonSerializer.Deserialize<List<ProductWriteReceipt>>(File.ReadAllText(PathName))??throw new JsonException("Invalid receipt history.");
    }
    public ProductWriteReceipt? Find(string? device,string firmware,string target,string value)
    {
        if(device is null)return null;
        lock(sync)try{return Load().LastOrDefault(x=>x.DeviceHash==device && x.Firmware==firmware && x.Target==target && x.ValueHash==value);}
        catch(Exception ex)when(ex is IOException or JsonException or UnauthorizedAccessException){return null;}
    }
    // A local baseline only. It must never establish a write on another connection/device.
    public bool HasMatchingLocalValue(string target,string value)
    {
        lock(sync)try{return Load().Any(x=>x.Target==target && x.ValueHash==value);}
        catch(Exception ex)when(ex is IOException or JsonException or UnauthorizedAccessException){return false;}
    }
    public void Record(ProductWriteReceipt receipt)
    {
        lock(sync)
        {
            var items=Load();items.RemoveAll(x=>x.DeviceHash==receipt.DeviceHash && x.Target==receipt.Target);items.Add(receipt);
            Directory.CreateDirectory(settings.Root);var temp=PathName+".tmp";
            using(var stream=new FileStream(temp,FileMode.Create,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(stream,items);stream.Flush(true);}
            File.Move(temp,PathName,true);
        }
    }
    public void Forget(string device,string target)
    {
        lock(sync)
        {
            var items=Load();items.RemoveAll(x=>x.DeviceHash==device && x.Target==target);
            Directory.CreateDirectory(settings.Root);var temp=PathName+".tmp";
            using(var stream=new FileStream(temp,FileMode.Create,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(stream,items);stream.Flush(true);}
            File.Move(temp,PathName,true);
        }
    }
    public static string KeyHash(string shortcut,string label)=>Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(shortcut+"\0"+label)));
}
