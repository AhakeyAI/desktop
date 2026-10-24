import Foundation

/// 同一 socket 路径的 Agent 单实例锁。
///
/// 仅靠 connect() 探测判断「socket 是否还有人在监听」并不可靠：首个 Agent 的 accept
/// 队列被占满时 connect 会返回 ECONNREFUSED，第二个 Agent 会误判为残留 socket 而 unlink
/// 并重新 bind，导致首个 Agent 进程存活却失去服务（AHK-015）。
///
/// 持有 `<socketPath>.lock` 上的 flock 才有资格清理并绑定 socket；进程退出（含崩溃）时
/// 内核自动释放锁，不会留下死锁。
enum AgentInstanceLock {
    enum Result: Equatable {
        /// 拿到锁；fd 需在进程生命周期内保持打开。
        case acquired(Int32)
        /// 另一个 Agent 正持有锁。
        case heldByOther
        /// 锁文件无法打开（权限等），调用方回退到仅 connect 探测。
        case unavailable(Int32)
    }

    static func lockPath(for socketPath: String) -> String {
        socketPath + ".lock"
    }

    static func acquire(socketPath: String) -> Result {
        let fd = open(lockPath(for: socketPath), O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .unavailable(errno) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            return .acquired(fd)
        }
        let err = errno
        close(fd)
        return err == EWOULDBLOCK ? .heldByOther : .unavailable(err)
    }

    /// sockaddr_un.sun_path 含结尾 NUL 的容量（macOS 为 104）。
    static let maxSocketPathBytes = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

    static func isValidSocketPath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count < maxSocketPathBytes
    }
}
