using System;

namespace BleTcpBridge
{
    /// <summary>
    /// BLE 桥接抽象接口
    /// TcpServer 通过此接口与 BLE 层交互，不再直接依赖平台 BLE 类型。
    /// </summary>
    interface IBleBridge
    {
        // ── 连接状态 ──

        /// <summary>
        /// 当前是否已连接 BLE 设备
        /// </summary>
        bool IsConnected { get; }

        /// <summary>
        /// 当前连接的设备名称（未连接时返回空字符串）
        /// </summary>
        string DeviceName { get; }

        /// <summary>
        /// 当前连接的设备标识（Windows 上是 MAC，mac 上是平台 UUID）
        /// </summary>
        string DeviceId { get; }

        // ── 特征就绪状态 ──

        /// <summary>
        /// 数据写特征 (0x7341) 是否就绪
        /// </summary>
        bool IsDataCharacteristicReady { get; }

        /// <summary>
        /// 命令写特征 (0x7343) 是否就绪
        /// </summary>
        bool IsWriteCharacteristicReady { get; }

        /// <summary>
        /// 通知特征 (0x7344) 是否就绪
        /// </summary>
        bool IsNotifyCharacteristicReady { get; }

        /// <summary>
        /// 三个关键特征是否全部就绪
        /// </summary>
        bool IsTargetDevice { get; }

        // ── 写操作 ──

        /// <summary>
        /// 向数据特征 (0x7341) 写入数据
        /// </summary>
        void WriteData(byte[] data);

        /// <summary>
        /// 向命令特征 (0x7343) 写入命令
        /// </summary>
        void WriteCommand(byte[] data);

        // ── 扫描与连接 ──

        /// <summary>
        /// 开始扫描 BLE 设备
        /// </summary>
        void StartScanning();

        /// <summary>
        /// 停止扫描
        /// </summary>
        void StopScanning();

        /// <summary>
        /// 断开当前连接
        /// </summary>
        void Disconnect();

        // ── 事件 ──

        /// <summary>
        /// 收到 BLE 通知数据 (来自 0x7344)
        /// 签名: (byte[] data)，不再暴露平台特征类型
        /// </summary>
        event Action<byte[]> OnNotifyDataReceived;

        /// <summary>
        /// 设备连接状态变化
        /// </summary>
        event Action<bool> OnConnectionStateChanged;

        /// <summary>
        /// 所有关键特征发现完毕
        /// </summary>
        event Action OnCharacteristicsDiscovered;
    }
}

