import Foundation

/// Agent 与 hook 客户端之间 Unix socket 的路径与权限。
///
/// 不放 `/tmp`：该目录全局可写，其他用户可以在 agent 启动前抢先 bind 同名路径冒充它
/// （`AhaKeyAgent.startSocketListener` 见到已有监听会主动让位），对每次审批请求回自动批准。
/// 同 uid 的进程仍连得上，Unix 权限位管不了这层。
enum AhaKeySocket {
    static var defaultPath: String {
        directoryURL.appendingPathComponent("agent.sock").path
    }

    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig", isDirectory: true)
    }

    /// 建目录并置为 0700，已存在时也改一次。
    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    static func peerIsSameUser(_ fd: Int32) -> Bool {
        var uid = uid_t(0)
        var gid = gid_t(0)
        guard getpeereid(fd, &uid, &gid) == 0 else { return false }
        return uid == getuid()
    }

    /// 填充 `sockaddr_un`，路径放不下时返回 nil。
    ///
    /// `sun_path` 只有 104 字节，而这条路径含用户主目录，长度随用户名变化。
    static func makeAddress(path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            let dst = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
            path.withCString { _ = strlcpy(dst, $0, capacity) }
        }
        return addr
    }
}
