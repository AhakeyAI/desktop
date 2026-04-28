using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace BleTcpBridge
{
    /// <summary>
    /// 通过 Swift 子进程 (ble_helper.swift) 实现 BLE 操作的桥接类。
    /// 使用 stdin/stdout JSON 行协议通信。
    /// </summary>
    class SwiftBleBridge : IBleBridge
    {
        private Process _process;
        private StreamWriter _stdin;
        private Thread _readerThread;
        private volatile bool _running;
        private volatile bool _stopping;

        private volatile bool _connected;
        private string _deviceName = "";
        private string _deviceId = "";
        private volatile bool _charDataReady;
        private volatile bool _charCommandReady;
        private volatile bool _charNotifyReady;

        private readonly string _helperPath;
        private string _targetDeviceName;
        private string _targetDeviceId;
        private bool _autoReconnect;
        private Timer _reconnectTimer;
        private Timer _helperRestartTimer;

        // ── IBleBridge 属性 ──
        public bool IsConnected => _connected;
        public string DeviceName => _deviceName;
        public string DeviceId => _deviceId;
        public bool IsDataCharacteristicReady => _charDataReady;
        public bool IsWriteCharacteristicReady => _charCommandReady;
        public bool IsNotifyCharacteristicReady => _charNotifyReady;
        public bool IsTargetDevice => _charDataReady && _charCommandReady && _charNotifyReady;

        // ── 事件 ──
        public event Action<byte[]> OnNotifyDataReceived;
        public event Action<bool> OnConnectionStateChanged;
        public event Action OnCharacteristicsDiscovered;
        public event Action<string> OnLog;

        public SwiftBleBridge(string helperPath, string targetDeviceName = null,
            string targetDeviceId = null, bool autoReconnect = true)
        {
            _helperPath = helperPath;
            _targetDeviceName = targetDeviceName;
            _targetDeviceId = targetDeviceId;
            _autoReconnect = autoReconnect;
        }

        /// <summary>
        /// 启动 Swift 子进程
        /// </summary>
        public void Start()
        {
            if (_process != null)
            {
                try
                {
                    if (!_process.HasExited)
                        return;
                }
                catch { }
            }

            _running = true;
            _stopping = false;

            bool useSwiftInterpreter = string.Equals(
                Path.GetExtension(_helperPath),
                ".swift",
                StringComparison.OrdinalIgnoreCase);

            var psi = new ProcessStartInfo
            {
                FileName = useSwiftInterpreter ? "swift" : _helperPath,
                Arguments = useSwiftInterpreter ? QuoteArg(_helperPath) : "",
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };

            _process = new Process { StartInfo = psi };
            _process.Start();
            _stdin = _process.StandardInput;
            _stdin.AutoFlush = true;
            _helperRestartTimer?.Dispose();
            _helperRestartTimer = null;

            Log((useSwiftInterpreter ? "Swift BLE Helper" : "BLE Helper") + " 已启动 (PID=" + _process.Id + ")");

            // 读取 stdout 事件
            _readerThread = new Thread(ReadLoop) { IsBackground = true };
            _readerThread.Start();

            // 读取 stderr 日志
            var errThread = new Thread(() => ReadStdErr()) { IsBackground = true };
            errThread.Start();
        }

        public void StartScanning()
        {
            var cmd = "{\"cmd\":\"scan\"";
            if (!string.IsNullOrEmpty(_targetDeviceId))
                cmd += ",\"address\":\"" + JsonEsc(_targetDeviceId) + "\"";
            if (!string.IsNullOrEmpty(_targetDeviceName))
                cmd += ",\"name\":\"" + JsonEsc(_targetDeviceName) + "\"";
            cmd += "}";
            SendCommand(cmd);
        }

        public void StopScanning()
        {
            // Swift端scan可以通过disconnect停止, 或发新命令覆盖
        }

        public void Disconnect()
        {
            _autoReconnect = false;
            _reconnectTimer?.Dispose();
            _reconnectTimer = null;
            SendCommand("{\"cmd\":\"disconnect\"}");
        }

        public void WriteData(byte[] data)
        {
            if (data == null || data.Length == 0) return;
            string b64 = Convert.ToBase64String(data);
            SendCommand("{\"cmd\":\"write_data\",\"data\":\"" + b64 + "\"}");
        }

        public void WriteCommand(byte[] data)
        {
            if (data == null || data.Length == 0) return;
            string b64 = Convert.ToBase64String(data);
            SendCommand("{\"cmd\":\"write_command\",\"data\":\"" + b64 + "\"}");
        }

        public void SetTargetDevice(string name, string deviceId)
        {
            _targetDeviceName = name;
            _targetDeviceId = deviceId;
        }

        public void EnableAutoReconnect(bool enable) { _autoReconnect = enable; }

        /// <summary>
        /// 停止子进程
        /// </summary>
        public void Stop()
        {
            _stopping = true;
            _running = false;
            _reconnectTimer?.Dispose();
            _helperRestartTimer?.Dispose();
            try { SendCommand("{\"cmd\":\"stop\"}"); } catch { }
            try { _process?.Kill(); } catch { }
            _process = null;
        }

        // ── 内部方法 ──

        private void SendCommand(string json)
        {
            try { _stdin?.WriteLine(json); }
            catch (Exception ex) { Log("发送命令失败: " + ex.Message); }
        }

        private void ReadLoop()
        {
            try
            {
                var reader = _process.StandardOutput;
                while (_running && !reader.EndOfStream)
                {
                    string line = reader.ReadLine();
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    HandleEvent(line);
                }
            }
            catch (Exception ex)
            {
                if (_running) Log("读取事件异常: " + ex.Message);
            }

            if (_running)
            {
                int exitCode = -1;
                try
                {
                    if (_process != null && _process.HasExited)
                        exitCode = _process.ExitCode;
                }
                catch { }

                Log("Swift 子进程已退出 (exit=" + exitCode + ")");
                _connected = false;
                ResetChars();
                OnConnectionStateChanged?.Invoke(false);

                if (_autoReconnect && !_stopping)
                {
                    Log("BLE Helper 意外退出，2 秒后自动重启...");
                    _helperRestartTimer?.Dispose();
                    _helperRestartTimer = new Timer(_ =>
                    {
                        try
                        {
                            Start();
                            StartScanning();
                        }
                        catch (Exception ex)
                        {
                            Log("重启 BLE Helper 失败: " + ex.Message);
                        }
                    }, null, 2000, Timeout.Infinite);
                }
            }
        }

        private void ReadStdErr()
        {
            try
            {
                var reader = _process.StandardError;
                while (_running && !reader.EndOfStream)
                {
                    string line = reader.ReadLine();
                    if (!string.IsNullOrWhiteSpace(line))
                        Log("[stderr] " + line);
                }
            }
            catch { }
        }

        private void HandleEvent(string json)
        {
            string eventType = JsonExtract(json, "event");
            if (string.IsNullOrEmpty(eventType)) return;

            switch (eventType)
            {
                case "ready":
                    Log("蓝牙已就绪");
                    break;

                case "discovered":
                    string dName = JsonExtract(json, "name");
                    string dAddr = JsonExtract(json, "address");
                    Log("发现设备: " + dName + " [" + dAddr + "]");
                    break;

                case "connected":
                    _deviceName = JsonExtract(json, "name");
                    _deviceId = JsonExtract(json, "address");
                    _connected = true;
                    Log("已连接: " + _deviceName);
                    OnConnectionStateChanged?.Invoke(true);
                    break;

                case "characteristics_ready":
                    _charDataReady = true;
                    _charCommandReady = true;
                    _charNotifyReady = true;
                    Log("所有目标特征已就绪!");
                    OnCharacteristicsDiscovered?.Invoke();

                    // 自动发送设备状态查询
                    WriteCommand(ProtocolHelper.DeviceStatusQueryCommand);
                    Log("已自动发送设备状态查询指令");

                    // 恢复 Claude 状态
                    if (ProtocolHelper.LastClaudeState != null)
                    {
                        WriteCommand(ProtocolHelper.LastClaudeState);
                        Log("已恢复 Claude 状态");
                    }
                    break;

                case "notify":
                    string b64 = JsonExtract(json, "data");
                    if (!string.IsNullOrEmpty(b64))
                    {
                        try
                        {
                            byte[] data = Convert.FromBase64String(b64);
                            OnNotifyDataReceived?.Invoke(data);
                        }
                        catch { }
                    }
                    break;

                case "disconnected":
                    _connected = false;
                    ResetChars();
                    OnConnectionStateChanged?.Invoke(false);

                    if (_autoReconnect)
                    {
                        Log("将在 5 秒后重新扫描...");
                        _reconnectTimer?.Dispose();
                        _reconnectTimer = new Timer(_ =>
                        {
                            Log("重连: 开始扫描...");
                            StartScanning();
                        }, null, 5000, Timeout.Infinite);
                    }
                    break;

                case "log":
                    Log(JsonExtract(json, "message"));
                    break;

                case "error":
                    Log("错误: " + JsonExtract(json, "message"));
                    break;
            }
        }

        private void ResetChars()
        {
            _charDataReady = false;
            _charCommandReady = false;
            _charNotifyReady = false;
        }

        private void Log(string msg) => OnLog?.Invoke(msg);

        /// <summary>
        /// 简单JSON字符串提取 (不依赖外部库)
        /// </summary>
        private static string JsonExtract(string json, string key)
        {
            var match = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
            return match.Success ? match.Groups[1].Value : "";
        }

        private static string JsonEsc(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        private static string QuoteArg(string path)
        {
            if (string.IsNullOrEmpty(path)) return "\"\"";
            return "\"" + path.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
        }
    }
}
