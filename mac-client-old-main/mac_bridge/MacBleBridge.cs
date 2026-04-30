using System;
using System.Threading;
using CoreBluetooth;
using Foundation;

namespace BleTcpBridge
{
    /// <summary>
    /// macOS CoreBluetooth 实现的 BLE 桥接
    /// </summary>
    class MacBleBridge : IBleBridge
    {
        // ── 目标特征 UUID ──
        static readonly CBUUID UuidData    = CBUUID.FromString("7341");  // 数据写
        static readonly CBUUID UuidCommand = CBUUID.FromString("7343");  // 命令写
        static readonly CBUUID UuidNotify  = CBUUID.FromString("7344");  // 通知

        private CBCentralManager _central;
        private CBPeripheral _peripheral;
        private CBCharacteristic _charData;
        private CBCharacteristic _charCommand;
        private CBCharacteristic _charNotify;

        private string _targetDeviceName;
        private string _targetDeviceId;   // macOS UUID (非 MAC 地址)
        private bool _scanning;
        private bool _autoReconnect;
        private bool _pendingScan;  // 蓝牙未就绪时先标记, 就绪后自动开始
        private Timer _reconnectTimer;

        // ── IBleBridge 属性 ──
        public bool IsConnected => _peripheral != null && _peripheral.State == CBPeripheralState.Connected;
        public string DeviceName => _peripheral?.Name ?? "";
        public string DeviceId => _peripheral?.Identifier?.ToString() ?? "";
        public bool IsDataCharacteristicReady => _charData != null;
        public bool IsWriteCharacteristicReady => _charCommand != null;
        public bool IsNotifyCharacteristicReady => _charNotify != null;
        public bool IsTargetDevice => IsDataCharacteristicReady && IsWriteCharacteristicReady && IsNotifyCharacteristicReady;

        // ── 事件 ──
        public event Action<byte[]> OnNotifyDataReceived;
        public event Action<bool> OnConnectionStateChanged;
        public event Action OnCharacteristicsDiscovered;

        /// <summary>
        /// 日志事件
        /// </summary>
        public event Action<string> OnLog;

        public MacBleBridge(string targetDeviceName = null, string targetDeviceId = null, bool autoReconnect = true)
        {
            _targetDeviceName = targetDeviceName;
            _targetDeviceId = targetDeviceId;
            _autoReconnect = autoReconnect;
        }

        /// <summary>
        /// 初始化 CBCentralManager (必须在主线程或有 RunLoop 的线程调用)
        /// </summary>
        public void Initialize()
        {
            _central = new CBCentralManager();
            _central.UpdatedState += OnCentralStateUpdated;
            _central.DiscoveredPeripheral += OnDiscoveredPeripheral;
            _central.ConnectedPeripheral += OnConnectedPeripheral;
            _central.DisconnectedPeripheral += OnDisconnectedPeripheral;
            _central.FailedToConnectPeripheral += OnFailedToConnect;
            Log("CoreBluetooth CentralManager 已初始化");
        }

        // ── IBleBridge 方法 ──

        public void StartScanning()
        {
            if (_central == null)
            {
                Log("CentralManager 未初始化");
                return;
            }
            if (_central.State != CBCentralManagerState.PoweredOn)
            {
                Log("蓝牙未就绪, 等待就绪后自动扫描...");
                _pendingScan = true;
                return;
            }
            _scanning = true;
            // 扫描所有设备, 允许重复以便更新 RSSI
            _central.ScanForPeripherals((CBUUID[])null, new PeripheralScanningOptions { AllowDuplicatesKey = false });
            Log("开始扫描 BLE 设备...");
        }

        public void StopScanning()
        {
            if (_central != null && _scanning)
            {
                _central.StopScan();
                _scanning = false;
                Log("已停止扫描");
            }
        }

        public void Disconnect()
        {
            _autoReconnect = false;
            _reconnectTimer?.Dispose();
            _reconnectTimer = null;

            if (_peripheral != null && _central != null)
            {
                _central.CancelPeripheralConnection(_peripheral);
                Log("断开 BLE 连接");
            }
            ResetCharacteristics();
        }

        public void WriteData(byte[] data)
        {
            if (_charData == null || _peripheral == null) return;
            _peripheral.WriteValue(NSData.FromArray(data), _charData, CBCharacteristicWriteType.WithoutResponse);
        }

        public void WriteCommand(byte[] data)
        {
            if (_charCommand == null || _peripheral == null) return;
            _peripheral.WriteValue(NSData.FromArray(data), _charCommand, CBCharacteristicWriteType.WithoutResponse);
        }

        /// <summary>
        /// 设置目标设备 (用于自动连接)
        /// </summary>
        public void SetTargetDevice(string name, string deviceId)
        {
            _targetDeviceName = name;
            _targetDeviceId = deviceId;
        }

        public void EnableAutoReconnect(bool enable)
        {
            _autoReconnect = enable;
        }

        // ── CBCentralManager 事件处理 ──

        private void OnCentralStateUpdated(object sender, EventArgs e)
        {
            Log($"蓝牙状态: {_central.State}");
            if (_central.State == CBCentralManagerState.PoweredOn)
            {
                Log("蓝牙已就绪");
                if (_pendingScan)
                {
                    _pendingScan = false;
                    StartScanning();
                }
            }
        }

