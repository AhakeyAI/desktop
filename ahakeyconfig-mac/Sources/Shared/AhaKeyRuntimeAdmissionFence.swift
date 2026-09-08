import Foundation

/// Resource-bearing ingest/apply 与连接 generation/fact mutation 共享的线性化栅栏。
///
/// `reserve` 在 token 已与 live 投影一致时取得 reservation；`withReservedWrite` 在同一把锁内
/// 复核 reservation 仍有效后再执行 Store CAS/WAL。连接 mutation 必须经 `publish` 换代：
/// 若 mutation 发生在 reservation 之后、写入之前，reservation 作废且不得提交；
/// 若 mutation 与写入抢锁，写入先完成，mutation 排在提交之后。
public enum AhaKeyRuntimeAdmissionWriteError: Error, Equatable, Sendable {
    case staleReservation
}

public struct AhaKeyRuntimeAdmissionReservation: Equatable, Sendable {
    public let token: AhaKeyRuntimeResourceAdmissionToken
    let epoch: UInt64
}

public final class AhaKeyRuntimeAdmissionFence: @unchecked Sendable {
    private let lock = NSLock()
    private var live: AhaKeyRuntimeResourceAdmissionToken?
    private var epoch: UInt64 = 0
    private var writeLockedProbe: (() -> Void)?

    public init() {}

    /// 连接投影变化时发布当前可写 token；无 fact 时发布 `nil` 使既有 reservation 全部失效。
    public func publish(_ token: AhaKeyRuntimeResourceAdmissionToken?) {
        lock.lock()
        defer { lock.unlock() }
        if live != token {
            live = token
            epoch &+= 1
        }
    }

    public func reserve(
        _ token: AhaKeyRuntimeResourceAdmissionToken
    ) -> AhaKeyRuntimeAdmissionReservation? {
        lock.lock()
        defer { lock.unlock() }
        guard live == token else { return nil }
        return AhaKeyRuntimeAdmissionReservation(token: token, epoch: epoch)
    }

    public func withReservedWrite<T>(
        _ reservation: AhaKeyRuntimeAdmissionReservation,
        _ body: () throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }
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
}
