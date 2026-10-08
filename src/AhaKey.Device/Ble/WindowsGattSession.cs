#if WINDOWS
using System.Collections.Immutable;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Devices.Radios;
using Windows.Foundation;
using Windows.Security.Cryptography;
using AhaKey.Protocol;
namespace AhaKey.Device.Ble;
public sealed class WindowsGattSessionFactory : IWindowsGattSessionFactory
{
    public IWindowsGattSession Create(Guid id)=>new WindowsGattSession(id);
}
// All native objects belong to this instance. The portable transport owns its lifetime/generation.
public sealed class WindowsGattSession(Guid id,LegacyCharacterizationPermit? characterizationPermit=null) : IWindowsGattSession
{
    private readonly CancellationTokenSource lifetime=new();
    private readonly List<GattDeviceService> services=[];
    private readonly Dictionary<(Guid,Guid),GattCharacteristic> characteristics=[];
    private BluetoothLEDevice? device;
    private DeviceWatcher? watcher;
    private Radio? radio;
    private GattCharacteristic? notify;
    private TypedEventHandler<GattCharacteristic,GattValueChangedEventArgs>? notificationHandler;
    private int disposed;
    public Guid Id {get;}=id;
    public GattResult? TeardownResult {get;private set;}
    public AdapterInfo Adapter {get;private set;}=new(null,"Unknown");
    public bool NativeConnected=>device?.ConnectionStatus==BluetoothConnectionStatus.Connected;
    public event Action<Guid,bool>? ConnectionChanged;
    private bool Active=>Volatile.Read(ref disposed)==0 && !lifetime.IsCancellationRequested;
    private async Task CheckAdapter(CancellationToken ct)
    {
        var adapter=await BluetoothAdapter.GetDefaultAsync().AsTask(ct);
        if(!Active || ct.IsCancellationRequested) throw new OperationCanceledException(ct);
        if(adapter is null || !adapter.IsLowEnergySupported) throw new BleException("BleAdapterUnavailable","No BLE-capable Windows adapter.");
        var info=await DeviceInformation.CreateFromIdAsync(adapter.DeviceId).AsTask(ct);
        var foundRadio=await adapter.GetRadioAsync().AsTask(ct);
        if(!Active || ct.IsCancellationRequested) throw new OperationCanceledException(ct);
        Adapter=new(info.Name,foundRadio?.State.ToString()??"Unavailable");
        radio=foundRadio;
        if(radio is not null) {radio.StateChanged+=RadioChanged;if(radio.State!=RadioState.On) throw new BleException("BleAdapterUnavailable","Bluetooth radio is not On.");}
    }
    private void RadioChanged(Radio sender,object args)
    {if(Active && ReferenceEquals(sender,radio)) {Adapter=Adapter with{State=sender.State.ToString()};if(sender.State!=RadioState.On) ConnectionChanged?.Invoke(Id,false);}}
    public async Task<IReadOnlyList<BleDeviceInfo>> DiscoverAsync(TimeSpan duration,CancellationToken ct)
    {
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        await CheckAdapter(linked.Token);
        var found=new Dictionary<string,BleDeviceInfo>();var sync=new object();
        var complete=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var stopped=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var current=DeviceInformation.CreateWatcher("(System.Devices.Aep.ProtocolId:=\"{bb7bb05e-5972-42b5-94fc-76eaa7084d49}\")",
            new[]{"System.Devices.Aep.DeviceAddress","System.Devices.Aep.Bluetooth.Le.IsConnectable"},DeviceInformationKind.AssociationEndpoint);
        watcher=current;
        bool Valid()=>Active && !linked.IsCancellationRequested && ReferenceEquals(current,watcher);
        void Added(DeviceWatcher sender,DeviceInformation value)
        {lock(sync){if(Valid()) found[value.Id]=new(value.Id,value.Name,value.Properties.TryGetValue("System.Devices.Aep.DeviceAddress",out var address)?address as string:null);}}
        void Updated(DeviceWatcher sender,DeviceInformationUpdate value)
        {lock(sync){if(Valid() && found.TryGetValue(value.Id,out var old) && value.Properties.TryGetValue("System.Devices.Aep.DeviceAddress",out var address)) found[value.Id]=old with{Address=address as string};}}
        void Removed(DeviceWatcher sender,DeviceInformationUpdate value) {lock(sync){if(Valid()) found.Remove(value.Id);}}
        void Completed(DeviceWatcher sender,object args) {if(Valid()) complete.TrySetResult();}
        void Stopped(DeviceWatcher sender,object args)=>stopped.TrySetResult();
        current.Added+=Added;current.Updated+=Updated;current.Removed+=Removed;current.EnumerationCompleted+=Completed;current.Stopped+=Stopped;
        try
        {
            current.Start();await Task.WhenAny(complete.Task,Task.Delay(duration,linked.Token));linked.Token.ThrowIfCancellationRequested();
            lock(sync) return found.Values.OrderBy(x=>x.Name).ToArray();
        }
        finally
        {
            watcher=null;
            if(current.Status is DeviceWatcherStatus.Started or DeviceWatcherStatus.EnumerationCompleted) current.Stop();
            if(current.Status==DeviceWatcherStatus.Stopping) await Task.WhenAny(stopped.Task,Task.Delay(1000));
            current.Added-=Added;current.Updated-=Updated;current.Removed-=Removed;current.EnumerationCompleted-=Completed;current.Stopped-=Stopped;
        }
    }
    public async Task AcquireAsync(string deviceId,CancellationToken ct)
    {
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        await CheckAdapter(linked.Token);
        var acquired=await BluetoothLEDevice.FromIdAsync(deviceId).AsTask(linked.Token);
        if(!Active || linked.IsCancellationRequested) {acquired?.Dispose();throw new OperationCanceledException(linked.Token);}
        device=acquired??throw new BleException("BleAcquireFailure","Windows did not return a BluetoothLEDevice.");
        device.ConnectionStatusChanged+=NativeConnectionChanged;
    }
    private void NativeConnectionChanged(BluetoothLEDevice sender,object args)
    {if(Active && ReferenceEquals(sender,device)) ConnectionChanged?.Invoke(Id,sender.ConnectionStatus==BluetoothConnectionStatus.Connected);}
    public async Task<ImmutableArray<GattServiceInfo>> DiscoverGattAsync(CancellationToken ct)
    {
        var current=device??throw new InvalidOperationException("Native device unavailable.");
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        var result=await current.GetGattServicesAsync(BluetoothCacheMode.Uncached).AsTask(linked.Token);
        if(!Active || linked.IsCancellationRequested) {foreach(var s in result.Services) s.Dispose();throw new OperationCanceledException(linked.Token);}
        services.AddRange(result.Services);
        Result(result.Status,result.ProtocolError).RequireSuccess("Services");
        var catalog=ImmutableArray.CreateBuilder<GattServiceInfo>();
        foreach(var service in services)
        {
            var chars=await service.GetCharacteristicsAsync(BluetoothCacheMode.Uncached).AsTask(linked.Token);
            if(!Active || linked.IsCancellationRequested) throw new OperationCanceledException(linked.Token);
            var items=ImmutableArray.CreateBuilder<GattCharacteristicInfo>();
            foreach(var c in chars.Characteristics)
            {
                var flags=GattFeatures.None;
                if(c.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Read)) flags|=GattFeatures.Read;
                if(c.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Write)) flags|=GattFeatures.Write;
                if(c.CharacteristicProperties.HasFlag(GattCharacteristicProperties.WriteWithoutResponse)) flags|=GattFeatures.WriteWithoutResponse;
                if(c.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Notify)) flags|=GattFeatures.Notify;
                if(c.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Indicate)) flags|=GattFeatures.Indicate;
                items.Add(new(c.Uuid,flags));characteristics[(service.Uuid,c.Uuid)]=c;
            }
            catalog.Add(new(service.Uuid,items.ToImmutable(),Result(chars.Status,chars.ProtocolError)));
        }
        return catalog.ToImmutable();
    }
    public async Task<GattResult> SubscribeAsync(Guid service,Guid characteristic,Action<BleNotification> receiver,CancellationToken ct)
    {
        var selected=characteristics[(service,characteristic)];
        if(notify is null)
        {
            notify=selected;
            notificationHandler=(sender,args)=>
            {
                if(!Active || !ReferenceEquals(sender,notify)) return;
                var arrived=DateTimeOffset.UtcNow;
                if(args.CharacteristicValue.Length>512) return;
                CryptographicBuffer.CopyToByteArray(args.CharacteristicValue,out var bytes);
                var copy=ImmutableArray.CreateRange(bytes);
                if(Active && ReferenceEquals(sender,notify)) receiver(new(Id,arrived,copy));
            };
            selected.ValueChanged+=notificationHandler;
        }
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        var result=await selected.WriteClientCharacteristicConfigurationDescriptorWithResultAsync(GattClientCharacteristicConfigurationDescriptorValue.Notify).AsTask(linked.Token);
        if(!Active || linked.IsCancellationRequested) throw new OperationCanceledException(linked.Token);
        return Result(result.Status,result.ProtocolError);
    }
    public async Task<GattResult> WriteCommandAsync(Guid service,Guid characteristic,ImmutableArray<byte> frame,CancellationToken ct)
    {
        if(!AhaKeyProtocol.IsAllowedQuery(frame.AsSpan()))
        {
            if(characterizationPermit is null || service!=GattContract.WindowsObserved.Service || characteristic!=GattContract.WindowsObserved.Command)
                throw new BleException("BleReadOnly","Unauthorized device command.");
            ct.ThrowIfCancellationRequested();
            characterizationPermit.Consume(frame.AsSpan(),Id);
        }
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        var result=await characteristics[(service,characteristic)].WriteValueWithResultAsync(CryptographicBuffer.CreateFromByteArray(frame.ToArray()),GattWriteOption.WriteWithResponse).AsTask(linked.Token);
        if(!Active || linked.IsCancellationRequested) throw new OperationCanceledException(linked.Token);
        return Result(result.Status,result.ProtocolError);
    }
    public async Task<GattResult> WriteConfigAsync(Guid service,Guid characteristic,Usb.ApprovedConfigRead query,CancellationToken ct)
    {
        if(service!=GattContract.WindowsObserved.Service || characteristic!=GattContract.WindowsObserved.Command)throw new InvalidOperationException("Unvalidated GATT endpoint.");
        ct.ThrowIfCancellationRequested();query.Consume(Id);
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        var result=await characteristics[(service,characteristic)].WriteValueWithResultAsync(CryptographicBuffer.CreateFromByteArray(query.Frame.ToArray()),GattWriteOption.WriteWithResponse).AsTask(linked.Token);
        if(!Active || linked.IsCancellationRequested)throw new OperationCanceledException(linked.Token);
        return Result(result.Status,result.ProtocolError);
    }
    public async Task<GattResult> WriteControlAsync(Guid service,Guid characteristic,ApprovedControl control,CancellationToken ct)
    {
        if(service!=GattContract.WindowsObserved.Service || characteristic!=GattContract.WindowsObserved.Command)throw new InvalidOperationException("Unvalidated GATT endpoint.");
        ct.ThrowIfCancellationRequested();control.Consume(Id,control.Command.Frame.AsSpan());
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        // Source receive_bytes accumulates the command frame across 20-byte writes.
        // Await every chunk; never restart or retry a partially transmitted command.
        foreach(var chunk in control.Command.Frame.Chunk(20))
        {
            var result=await characteristics[(service,characteristic)].WriteValueWithResultAsync(CryptographicBuffer.CreateFromByteArray(chunk),GattWriteOption.WriteWithResponse).AsTask(linked.Token);
            if(!Active || linked.IsCancellationRequested)throw new OperationCanceledException(linked.Token);
            var status=Result(result.Status,result.ProtocolError);if(!status.Success)return status;
        }
        return new(GattResultStatus.Success);
    }
    private static GattResult Result(GattCommunicationStatus status,byte? error)=>new(status switch
    {GattCommunicationStatus.Success=>GattResultStatus.Success,GattCommunicationStatus.Unreachable=>GattResultStatus.Unreachable,GattCommunicationStatus.ProtocolError=>GattResultStatus.ProtocolError,GattCommunicationStatus.AccessDenied=>GattResultStatus.AccessDenied,_=>GattResultStatus.Unknown},error);
    public async ValueTask DisposeAsync()
    {
        if(Interlocked.Exchange(ref disposed,1)!=0) return;
        lifetime.Cancel();
        if(watcher?.Status is DeviceWatcherStatus.Started or DeviceWatcherStatus.EnumerationCompleted) watcher.Stop();
        if(radio is not null) radio.StateChanged-=RadioChanged;
        if(device is not null) device.ConnectionStatusChanged-=NativeConnectionChanged;
        var previous=notify;notify=null;
        if(previous is not null)
        {
            previous.ValueChanged-=notificationHandler;
            try {using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(2));var result=await previous.WriteClientCharacteristicConfigurationDescriptorWithResultAsync(GattClientCharacteristicConfigurationDescriptorValue.None).AsTask(timeout.Token).ConfigureAwait(false);TeardownResult=Result(result.Status,result.ProtocolError);}
            catch(Exception) { TeardownResult=new(GattResultStatus.Unreachable); }
        }
        foreach(var service in services) service.Dispose();services.Clear();characteristics.Clear();device?.Dispose();device=null;
        lifetime.Dispose();
    }
}
#endif
