using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;

namespace BLE_tcp_driver
{
    class TcpServer
    {
        private TcpListener _listener;
        private readonly BleCore _bleCore;
        private readonly int _port;
        private readonly List<TcpClient> _clients = new List<TcpClient>();
        private readonly object _clientLock = new object();
        private volatile bool _running;

        private DeviceStatusInfo _deviceStatus;
        private readonly object _statusLock = new object();

        // 状态缓存文件: 驱动重启后先回放上次真实状态,
        // 避免在键盘首次推送前合成帧/缓存查询返回全0(全0会被客户端当成"自动批准")
        private static readonly string StatusCachePath = Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory, "device_status.cache");

        /// <summary>
        /// 日志事件 (从后台线程触发, UI层需BeginInvoke)
        /// </summary>
        public event Action<string> OnLog;

        /// <summary>
        /// TCP客户端数量变化事件
        /// </summary>
        public event Action<int> OnClientCountChanged;

        public int Port => _port;
        public int ClientCount { get { lock (_clientLock) return _clients.Count; } }

        public TcpServer(BleCore bleCore, int port = 9000)
        {
            _bleCore = bleCore;
            _port = port;
            _deviceStatus = LoadStatusCache();
        }

        private static DeviceStatusInfo LoadStatusCache()
        {
            var info = new DeviceStatusInfo();
            try
            {
                if (File.Exists(StatusCachePath))
                {
                    var parts = File.ReadAllText(StatusCachePath).Trim().Split(',');
                    if (parts.Length == 8)
                    {
                        info.BatteryLevel = byte.Parse(parts[0]);
                        info.SignalStrength = byte.Parse(parts[1]);
                        info.FirmwareVersionMain = byte.Parse(parts[2]);
                        info.FirmwareVersionSub = byte.Parse(parts[3]);
                        info.WorkMode = byte.Parse(parts[4]);
                        info.LightMode = byte.Parse(parts[5]);
                        info.SwitchState = byte.Parse(parts[6]);
                        info.Reserve = byte.Parse(parts[7]);
                    }
                }
            }
            catch { }
            return info;
        }

        private static void SaveStatusCache(DeviceStatusInfo info)
        {
            try
            {
                File.WriteAllText(StatusCachePath, string.Join(",",
                    info.BatteryLevel, info.SignalStrength,
                    info.FirmwareVersionMain, info.FirmwareVersionSub,
                    info.WorkMode, info.LightMode,
                    info.SwitchState, info.Reserve));
            }
            catch { }
        }

        public void Start()
        {
            if (_running) return;
            _listener = new TcpListener(IPAddress.Any, _port);
            _listener.Start();
            _running = true;

            // 订阅BLE通知, 转发给所有TCP客户端
            _bleCore.ReceiveNotifyData += OnBleNotify;

            Log($"TCP服务器已启动, 监听端口: {_port}");
            Task.Run(() => AcceptLoop());
        }

        public void Stop()
        {
            if (!_running) return;
            _running = false;
            _bleCore.ReceiveNotifyData -= OnBleNotify;

            try { _listener?.Stop(); } catch { }

            lock (_clientLock)
            {
                foreach (var c in _clients)
                    try { c.Close(); } catch { }
                _clients.Clear();
            }
            OnClientCountChanged?.Invoke(0);
            Log("TCP服务器已停止");
        }

        /// <summary>
        /// 接受TCP客户端连接循环
        /// </summary>
        private async Task AcceptLoop()
        {
            while (_running)
            {
                try
                {
                    var client = await _listener.AcceptTcpClientAsync();
                    lock (_clientLock) _clients.Add(client);

                    string ep = GetEndpointString(client);
                    Log($"TCP客户端已连接: {ep}");
                    OnClientCountChanged?.Invoke(ClientCount);

                    var _ = Task.Run(() => ClientLoop(client));
                }
                catch (ObjectDisposedException) { break; }
                catch (SocketException) { if (!_running) break; }
                catch (Exception ex)
                {
                    if (_running) Log($"接受连接异常: {ex.Message}");
                }
            }
        }

