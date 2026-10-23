using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Diagnostics;
using System.Threading;
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
        private const int MaxPendingBleTransactions = 24;
        private readonly object _writeQueueLock = new object();
        private readonly BoundedAsyncFifo<BleWriteRequest> _writeQueue;
        private long _nextWriteSequence;

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
            _writeQueue = new BoundedAsyncFifo<BleWriteRequest>(
                MaxPendingBleTransactions,
                ProcessWriteRequest,
                (request, ex) => Log($"GATT事务失败 seq={request.Sequence} gen={request.Generation} error={ex.GetType().Name} hresult=0x{ex.HResult:X8} message={ex.Message}"));
        }

        public void Start()
        {
            if (_running) return;
            _listener = new TcpListener(IPAddress.Any, _port);
            _listener.Start();
            _running = true;

            // 订阅BLE通知, 转发给所有TCP客户端
            _bleCore.ReceiveNotifyData += OnBleNotify;
            _bleCore.ConnectionGenerationChanged += OnConnectionGenerationChanged;

            Log($"TCP服务器已启动, 监听端口: {_port}");
            Task.Run(() => AcceptLoop());
        }

        public void Stop()
        {
            if (!_running) return;
            _running = false;
            _bleCore.ReceiveNotifyData -= OnBleNotify;
            _bleCore.ConnectionGenerationChanged -= OnConnectionGenerationChanged;
            CancelQueuedWrites("TCP服务器停止");

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
                    int n = await stream.ReadAsync(header, 0, 1);
                    if (n < 1) break;
                    long frameReadStartedAt = Stopwatch.GetTimestamp();
                    n = await ReadExact(stream, header, 1, 2);
                    if (n < 2) break;

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

                    long frameReceivedAt = Stopwatch.GetTimestamp();
                    await HandlePacket(client, type, data, frameReceivedAt,
                        ElapsedMilliseconds(frameReadStartedAt));
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
        private async Task HandlePacket(TcpClient client, PacketType type, byte[] data,
            long frameReceivedAt, double frameReadMs)
        {
            switch (type)
            {
                case PacketType.WriteData:
                    await QueueBleWrite(client, type, _bleCore.CurrentDataCharacteristic, data, frameReceivedAt, frameReadMs);
                    break;

                case PacketType.WriteCommand:
                    // 记录状态信息
                    if (ProtocolHelper.IsClaudeStatusUpload(data))
                    {
                        ProtocolHelper.LastClaudeState = data;
                    }
                    await QueueBleWrite(client, type, _bleCore.CurrentWriteCharacteristic, data, frameReceivedAt, frameReadMs);
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
        /// BLE通知回调 → 过滤设备状态通知, 其余广播给所有TCP客户端
        /// </summary>
        private void OnBleNotify(GattCharacteristic sender, byte[] data, long generation, long discoveryId)
        {
            if (!_bleCore.IsCurrentDiscovery(generation, discoveryId)) return;
            // 设备状态通知: 解析并更新内存, 不广播给客户端
            if (ProtocolHelper.IsDeviceStatusNotification(data))
            {
                var newStatus = ProtocolHelper.ParseDeviceStatusFromNotification(data);
                lock (_statusLock) _deviceStatus = newStatus;
                Log($"设备状态更新: 电量={newStatus.BatteryLevel} 信号={newStatus.SignalStrength} " +
                    $"固件={newStatus.FirmwareVersionMain}.{newStatus.FirmwareVersionSub} " +
                    $"工作模式={newStatus.WorkMode} 灯光={newStatus.LightMode} 开关={newStatus.SwitchState}");
                return;
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
            long startedAt = Stopwatch.GetTimestamp();
            try
            {
                lock (client)
                {
                    if (client.Connected)
                    {
                        var stream = client.GetStream();
                        stream.Write(packet, 0, packet.Length);
                    }
                }
                Log($"TCP回传 type=0x{packet[0]:X2} bytes={packet.Length} write_ms={ElapsedMilliseconds(startedAt):F3}");
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
                int canceled = _writeQueue.CancelWhere(
                    request => ReferenceEquals(request.Client, client), request => request.Cancellation.Cancel());
                if (canceled > 0) Log($"GATT队列取消离开客户端事务 count={canceled} client={ep}");
                OnClientCountChanged?.Invoke(ClientCount);
            }
        }

        /// <summary>
        /// 从NetworkStream精确读取count字节
        /// </summary>
        private static async Task<int> ReadExact(NetworkStream stream, byte[] buf, int count)
        {
            return await ReadExact(stream, buf, 0, count);
        }

        private static async Task<int> ReadExact(NetworkStream stream, byte[] buf, int offset, int count)
        {
            int total = 0;
            while (total < count)
            {
                int n = await stream.ReadAsync(buf, offset + total, count - total);
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

        private async Task QueueBleWrite(TcpClient client, PacketType type, GattCharacteristic characteristic,
            byte[] data, long frameReceivedAt, double frameReadMs)
        {
            if (client != null && !IsClientActive(client))
            {
                Log($"GATT拒绝离线客户端事务 type=0x{(byte)type:X2}");
                return;
            }
            if (characteristic == null)
            {
                Log($"GATT拒绝入队 type=0x{(byte)type:X2}: 写特征未就绪");
                return;
            }

            long generation = _bleCore.ConnectionGeneration;
            var request = new BleWriteRequest(
                Interlocked.Increment(ref _nextWriteSequence), client, type, characteristic,
                data == null ? new byte[0] : (byte[])data.Clone(), generation, frameReceivedAt, frameReadMs);

            Task<bool> completion;
            lock (_writeQueueLock)
            {
                GattCharacteristic currentCharacteristic = type == PacketType.WriteData
                    ? _bleCore.CurrentDataCharacteristic
                    : _bleCore.CurrentWriteCharacteristic;
                if (!_running || !_bleCore.IsCurrentConnection(generation)
                    || !ReferenceEquals(characteristic, currentCharacteristic)
                    || (client != null && !client.Connected))
                {
                    request.Cancellation.Dispose();
                    Log($"GATT拒绝入队 seq={request.Sequence} gen={generation}: 设备未连接或代次已变化");
                    return;
                }
                if (!_writeQueue.TryEnqueue(request, out completion))
                {
                    request.Cancellation.Dispose();
                    Log($"GATT队列已满，丢弃事务 seq={request.Sequence} type=0x{(byte)type:X2} bytes={request.Data.Length}");
                    return;
                }
            }

            try { await completion; }
            finally { request.Cancellation.Dispose(); }
        }

        private async Task<bool> ProcessWriteRequest(BleWriteRequest request)
        {
            double queueWaitMs = ElapsedMilliseconds(request.FrameReceivedAt);
            if (!_running || !_bleCore.IsCurrentConnection(request.Generation) || !IsClientActive(request.Client))
            {
                Log($"GATT取消旧事务 seq={request.Sequence} gen={request.Generation} queue_wait_ms={queueWaitMs:F3}");
                return false;
            }

            int reportedPduSize;
            string mtuSource;
            int fragmentSize = _bleCore.GetMaxGattWritePayload(request.Generation, out reportedPduSize, out mtuSource);
            int fragmentCount = request.Data.Length == 0 ? 0 : (request.Data.Length + fragmentSize - 1) / fragmentSize;
            long transactionStartedAt = Stopwatch.GetTimestamp();
            Log($"GATT事务开始 seq={request.Sequence} type=0x{(byte)request.Type:X2} bytes={request.Data.Length} gen={request.Generation} tcp_frame_read_ms={request.FrameReadMs:F3} queue_wait_ms={queueWaitMs:F3} pdu={reportedPduSize} chunk={fragmentSize} mtu_source={mtuSource} fragments={fragmentCount}");

            bool sent = await BridgeMtuPolicy.SendFragmentsAsync(
                request.Data,
                fragmentSize,
                async (offset, chunk, fragment, count) =>
            {
                long fragmentStartedAt = Stopwatch.GetTimestamp();
                Task<BleCore.GattWriteResult> writeTask = _bleCore.WriteDataToCharacteristicAsync(
                    request.Characteristic, chunk, request.Generation, request.Cancellation.Token);
                while (!writeTask.IsCompleted)
                {
                    await Task.WhenAny(writeTask, Task.Delay(50));
                    if (!_running || !IsClientActive(request.Client))
                        request.Cancellation.Cancel();
                }
                BleCore.GattWriteResult result = await writeTask;
                double fragmentMs = ElapsedMilliseconds(fragmentStartedAt);

                Log($"GATT分片 seq={request.Sequence} fragment={fragment}/{count} offset={offset} bytes={chunk.Length} gen={request.Generation} async={result.AsyncStatus} communication={(result.CommunicationStatus.HasValue ? result.CommunicationStatus.Value.ToString() : "n/a")} elapsed_ms={fragmentMs:F3}");
                if (!result.Success)
                {
                    Exception error = result.Error;
                    Log($"GATT事务中止 seq={request.Sequence} sent_fragments={fragment - 1} total_fragments={count} async={result.AsyncStatus} communication={(result.CommunicationStatus.HasValue ? result.CommunicationStatus.Value.ToString() : "n/a")} error={(error == null ? "none" : error.GetType().Name + ":" + error.Message)} hresult={(error == null ? "n/a" : "0x" + error.HResult.ToString("X8"))}; 不自动重发");
                    return false;
                }
                if (!_bleCore.IsCurrentConnection(request.Generation) || request.Cancellation.IsCancellationRequested
                    || !IsClientActive(request.Client))
                {
                    Log($"GATT事务取消 seq={request.Sequence} gen={request.Generation}: 代次变化或客户端/服务器已关闭");
                    return false;
                }
                return true;
            },
            () => _running && _bleCore.IsCurrentConnection(request.Generation)
                && !request.Cancellation.IsCancellationRequested && IsClientActive(request.Client));

            if (!sent)
            {
                Log($"GATT事务取消/中止 seq={request.Sequence} gen={request.Generation}: 未继续后续分片");
                return false;
            }

            Log($"GATT事务完成 seq={request.Sequence} type=0x{(byte)request.Type:X2} bytes={request.Data.Length} gen={request.Generation} gatt_ms={ElapsedMilliseconds(transactionStartedAt):F3}; 未生成固件ACK");
            return _bleCore.IsCurrentConnection(request.Generation);
        }

        public Task QueueControlWrite(GattCharacteristic characteristic, byte[] data)
        {
            return QueueBleWrite(null, PacketType.WriteCommand, characteristic, data, Stopwatch.GetTimestamp(), 0);
        }

        private void OnConnectionGenerationChanged(long generation)
        {
            lock (_writeQueueLock)
            {
                int canceled = _writeQueue.CancelWhere(
                    request => request.Generation != generation, request => request.Cancellation.Cancel());
                if (canceled > 0) Log($"GATT队列清除旧事务 count={canceled} new_gen={generation}");
            }
        }

        private void CancelQueuedWrites(string reason)
        {
            lock (_writeQueueLock)
            {
                int canceled = _writeQueue.CancelWhere(_ => true, request => request.Cancellation.Cancel());
                if (canceled > 0) Log($"GATT队列取消 count={canceled} reason={reason}");
            }
        }

        private bool IsClientActive(TcpClient client)
        {
            if (client == null) return true;
            try
            {
                lock (_clientLock)
                {
                    return _clients.Contains(client) && client.Connected
                        && !(client.Client.Poll(0, SelectMode.SelectRead) && client.Available == 0);
                }
            }
            catch { return false; }
        }

        private static double ElapsedMilliseconds(long startedAt)
        {
            return (Stopwatch.GetTimestamp() - startedAt) * 1000.0 / Stopwatch.Frequency;
        }

        private sealed class BleWriteRequest
        {
            public long Sequence { get; }
            public TcpClient Client { get; }
            public PacketType Type { get; }
            public GattCharacteristic Characteristic { get; }
            public byte[] Data { get; }
            public long Generation { get; }
            public long FrameReceivedAt { get; }
            public double FrameReadMs { get; }
            public CancellationTokenSource Cancellation { get; } = new CancellationTokenSource();

            public BleWriteRequest(long sequence, TcpClient client, PacketType type, GattCharacteristic characteristic,
                byte[] data, long generation, long frameReceivedAt, double frameReadMs)
            {
                Sequence = sequence;
                Client = client;
                Type = type;
                Characteristic = characteristic;
                Data = data;
                Generation = generation;
                FrameReceivedAt = frameReceivedAt;
                FrameReadMs = frameReadMs;
            }
        }

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

    internal sealed class BoundedAsyncFifo<T>
    {
        private readonly object _gate = new object();
        private readonly Queue<Entry> _pending = new Queue<Entry>();
        private readonly int _capacity;
        private readonly Func<T, Task<bool>> _processor;
        private readonly Action<T, Exception> _onError;
        private int _outstanding;
        private bool _workerRunning;

        public BoundedAsyncFifo(int capacity, Func<T, Task<bool>> processor, Action<T, Exception> onError)
        {
            if (capacity <= 0) throw new ArgumentOutOfRangeException("capacity");
            _capacity = capacity;
            if (processor == null) throw new ArgumentNullException("processor");
            _processor = processor;
            _onError = onError;
        }

        public bool TryEnqueue(T item, out Task<bool> completion)
        {
            lock (_gate)
            {
                if (_outstanding >= _capacity)
                {
                    completion = null;
                    return false;
                }

                var entry = new Entry(item);
                _pending.Enqueue(entry);
                _outstanding++;
                completion = entry.Completion.Task;
                if (!_workerRunning)
                {
                    _workerRunning = true;
                    Task.Run(() => ProcessQueue());
                }
                return true;
            }
        }

        public int CancelWhere(Predicate<T> predicate, Action<T> onCancel = null)
        {
            if (predicate == null) throw new ArgumentNullException("predicate");
            lock (_gate)
            {
                var retained = new Queue<Entry>();
                int canceled = 0;
                while (_pending.Count > 0)
                {
                    Entry entry = _pending.Dequeue();
                    if (predicate(entry.Item))
                    {
                        _outstanding--;
                        try { if (onCancel != null) onCancel(entry.Item); }
                        catch { }
                        entry.Completion.TrySetResult(false);
                        canceled++;
                    }
                    else
                    {
                        retained.Enqueue(entry);
                    }
                }
                while (retained.Count > 0) _pending.Enqueue(retained.Dequeue());
                return canceled;
            }
        }

        private async Task ProcessQueue()
        {
            while (true)
            {
                Entry entry;
                lock (_gate)
                {
                    if (_pending.Count == 0)
                    {
                        _workerRunning = false;
                        return;
                    }
                    entry = _pending.Dequeue();
                }

                bool succeeded = false;
                try
                {
                    succeeded = await _processor(entry.Item);
                }
                catch (Exception ex)
                {
                    try { if (_onError != null) _onError(entry.Item, ex); }
                    catch { }
                }
                finally
                {
                    lock (_gate) _outstanding--;
                    entry.Completion.TrySetResult(succeeded);
                }
            }
        }

        private sealed class Entry
        {
            public T Item { get; private set; }
            public TaskCompletionSource<bool> Completion { get; private set; }

            public Entry(T item)
            {
                Item = item;
                Completion = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            }
        }
    }

    internal static class BridgeMtuPolicy
    {
        public const int FallbackPayload = 20;

        public static int SelectPayload(int pduSize, bool negotiated, int characteristicLimit)
        {
            if (characteristicLimit <= 0) throw new ArgumentOutOfRangeException("characteristicLimit");
            if (!negotiated || pduSize <= 23) return FallbackPayload;
            return Math.Max(FallbackPayload, Math.Min(characteristicLimit, pduSize - 3));
        }

        public static async Task<bool> SendFragmentsAsync(byte[] payload, int fragmentSize,
            Func<int, byte[], int, int, Task<bool>> sendFragment, Func<bool> canContinue)
        {
            if (payload == null) throw new ArgumentNullException("payload");
            if (fragmentSize <= 0) throw new ArgumentOutOfRangeException("fragmentSize");
            if (sendFragment == null) throw new ArgumentNullException("sendFragment");
            if (canContinue == null) throw new ArgumentNullException("canContinue");

            int count = payload.Length == 0 ? 0 : (payload.Length + fragmentSize - 1) / fragmentSize;
            for (int offset = 0, fragment = 1; offset < payload.Length; offset += fragmentSize, fragment++)
            {
                if (!canContinue()) return false;
                int length = Math.Min(fragmentSize, payload.Length - offset);
                byte[] chunk = new byte[length];
                Buffer.BlockCopy(payload, offset, chunk, 0, length);
                if (!await sendFragment(offset, chunk, fragment, count)) return false;
            }
            return canContinue();
        }
    }

    internal static class BridgeRoundIdentity
    {
        public static bool Matches(long expectedGeneration, long expectedDiscoveryId,
            long activeGeneration, long activeDiscoveryId)
        {
            return expectedGeneration == activeGeneration && expectedDiscoveryId == activeDiscoveryId;
        }
    }
}
