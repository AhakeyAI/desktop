using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Foundation;
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
        private readonly object _discoverySync = new object();
        private int _pendingServiceCount = 0;
        private int _discoveryGeneration = 0;
        private bool _discoveryFinalized;
        private bool _targetServiceFound;

        /// <summary>
        /// 当前连接的服务
        /// </summary>
        public GattDeviceService CurrentService { get; private set; }

        /// <summary>
        /// 当前连接的蓝牙设备
        /// </summary>
        public BluetoothLEDevice CurrentDevice { get; private set; }

        /// <summary>
        /// 写特征对象 (命令 0x7343)
        /// </summary>
        public GattCharacteristic CurrentWriteCharacteristic { get; private set; }

        /// <summary>
        /// 数据写特征对象 (数据 0x7341)
        /// </summary>
        public GattCharacteristic CurrentDataCharacteristic { get; private set; }

        /// <summary>
        /// 通知特征对象 (通知 0x7344)
        /// </summary>
        public GattCharacteristic CurrentNotifyCharacteristic { get; private set; }

        /// <summary>
        /// 由发现线程同步维护的目标服务/特征结果。UI 不参与分类，避免 BeginInvoke
        /// 尚未执行时 AllCharacteristicsDiscovered 已经读取到 null 的竞态。
        /// </summary>
        public bool TargetServiceFound
        {
            get { lock (_discoverySync) return _targetServiceFound; }
        }

        public bool HasCompleteTargetCharacteristics
        {
            get
            {
                lock (_discoverySync)
                {
                    return _targetServiceFound
                        && CurrentDataCharacteristic != null
                        && CurrentWriteCharacteristic != null
                        && CurrentNotifyCharacteristic != null;
                }
            }
        }

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
        public delegate void CharacteristicFinishEvent(int size);

        /// <summary>
        /// 发现特征事件
        /// </summary>
        public event CharacteristicAddedEvent CharacteristicAdded;
        public delegate void CharacteristicAddedEvent(GattCharacteristic gattCharacteristic);

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
        public delegate void ReceiveNotifyDataEvent(GattCharacteristic sender, byte[] data);

        /// <summary>
        /// 设备断开连接事件
        /// </summary>
        public event Action<BluetoothLEDevice> DeviceDisconnected;

        /// <summary>
        /// 所有服务的特征发现完毕事件
        /// </summary>
        public event Action AllCharacteristicsDiscovered;

        /// <summary>
        /// 发现诊断日志。事件可能从 WinRT 发现线程触发，UI 层只能将其排队显示。
        /// </summary>
        public event Action<string> DiscoveryDiagnostic;

        /// <summary>
        /// 当前连接的蓝牙Mac
        /// </summary>
        private string CurrentDeviceMAC { get; set; }


        public BleCore()
        {
            CharacteristicList = new List<GattCharacteristic>();
        }

        private void LogDiscovery(string message)
        {
            string line = "[GATT] " + message;
            Console.WriteLine(line);
            try
            {
                DiscoveryDiagnostic?.Invoke(message);
            }
            catch (Exception ex)
            {
                // 诊断日志不能让 WinRT discovery callback 失败。
                Console.WriteLine("[GATT] diagnostic sink failed: " + ex.Message);
            }
        }

        private static string FormatProtocolError(object protocolError)
        {
            return protocolError == null ? "<none>" : protocolError.ToString();
        }

        private static string GetAttributeHandle(object winRtObject)
        {
            if (winRtObject == null) return "<unavailable>";
            try
            {
                // AttributeHandle 并非所有目标 Windows SDK 投影都提供；诊断版使用
                // reflection，既不改变运行时兼容性，也能在可用时打印真实 handle。
                var property = winRtObject.GetType().GetProperty("AttributeHandle");
                object value = property?.GetValue(winRtObject, null);
                return value == null ? "<unavailable>" : value.ToString();
            }
            catch (Exception ex)
            {
                return "<unavailable: " + ex.GetType().Name + ">";
            }
        }

        private static ushort GetShortUuid(Guid uuid)
        {
            return Utilities.ConvertUuidToShortId(uuid);
        }

        private int BeginDiscovery(BluetoothLEDevice device)
        {
            int generation = Interlocked.Increment(ref _discoveryGeneration);
            lock (_discoverySync)
            {
                _pendingServiceCount = 0;
                _discoveryFinalized = false;
                _targetServiceFound = false;
                CharacteristicList.Clear();
                CurrentService = null;
                CurrentWriteCharacteristic = null;
                CurrentDataCharacteristic = null;
                CurrentNotifyCharacteristic = null;
            }

            LogDiscovery("DISCOVERY START generation=" + generation +
                ", device=" + (device?.Name ?? "<unknown>"));
            return generation;
        }

        private bool IsCurrentDiscovery(int generation)
        {
            return Interlocked.CompareExchange(ref _discoveryGeneration, 0, 0) == generation;
        }

        private void FinishDiscoveryIfReady(int generation)
        {
            if (!IsCurrentDiscovery(generation)) return;

            bool shouldNotify = false;
            bool serviceFound;
            bool dataFound;
            bool writeFound;
            bool notifyFound;
            lock (_discoverySync)
            {
                if (!IsCurrentDiscovery(generation) || _discoveryFinalized || _pendingServiceCount != 0) return;
                _discoveryFinalized = true;
                serviceFound = _targetServiceFound;
                dataFound = CurrentDataCharacteristic != null;
                writeFound = CurrentWriteCharacteristic != null;
                notifyFound = CurrentNotifyCharacteristic != null;
                shouldNotify = true;
            }

            if (!shouldNotify) return;

            LogDiscovery("TARGET SUMMARY:");
            LogDiscovery("7340 service = " + (serviceFound ? "YES" : "NO"));
            LogDiscovery("7341 = " + (dataFound ? "YES" : "NO"));
            LogDiscovery("7343 = " + (writeFound ? "YES" : "NO"));
            LogDiscovery("7344 = " + (notifyFound ? "YES" : "NO"));
            // 额外输出机器可读的诊断结果，便于从 UI 日志直接复制给 HV-005 调查。
            LogDiscovery("SERVICE_7340_FOUND=" + (serviceFound ? "YES" : "NO"));
            LogDiscovery("CHAR_7341_FOUND=" + (dataFound ? "YES" : "NO"));
            LogDiscovery("CHAR_7343_FOUND=" + (writeFound ? "YES" : "NO"));
            LogDiscovery("CHAR_7344_FOUND=" + (notifyFound ? "YES" : "NO"));

            // 初始查询也在 discovery 线程发出，避免依赖 CharacteristicAdded 的 UI
            // BeginInvoke 顺序。Form1 只负责保存配置及更新显示。
            if (serviceFound && dataFound && writeFound && notifyFound)
            {
                GattCharacteristic writeCharacteristic;
                lock (_discoverySync) writeCharacteristic = CurrentWriteCharacteristic;
                LogDiscovery("TARGET DISCOVERY COMPLETE; sending initial status query");
                WriteDataToCharacterstuc(writeCharacteristic, ProtocolHelper.DeviceStatusQueryCommand);
                if (ProtocolHelper.LastClaudeState != null)
                {
                    WriteDataToCharacterstuc(writeCharacteristic, ProtocolHelper.LastClaudeState);
                }
            }

            AllCharacteristicsDiscovered?.Invoke();
        }

        private void CompleteDiscoveryWithFailure(int generation, string operation, string detail)
        {
            if (!IsCurrentDiscovery(generation)) return;
            LogDiscovery(operation + " failed: " + detail);
            lock (_discoverySync)
            {
                if (!IsCurrentDiscovery(generation)) return;
                _pendingServiceCount = 0;
            }
            if (operation == "GetGattServicesAsync")
            {
                LogDiscovery("SERVICE 0x7340 NOT FOUND (service enumeration failed)");
            }
            FinishDiscoveryIfReady(generation);
        }

        private void RecordCharacteristic(GattDeviceService service,
            GattCharacteristic characteristic, int generation)
        {
            if (!IsCurrentDiscovery(generation))
            {
                LogDiscovery("Ignoring characteristic from stale discovery generation " + generation);
                return;
            }

            ushort serviceShortId = GetShortUuid(service.Uuid);
            ushort shortId = GetShortUuid(characteristic.Uuid);
            bool isTargetService = serviceShortId == 0x7340;
            bool isTarget = false;
            bool enableNotifications = false;

            lock (_discoverySync)
            {
                if (!IsCurrentDiscovery(generation)) return;
                CharacteristicList.Add(characteristic);
                if (isTargetService)
                {
                    switch (shortId)
                    {
                        case 0x7341:
                            if (CurrentDataCharacteristic == null) CurrentDataCharacteristic = characteristic;
                            isTarget = true;
                            break;
                        case 0x7343:
                            if (CurrentWriteCharacteristic == null) CurrentWriteCharacteristic = characteristic;
                            isTarget = true;
                            break;
                        case 0x7344:
                            if (CurrentNotifyCharacteristic == null)
                            {
                                CurrentNotifyCharacteristic = characteristic;
                                enableNotifications = true;
                            }
                            isTarget = true;
                            break;
                    }
                }
            }

            LogDiscovery("CHARACTERISTIC service=" + service.Uuid.ToString() +
                " short=0x" + serviceShortId.ToString("X4") +
                " uuid=" + characteristic.Uuid.ToString() +
                " short=0x" + shortId.ToString("X4") +
                " handle=" + GetAttributeHandle(characteristic));

            if (isTarget)
            {
                LogDiscovery("TARGET 0x" + shortId.ToString("X4") + " FOUND");
                if (enableNotifications)
                {
                    EnableNotifications(characteristic);
                }
            }

            // 只有在引用已经同步保存后才把事件交给 Form1；UI 事件不再承担分类职责。
            CharacteristicAdded?.Invoke(characteristic);
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
            // 取消订阅旧设备的事件
            if (CurrentDevice != null)
                CurrentDevice.ConnectionStatusChanged -= CurrentDevice_ConnectionStatusChanged;

            // 重置特征引用
            CurrentWriteCharacteristic = null;
            CurrentDataCharacteristic = null;
            CurrentNotifyCharacteristic = null;

            CurrentDevice = Device;
            CurrentDevice.ConnectionStatusChanged += CurrentDevice_ConnectionStatusChanged;
            ConnectDeviceSuccess?.Invoke(Device);
            FindService(CurrentDevice);
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
            // 使尚未完成的 WinRT discovery callback 失效，避免断开后回调污染下一次连接。
            Interlocked.Increment(ref _discoveryGeneration);
            CurrentDeviceMAC = null;
            if (CurrentDevice != null)
                CurrentDevice.ConnectionStatusChanged -= CurrentDevice_ConnectionStatusChanged;
            CurrentService?.Dispose();
            CurrentDevice?.Dispose();
            CurrentDevice = null;
            CurrentService = null;
            lock (_discoverySync)
            {
                _pendingServiceCount = 0;
                _discoveryFinalized = true;
                _targetServiceFound = false;
                CurrentWriteCharacteristic = null;
                CurrentDataCharacteristic = null;
                CurrentNotifyCharacteristic = null;
                CharacteristicList.Clear();
            }
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
            if (CurrentWriteCharacteristic != null)
            {
                CurrentWriteCharacteristic.WriteValueAsync(CryptographicBuffer.CreateFromByteArray(data), GattWriteOption.WriteWithResponse).Completed = (asyncInfo, asyncStatus) =>
                {
                    if (asyncStatus == AsyncStatus.Completed)
                    {
                        GattCommunicationStatus a = asyncInfo.GetResults();
                        Console.WriteLine("发送数据：" + BitConverter.ToString(data) + " State : " + a);
                        WriteDataSuccess?.Invoke(CurrentWriteCharacteristic, data);
                    }
                    else
                    {
                        Console.WriteLine("ERROR");
                    }
                };
            }
            else
            {
                Console.WriteLine("当前没有设置写服务特征");
            }

        }
        /// <summary>
        /// 发送数据接口
        /// </summary>
        /// <returns></returns>
        public void WriteDataToCharacterstuc(GattCharacteristic c, byte[] data)
        {
            if (c != null)
            {
                c.WriteValueAsync(CryptographicBuffer.CreateFromByteArray(data), GattWriteOption.WriteWithResponse).Completed = (asyncInfo, asyncStatus) =>
                {
                    if (asyncStatus == AsyncStatus.Completed)
                    {
                        GattCommunicationStatus a = asyncInfo.GetResults();
                        Console.WriteLine("发送数据：" + BitConverter.ToString(data) + " State : " + a);
                        WriteDataSuccess?.Invoke(c, data);
                    }
                };
            }
            else
            {
                Console.WriteLine("当前没有设置写服务特征");
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
        public void FindService(BluetoothLEDevice dev)
        {
            if (dev == null)
            {
                Console.WriteLine("当前没有打开设备");
                return;
            }

            int generation = BeginDiscovery(dev);
            try
            {
                dev.GetGattServicesAsync(BluetoothCacheMode.Uncached).Completed = (asyncInfo, asyncStatus) =>
                {
                    LogDiscovery("GetGattServicesAsync: AsyncStatus=" + asyncStatus);
                    if (asyncStatus != AsyncStatus.Completed)
                    {
                        CompleteDiscoveryWithFailure(generation, "GetGattServicesAsync",
                            "AsyncStatus=" + asyncStatus +
                            ", GattCommunicationStatus=<not available>, ProtocolError=<not available>, service count=0");
                        return;
                    }

                    try
                    {
                        var result = asyncInfo.GetResults();
                        var services = result.Services;
                        int serviceCount = services == null ? 0 : services.Count;
                        LogDiscovery("GetGattServicesAsync: AsyncStatus=" + asyncStatus +
                            ", GattCommunicationStatus=" + result.Status +
                            ", ProtocolError=" + FormatProtocolError(result.ProtocolError) +
                            ", service count=" + serviceCount);

                        if (result.Status != GattCommunicationStatus.Success)
                        {
                            CompleteDiscoveryWithFailure(generation, "GetGattServicesAsync",
                                "GattCommunicationStatus=" + result.Status +
                                ", ProtocolError=" + FormatProtocolError(result.ProtocolError) +
                                ", service count=" + serviceCount);
                            return;
                        }

                        lock (_discoverySync)
                        {
                            _pendingServiceCount = serviceCount;
                        }

                        bool targetServiceFound = false;
                        if (services != null)
                        {
                            for (int i = 0; i < services.Count; i++)
                            {
                                GattDeviceService service = services[i];
                                ushort shortId = GetShortUuid(service.Uuid);
                                bool isTarget = shortId == 0x7340;
                                targetServiceFound |= isTarget;
                                LogDiscovery("SERVICE " + service.Uuid.ToString() +
                                    " short=0x" + shortId.ToString("X4") +
                                    " handle=" + GetAttributeHandle(service) +
                                    (isTarget ? " FOUND" : ""));
                                if (isTarget)
                                {
                                    LogDiscovery("SERVICE 0x7340 FOUND");
                                }
                            }
                        }
                        lock (_discoverySync) _targetServiceFound = targetServiceFound;
                        if (!targetServiceFound)
                        {
                            LogDiscovery("SERVICE 0x7340 NOT FOUND");
                        }

                        if (serviceCount == 0)
                        {
                            FinishDiscoveryIfReady(generation);
                        }
                        else
                        {
                            foreach (GattDeviceService service in services)
                            {
                                FindCharacteristic(service, generation);
                            }
                        }
                        CharacteristicFinish?.Invoke(serviceCount);
                    }
                    catch (Exception ex)
                    {
                        CompleteDiscoveryWithFailure(generation, "GetGattServicesAsync",
                            "GetResults exception=" + ex.GetType().Name + ": " + ex.Message);
                    }
                };
            }
            catch (Exception ex)
            {
                CompleteDiscoveryWithFailure(generation, "GetGattServicesAsync",
                    "start exception=" + ex.GetType().Name + ": " + ex.Message);
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
                this.CurrentNotifyCharacteristic.ValueChanged += Characteristic_ValueChanged;
                this.CurrentDevice.ConnectionStatusChanged += this.CurrentDevice_ConnectionStatusChanged;
                this.EnableNotifications(CurrentNotifyCharacteristic);
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
        private void FindCharacteristic(GattDeviceService gattDeviceService, int generation)
        {
            if (!IsCurrentDiscovery(generation)) return;

            // 不再把并发 service 查询写入共享 CurrentService；每个 callback 只使用
            // 自己捕获的 service，旧 discovery generation 也不会触碰新结果。
            try
            {
                gattDeviceService.GetCharacteristicsAsync(BluetoothCacheMode.Uncached).Completed =
                    (asyncInfo, asyncStatus) =>
                    {
                        try
                        {
                            LogDiscovery("GetCharacteristicsAsync service=" +
                                gattDeviceService.Uuid.ToString() +
                                " short=0x" + GetShortUuid(gattDeviceService.Uuid).ToString("X4") +
                                ": AsyncStatus=" + asyncStatus);

                            if (asyncStatus != AsyncStatus.Completed)
                            {
                                LogDiscovery("GetCharacteristicsAsync service=" +
                                    gattDeviceService.Uuid.ToString() +
                                    ": GattCommunicationStatus=<not available>, ProtocolError=<not available>, characteristic count=0");
                                return;
                            }

                            var result = asyncInfo.GetResults();
                            var characteristics = result.Characteristics;
                            int characteristicCount = characteristics == null ? 0 : characteristics.Count;
                            LogDiscovery("GetCharacteristicsAsync service=" +
                                gattDeviceService.Uuid.ToString() +
                                ": GattCommunicationStatus=" + result.Status +
                                ", ProtocolError=" + FormatProtocolError(result.ProtocolError) +
                                ", characteristic count=" + characteristicCount);

                            if (result.Status != GattCommunicationStatus.Success)
                            {
                                // 保留真实 GATT 失败状态；不要把 Unreachable、ProtocolError
                                // 或 AccessDenied 伪装为空 characteristic 集合。
                                LogDiscovery("GetCharacteristicsAsync service=" +
                                    gattDeviceService.Uuid.ToString() +
                                    " FAILED; preserving GATT status=" + result.Status +
                                    ", ProtocolError=" + FormatProtocolError(result.ProtocolError));
                                return;
                            }

                            if (characteristics != null)
                            {
                                foreach (GattCharacteristic characteristic in characteristics)
                                {
                                    RecordCharacteristic(gattDeviceService, characteristic, generation);
                                }
                            }
                        }
                        catch (Exception ex)
                        {
                            LogDiscovery("GetCharacteristicsAsync service=" +
                                gattDeviceService.Uuid.ToString() +
                                " FAILED; exception=" + ex.GetType().Name + ": " + ex.Message);
                        }
                        finally
                        {
                            if (IsCurrentDiscovery(generation) &&
                                Interlocked.Decrement(ref _pendingServiceCount) == 0)
                            {
                                FinishDiscoveryIfReady(generation);
                            }
                        }
                    };
            }
            catch (Exception ex)
            {
                LogDiscovery("GetCharacteristicsAsync service=" + gattDeviceService.Uuid.ToString() +
                    " FAILED; start exception=" + ex.GetType().Name + ": " + ex.Message);
                if (IsCurrentDiscovery(generation) &&
                    Interlocked.Decrement(ref _pendingServiceCount) == 0)
                {
                    FinishDiscoveryIfReady(generation);
                }
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
            if (sender.ConnectionStatus == BluetoothConnectionStatus.Disconnected)
            {
                Console.WriteLine("设备已断开");
                DeviceDisconnected?.Invoke(sender);
            }
            else
            {
                Console.WriteLine("设备已连接");
            }
        }

        /// <summary>
        /// 设置特征对象为接收通知对象
        /// </summary>
        /// <param name="characteristic"></param>
        /// <returns></returns>
        public void EnableNotifications(GattCharacteristic characteristic)
        {
            Console.WriteLine("收通知对象=" + CurrentDevice.Name + ":" + CurrentDevice.ConnectionStatus);
            characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(CHARACTERISTIC_NOTIFICATION_TYPE).Completed = (asyncInfo, asyncStatus) =>
            {
                if (asyncStatus == AsyncStatus.Completed)
                {
                    GattCommunicationStatus status = asyncInfo.GetResults();
                    if (status == GattCommunicationStatus.Unreachable)
                    {
                        Console.WriteLine("设备不可用");
                        if (CurrentNotifyCharacteristic != null && !asyncLock)
                        {
                            this.EnableNotifications(CurrentNotifyCharacteristic);
                        }
                        return;
                    }
                    else
                    {
                        CurrentNotifyCharacteristic.ValueChanged += Characteristic_ValueChanged;
                    }
                    asyncLock = false;
                    Console.WriteLine("设备连接状态" + status);
                }
            };
        }

        /// <summary>
        /// 接受到蓝牙数据
        /// </summary>
        private void Characteristic_ValueChanged(GattCharacteristic sender, GattValueChangedEventArgs args)
        {
            byte[] data;
            CryptographicBuffer.CopyToByteArray(args.CharacteristicValue, out data);
            ReceiveNotifyData?.Invoke(sender, data);
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
