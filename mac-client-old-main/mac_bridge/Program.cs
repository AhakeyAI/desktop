using System;
using System.IO;
using System.Linq;
using System.Threading;

namespace BleTcpBridge
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("=== BLE-TCP Bridge (mac) ===");
            Console.WriteLine();

            // 加载配置
            var config = AppConfig.Load();
            Console.WriteLine($"配置已加载: 端口={config.ServerPort}, IP={config.ServerIP}");
            if (config.HasSavedDevice)
                Console.WriteLine($"已保存设备: {config.BleName} ({config.BleMac})");
            else
                Console.WriteLine("无已保存设备");
            Console.WriteLine();

            string helperPath = ResolveHelperPath();
            if (string.IsNullOrEmpty(helperPath))
            {
                Console.WriteLine("错误: 找不到 ble_helper 或 ble_helper.swift");
                Console.WriteLine("请确保 helper 与程序在同一目录或 BLE_TCP_BRIDGE_HOME 指定的目录中");
                return;
            }
            Console.WriteLine($"BLE Helper: {helperPath}");

            string targetDeviceName = !string.IsNullOrWhiteSpace(config.BleName) ? config.BleName : "vibe code";
            string targetDeviceId = !string.IsNullOrWhiteSpace(config.BleMac) ? config.BleMac : null;

            if (!string.IsNullOrWhiteSpace(targetDeviceId))
            {
                Console.WriteLine($"连接策略: 优先用已保存 UUID 直连 {targetDeviceId}");
                Console.WriteLine($"回退策略: 如果系统缓存未命中，则按名称前缀 \"{targetDeviceName}\" 扫描并自动连接");
            }
            else
            {
                Console.WriteLine($"连接策略: 首次运行，扫描名称以 \"{targetDeviceName}\" 开头的 BLE 设备并自动连接");
            }
            Console.WriteLine();

            // 创建 BLE 桥接 (Swift 子进程方式)
            var ble = new SwiftBleBridge(
                helperPath: helperPath,
                targetDeviceName: targetDeviceName,
                targetDeviceId: targetDeviceId,
                autoReconnect: true
            );
            ble.OnLog += msg => Console.WriteLine($"[BLE] {msg}");

            // 特征发现完毕后保存设备信息
            ble.OnCharacteristicsDiscovered += () =>
            {
                if (!config.HasSavedDevice || config.BleName != ble.DeviceName || config.BleMac != ble.DeviceId)
                {
                    config.BleName = ble.DeviceName;
                    config.BleMac = ble.DeviceId;  // macOS 上存 UUID
                    config.Save();
                    Console.WriteLine($"[配置] 已保存设备: {config.BleName} ({config.BleMac})");
                }
            };

            ble.OnConnectionStateChanged += connected =>
            {
                Console.WriteLine(connected ? "[BLE] 设备已连接" : "[BLE] 设备已断开");
            };

            Console.WriteLine("BLE 桥接: SwiftBleBridge (CoreBluetooth via Swift 子进程)");

            // 启动 TCP 服务
            var server = new TcpServer(ble, config.ServerPort);
            server.OnLog += msg => Console.WriteLine($"[TCP] {msg}");
            server.OnClientCountChanged += count => Console.WriteLine($"[TCP] 当前客户端数: {count}");
            server.Start();

            string localIp = TcpServer.GetLocalIPAddress();
            Console.WriteLine($"本机IP: {localIp}");
            Console.WriteLine();

            // 启动 Swift BLE 子进程
            ble.Start();

            // 开始扫描
            ble.StartScanning();

            Console.WriteLine("按 Ctrl+C 退出...");
            Console.WriteLine();

            // 保持主线程运行
            var exitEvent = new ManualResetEvent(false);
            Console.CancelKeyPress += (s, e) =>
            {
                e.Cancel = true;
                exitEvent.Set();
            };
            exitEvent.WaitOne();

            // 清理
            server.Stop();
            ble.Stop();
            Console.WriteLine("已退出。");
        }

        static string ResolveHelperPath()
        {
            var roots = new[]
            {
                Environment.GetEnvironmentVariable("BLE_TCP_BRIDGE_HOME"),
                AppContext.BaseDirectory,
                Path.Combine(AppContext.BaseDirectory, "..", "Resources", "bridge"),
                Directory.GetCurrentDirectory(),
            }
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Select(path =>
            {
                try { return Path.GetFullPath(path); }
                catch { return null; }
            })
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Distinct(StringComparer.OrdinalIgnoreCase);

            foreach (var root in roots)
            {
                string compiledHelper = Path.Combine(root, "ble_helper");
                if (File.Exists(compiledHelper))
                    return compiledHelper;

                string scriptHelper = Path.Combine(root, "ble_helper.swift");
                if (File.Exists(scriptHelper))
                    return scriptHelper;
            }

            return "";
        }
    }
}
