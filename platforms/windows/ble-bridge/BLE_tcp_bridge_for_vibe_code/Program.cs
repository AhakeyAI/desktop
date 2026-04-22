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
        private int _pendingServiceCount = 0;

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
            if (dev != null)
            {
                dev.GetGattServicesAsync(BluetoothCacheMode.Uncached).Completed = (asyncInfo, asyncStatus) =>
                {
                    if (asyncStatus == AsyncStatus.Completed)
                    {
                        var services = asyncInfo.GetResults().Services;
                        Console.WriteLine("GattServices size=" + services.Count);
                        CharacteristicList.Clear();

                        for (int i = 0; i < services.Count; i++)
                        {
                            Console.WriteLine($"#{i:00}: {services[i].Uuid.ToString()}");
                        }

                        _pendingServiceCount = services.Count;
                        if (_pendingServiceCount == 0)
                        {
                            AllCharacteristicsDiscovered?.Invoke();
                        }
                        else
                        {
                            foreach (GattDeviceService ser in services)
                            {
                                FindCharacteristic(ser);
                            }
                        }
                        CharacteristicFinish?.Invoke(services.Count);
                    }
                };
            }
            else
            {
                Console.WriteLine("当前没有打开设备");
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
        private void FindCharacteristic(GattDeviceService gattDeviceService)
        {
            this.CurrentService = gattDeviceService;
            this.CurrentService.GetCharacteristicsAsync(BluetoothCacheMode.Uncached).Completed = (asyncInfo, asyncStatus) =>
            {
                if (asyncStatus == AsyncStatus.Completed)
                {
                    var characteristics = asyncInfo.GetResults().Characteristics;
                    foreach (var c in characteristics)
                    {
                        CharacteristicList.Add(c);
                        this.CharacteristicAdded?.Invoke(c);
                    }
                }

                if (Interlocked.Decrement(ref _pendingServiceCount) == 0)
                    AllCharacteristicsDiscovered?.Invoke();
            };
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
