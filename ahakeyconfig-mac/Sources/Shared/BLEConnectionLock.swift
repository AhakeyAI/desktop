import Foundation

/// 跨进程 BLE 连接锁（阶段 3，flock）：谁要发起 BLE 连接，谁先持有锁；持有期间独占键盘。
/// GUI（AhaKeyBLEManager）与 Agent（AhaKeyAgent）共用本实现，互斥防双连。
/// flock 关联 open file description，进程死亡时系统自动关闭 fd 并释放锁，无需清理残留。
public final class BLEConnectionLock {
    private let lockURL: URL
    private var lockFd: Int32 = -1

    /// 默认锁文件：`~/Library/Application Support/AhaKeyConfig/ble-owner.lock`（与诊断文件同目录）。
    public convenience init() {
        self.init(lockURL: URL(fileURLWithPath: AhaKeyPaths.bleConnectionLockPath))
    }

    /// 路径可注入（测试用临时目录）。
    public init(lockURL: URL) {
        self.lockURL = lockURL
        try? FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// 尝试排他非阻塞加锁。已持有返回 true；被其他进程（或本进程其他实例）持有返回 false。
    @discardableResult
    public func acquire() -> Bool {
        guard lockFd == -1 else { return true }

        let fd = lockURL.path.withCString { open($0, O_CREAT | O_RDWR, 0o644) }
        guard fd >= 0 else { return false }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            lockFd = fd
            // 记录持锁进程 PID，便于排查占用方。
            ftruncate(fd, 0)
            let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
            _ = pid.withCString { write(fd, $0, strlen($0)) }
            return true
        }
        close(fd)
        return false
    }

    public var holdsLock: Bool { lockFd >= 0 }

    public func release() {
        guard lockFd >= 0 else { return }
        flock(lockFd, LOCK_UN)
        close(lockFd)
        lockFd = -1
    }

    deinit {
        release()
    }
}
