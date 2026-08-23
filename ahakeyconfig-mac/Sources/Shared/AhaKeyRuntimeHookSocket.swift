import Darwin
import Foundation

public enum AhaKeyRuntimeHookSocketError: Error, Equatable, Sendable {
    case pathTooLong
    case unsafeDirectory
    case unsafeExistingPath
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case permissionHardeningFailed
    case unsafeSocket
    case connectionFailed(Int32)
    case ioFailure(Int32)
    case invalidHandshakeResponse
    case lockUnavailable
}

public struct AhaKeyRuntimeHookSocketClient: Sendable {
    public let socketURL: URL
    private let codec: AhaKeyRuntimeJSONFrameCodec

    public init(socketURL: URL, maximumPayloadBytes: Int = 64 * 1_024) {
        self.socketURL = socketURL
        self.codec = .init(maximumPayloadBytes: maximumPayloadBytes)
    }

    public func exchange(
        handshake: AhaKeyRuntimeHookHandshake,
        request: AhaKeyRuntimeHookRequest,
        timeout: TimeInterval
    ) throws -> AhaKeyRuntimeHookResponse {
        precondition(timeout > 0)
        try validateSocketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AhaKeyRuntimeHookSocketError.socketCreationFailed(errno) }
        defer { close(fd) }

        var noSigPipe: Int32 = 1
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw AhaKeyRuntimeHookSocketError.ioFailure(errno)
        }
        var socketTimeout = timeval(
            tv_sec: __darwin_time_t(timeout),
            tv_usec: suseconds_t((timeout - Double(Int(timeout))) * 1_000_000)
        )
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &socketTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0,
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &socketTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw AhaKeyRuntimeHookSocketError.ioFailure(errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw AhaKeyRuntimeHookSocketError.pathTooLong }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { target in
                _ = strlcpy(
                    UnsafeMutableRawPointer(target).assumingMemoryBound(to: CChar.self),
                    source,
                    capacity
                )
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw AhaKeyRuntimeHookSocketError.connectionFailed(errno) }
        var peerUserID: uid_t = 0
        var peerGroupID: gid_t = 0
        guard getpeereid(fd, &peerUserID, &peerGroupID) == 0,
              peerUserID == getuid() else {
            throw AhaKeyRuntimeHookSocketError.unsafeSocket
        }

        var outbound = try codec.encode(AhaKeyRuntimeHookRequest.handshake(handshake))
        outbound.append(try codec.encode(request))
        try writeAll(outbound, to: fd)

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4_096)
        var handshakeAccepted = false
        while true {
            while let response = try codec.decodeOne(AhaKeyRuntimeHookResponse.self, from: &buffer) {
                if !handshakeAccepted {
                    guard response == .handshakeAccepted(handshake.protocolVersion) else {
                        throw AhaKeyRuntimeHookSocketError.invalidHandshakeResponse
                    }
                    handshakeAccepted = true
                } else {
                    return response
                }
            }
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else { throw AhaKeyRuntimeHookSocketError.ioFailure(errno) }
            buffer.append(contentsOf: chunk.prefix(count))
        }
    }

    private func validateSocketPath() throws {
        var status = stat()
        guard lstat(socketURL.path, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFSOCK,
              status.st_uid == getuid(),
              (status.st_mode & 0o777) == 0o600 else {
            throw AhaKeyRuntimeHookSocketError.unsafeSocket
        }
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let start = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(fd, start.advanced(by: written), rawBuffer.count - written)
                guard result > 0 else { throw AhaKeyRuntimeHookSocketError.ioFailure(errno) }
                written += result
            }
        }
    }
}

