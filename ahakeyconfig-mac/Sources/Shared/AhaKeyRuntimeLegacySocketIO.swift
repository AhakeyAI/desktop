import Darwin
import Foundation

/// Production I/O for the legacy `ahakey.sock` JSON replies.
///
/// Restricted `hook.sock` already uses `SO_NOSIGPIPE` + write-all. This type is the
/// matching seam for accepted legacy clients so a closed peer cannot deliver SIGPIPE
/// to the Runtime process.
public enum AhaKeyRuntimeLegacySocketIO {
    public enum WriteResult: Equatable, Sendable {
        case completed
        case peerClosed
        case failed(Int32)
    }

    /// Test / probe helper. Not part of the production listen/accept path.
    package static func makeUnixStreamPair() -> (Int32, Int32)? {
        var pair = (Int32(-1), Int32(-1))
        let rc = withUnsafeMutablePointer(to: &pair) { pointer in
            pointer.withMemoryRebound(to: Int32.self, capacity: 2) { fds in
                socketpair(AF_UNIX, SOCK_STREAM, 0, fds)
            }
        }
        guard rc == 0, pair.0 >= 0, pair.1 >= 0 else { return nil }
        return pair
    }

    public static func prepareAcceptedClient(_ fd: Int32) -> Bool {
        guard fd >= 0 else { return false }
        var noSigPipe: Int32 = 1
        return setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0
    }

    public static func writeAll(
        _ data: Data,
        to fd: Int32,
        timeout: TimeInterval = 2
    ) -> WriteResult {
        guard fd >= 0 else { return .failed(EBADF) }
        if data.isEmpty { return .completed }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        return data.withUnsafeBytes { rawBuffer in
            guard let start = rawBuffer.baseAddress else { return .failed(EINVAL) }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(fd, start.advanced(by: written), rawBuffer.count - written)
                if result > 0 {
                    written += result
                    continue
                }
                if result < 0 && errno == EINTR {
                    continue
                }
                if result < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    let remaining = deadline.timeIntervalSinceNow
                    if remaining <= 0 {
                        return .failed(ETIMEDOUT)
                    }
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    let ms = Int32(min(max(remaining * 1_000, 1), Double(Int32.max)))
                    let prc = poll(&pfd, 1, ms)
                    if prc == 0 {
                        return .failed(ETIMEDOUT)
                    }
                    if prc < 0 {
                        if errno == EINTR { continue }
                        return .failed(errno)
                    }
                    continue
                }
                if result < 0 && (errno == EPIPE || errno == ECONNRESET) {
                    return .peerClosed
                }
                return .failed(errno)
            }
            return .completed
        }
    }

    public static func closeOnce(_ fd: inout Int32) {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }
}
