using System;

namespace BleTcpBridge
{
    /// <summary>
    /// BLE 占位实现，用于 Phase 1 测试。
    /// 所有方法打日志但不执行真实 BLE 操作。
    /// </summary>
    class MockBleBridge : IBleBridge
    {
        public bool IsConnected => false;
        public string DeviceName => "";
        public string DeviceId => "";

        public bool IsDataCharacteristicReady => false;
        public bool IsWriteCharacteristicReady => false;
        public bool IsNotifyCharacteristicReady => false;
        public bool IsTargetDevice => false;

        public event Action<byte[]> OnNotifyDataReceived;
        public event Action<bool> OnConnectionStateChanged;
        public event Action OnCharacteristicsDiscovered;

        public void WriteData(byte[] data)
        {
            Console.WriteLine($"[MockBLE] WriteData called, {data?.Length ?? 0} bytes (no-op)");
        }

        public void WriteCommand(byte[] data)
        {
            Console.WriteLine($"[MockBLE] WriteCommand called, {data?.Length ?? 0} bytes (no-op)");
        }

        public void StartScanning()
        {
            Console.WriteLine("[MockBLE] StartScanning called (no-op)");
        }

        public void StopScanning()
        {
            Console.WriteLine("[MockBLE] StopScanning called (no-op)");
        }

        public void Disconnect()
        {
            Console.WriteLine("[MockBLE] Disconnect called (no-op)");
        }
    }
}