/// Restricted same-user Hook endpoint. Each connection must negotiate before sending messages.
public final class AhaKeyRuntimeHookSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (
        AhaKeyRuntimeHookHandshake,
        AhaKeyRuntimeHookRequest
    ) -> AhaKeyRuntimeHookResponse

    public let socketURL: URL
    private let codec: AhaKeyRuntimeJSONFrameCodec
    private let rateLimit: Int
    private let rateWindow: TimeInterval
    private let handler: Handler
    private let clientSlots: DispatchSemaphore
    private let stateLock = NSLock()
    private var listenerFD: Int32 = -1
    private var ownershipLockFD: Int32 = -1
    private var socketIdentity: (device: dev_t, inode: ino_t)?
    private let rateLock = NSLock()
    private var acceptedFrameTimes: [TimeInterval] = []
    private let acceptQueue = DispatchQueue(label: "ai.ahakey.runtime.hook.accept", qos: .utility)
    private let clientQueue = DispatchQueue(label: "ai.ahakey.runtime.hook.clients", qos: .utility, attributes: .concurrent)

    public init(
        socketURL: URL,
        maximumPayloadBytes: Int = 64 * 1_024,
        rateLimit: Int = 60,
        rateWindow: TimeInterval = 1,
        maximumConcurrentClients: Int = 32,
        handler: @escaping Handler
    ) {
        precondition(maximumConcurrentClients > 0)
        self.socketURL = socketURL
        self.codec = .init(maximumPayloadBytes: maximumPayloadBytes)
        self.rateLimit = rateLimit
        self.rateWindow = rateWindow
        self.handler = handler
        self.clientSlots = DispatchSemaphore(value: maximumConcurrentClients)
    }

    deinit {
        stop()
    }

    public func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard listenerFD < 0 else { return }

        try hardenParentDirectory()
        try acquireOwnershipLock()
        var fd: Int32 = -1
        do {
            try removeOwnedStaleSocketIfPresent()
            let path = socketURL.path
            guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
                throw AhaKeyRuntimeHookSocketError.pathTooLong
            }

            fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw AhaKeyRuntimeHookSocketError.socketCreationFailed(errno) }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
            path.withCString { source in
                withUnsafeMutablePointer(to: &address.sun_path) { target in
                    _ = strlcpy(
                        UnsafeMutableRawPointer(target).assumingMemoryBound(to: CChar.self),
                        source,
                        pathCapacity
                    )
                }
            }
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else { throw AhaKeyRuntimeHookSocketError.bindFailed(errno) }
            var status = stat()
            guard lstat(path, &status) == 0,
                  (status.st_mode & S_IFMT) == S_IFSOCK,
                  status.st_uid == getuid() else {
                throw AhaKeyRuntimeHookSocketError.permissionHardeningFailed
            }
            socketIdentity = (status.st_dev, status.st_ino)
            guard chmod(path, 0o600) == 0, try socketPathIsHardened() else {
                throw AhaKeyRuntimeHookSocketError.permissionHardeningFailed
            }
            guard Darwin.listen(fd, 16) == 0 else {
                throw AhaKeyRuntimeHookSocketError.listenFailed(errno)
            }
            listenerFD = fd
        } catch {
            if fd >= 0 { close(fd) }
            let identity = socketIdentity
            socketIdentity = nil
            removeSocketIfItMatches(identity)
            releaseOwnershipLock()
            throw error
        }

        acceptQueue.async { [weak self] in self?.acceptConnections() }
    }

    public func stop() {
        stateLock.lock()
        let fd = listenerFD
        listenerFD = -1
        let lockFD = ownershipLockFD
        ownershipLockFD = -1
        stateLock.unlock()
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
        removeCreatedSocketIfUnchanged()
        if lockFD >= 0 {
            _ = flock(lockFD, LOCK_UN)
            close(lockFD)
        }
    }

    private func acceptConnections() {
        while true {
            stateLock.lock()
            let fd = listenerFD
            stateLock.unlock()
            guard fd >= 0 else { return }
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            guard clientSlots.wait(timeout: .now()) == .success else {
                close(client)
                continue
            }
            clientQueue.async { [self] in
                defer { clientSlots.signal() }
                serve(client)
            }
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var peerUserID: uid_t = 0
        var peerGroupID: gid_t = 0
        guard getpeereid(client, &peerUserID, &peerGroupID) == 0,
              peerUserID == getuid() else { return }

        var noSigPipe: Int32 = 1
        guard setsockopt(
            client,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else { return }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        guard setsockopt(
            client,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0,
        setsockopt(
            client,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else { return }
        var session = AhaKeyRuntimeHookSession(rateLimit: rateLimit, rateWindow: rateWindow)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4_096)

        while true {
            let count = read(client, &chunk, chunk.count)
            guard count > 0 else { return }
            buffer.append(contentsOf: chunk.prefix(count))
            do {
                while let request = try codec.decodeOne(AhaKeyRuntimeHookRequest.self, from: &buffer) {
                    let now = ProcessInfo.processInfo.systemUptime
                    guard consumeGlobalRateToken(at: now) else { return }
                    let acceptance = try session.accept(request, at: now)
                    let response: AhaKeyRuntimeHookResponse
                    switch acceptance {
                    case .handshakeAccepted(let version): response = .handshakeAccepted(version)
                    case .messageAccepted(let clientContext):
                        response = handler(clientContext, request)
                    }
                    try writeAll(codec.encode(response), to: client)
                }
            } catch {
                return
            }
        }
    }

    private func hardenParentDirectory() throws {
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var status = stat()
        guard lstat(directory.path, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFDIR,
              status.st_uid == getuid(),
              (status.st_mode & 0o077) == 0 else {
            throw AhaKeyRuntimeHookSocketError.unsafeDirectory
        }
    }

    private func removeOwnedStaleSocketIfPresent() throws {
        var status = stat()
        guard lstat(socketURL.path, &status) == 0 else {
            if errno == ENOENT { return }
            throw AhaKeyRuntimeHookSocketError.unsafeExistingPath
        }
        guard (status.st_mode & S_IFMT) == S_IFSOCK, status.st_uid == getuid() else {
            throw AhaKeyRuntimeHookSocketError.unsafeExistingPath
        }
        guard unlink(socketURL.path) == 0 else {
            throw AhaKeyRuntimeHookSocketError.unsafeExistingPath
        }
    }

    /// The lock proves no cooperating Runtime owns the fixed endpoint before stale cleanup.
    private func acquireOwnershipLock() throws {
        let lockURL = socketURL.appendingPathExtension("lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AhaKeyRuntimeHookSocketError.lockUnavailable }
        var status = stat()
        guard fstat(fd, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == getuid(),
              (status.st_mode & 0o077) == 0,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw AhaKeyRuntimeHookSocketError.lockUnavailable
        }
        ownershipLockFD = fd
    }

    private func releaseOwnershipLock() {
        let fd = ownershipLockFD
        ownershipLockFD = -1
        guard fd >= 0 else { return }
        _ = flock(fd, LOCK_UN)
        close(fd)
    }

    private func socketPathIsHardened() throws -> Bool {
        var status = stat()
        guard lstat(socketURL.path, &status) == 0 else { return false }
        return (status.st_mode & S_IFMT) == S_IFSOCK
            && status.st_uid == getuid()
            && (status.st_mode & 0o777) == 0o600
    }

    private func consumeGlobalRateToken(at now: TimeInterval) -> Bool {
        rateLock.lock()
        defer { rateLock.unlock() }
        acceptedFrameTimes.removeAll { now - $0 >= rateWindow }
        guard acceptedFrameTimes.count < rateLimit else { return false }
        acceptedFrameTimes.append(now)
        return true
    }

    private func removeCreatedSocketIfUnchanged() {
        stateLock.lock()
        let identity = socketIdentity
        socketIdentity = nil
        stateLock.unlock()
        removeSocketIfItMatches(identity)
    }

    private func removeSocketIfItMatches(_ identity: (device: dev_t, inode: ino_t)?) {
        guard let identity else { return }
        var status = stat()
        guard lstat(socketURL.path, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFSOCK,
              status.st_uid == getuid(),
              status.st_dev == identity.device,
              status.st_ino == identity.inode else { return }
        _ = unlink(socketURL.path)
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let start = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(fd, start.advanced(by: written), rawBuffer.count - written)
                guard result > 0 else { throw AhaKeyRuntimeProductionSeamError.malformedFrame }
                written += result
            }
        }
    }
}
