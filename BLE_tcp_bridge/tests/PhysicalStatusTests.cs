// Compile the production TCP server/protocol with a hardware-only test double.
// No Bluetooth discovery, device writes or firmware operations are performed.
using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Threading;
using BLE_tcp_driver;

namespace Windows.Devices.Bluetooth
{
    enum BluetoothConnectionStatus { Disconnected, Connected }
    class BluetoothLEDevice
    {
        public BluetoothConnectionStatus ConnectionStatus = BluetoothConnectionStatus.Connected;
        public string Name = "AhaKey AE1E";
        public ulong BluetoothAddress = 0x112233445566;
    }
}
namespace Windows.Devices.Bluetooth.GenericAttributeProfile
{
    class GattCharacteristic { }
}
namespace BLE_tcp_driver
{
    class BleCore
    {
        public Windows.Devices.Bluetooth.BluetoothLEDevice CurrentDevice =
            new Windows.Devices.Bluetooth.BluetoothLEDevice();
        public Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristic
            CurrentDataCharacteristic = new Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristic(),
            CurrentWriteCharacteristic = new Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristic(),
            CurrentNotifyCharacteristic = new Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristic();
        public event Action<Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristic, byte[]> ReceiveNotifyData;
        public byte[] LastCommand;
        public readonly ManualResetEventSlim Written = new ManualResetEventSlim();
        public void WriteDataToCharacterstuc(
            Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristic characteristic, byte[] data)
        {
            LastCommand = data;
            Written.Set();
        }
        public void Notify(byte[] data) { ReceiveNotifyData?.Invoke(CurrentNotifyCharacteristic, data); }
    }
}

static class PhysicalStatusTests
{
    static void Equal(byte[] expected, byte[] actual, string message)
    {
        if (!expected.SequenceEqual(actual))
            throw new Exception(message + ": " + BitConverter.ToString(actual));
    }

    static byte[] ReadExact(NetworkStream stream, int length)
    {
        byte[] bytes = new byte[length];
        for (int offset = 0; offset < length;)
        {
            int count = stream.Read(bytes, offset, length - offset);
            if (count == 0) throw new EndOfStreamException();
            offset += count;
        }
        return bytes;
    }

    static byte[] ReadPacket(NetworkStream stream)
    {
        byte[] header = ReadExact(stream, 3);
        return header.Concat(ReadExact(stream, header[1] | (header[2] << 8))).ToArray();
    }

    public static int Main()
    {
        var core = new BleCore();
        var server = new TcpServer(core, 0);
        server.Start();
        try
        {
            var listener = (TcpListener)typeof(TcpServer).GetField("_listener",
                BindingFlags.Instance | BindingFlags.NonPublic).GetValue(server);
            using (var client = new TcpClient())
            {
                client.Connect(IPAddress.Loopback, ((IPEndPoint)listener.LocalEndpoint).Port);
                var stream = client.GetStream();
                stream.ReadTimeout = 2000;
                byte[] query = ProtocolHelper.BuildPacket(PacketType.QueryBleStatus);
                stream.Write(query, 0, query.Length);
                byte[] link = ReadPacket(stream);
                if (link[0] != 0x82 || link[3] != 1) throw new Exception("Missing connection status");

                // Fragmented TCP request must still reach the command characteristic intact.
                query = ProtocolHelper.BuildPacket(PacketType.WriteCommand, ProtocolHelper.DeviceStatusQueryCommand);
                for (int i = 0; i < query.Length; i++) stream.WriteByte(query[i]);
                if (!core.Written.Wait(2000)) throw new Exception("Physical query was not written");
                Equal(new byte[] { 0xAA, 0xBB, 0x00, 0xCC, 0xDD }, core.LastCommand, "Status query");

                byte[] legacy = { 0xAA, 0xBB, 0, 98, 50, 1, 0, 2, 0, 0, 0, 0xCC, 0xDD };
                core.Notify(legacy);
                Equal(new byte[] { 0x81, 13, 0 }.Concat(legacy).ToArray(), ReadPacket(stream),
                    "Legacy physical status must be forwarded unchanged as 0x81");

                query = ProtocolHelper.BuildPacket(PacketType.QueryDeviceInfo);
                stream.Write(query, 0, query.Length);
                Equal(new byte[] { 0x83, 8, 0, 98, 50, 1, 0, 2, 0, 0, 0 }, ReadPacket(stream),
                    "Forwarding must preserve legacy cache metadata");

                byte[] extended = { 0xAA, 0xBB, 0, 98, 50, 1, 4, 2, 0, 1, 35, 3, 0xCC, 0xDD };
                core.Notify(extended);
                Equal(new byte[] { 0x81, 14, 0 }.Concat(extended).ToArray(), ReadPacket(stream),
                    "Extended physical status must retain readiness flags");
                byte[] ack = { 0xAA, 0xBB, 0x98, 0, 1, 0xCC, 0xDD };
                core.Notify(ack);
                Equal(new byte[] { 0x81, 7, 0 }.Concat(ack).ToArray(), ReadPacket(stream),
                    "Command responses must retain command/status/payload");
                if (client.Available != 0) throw new Exception("Duplicate status notification");
            }
            Console.WriteLine("BLE_PHYSICAL_STATUS_TESTS=PASS (query routing, legacy notify, cache, extended notify, command response)");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
        finally { server.Stop(); }
    }
}
