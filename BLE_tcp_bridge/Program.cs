using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Foundation;
using Windows.Foundation.Metadata;
using Windows.Security.Cryptography;
using Windows.Storage.Streams;
namespace BLE_tcp_driver
{
    class BleCore
    {
        // "Magic" string for all BLE devices
        static string _aqsAllBLEDevices = "(System.Devices.Aep.ProtocolId:=\"{bb7bb05e-5972-42b5-94fc-76eaa7084d49}\")";
        static string[] _requestedBLEProperties = { "System.Devices.Aep.DeviceAddress", "System.Devices.Aep.Bluetooth.Le.IsConnectable", };
        static List<DeviceInformation> _deviceList = new List<DeviceInformation>();
        static DeviceWatcher watcher;

        private bool asyncLock = false;
        private long _connectionGeneration;
        private long _nextDiscoveryId;
        private readonly object _discoveryLock = new object();
        private DiscoveryRound _activeDiscovery;
        private GattCharacteristic _notifySubscriptionCharacteristic;
        private TypedEventHandler<GattCharacteristic, GattValueChangedEventArgs> _notifySubscriptionHandler;
        private readonly object _activeWriteLock = new object();
        private readonly Dictionary<long, ActiveGattWrite> _activeGattWrites = new Dictionary<long, ActiveGattWrite>();
        private long _nextGattWriteId;
        private readonly object _sessionLock = new object();
        private GattSession _gattSession;
        private long _gattSessionGeneration = -1;

        /// <summary>
        /// 当前连接的服务
        /// </summary>
        public GattDeviceService CurrentService { get; private set; }

        /// <summary>
        /// 当前连接的蓝牙设备
        /// </summary>
        public BluetoothLEDevice CurrentDevice { get; private set; }

        public long ConnectionGeneration => Interlocked.Read(ref _connectionGeneration);

        public event Action<long> ConnectionGenerationChanged;

        public bool IsCurrentConnection(long generation)
        {
            var device = CurrentDevice;
            return generation == ConnectionGeneration
                && device != null
                && device.ConnectionStatus == BluetoothConnectionStatus.Connected;
        }

        public bool IsCurrentDiscovery(long generation, long discoveryId)
        {
            lock (_discoveryLock)
                return IsCurrentDiscoveryLocked(generation, discoveryId);
        }

        private bool IsCurrentDiscoveryLocked(long generation, long discoveryId)
        {
            return _activeDiscovery != null
                && BridgeRoundIdentity.Matches(generation, discoveryId,
                    _activeDiscovery.Generation, _activeDiscovery.Id)
                && ReferenceEquals(CurrentDevice, _activeDiscovery.Device)
                && IsCurrentConnection(generation);
        }

        public bool TryAcceptDiscoveredCharacteristic(GattCharacteristic characteristic, long generation, long discoveryId)
        {
            lock (_discoveryLock)
            {
                if (!IsCurrentDiscoveryLocked(generation, discoveryId))
                    return false;

                switch (Utilities.ConvertUuidToShortId(characteristic.Uuid))
                {
                    case 0x7341:
                        CurrentDataCharacteristic = characteristic;
                        break;
                    case 0x7343:
                        CurrentWriteCharacteristic = characteristic;
                        break;
                    case 0x7344:
                        CurrentNotifyCharacteristic = characteristic;
                        break;
                }
                return true;
            }
        }

        /// <summary>
        /// 写特征对象 (命令 0x7343)
        /// </summary>
        public GattCharacteristic CurrentWriteCharacteristic { get; set; }

        /// <summary>
        /// 数据写特征对象 (数据 0x7341)
        /// </summary>
        public GattCharacteristic CurrentDataCharacteristic { get; set; }

        /// <summary>
        /// 通知特征对象 (通知 0x7344)
        /// </summary>
        public GattCharacteristic CurrentNotifyCharacteristic { get; set; }

        /// <summary>
        /// 存储检测到的特征
        /// </summary>
        public List<GattCharacteristic> CharacteristicList { get; private set; }

        /// <summary>
        /// 特性通知类型通知启用
        /// </summary>
        private const GattClientCharacteristicConfigurationDescriptorValue CHARACTERISTIC_NOTIFICATION_TYPE = GattClientCharacteristicConfigurationDescriptorValue.Notify;


        /// <summary>
        /// 获取服务及特征完成事件
        /// </summary>
        public event CharacteristicFinishEvent CharacteristicFinish;
        public delegate void CharacteristicFinishEvent(int size, long generation, long discoveryId);

        /// <summary>
        /// 发现特征事件
        /// </summary>
        public event CharacteristicAddedEvent CharacteristicAdded;
        public delegate void CharacteristicAddedEvent(GattCharacteristic gattCharacteristic, long generation, long discoveryId);

