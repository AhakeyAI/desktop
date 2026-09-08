import Foundation

/// Resource-bearing ingest/apply 与连接 generation/fact mutation 共享的线性化栅栏。
///
/// 真实 BLE/OLED identity mutation 必须先 `beginIdentityMutation()` 再改 generation/fact/target。
/// `reserve` 签发带 opaque identity 的一次性凭证；`withReservedWrite` 在同一把锁内单次消费后再执行 Store 写。
/// 未进入写入的 reservation 必须 `discard`（幂等）；`beginIdentityMutation` 同时清空 outstanding。
public enum AhaKeyRuntimeAdmissionWriteError: Error, Equatable, Sendable {
    case staleReservation
}

public struct AhaKeyRuntimeAdmissionReservation: Equatable, Sendable {
    public let token: AhaKeyRuntimeResourceAdmissionToken
    let identity: UUID
    let epoch: UInt64
}

/// 绑定某次 identity mutation 的 publication ticket。epoch 已前进时迟到 publish 必须 no-op。
public struct AhaKeyRuntimeAdmissionPublicationTicket: Equatable, Sendable {
    let epoch: UInt64
}

public final class AhaKeyRuntimeAdmissionFence: @unchecked Sendable {
    private let lock = NSLock()
    private var live: AhaKeyRuntimeResourceAdmissionToken?
    private var epoch: UInt64 = 0
    private var outstanding: Set<UUID> = []
    private var writeLockedProbe: (() -> Void)?

    public init() {}

    /// 连接投影稳定后发布当前可写 token。同步 proven 路径使用；不得替代 mutation 前的 `beginIdentityMutation`。
    public func publish(_ token: AhaKeyRuntimeResourceAdmissionToken?) {
        lock.lock()
        defer { lock.unlock() }
        applyPublishLocked(token)
    }

    /// 当前 publication epoch。必须在 identity mutation 之后、异步发布之前同步取样。
    public func publicationTicket() -> AhaKeyRuntimeAdmissionPublicationTicket {
        lock.lock()
        defer { lock.unlock() }
        return AhaKeyRuntimeAdmissionPublicationTicket(epoch: epoch)
    }

    /// CAS publish：ticket epoch 与当前不一致则 no-op，不恢复 live token。
    @discardableResult
    public func publish(
        _ token: AhaKeyRuntimeResourceAdmissionToken?,
        ticket: AhaKeyRuntimeAdmissionPublicationTicket
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard ticket.epoch == epoch else { return false }
        applyPublishLocked(token)
        return true
    }

    private func applyPublishLocked(_ token: AhaKeyRuntimeResourceAdmissionToken?) {
        if live != token {
            live = token
            epoch &+= 1
        }
    }

    /// 真实 identity mutation 之前同步进入栅栏：作废 live token 与既有 reservation。
    /// 若写请求正持锁，调用方在改变 generation/fact 之前等待写入完成。
    public func beginIdentityMutation() {
        lock.lock()
        defer { lock.unlock() }
        live = nil
        epoch &+= 1
        outstanding.removeAll()
    }

    public func reserve(
        _ token: AhaKeyRuntimeResourceAdmissionToken
    ) -> AhaKeyRuntimeAdmissionReservation? {
        lock.lock()
        defer { lock.unlock() }
        guard live == token else { return nil }
        let identity = UUID()
        outstanding.insert(identity)
        return AhaKeyRuntimeAdmissionReservation(token: token, identity: identity, epoch: epoch)
    }

    /// 放弃尚未写入的 reservation。已消费或已 discard 时为幂等 no-op。
    public func discard(_ reservation: AhaKeyRuntimeAdmissionReservation) {
        lock.lock()
        outstanding.remove(reservation.identity)
        lock.unlock()
    }

    public func withReservedWrite<T>(
        _ reservation: AhaKeyRuntimeAdmissionReservation,
        _ body: () throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard outstanding.remove(reservation.identity) != nil else {
            throw AhaKeyRuntimeAdmissionWriteError.staleReservation
        }
        guard live == reservation.token, epoch == reservation.epoch else {
            throw AhaKeyRuntimeAdmissionWriteError.staleReservation
        }
        writeLockedProbe?()
        return try body()
    }

    public func setWriteLockedProbeForTesting(_ probe: (() -> Void)?) {
        lock.lock()
        writeLockedProbe = probe
        lock.unlock()
    }

    public func outstandingCountForTesting() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return outstanding.count
    }

    public func liveTokenForTesting() -> AhaKeyRuntimeResourceAdmissionToken? {
        lock.lock()
        defer { lock.unlock() }
        return live
    }
}
