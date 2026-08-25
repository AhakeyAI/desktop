import Foundation

/// 应用级路径常量，供主 App 与 Agent target 共享。
public enum AhaKeyPaths {
    /// 用户目录下的 Application Support 子目录（`~/Library/Application Support/AhaKeyConfig`）。
    public static var applicationSupportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("AhaKeyConfig", isDirectory: true)
    }

    /// Agent Unix Domain Socket 路径。
    public static var agentSocketPath: String {
        applicationSupportDirectory.appendingPathComponent("ahakey.sock").path
    }

    /// Runtime restricted Hook socket；父目录由 Runtime 以 0700 创建，socket 为 0600。
    public static var runtimeHookSocketURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("private", isDirectory: true)
            .appendingPathComponent("hook.sock")
    }

    /// 跨进程 BLE 连接锁（flock）文件路径，见 `BLEConnectionLock`。
    public static var bleConnectionLockPath: String {
        applicationSupportDirectory.appendingPathComponent("ble-owner.lock").path
    }

    /// 稳定设备身份缓存（WBS-5.5）：UUID → 设备编号。
    /// 广播路径从 manufacturer data 学到后持久化；系统已连/已知 UUID 路径（无广播包）回查。
    public static var deviceIdentityCacheURL: URL {
        applicationSupportDirectory.appendingPathComponent("device-identity.json")
    }

    /// Runtime 持久事务存储根（WBS-5.1 WAL + CAS；5.6 配置事务恢复从这里捞）。
    public static var runtimeStoreDirectory: URL {
        applicationSupportDirectory
            .appendingPathComponent("private", isDirectory: true)
            .appendingPathComponent("runtime-store", isDirectory: true)
    }

    /// 确保 Application Support 子目录存在，并设置为仅用户自己可访问（0700）。
    public static func ensureApplicationSupportDirectory() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