        /// <summary>
        /// 发现设备事件
        /// </summary>
        public event DeviceAddedEvent DeviceAdded;
        public delegate void DeviceAddedEvent(DeviceInformation deviceInformation);

        /// <summary>
        /// 设备连接成功事件
        /// </summary>
        public event ConnectDeviceSuccessEvent ConnectDeviceSuccess;
        public delegate void ConnectDeviceSuccessEvent(BluetoothLEDevice bluetoothLEDevice);

        /// <summary>
        /// 向特征写事件成功事件
        /// </summary>
        public event WriteDataSuccessEvent WriteDataSuccess;
        public delegate void WriteDataSuccessEvent(GattCharacteristic sendrt, byte[] data);

        /// <summary>
        /// 向特征读取事件成功事件
        /// </summary>
        public event ReadDataSuccessEvent ReadDataSuccess;
        public delegate void ReadDataSuccessEvent(GattCharacteristic sendrt, byte[] data);


        /// <summary>
        /// 收到特征发送的通知事件
        /// </summary>
        public event ReceiveNotifyDataEvent ReceiveNotifyData;
        public delegate void ReceiveNotifyDataEvent(GattCharacteristic sender, byte[] data, long generation, long discoveryId);

        /// <summary>
        /// 设备断开连接事件
        /// </summary>
        public event Action<BluetoothLEDevice> DeviceDisconnected;

        /// <summary>
        /// 所有服务的特征发现完毕事件
        /// </summary>
        public event Action<long, long, bool> AllCharacteristicsDiscovered;

        /// <summary>
        /// 当前连接的蓝牙Mac
        /// </summary>
        private string CurrentDeviceMAC { get; set; }


        public BleCore()
        {
            CharacteristicList = new List<GattCharacteristic>();
        }
        /// <summary>
        /// 获取发现的蓝牙设备
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="args"></param>
        private void DeviceWatcher_Added(DeviceWatcher sender, DeviceInformation args)
        {
            Console.WriteLine("发现设备:" + args.Id + "Name:" + args.Name);
            _deviceList.Add(args);
            DeviceAdded?.Invoke(args);
            //Console.WriteLine("Pairing:" + args.Pairing.IsPaired );
            //if (args.Name.StartsWith("Progame.bleNameSuffix"))
            //{
            //    var res = BluetoothLEDevice.FromIdAsync(args.Id).Completed = (asyncInfo, asyncStatus) =>
            //    {
            //        if (asyncStatus == AsyncStatus.Completed)
            //        {
            //            Progame.ConnectDevice(asyncInfo.GetResults());
            //            //GattCommunicationStatus a = asyncInfo.GetResults();
            //            //Console.WriteLine("发送数据：" + BitConverter.ToString(data) + " State : " + a);
            //            //Progame.sendOk = 1;
            //        }
            //    };
            //}
            //this.Matching(args.Id);
        }
        /// <summary>
        /// 根据设备信息连接设备
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="args"></param>
        public void ConnectDeviceByInfo(DeviceInformation args)
        {
            Console.WriteLine("连接设备:" + args.Id + "Name:" + args.Name);
            var res = BluetoothLEDevice.FromIdAsync(args.Id).Completed = (asyncInfo, asyncStatus) =>
            {
                if (asyncStatus == AsyncStatus.Completed)
                {
                    ConnectDevice(asyncInfo.GetResults());
                }
            };
        }
        private void ConnectDevice(BluetoothLEDevice Device)
        {
            long generation;
            lock (_discoveryLock)
            {
                if (CurrentDevice != null)
                    CurrentDevice.ConnectionStatusChanged -= CurrentDevice_ConnectionStatusChanged;

                InvalidateDiscoveryLocked();
                CurrentWriteCharacteristic = null;
                CurrentDataCharacteristic = null;
                CurrentNotifyCharacteristic = null;
                CurrentDevice = Device;
                generation = AdvanceConnectionGeneration();
                CurrentDevice.ConnectionStatusChanged += CurrentDevice_ConnectionStatusChanged;
            }
            ConnectDeviceSuccess?.Invoke(Device);
            FindService(Device, generation);
        }

