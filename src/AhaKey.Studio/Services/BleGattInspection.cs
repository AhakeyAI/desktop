using System.IO;
using System.Text.Json;
using AhaKey.Device.Ble;
namespace AhaKey.Studio.Services;
// Explicit developer acceptance mode, in the Studio process. Inspection sends no device command.
public static class BleGattInspection
{
    public static async Task RunAsync(string output,string selectedName)
    {
        Directory.CreateDirectory(output);
        using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(45));
        var factory=new WindowsGattSessionFactory();
        await using var scan=factory.Create(Guid.NewGuid());
        var devices=await scan.DiscoverAsync(TimeSpan.FromSeconds(8),timeout.Token);
        await File.WriteAllTextAsync(Path.Combine(output,"discovered-private.json"),JsonSerializer.Serialize(devices,new JsonSerializerOptions{WriteIndented=true}));
        var matches=devices.Where(x=>x.Name==selectedName).ToArray();
        if(matches.Length!=1) throw new InvalidOperationException("Selected name must identify exactly one discovered device; inspect private discovery results.");
        await using var session=factory.Create(Guid.NewGuid());
        await session.AcquireAsync(matches[0].Id,timeout.Token);
        var catalog=await session.DiscoverGattAsync(timeout.Token);
        await File.WriteAllTextAsync(Path.Combine(output,"gatt-inspection.json"),JsonSerializer.Serialize(new {session.Adapter,session.Id,NativeConnected=session.NativeConnected,Catalog=catalog,CommandsSent=Array.Empty<string>()},new JsonSerializerOptions{WriteIndented=true}));
    }
}