        private void OnDiscoveredPeripheral(object sender, CBDiscoveredPeripheralEventArgs e)
        {
            var peripheral = e.Peripheral;
            string name = peripheral.Name;
            if (string.IsNullOrEmpty(name)) return;

            string uuid = peripheral.Identifier?.ToString() ?? "";
            Log($"发现设备: {name} [{uuid}]");

            // 检查是否匹配目标设备
            bool match = false;
            if (!string.IsNullOrEmpty(_targetDeviceId))
            {
                // 优先按 UUID 匹配
                match = string.Equals(uuid, _targetDeviceId, StringComparison.OrdinalIgnoreCase);
            }
            else if (!string.IsNullOrEmpty(_targetDeviceName))
            {
                // 按名称匹配
                match = name == _targetDeviceName;
            }

            if (match)
            {
                Log($"匹配目标设备: {name}, 开始连接...");
                StopScanning();
                _peripheral = peripheral;
                _peripheral.Delegate = new PeripheralDelegate(this);
                _central.ConnectPeripheral(peripheral);
            }
        }

        private void OnConnectedPeripheral(object sender, CBPeripheralEventArgs e)
        {
            Log($"已连接: {e.Peripheral.Name}");
            OnConnectionStateChanged?.Invoke(true);

            // 发现所有服务
            e.Peripheral.DiscoverServices();
        }

        private void OnDisconnectedPeripheral(object sender, CBPeripheralErrorEventArgs e)
        {
            Log($"已断开: {e.Peripheral?.Name ?? "未知"}");
            ResetCharacteristics();
            OnConnectionStateChanged?.Invoke(false);

            // 自动重连
            if (_autoReconnect)
            {
                Log("将在 5 秒后尝试重新扫描...");
                _reconnectTimer?.Dispose();
                _reconnectTimer = new Timer(_ =>
                {
                    Log("重连: 开始扫描...");
                    StartScanning();
                }, null, 5000, Timeout.Infinite);
            }
        }

        private void OnFailedToConnect(object sender, CBPeripheralErrorEventArgs e)
        {
            Log($"连接失败: {e.Peripheral?.Name ?? "未知"}, 错误: {e.Error?.LocalizedDescription ?? "未知"}");
            ResetCharacteristics();

            if (_autoReconnect)
            {
                Log("将在 5 秒后重试...");
                _reconnectTimer?.Dispose();
                _reconnectTimer = new Timer(_ => StartScanning(), null, 5000, Timeout.Infinite);
            }
        }

        // ── CBPeripheralDelegate 实现 ──

        private class PeripheralDelegate : CBPeripheralDelegate
        {
            private readonly MacBleBridge _bridge;

            public PeripheralDelegate(MacBleBridge bridge)
            {
                _bridge = bridge;
            }

            public override void DiscoveredService(CBPeripheral peripheral, NSError error)
            {
                if (error != null)
                {
                    _bridge.Log($"服务发现错误: {error.LocalizedDescription}");
                    return;
                }

                var services = peripheral.Services;
                if (services == null) return;

                _bridge.Log($"发现 {services.Length} 个服务");
                foreach (var service in services)
                {
                    _bridge.Log($"  服务: {service.UUID}");
                    // 发现每个服务的特征
                    peripheral.DiscoverCharacteristics(service);
                }
            }

            public override void DiscoveredCharacteristics(CBPeripheral peripheral, CBService service, NSError error)
            {
                if (error != null)
                {
                    _bridge.Log($"特征发现错误: {error.LocalizedDescription}");
                    return;
                }

                var chars = service.Characteristics;
                if (chars == null) return;

                foreach (var c in chars)
                {
                    _bridge.Log($"  特征: {c.UUID}");

                    if (c.UUID.Equals(UuidData))
                    {
                        _bridge._charData = c;
                        _bridge.Log("  → 数据特征(0x7341)已就绪");
                    }
                    else if (c.UUID.Equals(UuidCommand))
                    {
                        _bridge._charCommand = c;
                        _bridge.Log("  → 命令特征(0x7343)已就绪");
                    }
                    else if (c.UUID.Equals(UuidNotify))
                    {
                        _bridge._charNotify = c;
                        // 订阅通知
                        peripheral.SetNotifyValue(true, c);
                        _bridge.Log("  → 通知特征(0x7344)已就绪, 已订阅通知");
                    }
                }

                // 检查是否所有目标特征都已就绪
                if (_bridge.IsTargetDevice)
                {
                    _bridge.Log("所有目标特征已就绪!");
                    _bridge.OnCharacteristicsDiscovered?.Invoke();

                    // 自动发送设备状态查询
                    _bridge.WriteCommand(ProtocolHelper.DeviceStatusQueryCommand);
                    _bridge.Log("已自动发送设备状态查询指令");

                    // 恢复上次 Claude 状态
                    if (ProtocolHelper.LastClaudeState != null)
                    {
                        _bridge.WriteCommand(ProtocolHelper.LastClaudeState);
                        _bridge.Log("已恢复 Claude 状态");
                    }
                }
            }

            public override void UpdatedCharacterteristicValue(CBPeripheral peripheral, CBCharacteristic characteristic, NSError error)
            {
                if (error != null)
                {
                    _bridge.Log($"通知数据错误: {error.LocalizedDescription}");
                    return;
                }

                var data = characteristic.Value?.ToArray();
                if (data != null && data.Length > 0)
                {
                    _bridge.OnNotifyDataReceived?.Invoke(data);
                }
            }
        }

        // ── 内部工具 ──

        private void ResetCharacteristics()
        {
            _charData = null;
            _charCommand = null;
            _charNotify = null;
        }

        private void Log(string msg) => OnLog?.Invoke(msg);
    }
}