        /// <summary>
        /// 单个TCP客户端读取循环
        /// </summary>
        private async Task ClientLoop(TcpClient client)
        {
            try
            {
                var stream = client.GetStream();
                byte[] header = new byte[3];

                while (_running && client.Connected)
                {
                    // 读包头: [Type:1][Length:2]
                    int n = await ReadExact(stream, header, 3);
                    if (n < 3) break;

                    PacketType type = (PacketType)header[0];
                    int dataLen = header[1] | (header[2] << 8);

                    // 读包体
                    byte[] data = null;
                    if (dataLen > 0)
                    {
                        if (dataLen > 65535) break; // 防止异常大包
                        data = new byte[dataLen];
                        n = await ReadExact(stream, data, dataLen);
                        if (n < dataLen) break;
                    }

                    HandlePacket(client, type, data);
                }
            }
            catch (IOException) { }
            catch (SocketException) { }
            catch (ObjectDisposedException) { }
            catch (Exception ex) { Log($"客户端处理异常: {ex.Message}"); }
            finally
            {
                RemoveClient(client);
            }
        }

        /// <summary>
        /// 处理收到的TCP包, 路由到BLE或返回查询结果
        /// </summary>
        private void HandlePacket(TcpClient client, PacketType type, byte[] data)
        {
            switch (type)
            {
                case PacketType.WriteData:
                    if (_bleCore.CurrentDataCharacteristic != null)
                    {
                        for (int i = 0; i < data.Count(); i += 200)
                        {
                            _bleCore.WriteDataToCharacterstuc(_bleCore.CurrentDataCharacteristic, data.Skip(i).Take(Math.Min(data.Count() - i, 200)).ToArray());
                        }
                        //_bleCore.WriteDataToCharacterstuc(_bleCore.CurrentDataCharacteristic, data ?? new byte[0]);
                        Log($"→BLE数据(0x7341) [{data?.Length ?? 0}字节]");
                    }
                    else
                        Log("BLE数据特征(0x7341)未就绪");
                    break;

                case PacketType.WriteCommand:
                    // 记录状态信息
                    if (ProtocolHelper.IsClaudeStatusUpload(data))
                    {
                        ProtocolHelper.LastClaudeState = data;
                    }
                    if (_bleCore.CurrentWriteCharacteristic != null)
                    {
                        for (int i = 0; i < data.Count(); i += 20)
                        {
                            _bleCore.WriteDataToCharacterstuc(_bleCore.CurrentWriteCharacteristic, data.Skip(i).Take(Math.Min(data.Count() - i, 20)).ToArray());
                        }
                        //_bleCore.WriteDataToCharacterstuc(_bleCore.CurrentWriteCharacteristic, data ?? new byte[0]);
                        Log($"→BLE命令(0x7343) [{data?.Length ?? 0}字节]");
                    }
                    else
                        Log("BLE命令特征(0x7343)未就绪");

                    // 状态查询(AA BB 00 CC DD)在BLE下无回包: 固件只在状态变化时主动推送。
                    // 用缓存合成一帧状态广播, 供 1.5.3+ 客户端的实时状态轮询链路使用。
                    if (data != null && data.Length == 5 &&
                        data[0] == 0xAA && data[1] == 0xBB && data[2] == 0x00 && data[3] == 0xCC && data[4] == 0xDD)
                    {
                        DeviceStatusInfo snap;
                        lock (_statusLock) snap = _deviceStatus;
                        byte[] frame =
                        {
                            0xAA, 0xBB, 0x00,
                            (byte)snap.BatteryLevel, (byte)snap.SignalStrength,
                            (byte)snap.FirmwareVersionMain, (byte)snap.FirmwareVersionSub,
                            (byte)snap.WorkMode, (byte)snap.LightMode,
                            (byte)snap.SwitchState, (byte)snap.Reserve,
                            0xCC, 0xDD
                        };
                        BroadcastToAll(ProtocolHelper.BuildPacket(PacketType.BleNotify, frame));
                    }
                    break;

                case PacketType.QueryBleStatus:
                    var status = BuildBleStatus();
                    SendToClient(client, ProtocolHelper.BuildBleStatusPacket(status));
                    Log("响应BLE状态查询");
                    break;

                case PacketType.QueryDeviceInfo:
                    DeviceStatusInfo info;
                    lock (_statusLock) info = _deviceStatus;
                    SendToClient(client, ProtocolHelper.BuildDeviceInfoPacket(info));
                    Log("响应设备信息查询");
                    break;

                default:
                    Log($"未知包类型: 0x{(byte)type:X2}");
                    break;
            }
        }