        /// <summary>
        /// 搜索蓝牙设备
        /// </summary>
        public void StartBleDeviceWatcher()
        {
            _deviceList = new List<DeviceInformation>();
            // Start endless BLE device watcher
            watcher = DeviceInformation.CreateWatcher(_aqsAllBLEDevices, _requestedBLEProperties, DeviceInformationKind.AssociationEndpoint);
            watcher.Added += (DeviceWatcher sender, DeviceInformation devInfo) =>
            {
                if (_deviceList.FirstOrDefault(d => d.Id.Equals(devInfo.Id) || d.Name.Equals(devInfo.Name)) == null) _deviceList.Add(devInfo);
            };
            watcher.Updated += (_, __) => { }; // We need handler for this event, even an empty!
            //Watch for a device being removed by the watcher
            //watcher.Removed += (DeviceWatcher sender, DeviceInformationUpdate devInfo) =>
            //{
            //    _deviceList.Remove(FindKnownDevice(devInfo.Id));
            //};
            watcher.EnumerationCompleted += (DeviceWatcher sender, object arg) => { sender.Stop(); };
            //watcher.Stopped += (DeviceWatcher sender, object arg) => { _deviceList.Clear(); sender.Start(); };
            watcher.Stopped += (DeviceWatcher sender, object arg) => { };
            watcher.Added += DeviceWatcher_Added;
            watcher.Start();
            Console.WriteLine("自动发现设备中..");
        }

        /// <summary>
        /// 停止搜索蓝牙
        /// </summary>
        public void StopBleDeviceWatcher()
        {
            watcher?.Stop();
        }

        /// <summary>
        /// 主动断开连接
        /// </summary>
        /// <returns></returns>
        public void Dispose()
        {
            lock (_discoveryLock)
                DisposeCurrentConnectionLocked();
        }

        public bool TryDisposeIncompleteDiscovery(long generation, long discoveryId)
        {
            lock (_discoveryLock)
            {
                if (!IsCurrentDiscoveryLocked(generation, discoveryId))
                    return false;
                DisposeCurrentConnectionLocked();
                return true;
            }
        }

        private void DisposeCurrentConnectionLocked()
        {
            InvalidateDiscoveryLocked();
            AdvanceConnectionGeneration();
            CurrentDeviceMAC = null;
            if (CurrentDevice != null)
                CurrentDevice.ConnectionStatusChanged -= CurrentDevice_ConnectionStatusChanged;
            CurrentService?.Dispose();
            CurrentDevice?.Dispose();
            CurrentDevice = null;
            CurrentService = null;
            CurrentWriteCharacteristic = null;
            CurrentDataCharacteristic = null;
            CurrentNotifyCharacteristic = null;
            Console.WriteLine("主动断开连接");
        }

        /// <summary>
        /// 匹配
        /// </summary>
        /// <param name="Device"></param>
        public void StartMatching(BluetoothLEDevice Device)
        {
            this.CurrentDevice = Device;
        }

        /// <summary>
        /// 发送数据接口
        /// </summary>
        /// <returns></returns>
        public void Write(byte[] data)
        {
            var characteristic = CurrentWriteCharacteristic;
            long generation = ConnectionGeneration;
            if (characteristic == null)
            {
                Console.WriteLine("当前没有设置写服务特征");
                return;
            }
            _ = WriteDataToCharacteristicAsync(characteristic, data, generation);
        }
        /// <summary>
        /// 发送数据接口
        /// </summary>
        /// <returns></returns>
        public Task<GattWriteResult> WriteDataToCharacteristicAsync(GattCharacteristic c, byte[] data, long generation,
            CancellationToken cancellationToken = default(CancellationToken))
        {
            if (c == null)
            {
                return Task.FromResult(new GattWriteResult(AsyncStatus.Error, null, new InvalidOperationException("写特征为空")));
            }
            if (!IsCurrentConnection(generation))
            {
                return Task.FromResult(new GattWriteResult(AsyncStatus.Canceled, null, new OperationCanceledException("连接代次已变化")));
            }
            return WriteValueAsync(c, data ?? new byte[0], generation, cancellationToken);
        }

        public void WriteDataToCharacterstuc(GattCharacteristic c, byte[] data)
        {
            _ = WriteDataToCharacteristicAsync(c, data, ConnectionGeneration);
        }

