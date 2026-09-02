import Darwin
import Foundation

/// Production I/O for the legacy `ahakey.sock` JSON replies.
///
/// Restricted `hook.sock` already uses `SO_NOSIGPIPE` + write-all. This type is the
/// matching seam for accepted legacy clients so a closed peer cannot deliver SIGPIPE
/// to the Runtime process. Accepted fds are nonblocking; `writeAll` is bounded by a
/// monotonic deadline covering write, poll, and EINTR.
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
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else { return false }
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0
    }

    public static func writeAll(
        _ data: Data,
        to fd: Int32,
        timeout: TimeInterval = 2
    ) -> WriteResult {
        guard fd >= 0 else { return .failed(EBADF) }
        if data.isEmpty { return .completed }
        let deadline = DispatchTime.now() + max(0, timeout)
        return data.withUnsafeBytes { rawBuffer in
            guard let start = rawBuffer.baseAddress else { return .failed(EINVAL) }
            var written = 0
            while written < rawBuffer.count {
                if remainingMillis(until: deadline) == nil {
                    return .failed(ETIMEDOUT)
                }
                let result = Darwin.write(fd, start.advanced(by: written), rawBuffer.count - written)
                if result > 0 {
                    written += result
                    continue
                }
                if result < 0 && errno == EINTR {
                    continue
                }
                if result < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    switch waitFor(fd, events: Int16(POLLOUT), until: deadline) {
                    case .ready:
                        continue
                    case .peerClosed:
                        return .peerClosed
                    case .failed(let code):
                        return .failed(code)
                    }
                }
                if result < 0 && (errno == EPIPE || errno == ECONNRESET) {
                    return .peerClosed
                }
                return .failed(errno)
            }
            return .completed
        }
    }

    public static func waitForReadable(_ fd: Int32, timeout: TimeInterval) -> WriteResult {
        guard fd >= 0 else { return .failed(EBADF) }
        let deadline = DispatchTime.now() + max(0, timeout)
        switch waitFor(fd, events: Int16(POLLIN), until: deadline) {
        case .ready:
            return .completed
        case .peerClosed:
            return .peerClosed
        case .failed(let code):
            return .failed(code)
        }
    }

    public static func closeOnce(_ fd: inout Int32) {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }

    private enum PollWait {
        case ready
        case peerClosed
        case failed(Int32)
    }

    private static func remainingMillis(until deadline: DispatchTime) -> Int32? {
        let now = DispatchTime.now()
        if now.uptimeNanoseconds >= deadline.uptimeNanoseconds {
            return nil
        }
        let ns = deadline.uptimeNanoseconds - now.uptimeNanoseconds
        let ms = ns / 1_000_000
        if ms == 0 { return 1 }
        return Int32(min(ms, UInt64(Int32.max)))
    }

    private static func waitFor(_ fd: Int32, events: Int16, until deadline: DispatchTime) -> PollWait {
        while true {
            guard let ms = remainingMillis(until: deadline) else {
                return .failed(ETIMEDOUT)
            }
            var pfd = pollfd(fd: fd, events: events, revents: 0)
            let prc = poll(&pfd, 1, ms)
            if prc == 0 {
                return .failed(ETIMEDOUT)
            }
            if prc < 0 {
                if errno == EINTR { continue }
                return .failed(errno)
            }
            let rev = pfd.revents
            if rev & Int16(POLLNVAL) != 0 {
                return .failed(EBADF)
            }
            if rev & Int16(POLLERR) != 0 {
                var soError: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                if getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length) == 0, soError != 0 {
                    if soError == EPIPE || soError == ECONNRESET {
                        return .peerClosed
                    }
                    return .failed(soError)
                }
                return .failed(EIO)
            }
            if rev & Int16(POLLHUP) != 0 && rev & events == 0 {
                return .peerClosed
            }
            return .ready
        }
    }
}