        /// <summary>
        /// 从BleCore获取当前BLE连接状态
        /// </summary>
        private BleStatusInfo BuildBleStatus()
        {
            var dev = _bleCore.CurrentDevice;
            bool connected = dev != null &&
                dev.ConnectionStatus == BluetoothConnectionStatus.Connected;

            string name = "";
            string mac = "";
            if (dev != null)
            {
                name = dev.Name ?? "";
                byte[] macBytes = BitConverter.GetBytes(dev.BluetoothAddress);
                Array.Reverse(macBytes);
                mac = BitConverter.ToString(macBytes, 2, 6).Replace('-', ':');
            }

            bool isTarget = _bleCore.CurrentDataCharacteristic != null
                         && _bleCore.CurrentWriteCharacteristic != null
                         && _bleCore.CurrentNotifyCharacteristic != null;

            return new BleStatusInfo
            {
                Connected = connected,
                DeviceName = name,
                MacAddress = mac,
                IsTargetDevice = isTarget
            };
        }

        /// <summary>
        /// BLE通知回调 → 所有通知(含设备状态通知)广播给所有TCP客户端
        /// </summary>
        private void OnBleNotify(GattCharacteristic sender, byte[] data)
        {
            // 设备状态通知: 解析并更新内存, 并随其它通知一起广播
            // (1.5.3+ 客户端不信任缓存的 DEVICE_INFO 应答, 只接受实时广播)
            if (ProtocolHelper.IsDeviceStatusNotification(data))
            {
                var newStatus = ProtocolHelper.ParseDeviceStatusFromNotification(data);
                lock (_statusLock) _deviceStatus = newStatus;
                SaveStatusCache(newStatus);
                Log($"设备状态更新: 电量={newStatus.BatteryLevel} 信号={newStatus.SignalStrength} " +
                    $"固件={newStatus.FirmwareVersionMain}.{newStatus.FirmwareVersionSub} " +
                    $"工作模式={newStatus.WorkMode} 灯光={newStatus.LightMode} 开关={newStatus.SwitchState}");
            }

            byte[] packet = ProtocolHelper.BuildPacket(PacketType.BleNotify, data);
            BroadcastToAll(packet);
        }

        /// <summary>
        /// 向所有已连接的TCP客户端广播数据
        /// </summary>
        public void BroadcastToAll(byte[] packet)
        {
            List<TcpClient> snapshot;
            lock (_clientLock) snapshot = new List<TcpClient>(_clients);
            foreach (var c in snapshot)
                SendToClient(c, packet);
        }

        private void SendToClient(TcpClient client, byte[] packet)
        {
            try
            {
                if (client.Connected)
                {
                    var stream = client.GetStream();
                    stream.Write(packet, 0, packet.Length);
                }
            }
            catch { RemoveClient(client); }
        }

        private void RemoveClient(TcpClient client)
        {
            bool removed;
            lock (_clientLock) removed = _clients.Remove(client);
            if (removed)
            {
                string ep = GetEndpointString(client);
                Log($"TCP客户端已断开: {ep}");
                try { client.Close(); } catch { }
                OnClientCountChanged?.Invoke(ClientCount);
            }
        }

        /// <summary>
        /// 从NetworkStream精确读取count字节
        /// </summary>
        private static async Task<int> ReadExact(NetworkStream stream, byte[] buf, int count)
        {
            int total = 0;
            while (total < count)
            {
                int n = await stream.ReadAsync(buf, total, count - total);
                if (n == 0) return total; // 连接关闭
                total += n;
            }
            return total;
        }

        private static string GetEndpointString(TcpClient client)
        {
            try { return client.Client.RemoteEndPoint?.ToString() ?? "unknown"; }
            catch { return "unknown"; }
        }

        private void Log(string msg) => OnLog?.Invoke(msg);

        /// <summary>
        /// 获取本机局域网IP地址
        /// </summary>
        public static string GetLocalIPAddress()
        {
            try
            {
                var host = Dns.GetHostEntry(Dns.GetHostName());
                var ip = host.AddressList.FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork);
                return ip?.ToString() ?? "127.0.0.1";
            }
            catch { return "127.0.0.1"; }
        }
    }
}