        private Task<GattWriteResult> WriteValueAsync(GattCharacteristic characteristic, byte[] data, long generation,
            CancellationToken cancellationToken)
        {
            var completion = new TaskCompletionSource<GattWriteResult>(TaskCreationOptions.RunContinuationsAsynchronously);
            try
            {
                var operation = characteristic.WriteValueAsync(
                    CryptographicBuffer.CreateFromByteArray(data),
                    GattWriteOption.WriteWithResponse);
                long operationId = Interlocked.Increment(ref _nextGattWriteId);
                lock (_activeWriteLock)
                {
                    if (!IsCurrentConnection(generation))
                    {
                        operation.Cancel();
                        completion.TrySetResult(new GattWriteResult(AsyncStatus.Canceled, null,
                            new OperationCanceledException("连接代次已变化")));
                        return completion.Task;
                    }
                    _activeGattWrites.Add(operationId, new ActiveGattWrite(operationId, generation, operation, completion));
                }

                CancellationTokenRegistration cancellationRegistration = default(CancellationTokenRegistration);
                if (cancellationToken.CanBeCanceled)
                {
                    cancellationRegistration = cancellationToken.Register(() =>
                    {
                        lock (_activeWriteLock) _activeGattWrites.Remove(operationId);
                        try { operation.Cancel(); }
                        catch (Exception ex) { Console.WriteLine("取消客户端GATT写操作失败: " + ex.Message); }
                        completion.TrySetResult(new GattWriteResult(AsyncStatus.Canceled, null,
                            new OperationCanceledException("事务已取消")));
                    });
                }

                operation.Completed = (asyncInfo, asyncStatus) =>
                {
                    try
                    {
                        if (cancellationToken.IsCancellationRequested || !IsCurrentConnection(generation))
                        {
                            completion.TrySetResult(new GattWriteResult(AsyncStatus.Canceled, null,
                                new OperationCanceledException("GATT完成时事务或连接代次已失效")));
                            return;
                        }
                        if (asyncStatus != AsyncStatus.Completed)
                        {
                            Exception error;
                            try { asyncInfo.GetResults(); error = new InvalidOperationException("GATT 写操作状态: " + asyncStatus); }
                            catch (Exception ex) { error = ex; }
                            completion.TrySetResult(new GattWriteResult(asyncStatus, null, error));
                            return;
                        }

                        GattCommunicationStatus communicationStatus = asyncInfo.GetResults();
                        if (communicationStatus == GattCommunicationStatus.Success && IsCurrentConnection(generation))
                            WriteDataSuccess?.Invoke(characteristic, data);
                        completion.TrySetResult(new GattWriteResult(asyncStatus, communicationStatus, null));
                    }
                    catch (Exception ex)
                    {
                        completion.TrySetResult(new GattWriteResult(asyncStatus, null, ex));
                    }
                    finally
                    {
                        cancellationRegistration.Dispose();
                        lock (_activeWriteLock) _activeGattWrites.Remove(operationId);
                    }
                };
            }
            catch (Exception ex)
            {
                completion.TrySetResult(new GattWriteResult(AsyncStatus.Error, null, ex));
            }
            return completion.Task;
        }

        public int GetMaxGattWritePayload(long generation, out int reportedPduSize, out string source)
        {
            const int fallbackPayload = 20;
            const int firmwareCharacteristicLimit = 200;
            reportedPduSize = 23;
            source = "legacy-default";
            if (!IsCurrentConnection(generation))
                return fallbackPayload;

            try
            {
                if (!ApiInformation.IsTypePresent("Windows.Devices.Bluetooth.GenericAttributeProfile.GattSession")
                    || !ApiInformation.IsPropertyPresent("Windows.Devices.Bluetooth.GenericAttributeProfile.GattSession", "MaxPduSize"))
                {
                    return fallbackPayload;
                }

                GattSession session;
                lock (_sessionLock)
                {
                    if (_gattSessionGeneration != generation || _gattSession == null)
                    {
                        _gattSession?.Dispose();
                        _gattSession = GattSession.FromDeviceIdAsync(CurrentDevice.BluetoothDeviceId)
                            .AsTask().GetAwaiter().GetResult();
                        _gattSessionGeneration = generation;
                    }
                    session = _gattSession;
                }

                if (session == null || !IsCurrentConnection(generation))
                    return fallbackPayload;

                reportedPduSize = session.MaxPduSize;
                if (reportedPduSize <= 23)
                {
                    source = "negotiated-default";
                    return fallbackPayload;
                }

                source = "GattSession.MaxPduSize";
                return BridgeMtuPolicy.SelectPayload(reportedPduSize, true, firmwareCharacteristicLimit);
            }
            catch (Exception ex)
            {
                Console.WriteLine("MTU读取失败，回退20字节: " + ex.Message);
                return fallbackPayload;
            }
        }

        private long AdvanceConnectionGeneration()
        {
            long generation = Interlocked.Increment(ref _connectionGeneration);
            InvalidateActiveGattWrites(generation);
            lock (_discoveryLock)
                InvalidateDiscoveryLocked();
            lock (_sessionLock)
            {
                _gattSession?.Dispose();
                _gattSession = null;
                _gattSessionGeneration = -1;
            }
            ConnectionGenerationChanged?.Invoke(generation);
            return generation;
        }

        private void InvalidateActiveGattWrites(long currentGeneration)
        {
            List<ActiveGattWrite> staleWrites;
            lock (_activeWriteLock)
            {
                staleWrites = _activeGattWrites.Values
                    .Where(write => write.Generation != currentGeneration)
                    .ToList();
                foreach (var write in staleWrites)
                    _activeGattWrites.Remove(write.Id);
            }

            foreach (var write in staleWrites)
            {
                try { write.Operation.Cancel(); }
                catch (Exception ex) { Console.WriteLine("取消旧GATT写操作失败: " + ex.Message); }
                write.Completion.TrySetResult(new GattWriteResult(AsyncStatus.Canceled, null,
                    new OperationCanceledException("连接代次已变化")));
            }
        }

