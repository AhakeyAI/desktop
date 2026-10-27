param([Parameter(Mandatory=$true)][string]$SourceRoot)
$ErrorActionPreference = 'Stop'
$program = [IO.File]::ReadAllText((Join-Path $SourceRoot 'Program.cs'))
$form = [IO.File]::ReadAllText((Join-Path $SourceRoot 'Form1.cs'))
$tcp = [IO.File]::ReadAllText((Join-Path $SourceRoot 'TcpServer.cs'))
$protocol = [IO.File]::ReadAllText((Join-Path $SourceRoot 'Protocol.cs'))
function Extract([string]$source, [string]$declaration) {
    $start = $source.IndexOf($declaration, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing production member: $declaration" }
    $open = $source.IndexOf('{', $start); $depth = 0
    for ($i=$open; $i -lt $source.Length; $i++) {
        if ($source[$i] -eq '{') { $depth++ }
        if ($source[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $source.Substring($start,$i-$start+1) } }
    }
    throw 'Unbalanced member'
}
$coreMethods = @('public bool IsCurrentConnection(', 'private bool IsCurrentDevice(', 'private bool IsCurrentDiscoveryLocked(',
 'public bool TryAcceptDiscoveredCharacteristic(', 'public bool TryConfirmReady(', 'public BleStatusInfo GetBleStatusInfo(', 'private sealed class DiscoveryRound',
 'public void FindService(', 'private void FindCharacteristic(', 'private void CompleteDiscovery(', 'public void EnableNotifications(',
 'private void InvalidateDiscoveryLocked(', 'private void RemoveNotifySubscriptionLocked(',
 'public bool TryDisposeIncompleteDiscovery(', 'private void DisposeCurrentConnectionLocked(', 'private void ConnectDevice(',
 'public void ConnectDeviceByInfo(', 'private long AdvanceConnectionGeneration(',
 'public Task<GattWriteResult> WriteDataToCharacteristicAsync(', 'private Task<GattWriteResult> WriteValueAsync(',
 'private sealed class ActiveGattWrite', 'internal sealed class GattWriteResult',
 'private void InvalidateActiveGattWrites(', 'private void CurrentDevice_ConnectionStatusChanged(') | ForEach-Object { Extract $program $_ }
$formMethods = @('private void DeviceConnected(', 'private void DeviceDisconnected(', 'private void CharacteristicAdded(',
 'private void OnAllCharacteristicsDiscovered(', 'private void RetryTimer_Tick(', 'private void DeviceAdded(',
 'private void ReceiveNotifyData(', 'private void log(') | ForEach-Object { Extract $form $_ }
$tcpMethods = @('private void OnBleNotify(', 'void BroadcastToAll(', 'private void SendToClient(',
 'private void OnConnectionGenerationChanged(', 'private DeviceStatusInfo GetCurrentDeviceStatus(', 'private BleStatusInfo BuildBleStatus(') | ForEach-Object { Extract $tcp $_ }
$identity = Extract $tcp 'internal static class BridgeRoundIdentity'
$protocol = $protocol.Replace('namespace BLE_tcp_driver','namespace BridgeFixProbe').Replace('using System;','').Replace('using System.Text;','')
$source = @"
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Net;
using System.Net.Sockets;
using System.Diagnostics;
using System.Drawing;
namespace BridgeFixProbe {
    enum BluetoothConnectionStatus { Disconnected, Connected }
    enum BluetoothCacheMode { Uncached }
    enum GattCommunicationStatus { Success, Unreachable, AccessDenied }
    enum AsyncStatus { Completed, Error, Canceled }
    enum GattClientCharacteristicConfigurationDescriptorValue { Notify }
    enum GattWriteOption { WriteWithResponse }
    interface IAsyncOperation<T> {Action<Operation<T>,AsyncStatus> Completed {set;}void Cancel();}
    class CryptographicBuffer {public static byte[] CreateFromByteArray(byte[] data){return data;}}
    delegate void TypedEventHandler<T,U>(T sender,U args);
    class GattValueChangedEventArgs {}
    class Operation<T> : IAsyncOperation<T> {
        public T Result;
        public bool Pending, ThrowResult;
        public AsyncStatus Status=AsyncStatus.Completed;
        Action<Operation<T>,AsyncStatus> callback;
        public T GetResults() {if(ThrowResult)throw new Exception("GetResults failure");return Result;}
        public Action<Operation<T>,AsyncStatus> Completed {set {callback=value;if(!Pending)Fire(Status);}}
        public void Fire(AsyncStatus status=AsyncStatus.Completed) {callback(this,status);}
        public Action<AsyncStatus> Capture(){var saved=callback;return status=>saved(this,status);}
        public int Cancels;
        public void Cancel(){Cancels++;}
    }
    class GattCharacteristic {
        public Guid Uuid;
        public string UserDescription="";
        public event TypedEventHandler<GattCharacteristic,GattValueChangedEventArgs> ValueChanged;
        public Operation<GattCommunicationStatus> Cccd=new Operation<GattCommunicationStatus>{Pending=true};
        public int CccdCalls;
        public bool ThrowStart;
        public Operation<GattCommunicationStatus> Write=new Operation<GattCommunicationStatus>{Pending=true};
        public int WriteCalls;
        public Operation<GattCommunicationStatus> WriteValueAsync(byte[] data,GattWriteOption option){WriteCalls++;return Write;}
        public Operation<GattCommunicationStatus> WriteClientCharacteristicConfigurationDescriptorAsync(GattClientCharacteristicConfigurationDescriptorValue value) {
            CccdCalls++; if(ThrowStart)throw new Exception("CCCD start failure"); return Cccd;
        }
    }
    class Utilities { public static ushort ConvertUuidToShortId(Guid id) { return (ushort)BitConverter.ToUInt32(id.ToByteArray(),0); } }
    class GattDeviceService {
        public Guid Uuid;
        public Operation<CharacteristicsResult> Operation=new Operation<CharacteristicsResult>{Result=new CharacteristicsResult()};
        public bool ThrowStart;
        public int Calls;
        public void Dispose() {}
        public Operation<CharacteristicsResult> GetCharacteristicsAsync(BluetoothCacheMode mode) {
            Calls++;if(ThrowStart)throw new Exception("characteristics start failure"); return Operation;
        }
    }
    class CharacteristicsResult { public GattCommunicationStatus Status; public List<GattCharacteristic> Characteristics=new List<GattCharacteristic>(); }
    class ServicesResult { public GattCommunicationStatus Status; public List<GattDeviceService> Services=new List<GattDeviceService>(); }
    class DeviceInformation { public string Id="target",Name="target"; }
    class BluetoothLEDevice {
        public string Name="target";
        public ulong BluetoothAddress=1;
        public int DisposeCalls,Calls;
        public event Action<BluetoothLEDevice,object> ConnectionStatusChanged;
        public void Dispose() {DisposeCalls++;}
        public static BluetoothLEDevice NextDevice;
        public static Operation<BluetoothLEDevice> FromIdAsync(string id) {return new Operation<BluetoothLEDevice>{Result=NextDevice};}
        public BluetoothConnectionStatus ConnectionStatus=BluetoothConnectionStatus.Connected;
        public Operation<ServicesResult> Operation=new Operation<ServicesResult>{Result=new ServicesResult()};
        public bool ThrowStart;
        public Operation<ServicesResult> GetGattServicesAsync(BluetoothCacheMode mode) {
            Calls++;if(ThrowStart)throw new Exception("services start failure");return Operation;
        }
    }
    $identity
    class BleCore {
        long _connectionGeneration;
        public long ConnectionGeneration {get{return Interlocked.Read(ref _connectionGeneration);}}
        public Action<BluetoothLEDevice> ConnectDeviceSuccess;
        public Action<long> ConnectionGenerationChanged;
        public string CurrentDeviceMAC;
        readonly object _sessionLock=new object();
        IDisposable _gattSession;
        long _gattSessionGeneration;
        public int ScanStarts,ScanStops;
        public void StartBleDeviceWatcher(){ScanStarts++;}
        public void StopBleDeviceWatcher(){ScanStops++;}
        readonly object _activeWriteLock=new object();
        readonly Dictionary<long,ActiveGattWrite> _activeGattWrites=new Dictionary<long,ActiveGattWrite>();
        long _nextGattWriteId;
        public Action<GattCharacteristic,byte[]> WriteDataSuccess;
        public Action<BluetoothLEDevice> DeviceDisconnected;
        public void Disconnect(){CurrentDevice.ConnectionStatus=BluetoothConnectionStatus.Disconnected;CurrentDevice_ConnectionStatusChanged(CurrentDevice,null);}
        public Task<GattWriteResult> PhysicalWrite(GattCharacteristic c,long generation){return WriteValueAsync(c,new byte[]{1},generation,CancellationToken.None);}
        public BluetoothLEDevice CurrentDevice;
        public GattDeviceService CurrentService;
        long _nextDiscoveryId;
        readonly object _discoveryLock=new object();
        DiscoveryRound _activeDiscovery;
        GattCharacteristic _notifySubscriptionCharacteristic;
        TypedEventHandler<GattCharacteristic,GattValueChangedEventArgs> _notifySubscriptionHandler;
        const GattClientCharacteristicConfigurationDescriptorValue CHARACTERISTIC_NOTIFICATION_TYPE=GattClientCharacteristicConfigurationDescriptorValue.Notify;
        public List<GattCharacteristic> CharacteristicList=new List<GattCharacteristic>();
        public Action<int,long,long> CharacteristicFinish;
        public Action<long,long,bool> AllCharacteristicsDiscovered;
        public Action<GattCharacteristic,long,long> CharacteristicAdded;
        public GattCharacteristic CurrentDataCharacteristic,CurrentWriteCharacteristic,CurrentNotifyCharacteristic;
        public ManualResetEventSlim NotificationChecked=new ManualResetEventSlim(false);
        public bool IsCurrentDiscovery(long g,long id) {
            bool result;lock(_discoveryLock)result=IsCurrentDiscoveryLocked(g,id);NotificationChecked.Set();return result;
        }
        void Characteristic_ValueChanged(GattCharacteristic sender,GattValueChangedEventArgs args,long generation,long discoveryId){}
        public void SetRound(long generation,long id) {
            lock(_discoveryLock){InvalidateDiscoveryLocked();_connectionGeneration=generation;
                CurrentDevice=new BluetoothLEDevice();_activeDiscovery=new DiscoveryRound(id,generation,CurrentDevice);}
        }
        public long RoundId {get{return _activeDiscovery.Id;}}
        public Action TimeoutCallback {get {var round=_activeDiscovery;return ()=>CompleteDiscovery(round,false,"test deadline scheduler");}}
        $($coreMethods -join "`n")
    }
    class TimerStub {public bool Enabled;public void Start(){Enabled=true;}public void Stop(){Enabled=false;}}
    class LabelStub {public string Text="";}
    class SelectStub {public List<string> Items=new List<string>();public int SelectedIndex=-1;}
    class ConfigStub {public bool HasSavedDevice=true;public string BleName="target",BleMac="MAC";}
    class ControlQueue {
        public int Queries; public GattCharacteristic LastCharacteristic;
        public Task QueueControlWrite(GattCharacteristic c,byte[] bytes){Queries++;LastCharacteristic=c;return Task.CompletedTask;}
    }
    class RichTextStub {
        readonly List<string> messages;
        public RichTextStub(List<string> messages){this.messages=messages;}
        public Color SelectionColor;public int SelectionStart;public string Text="";
        public void AppendText(string s){messages.Add(s);Text+=s;}
        public void ScrollToCaret(){}
    }
    class FormProbe {
        readonly BleCore bleCore;
        public ControlQueue tcpServer=new ControlQueue();
        public TimerStub retryTimer=new TimerStub();
        public LabelStub label_connected_devices=new LabelStub();
        SelectStub DeviceSelect=new SelectStub();
        public ConfigStub config=new ConfigStub();
        public bool autoConnecting;
        public int Saves,Terminals,Successes,Failures;
        List<DeviceInformation> devicesList=new List<DeviceInformation>();
        public List<string> Logs=new List<string>();
        RichTextStub rtbMsg;
        Queue<Action> ui=new Queue<Action>();
        public FormProbe(BleCore core){bleCore=core;rtbMsg=new RichTextStub(Logs);core.ConnectDeviceSuccess=DeviceConnected;
            core.DeviceDisconnected=DeviceDisconnected;
            core.CharacteristicAdded=CharacteristicAdded;
            core.AllCharacteristicsDiscovered=(g,id,ok)=>{Terminals++;if(ok)Successes++;else Failures++;OnAllCharacteristicsDiscovered(g,id,ok);};}
        void BeginInvoke(Action action){ui.Enqueue(action);}
        void SaveCurrentDeviceToConfig(){Saves++;}
        string GetMacFromDeviceInfo(DeviceInformation device){return "MAC";}
        public void Drain(){while(ui.Count>0)ui.Dequeue()();}
        public void Connected(BluetoothLEDevice device){DeviceConnected(device);}
        public void Disconnected(BluetoothLEDevice device){DeviceDisconnected(device);}
        public void Complete(long g,long id,bool ok){OnAllCharacteristicsDiscovered(g,id,ok);}
        public void Tick(){if(retryTimer.Enabled)RetryTimer_Tick(null,EventArgs.Empty);}
        public void FoundTarget(){DeviceAdded(new DeviceInformation());}
        public void NotifyUi(GattCharacteristic c,byte[] data,long g,long id){ReceiveNotifyData(c,data,g,id);}
        $($formMethods -join "`n")
    }
    class Request {public long Generation {get;set;}public CancellationTokenSource Cancellation=new CancellationTokenSource();}
    class QueueStub {public int CancelWhere(Func<Request,bool> predicate,Action<Request> cancel){return 0;}}
    class TcpServer {
        readonly BleCore _bleCore;
        readonly object _clientLock=new object(),_statusLock=new object(),_writeQueueLock=new object();
        readonly List<TcpClient> _clients=new List<TcpClient>();
        DeviceStatusInfo _deviceStatus;
        long _deviceStatusGeneration=-1,_deviceStatusDiscoveryId=-1;
        readonly QueueStub _writeQueue=new QueueStub();
        public TcpServer(BleCore core,TcpClient client){_bleCore=core;_clients.Add(client);}
        void Log(string message){}
        void RemoveClient(TcpClient client){throw new Exception("Unexpected socket failure");}
        double ElapsedMilliseconds(long start){return 0;}
        public void Notify(byte[] data,long generation,long id){OnBleNotify(null,data,generation,id);}
        public void Advance(long generation){OnConnectionGenerationChanged(generation);}
        public object StatusGate {get{return _statusLock;}}
        public byte CachedBattery {get{lock(_statusLock)return _deviceStatus.BatteryLevel;}}
        public BleStatusInfo Status(){return BuildBleStatus();}
        public void QueryStatus(TcpClient client){SendToClient(client,null,bleStatus:true);}
        $($tcpMethods -join "`n")
    }
    public static class Runner {
        static List<string> failures=new List<string>();
        static int checks;
        static void Check(bool ok,string name){checks++;Console.WriteLine((ok?"PASS ":"FAIL ")+name);if(!ok)failures.Add(name);}
        static void Wait(Task task){if(!task.Wait(3000))throw new Exception("Probe timed out");}
        static Guid Uuid(int id){return Guid.Parse("0000"+id.ToString("x4")+"-0000-1000-8000-00805f9b34fb");}
        static GattDeviceService Target(int missing=0){
            var s=new GattDeviceService{Uuid=Uuid(0x7340)};
            foreach(int id in new[]{0x7341,0x7343,0x7344})if(id!=missing)s.Operation.Result.Characteristics.Add(new GattCharacteristic{Uuid=Uuid(id)});
            return s;
        }
        static BleCore NewCore(){var core=new BleCore();core.SetRound(9,9);return core;}
        static GattCharacteristic Notify(GattDeviceService service){return service.Operation.Result.Characteristics.Single(c=>c.Uuid==Uuid(0x7344));}
        static void Start(BleCore core,params GattDeviceService[] services){core.CurrentDevice.Operation.Result.Services.AddRange(services);core.FindService(core.CurrentDevice,core.ConnectionGeneration);}
        static void FailedAndRetry(BleCore core,FormProbe form,BluetoothLEDevice old,string name){
            form.Drain();Check(form.Failures==1&&form.Successes==0&&old.DisposeCalls==1&&core.CurrentDevice==null&&form.retryTimer.Enabled&&form.Saves==0&&form.tcpServer.Queries==0,name);
            int scans=core.ScanStarts;form.Tick();Check(core.ScanStarts==scans+1,name+" reaches scan retry");
            BluetoothLEDevice.NextDevice=new BluetoothLEDevice();form.FoundTarget();form.Drain();
            Check(BluetoothLEDevice.NextDevice.Calls==1,name+" saved target restarts uncached discovery");
        }
        public static bool Run(){
            ProtocolHelper.LastClaudeState=null;
            var core=NewCore();core.CurrentDevice.ConnectionStatus=BluetoothConnectionStatus.Disconnected;
            core.FindService(core.CurrentDevice,9);
            Check(core.CurrentDevice.Calls==1&&!core.IsCurrentConnection(9),"cold disconnected device discovers while physical write admission stays closed");
            var stale=core.CurrentDevice;core.SetRound(10,10);core.FindService(stale,9);
            Check(stale.Calls==1,"stale discovery cannot start");
            foreach(bool targetFirst in new[]{false,true}) foreach(AsyncStatus result in new[]{AsyncStatus.Completed,AsyncStatus.Error,AsyncStatus.Canceled}) {
                var c=NewCore();var d=c.CurrentDevice;var f=new FormProbe(c);var t=Target();t.Operation.Pending=true;
                var other=new GattDeviceService{Uuid=Uuid(0x180f)};other.Operation.Pending=true;other.Operation.Result.Status=GattCommunicationStatus.Unreachable;
                Start(c,t,other);
                if(targetFirst){t.Operation.Fire();other.Operation.Fire(result);}else{other.Operation.Fire(result);t.Operation.Fire();}
                f.Drain();Check(f.Saves==0&&f.tcpServer.Queries==0&&f.Terminals==0&&Notify(t).CccdCalls==1,"CCCD pending is not ready, targetFirst="+targetFirst+" other="+result);
                Notify(t).Cccd.Fire();f.Drain();
                Check(f.Successes==1&&f.Saves==1&&f.Saves==1&&f.tcpServer.Queries==1&&d.DisposeCalls==0&&c.ConnectionGeneration==9,"unrelated failure survives both orders, targetFirst="+targetFirst+" other="+result);
                Notify(t).Cccd.Fire();Notify(t).Cccd.Fire(AsyncStatus.Error);f.Drain();
                Check(f.Terminals==1&&f.Saves==1&&f.tcpServer.Queries==1&&d.DisposeCalls==0,"CCCD success is consumed once, duplicate/late error ignored");
                f.Complete(9,c.RoundId,true);f.Drain();Check(f.tcpServer.Queries==1,"duplicate UI readiness cannot enqueue another query");
            }
            {
                var c=NewCore();var f=new FormProbe(c);var t=Target();var other=new GattDeviceService{Uuid=Uuid(0x180f)};other.Operation.Pending=true;
                // Unrelated service's spoofed characteristic must never replace the target object.
                other.Operation.Result.Characteristics.Add(new GattCharacteristic{Uuid=Uuid(0x7343)});
                Start(c,other,t);Notify(t).Cccd.Fire();f.Drain();var write=c.CurrentWriteCharacteristic;
                Check(f.Saves==1&&f.tcpServer.Queries==1,"unrelated pending service does not block target readiness");
                other.Operation.Fire();f.Drain();Check(ReferenceEquals(write,c.CurrentWriteCharacteristic)&&c.ConnectionGeneration==9,"unrelated matching short UUID cannot replace target characteristic");
            }
            foreach(int missing in new[]{0,0x7341,0x7343,0x7344}) {
                var c=NewCore();var d=c.CurrentDevice;var f=new FormProbe(c);
                Start(c,missing==0?new GattDeviceService{Uuid=Uuid(0x180f)}:Target(missing));
                FailedAndRetry(c,f,d,"required service/characteristic missing "+missing);
            }
            {
                var c=NewCore();var f=new FormProbe(c);var t=Target();var other=new GattDeviceService{Uuid=Uuid(0x180f)};
                other.Operation.Pending=true;other.Operation.Result.Status=GattCommunicationStatus.Unreachable;
                Start(c,t,other);var expire=c.TimeoutCallback;Notify(t).Cccd.Fire();f.Drain();other.Operation.Fire();expire();f.Drain();
                Check(f.Saves==1&&f.tcpServer.Queries==1&&f.Terminals==1&&c.ConnectionGeneration==9,"unrelated failure and queued timeout arriving after ready cannot dispose healthy target");
                f.Logs.Clear();f.NotifyUi(Notify(t),new byte[]{0x55},9,c.RoundId);c.SetRound(10,10);f.Drain();
                Check(f.Logs.Count==0,"actual notification UI logger rechecks identity at final queued append");
            }
            {
                var c=NewCore();var d=c.CurrentDevice;var f=new FormProbe(c);var t=Target();Start(c,t);
                c.CurrentNotifyCharacteristic=new GattCharacteristic{Uuid=Uuid(0x7344)};Notify(t).Cccd.Fire();f.Drain();
                Check(f.Terminals==0&&f.tcpServer.Queries==0,"stale CCCD characteristic object cannot complete same round");
                c.TimeoutCallback();FailedAndRetry(c,f,d,"replaced CCCD object remains bounded by deadline");
            }
            foreach(string mode in new[]{"service-result","service-error","service-canceled","service-start","service-get","required-result","required-error","required-canceled","required-start","required-get"}) {
                var c=NewCore();var d=c.CurrentDevice;var f=new FormProbe(c);var t=Target();
                if(mode=="service-result")d.Operation.Result.Status=GattCommunicationStatus.Unreachable;
                if(mode=="service-error")d.Operation.Status=AsyncStatus.Error;
                if(mode=="service-canceled")d.Operation.Status=AsyncStatus.Canceled;
                if(mode=="service-start")d.ThrowStart=true;
                if(mode=="service-get")d.Operation.ThrowResult=true;
                if(mode=="required-result")t.Operation.Result.Status=GattCommunicationStatus.Unreachable;
                if(mode=="required-error")t.Operation.Status=AsyncStatus.Error;
                if(mode=="required-canceled")t.Operation.Status=AsyncStatus.Canceled;
                if(mode=="required-start")t.ThrowStart=true;
                if(mode=="required-get")t.Operation.ThrowResult=true;
                Start(c,t);FailedAndRetry(c,f,d,mode);
            }
            foreach(string mode in new[]{"unreachable","denied","error","canceled","get","start","timeout"}) {
                var c=NewCore();var d=c.CurrentDevice;var f=new FormProbe(c);var t=Target();var n=Notify(t);
                if(mode=="start")n.ThrowStart=true;
                Start(c,t);var expire=c.TimeoutCallback;
                if(mode=="unreachable")n.Cccd.Result=GattCommunicationStatus.Unreachable;
                if(mode=="denied")n.Cccd.Result=GattCommunicationStatus.AccessDenied;
                if(mode=="get")n.Cccd.ThrowResult=true;
                if(mode=="timeout")expire();
                else if(mode!="start")n.Cccd.Fire(mode=="error"?AsyncStatus.Error:mode=="canceled"?AsyncStatus.Canceled:AsyncStatus.Completed);
                // Failed terminal is final even before failure UI gets its turn.
                if(mode!="start"){n.Cccd.ThrowResult=false;n.Cccd.Result=GattCommunicationStatus.Success;n.Cccd.Fire();}
                expire();FailedAndRetry(c,f,d,"CCCD "+mode);
                Check(n.CccdCalls==1,"CCCD "+mode+" never recursively retries");
            }
            {
                var c=NewCore();var d=c.CurrentDevice;var f=new FormProbe(c);var first=Target();var last=Target();last.Operation.Pending=true;
                Start(c,first,last);f.Drain();Check(Notify(first).CccdCalls==0&&f.Saves==0,"wait for every required discovery before CCCD");
                last.Operation.Result.Status=GattCommunicationStatus.Unreachable;last.Operation.Fire();
                FailedAndRetry(c,f,d,"late required failure cannot be overtaken by success");
            }
            foreach(bool pendingServices in new[]{false,true}) {
                var c=NewCore();var d=c.CurrentDevice;var f=new FormProbe(c);var t=Target();
                if(pendingServices)d.Operation.Pending=true;else t.Operation.Pending=true;
                Start(c,t);c.TimeoutCallback();FailedAndRetry(c,f,d,"pending discovery deadline "+pendingServices);
            }
            foreach(string race in new[]{"success-ui","failure-ui","cccd-success","cccd-error","timeout","device-connected","device-disconnected"}) {
                var c=NewCore();var f=new FormProbe(c);var t=Target();Start(c,t);var old=c.CurrentDevice;var expire=c.TimeoutCallback;
                if(race=="success-ui")Notify(t).Cccd.Fire();
                if(race=="failure-ui")Notify(t).Cccd.Fire(AsyncStatus.Error);
                if(race=="device-connected")f.Connected(old);
                if(race=="device-disconnected")f.Disconnected(old);
                c.SetRound(10,10);var current=c.CurrentDevice;
                if(race=="cccd-success")Notify(t).Cccd.Fire();
                if(race=="cccd-error")Notify(t).Cccd.Fire(AsyncStatus.Error);
                if(race=="timeout")expire();
                f.Drain();Check(ReferenceEquals(c.CurrentDevice,current)&&current.DisposeCalls==0&&!f.retryTimer.Enabled&&f.tcpServer.Queries==0&&f.Saves==0,"old "+race+" cannot touch replacement connection");
            }
            {
                var c=NewCore();var f=new FormProbe(c);var t=Target();Start(c,t);long oldId=c.RoundId;var oldNotify=Notify(t);var expire=c.TimeoutCallback;
                var staleCompletion=oldNotify.Cccd.Capture();c.FindService(c.CurrentDevice,9);long newId=c.RoundId;
                staleCompletion(AsyncStatus.Completed);f.Complete(9,oldId,false);expire();f.Drain();
                Check(newId!=oldId&&c.CurrentDevice!=null&&c.CurrentDevice.DisposeCalls==0&&!f.retryTimer.Enabled&&f.tcpServer.Queries==0,"old discovery failure/CCCD/timer cannot affect same-generation rediscovery");
            }
            {
                var c=NewCore();var f=new FormProbe(c);f.config.HasSavedDevice=false;var d=c.CurrentDevice;Start(c);f.Drain();
                Check(d.DisposeCalls==1&&!f.retryTimer.Enabled&&f.Saves==0,"unsaved target failure cleans up without saved-target retry");
            }
            {
                var c=NewCore();var f=new FormProbe(c);var t=Target();Start(c,t);var n=Notify(t);var write=c.CurrentWriteCharacteristic;
                var pending=c.WriteDataToCharacteristicAsync(write,new byte[]{1},9);
                Check(!pending.Result.Success&&write.WriteCalls==0,"physical GATT write rejects CCCD pending");
                n.Cccd.Fire();f.Drain();int successes=0;c.WriteDataSuccess=(ch,data)=>successes++;
                var good=c.WriteDataToCharacteristicAsync(write,new byte[]{1},9);write.Write.Fire();
                Check(good.Result.Success&&successes==1&&write.WriteCalls==1,"actual write completion succeeds for ready current characteristic");
                var foreign=new GattCharacteristic{Uuid=Uuid(0x7343)};
                Check(!c.PhysicalWrite(foreign,9).Result.Success&&foreign.WriteCalls==0,"final physical guard rejects replaced characteristic object");
                var token=new CancellationTokenSource();token.Cancel();
                Check(!c.WriteDataToCharacteristicAsync(write,new byte[]{1},9,token.Token).Result.Success&&write.WriteCalls==1,"already canceled request never reaches physical write");
                var oldWrite=c.WriteDataToCharacteristicAsync(write,new byte[]{2},9);c.Disconnect();f.Drain();
                Check(!oldWrite.Result.Success&&write.Write.Cancels==1&&successes==1,"actual disconnect cancels active GATT without replay");
                write.Write.Fire();Check(successes==1&&write.WriteCalls==2,"late disconnected GATT completion cannot report success or resend");
                Check(!c.PhysicalWrite(write,9).Result.Success&&write.WriteCalls==2,"final physical guard rejects stale generation");
            }
            {
                var c=NewCore();var t=Target();Start(c,t);Notify(t).Cccd.Fire();var write=c.CurrentWriteCharacteristic;
                var pending=c.WriteDataToCharacteristicAsync(write,new byte[]{1},9);
                c.FindService(c.CurrentDevice,9);write.Write.Fire();
                Check(!pending.Result.Success,"late GATT completion is canceled across same-generation discovery replacement");
            }
            {
                var c=NewCore();var f=new FormProbe(c);var t=Target();var server=new TcpServer(c,null);Start(c,t);
                var before=server.Status();
                Check(!before.Connected&&!before.IsTargetDevice&&c.IsCurrentConnection(9),"actual TCP status is unavailable while physical link is connected and CCCD pending");
                Notify(t).Cccd.Fire();f.Drain();var ready=server.Status();
                Check(ready.Connected&&ready.IsTargetDevice&&ready.DeviceName=="target"&&ready.MacAddress=="00:00:00:00:00:01","actual TCP status atomically reports ready target identity");
                c.Disconnect();var gone=server.Status();
                Check(!gone.Connected&&!gone.IsTargetDevice,"actual TCP status becomes unavailable on disconnect");
            }
            {
                var c=NewCore();var f=new FormProbe(c);var t=Target();Start(c,t);Notify(t).Cccd.Fire(AsyncStatus.Error);
                Check(!c.GetBleStatusInfo().Connected&&!c.GetBleStatusInfo().IsTargetDevice,"failed CCCD closes TCP availability even before queued failure cleanup");
                f.Drain();Check(!c.GetBleStatusInfo().Connected,"failed cleanup remains unavailable");
            }
            var listener=new TcpListener(IPAddress.Loopback,0);listener.Start();
            var peer=new TcpClient();peer.Connect(IPAddress.Loopback,((IPEndPoint)listener.LocalEndpoint).Port);
            var client=listener.AcceptTcpClient();listener.Stop();
            try {
                core.SetRound(3,3);var server=new TcpServer(core,client);
                core.NotificationChecked.Reset();Task pending;
                lock(client) {
                    pending=Task.Run(()=>server.Notify(new byte[]{0xAA,0xBB,0x8B,0,0xCC,0xDD},3,3));
                    if(!core.NotificationChecked.Wait(3000))throw new Exception("Notification did not enter");
                    core.SetRound(4,4);server.Advance(4);
                }
                Wait(pending);
                bool staleSent=peer.Client.Poll(100000,SelectMode.SelectRead)&&peer.Available>0;
                Check(!staleSent,"old ACK blocked at actual TCP socket write lock after reconnect");
                if(staleSent)peer.GetStream().Read(new byte[peer.Available],0,peer.Available);
                server.Notify(new byte[]{0x55},4,4);
                peer.ReceiveTimeout=1000;var bytes=new byte[4];int count=0;
                while(count<bytes.Length)count+=peer.GetStream().Read(bytes,count,bytes.Length-count);
                Check(bytes.SequenceEqual(new byte[]{0x81,1,0,0x55}),"current notification reaches real isolated socket unchanged");
                var target=Target();Start(core,target);Notify(target).Cccd.Fire();
                var entered=new ManualResetEventSlim(false);
                lock(client){
                    pending=Task.Run(()=>{entered.Set();server.QueryStatus(client);});
                    if(!entered.Wait(3000))throw new Exception("query worker did not start");
                    core.SetRound(4,44);core.CurrentDevice.Name="replacement";
                }
                Wait(pending);
                var packet=ProtocolHelper.BuildBleStatusPacket(core.GetBleStatusInfo());var read=new byte[packet.Length];int received=0;
                while(received<read.Length)received+=peer.GetStream().Read(read,received,read.Length-received);
                Check(read.SequenceEqual(packet)&&read[3]==0,"TCP status query waiting on socket lock resolves replacement unavailable identity at send time");
                core.SetRound(4,4);
                byte[] status={0xAA,0xBB,0,77,0,0,0,0,0,1,0,0xCC,0xDD};
                server.Notify(status,4,4);Check(server.CachedBattery==77,"current status is cached");
                core.SetRound(5,5);server.Advance(5);
                Check(server.CachedBattery==0,"new generation clears old status cache");
                core.NotificationChecked.Reset();
                lock(server.StatusGate) {
                    pending=Task.Run(()=>server.Notify(status,5,5));
                    if(!core.NotificationChecked.Wait(3000))throw new Exception("Status did not enter");
                    core.SetRound(6,6);
                }
                Wait(pending);
                Check(server.CachedBattery==0,"late status blocked after waiting on cache lock");
            } finally {client.Close();peer.Close();}
            Console.WriteLine("RESULT behavior_checks="+checks+" failures="+failures.Count);
            return failures.Count==0;
        }
    }
}
$protocol
"@
Add-Type -TypeDefinition $source -Language CSharp -IgnoreWarnings -WarningAction SilentlyContinue
if (-not [BridgeFixProbe.Runner]::Run()) { throw 'Bridge dependency regression failures (real extracted methods with controlled WinRT substitutes).' }
if (-not $program.Contains('null, 15000, Timeout.Infinite)')) {throw 'Missing finite per-round deadline wiring'}
if (-not $tcp.Contains('SendToClient(client, null, deviceInfo: true)')) {throw 'Missing socket-lock cache wiring'}
if (-not $tcp.Contains('SendToClient(client, null, bleStatus: true)')) {throw 'Missing socket-lock BLE readiness query wiring'}
Write-Output 'PASS deadline and query-to-write-lock wiring (static); callbacks and UI use deterministic substitutes; no real BLE hardware exercised'
