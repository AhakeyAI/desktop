using System;
using System.Text;

namespace BLE_tcp_driver
{
    /// <summary>
    /// TCP通信协议包类型
    /// 包格式: [Type:1字节][Length:2字节小端][Data:N字节]
    /// </summary>
    enum PacketType : byte
    {
        // 客户端 → 服务器
        WriteData       = 0x01,  // 写数据到BLE 0x7341
        WriteCommand    = 0x02,  // 写命令到BLE 0x7343
        QueryBleStatus  = 0x03,  // 查询BLE连接状态
        QueryDeviceInfo = 0x04,  // 查询设备状态信息

        // 服务器 → 客户端
        BleNotify       = 0x81,  // BLE通知数据 (来自0x7344)
        BleStatusResp   = 0x82,  // BLE连接状态响应
        DeviceInfoResp  = 0x83,  // 设备状态信息响应
    }

    /// <summary>
    /// BLE连接状态信息
    /// </summary>
    struct BleStatusInfo
    {
        public bool Connected;
        public string DeviceName;
        public string MacAddress;
        public bool IsTargetDevice; // 所有目标UUID (0x7341, 0x7343, 0x7344) 均已发现
    }

    /// <summary>
    /// 设备状态信息 (占位结构体, 后续根据需要填充具体字段)
    /// </summary>
    struct DeviceStatusInfo
    {
        public byte BatteryLevel;
        public byte SignalStrength;
        public byte FirmwareVersionMain;
        public byte FirmwareVersionSub;
        public byte WorkMode;
        public byte LightMode;
        public byte SwitchState;
        public byte Reserve;
    }

    /// <summary>
    /// 协议打包/解包工具
    /// </summary>
    static class ProtocolHelper
    {
        /// <summary>
        /// 构建协议包: [Type:1][Length:2 LE][Data:N]
        /// </summary>
        public static byte[] BuildPacket(PacketType type, byte[] data = null)
        {
            int len = data?.Length ?? 0;
            byte[] packet = new byte[3 + len];
            packet[0] = (byte)type;
            packet[1] = (byte)(len & 0xFF);
            packet[2] = (byte)((len >> 8) & 0xFF);
            if (data != null && len > 0)
                Array.Copy(data, 0, packet, 3, len);
            return packet;
        }

        /// <summary>
        /// 构建BLE状态响应包
        /// 数据格式: [Connected:1][NameLen:1][Name:N][MacLen:1][Mac:M][IsTarget:1]
        /// </summary>
        public static byte[] BuildBleStatusPacket(BleStatusInfo info)
        {
            byte[] nameBytes = Encoding.UTF8.GetBytes(info.DeviceName ?? "");
            byte[] macBytes = Encoding.UTF8.GetBytes(info.MacAddress ?? "");
            byte[] data = new byte[1 + 1 + nameBytes.Length + 1 + macBytes.Length + 1];
            int offset = 0;
            data[offset++] = (byte)(info.Connected ? 1 : 0);
            data[offset++] = (byte)nameBytes.Length;
            Array.Copy(nameBytes, 0, data, offset, nameBytes.Length);
            offset += nameBytes.Length;
            data[offset++] = (byte)macBytes.Length;
            Array.Copy(macBytes, 0, data, offset, macBytes.Length);
            offset += macBytes.Length;
            data[offset++] = (byte)(info.IsTargetDevice ? 1 : 0);
            return BuildPacket(PacketType.BleStatusResp, data);
        }

        /// <summary>
        /// 构建设备状态信息响应包
        /// 数据格式: [BatteryLevel:1][SignalStrength:1][FwMain:1][FwSub:1][WorkMode:1][LightMode:1][SwitchState:1][Reserve:1]
        /// </summary>
        public static byte[] BuildDeviceInfoPacket(DeviceStatusInfo info)
        {
            byte[] data = new byte[8];
            data[0] = info.BatteryLevel;
            data[1] = info.SignalStrength;
            data[2] = info.FirmwareVersionMain;
            data[3] = info.FirmwareVersionSub;
            data[4] = info.WorkMode;
            data[5] = info.LightMode;
            data[6] = info.SwitchState;
            data[7] = info.Reserve;
            return BuildPacket(PacketType.DeviceInfoResp, data);
        }

        /// <summary>
        /// 设备状态查询指令: 连接成功后自动发送到命令特征(0x7343)
        /// </summary>
        public static readonly byte[] DeviceStatusQueryCommand = { 0xAA, 0xBB, 0x00, 0xCC, 0xDD };

        public static byte[] LastClaudeState = null;

        /// <summary>
        /// 检查BLE通知数据是否为设备状态信息包
        /// 格式: [0xAA][0xBB][0x00][8字节设备信息][0xCC][0xDD] = 13字节
        /// </summary>
        public static bool IsDeviceStatusNotification(byte[] data)
        {
            if (data == null || data.Length != 13) return false;
            return data[0] == 0xAA && data[1] == 0xBB && data[2] == 0x00
                && data[11] == 0xCC && data[12] == 0xDD;
        }
        /// <summary>
        /// 检查数据是否是claude状态
        /// 格式: [0xAA][0xBB][0x90]
        /// </summary>
        public static bool IsClaudeStatusUpload(byte[] data)
        {
            if (data == null) return false;
            return data[0] == 0xAA && data[1] == 0xBB && data[2] == 0x90;
        }

        /// <summary>
        /// 从设备状态通知数据中解析DeviceStatusInfo
        /// </summary>
        public static DeviceStatusInfo ParseDeviceStatusFromNotification(byte[] data)
        {
            byte[] infoBytes = new byte[8];
            Array.Copy(data, 3, infoBytes, 0, 8);
            return ParseDeviceInfo(infoBytes);
        }

        /// <summary>
        /// 从字节数组解析DeviceStatusInfo
        /// </summary>
        public static DeviceStatusInfo ParseDeviceInfo(byte[] data)
        {
            var info = new DeviceStatusInfo();
            if (data != null && data.Length >= 8)
            {
                info.BatteryLevel = data[0];
                info.SignalStrength = data[1];
                info.FirmwareVersionMain = data[2];
                info.FirmwareVersionSub = data[3];
                info.WorkMode = data[4];
                info.LightMode = data[5];
                info.SwitchState = data[6];
                info.Reserve = data[7];
            }
            return info;
        }
    }
}