        private void InvalidateDiscoveryLocked()
        {
            _activeDiscovery = null;
            RemoveNotifySubscriptionLocked();
        }

        private void RemoveNotifySubscriptionLocked()
        {
            if (_notifySubscriptionCharacteristic != null && _notifySubscriptionHandler != null)
            {
                try { _notifySubscriptionCharacteristic.ValueChanged -= _notifySubscriptionHandler; }
                catch { }
            }
            _notifySubscriptionCharacteristic = null;
            _notifySubscriptionHandler = null;
        }

        private sealed class ActiveGattWrite
        {
            public long Id { get; }
            public long Generation { get; }
            public IAsyncOperation<GattCommunicationStatus> Operation { get; }
            public TaskCompletionSource<GattWriteResult> Completion { get; }

            public ActiveGattWrite(long id, long generation, IAsyncOperation<GattCommunicationStatus> operation,
                TaskCompletionSource<GattWriteResult> completion)
            {
                Id = id;
                Generation = generation;
                Operation = operation;
                Completion = completion;
            }
        }

        private sealed class DiscoveryRound
        {
            public long Id { get; }
            public long Generation { get; }
            public BluetoothLEDevice Device { get; }
            public int PendingServices { get; set; }
            public bool Failed { get; set; }

            public DiscoveryRound(long id, long generation, BluetoothLEDevice device)
            {
                Id = id;
                Generation = generation;
                Device = device;
            }
        }

        internal sealed class GattWriteResult
        {
            public AsyncStatus AsyncStatus { get; }
            public GattCommunicationStatus? CommunicationStatus { get; }
            public Exception Error { get; }
            public bool Success => AsyncStatus == AsyncStatus.Completed
                && CommunicationStatus == GattCommunicationStatus.Success
                && Error == null;

            public GattWriteResult(AsyncStatus asyncStatus, GattCommunicationStatus? communicationStatus, Exception error)
            {
                AsyncStatus = asyncStatus;
                CommunicationStatus = communicationStatus;
                Error = error;
            }
        }
        public void ReadDataFromCharacterstuc(GattCharacteristic c)
        {
            if (c != null)
            {
                c.ReadValueAsync(BluetoothCacheMode.Uncached).Completed = (asyncInfo, asyncStatus) =>
                {
                    if (asyncStatus == AsyncStatus.Completed)
                    {
                        //var a = asyncInfo.GetResults();
                        var test = asyncInfo.GetResults().Value;
                        byte[] data;
                        CryptographicBuffer.CopyToByteArray(test, out data);
                        Console.WriteLine("读取数据：" + BitConverter.ToString(data) + " State : " + asyncInfo.GetResults());
                        ReadDataSuccess?.Invoke(c, data);
                    }
                };
            }
            else
            {
                Console.WriteLine("当前没有设置写服务特征");
            }

        }
        /// <summary>
        /// 获取蓝牙服务
        /// </summary>
        public void FindService(BluetoothLEDevice dev, long generation)
        {
            if (dev == null)
            {
                Console.WriteLine("当前没有打开设备");
                return;
            }

            var round = new DiscoveryRound(Interlocked.Increment(ref _nextDiscoveryId), generation, dev);
            lock (_discoveryLock)
            {
                if (!IsCurrentConnection(generation) || !ReferenceEquals(CurrentDevice, dev))
                    return;
                InvalidateDiscoveryLocked();
                _activeDiscovery = round;
                CharacteristicList.Clear();
            }

            try
            {
                dev.GetGattServicesAsync(BluetoothCacheMode.Uncached).Completed = (asyncInfo, asyncStatus) =>
                {
                    List<GattDeviceService> services = new List<GattDeviceService>();
                    Exception error = null;
                    if (asyncStatus == AsyncStatus.Completed)
                    {
                        try
                        {
                            services.AddRange(asyncInfo.GetResults().Services);
                        }
                        catch (Exception ex) { error = ex; }
                    }

                    lock (_discoveryLock)
                    {
                        if (!IsCurrentDiscoveryLocked(generation, round.Id))
                            return;
                        if (error != null || asyncStatus != AsyncStatus.Completed)
                            round.Failed = true;
                        CurrentService = services.FirstOrDefault();
                        round.PendingServices = services.Count;
                    }

                    if (error != null || asyncStatus != AsyncStatus.Completed)
                    {
                        Console.WriteLine($"GATT服务发现失败 gen={generation} discovery={round.Id} status={asyncStatus} error={error?.Message}");
                        CharacteristicFinish?.Invoke(0, generation, round.Id);
                        AllCharacteristicsDiscovered?.Invoke(generation, round.Id, false);
                        return;
                    }
                    Console.WriteLine("GattServices size=" + services.Count);
                    for (int i = 0; i < services.Count; i++)
                        Console.WriteLine($"#{i:00}: {services[i].Uuid}");

                    CharacteristicFinish?.Invoke(services.Count, generation, round.Id);
                    if (services.Count == 0)
                    {
                        AllCharacteristicsDiscovered?.Invoke(generation, round.Id, true);
                        return;
                    }

                    foreach (GattDeviceService service in services)
                        FindCharacteristic(service, round);
                };
            }
            catch (Exception ex)
            {
                bool current;
                lock (_discoveryLock)
                        {
                    current = IsCurrentDiscoveryLocked(generation, round.Id);
                    if (current)
                    {
                        round.PendingServices = 0;
                        round.Failed = true;
                    }
                    }
                if (current)
                {
                    Console.WriteLine($"GATT服务发现启动失败 gen={generation} discovery={round.Id}: {ex.Message}");
                    CharacteristicFinish?.Invoke(0, generation, round.Id);
                    AllCharacteristicsDiscovered?.Invoke(generation, round.Id, false);
                }
            }
        }

        /// <summary>
        /// 按MAC地址直接组装设备ID查找设备
        /// </summary>
        public void SelectDeviceFromIdAsync(string MAC)
        {
            CurrentDeviceMAC = MAC;
            CurrentDevice = null;
            BluetoothAdapter.GetDefaultAsync().Completed = (asyncInfo, asyncStatus) =>
            {
                if (asyncStatus == AsyncStatus.Completed)
                {
                    BluetoothAdapter mBluetoothAdapter = asyncInfo.GetResults();
                    byte[] _Bytes1 = BitConverter.GetBytes(mBluetoothAdapter.BluetoothAddress);//ulong转换为byte数组
                    Array.Reverse(_Bytes1);
                    string macAddress = BitConverter.ToString(_Bytes1, 2, 6).Replace('-', ':').ToLower();
                    string Id = "BluetoothLE#BluetoothLE" + macAddress + "-" + MAC;
                    Matching(Id);
                }
            };
        }

        /// <summary>
        /// 获取操作
        /// </summary>
        /// <returns></returns>
        public void SetOpteron(GattCharacteristic gattCharacteristic)
        {
            byte[] _Bytes1 = BitConverter.GetBytes(this.CurrentDevice.BluetoothAddress);
            Array.Reverse(_Bytes1);
            this.CurrentDeviceMAC = BitConverter.ToString(_Bytes1, 2, 6).Replace('-', ':').ToLower();

            string msg = "正在连接设备<" + this.CurrentDeviceMAC + ">..";
            Console.WriteLine(msg);

            if (gattCharacteristic.CharacteristicProperties == GattCharacteristicProperties.Write)
            {
                this.CurrentWriteCharacteristic = gattCharacteristic;
            }
            if (gattCharacteristic.CharacteristicProperties == GattCharacteristicProperties.Notify)
            {
                this.CurrentNotifyCharacteristic = gattCharacteristic;
            }
            if ((uint)gattCharacteristic.CharacteristicProperties == 26)
            {

            }

            if (gattCharacteristic.CharacteristicProperties == (GattCharacteristicProperties.Write | GattCharacteristicProperties.Notify))
            {
                this.CurrentWriteCharacteristic = gattCharacteristic;
                this.CurrentNotifyCharacteristic = gattCharacteristic;
                this.CurrentNotifyCharacteristic.ProtectionLevel = GattProtectionLevel.Plain;
                this.CurrentDevice.ConnectionStatusChanged += this.CurrentDevice_ConnectionStatusChanged;
                DiscoveryRound round;
                lock (_discoveryLock) round = _activeDiscovery;
                if (round != null)
                    this.EnableNotifications(CurrentNotifyCharacteristic, round.Generation, round.Id);
            }

        }

        //private void OnAdvertisementReceived(BluetoothLEAdvertisementWatcher watcher, BluetoothLEAdvertisementReceivedEventArgs eventArgs)
        //{
        //    BluetoothLEDevice.FromBluetoothAddressAsync(eventArgs.BluetoothAddress).Completed = (asyncInfo, asyncStatus) =>
        //    {
        //        if (asyncStatus == AsyncStatus.Completed)
        //        {
        //            if (asyncInfo.GetResults() == null)
        //            {
        //                //Console.WriteLine("没有得到结果集");
        //            }
        //            else
        //            {
        //                BluetoothLEDevice currentDevice = asyncInfo.GetResults();

        //                if (DeviceList.FindIndex((x) => { return x.Name.Equals(currentDevice.Name); }) < 0)
        //                {
        //                    this.DeviceList.Add(currentDevice);
        //                    DeviceWatcherChanged?.Invoke(currentDevice);
        //                }

        //            }

        //        }
        //    };
        //}

        /// <summary>
        /// 获取特性
        /// </summary>
        private void FindCharacteristic(GattDeviceService gattDeviceService, DiscoveryRound round)
        {
            lock (_discoveryLock)
            {
                if (!IsCurrentDiscoveryLocked(round.Generation, round.Id))
                    return;
            }

            try
            {
                gattDeviceService.GetCharacteristicsAsync(BluetoothCacheMode.Uncached).Completed = (asyncInfo, asyncStatus) =>
                {
                    List<GattCharacteristic> characteristics = new List<GattCharacteristic>();
                    bool querySucceeded = asyncStatus == AsyncStatus.Completed;
                    if (asyncStatus == AsyncStatus.Completed)
                    {
                        try { characteristics.AddRange(asyncInfo.GetResults().Characteristics); }
                        catch (Exception ex)
                        {
                            querySucceeded = false;
                            Console.WriteLine($"GATT特征读取失败 gen={round.Generation} discovery={round.Id}: {ex.Message}");
                        }
                    }

                    bool completed;
                    bool succeeded;
                    lock (_discoveryLock)
                    {
                        if (!IsCurrentDiscoveryLocked(round.Generation, round.Id))
                            return;
                        if (!querySucceeded)
                            round.Failed = true;
                        CharacteristicList.AddRange(characteristics);
                        foreach (GattCharacteristic characteristic in characteristics)
                        {
                            switch (Utilities.ConvertUuidToShortId(characteristic.Uuid))
                            {
                                case 0x7341: CurrentDataCharacteristic = characteristic; break;
                                case 0x7343: CurrentWriteCharacteristic = characteristic; break;
                                case 0x7344: CurrentNotifyCharacteristic = characteristic; break;
                            }
                        }
                        round.PendingServices--;
                        completed = round.PendingServices == 0;
                        succeeded = completed && !round.Failed;
                    }

                    foreach (GattCharacteristic characteristic in characteristics)
                        CharacteristicAdded?.Invoke(characteristic, round.Generation, round.Id);
                    if (completed)
                        AllCharacteristicsDiscovered?.Invoke(round.Generation, round.Id, succeeded);
                };
            }
            catch (Exception ex)
            {
                bool completed;
                lock (_discoveryLock)
                {
                    if (!IsCurrentDiscoveryLocked(round.Generation, round.Id))
                        return;
                    round.Failed = true;
                    round.PendingServices--;
                    completed = round.PendingServices == 0;
                }
                Console.WriteLine($"GATT特征发现启动失败 gen={round.Generation} discovery={round.Id}: {ex.Message}");
                if (completed)
                    AllCharacteristicsDiscovered?.Invoke(round.Generation, round.Id, false);
            }
        }

        /// <summary>
        /// 搜索到的蓝牙设备
        /// </summary>
        /// <returns></returns>
        private void Matching(string Id)
        {
            try
            {
                BluetoothLEDevice.FromIdAsync(Id).Completed = (asyncInfo, asyncStatus) =>
                {
                    if (asyncStatus == AsyncStatus.Completed)
                    {
                        BluetoothLEDevice bleDevice = asyncInfo.GetResults();
                        //this.DeviceList.Add(bleDevice);
                        Console.WriteLine(bleDevice);
                    }

                    if (asyncStatus == AsyncStatus.Started)
                    {
                        Console.WriteLine(asyncStatus.ToString());
                    }
                    if (asyncStatus == AsyncStatus.Canceled)
                    {
                        Console.WriteLine(asyncStatus.ToString());
                    }
                    if (asyncStatus == AsyncStatus.Error)
                    {
                        Console.WriteLine(asyncStatus.ToString());
                    }
                };
            }
            catch (Exception e)
            {
                string msg = "没有发现设备" + e.ToString();
                Console.WriteLine(msg);
                this.StartBleDeviceWatcher();
            }
        }


        private void CurrentDevice_ConnectionStatusChanged(BluetoothLEDevice sender, object args)
        {
            lock (_discoveryLock)
            {
                if (!ReferenceEquals(sender, CurrentDevice))
                    return;
                if (sender.ConnectionStatus == BluetoothConnectionStatus.Disconnected)
                {
                    Console.WriteLine("设备已断开");
                    InvalidateDiscoveryLocked();
                    AdvanceConnectionGeneration();
                    CurrentWriteCharacteristic = null;
                    CurrentDataCharacteristic = null;
                    CurrentNotifyCharacteristic = null;
                    DeviceDisconnected?.Invoke(sender);
                }
                else
                {
                    Console.WriteLine("设备已连接");
                }
            }
        }

        /// <summary>
        /// 设置特征对象为接收通知对象
        /// </summary>
        /// <param name="characteristic"></param>
        /// <returns></returns>
        public void EnableNotifications(GattCharacteristic characteristic, long generation, long discoveryId)
        {
            if (!IsCurrentDiscovery(generation, discoveryId)
                || !ReferenceEquals(CurrentNotifyCharacteristic, characteristic))
                return;

            Console.WriteLine("收通知对象=" + CurrentDevice.Name + ":" + CurrentDevice.ConnectionStatus);
            try
            {
                characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(CHARACTERISTIC_NOTIFICATION_TYPE).Completed = (asyncInfo, asyncStatus) =>
                {
                    if (!IsCurrentDiscovery(generation, discoveryId)
                        || !ReferenceEquals(CurrentNotifyCharacteristic, characteristic))
                        return;

                    if (asyncStatus != AsyncStatus.Completed)
                    {
                        Console.WriteLine($"通知订阅失败 gen={generation} discovery={discoveryId} async={asyncStatus}");
                        return;
                    }

                    GattCommunicationStatus status;
                    try { status = asyncInfo.GetResults(); }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"通知订阅结果读取失败 gen={generation} discovery={discoveryId}: {ex.Message}");
                        return;
                    }

                    if (status == GattCommunicationStatus.Unreachable)
                    {
                        Console.WriteLine("设备不可用");
                        if (!asyncLock && IsCurrentDiscovery(generation, discoveryId))
                            EnableNotifications(characteristic, generation, discoveryId);
                        return;
                    }
                    if (status != GattCommunicationStatus.Success)
                    {
                        Console.WriteLine($"通知订阅返回失败状态 gen={generation} discovery={discoveryId}: {status}");
                        return;
                    }

                    lock (_discoveryLock)
                    {
                        if (!IsCurrentDiscoveryLocked(generation, discoveryId)
                            || !ReferenceEquals(CurrentNotifyCharacteristic, characteristic))
                            return;
                        RemoveNotifySubscriptionLocked();
                        _notifySubscriptionCharacteristic = characteristic;
                        _notifySubscriptionHandler = (notifySender, eventArgs) =>
                            Characteristic_ValueChanged(notifySender, eventArgs, generation, discoveryId);
                        characteristic.ValueChanged += _notifySubscriptionHandler;
                    }
                    asyncLock = false;
                    Console.WriteLine("设备连接状态" + status);
                };
            }
            catch (Exception ex)
            {
                Console.WriteLine($"通知订阅启动失败 gen={generation} discovery={discoveryId}: {ex.Message}");
            }
        }

        /// <summary>
        /// 接受到蓝牙数据
        /// </summary>
        private void Characteristic_ValueChanged(GattCharacteristic sender, GattValueChangedEventArgs args,
            long generation, long discoveryId)
        {
            lock (_discoveryLock)
            {
                if (!IsCurrentDiscoveryLocked(generation, discoveryId)
                    || !ReferenceEquals(sender, _notifySubscriptionCharacteristic))
                    return;
            }
            byte[] data;
            CryptographicBuffer.CopyToByteArray(args.CharacteristicValue, out data);
            if (IsCurrentDiscovery(generation, discoveryId))
                ReceiveNotifyData?.Invoke(sender, data, generation, discoveryId);
        }

    }


    class Utilities
    {
        /// <summary>
        ///     Converts from standard 128bit UUID to the assigned 32bit UUIDs. Makes it easy to compare services
        ///     that devices expose to the standard list.
        /// </summary>
        /// <param name="uuid">UUID to convert to 32 bit</param>
        /// <returns></returns>
        public static ushort ConvertUuidToShortId(Guid uuid)
        {
            // Get the short Uuid
            var bytes = uuid.ToByteArray();
            var shortUuid = (ushort)(bytes[0] | (bytes[1] << 8));
            return shortUuid;
        }

        /// <summary>
        ///     Converts from a buffer to a properly sized byte array
        /// </summary>
        /// <param name="buffer"></param>
        /// <returns></returns>
        public static byte[] ReadBufferToBytes(IBuffer buffer)
        {
            var dataLength = buffer.Length;
            var data = new byte[dataLength];
            using (var reader = DataReader.FromBuffer(buffer))
            {
                reader.ReadBytes(data);
            }
            return data;
        }

    }

    internal static class Program
    {

        /// <summary>
        /// 应用程序的主入口点。
        /// </summary>
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new Form1());
        }
    }
}
