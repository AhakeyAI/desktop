import Foundation
import AhaKeyConfigShared

/// C4R6：到期发布的完整身份。消费前必须同时匹配 operation、设备与 epoch。
struct AhaKeyAbandonDeadlineToken: Equatable, Sendable {
    var operationID: AhaKeyRuntimeOperationID
    var deviceID: AhaKeyRuntimeDeviceID
    var epoch: AhaKeyRuntimeDisconnectEpoch
}

/// 完整 deadline 状态机：pending/published/wake/fireAt/retry 全部隔离在本 actor 内。
actor AhaKeyAbandonDeadlineScheduler {
    private static let retryDelaysNanoseconds: [UInt64] = [
        20_000_000,
        80_000_000,
        320_000_000,
        1_280_000_000
    ]

    private var pending: [AhaKeyRuntimeDeviceID: AhaKeyAbandonDeadlineToken] = [:]
    private var published: [AhaKeyRuntimeDeviceID: AhaKeyAbandonDeadlineToken] = [:]
    private var wakeTask: Task<Void, Never>?
    private var scheduledFireAt: Date?
    private var retryAttempt = 0
    private var burstExhausted = false

    func pendingToken(for deviceID: AhaKeyRuntimeDeviceID) -> AhaKeyAbandonDeadlineToken? {
        pending[deviceID]
    }

    func upsert(
        _ token: AhaKeyAbandonDeadlineToken,
        reschedule: Bool,
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) {
        pending[token.deviceID] = token
        if published[token.deviceID] != token {
            published.removeValue(forKey: token.deviceID)
        }
        retryAttempt = 0
        burstExhausted = false
        if reschedule {
            startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
        }
    }

    func drop(
        _ deviceID: AhaKeyRuntimeDeviceID,
        reschedule: Bool,
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) {
        pending.removeValue(forKey: deviceID)
        published.removeValue(forKey: deviceID)
        if reschedule {
            startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
        }
    }

    func replaceAll(
        _ next: [AhaKeyRuntimeDeviceID: AhaKeyAbandonDeadlineToken],
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) {
        let stale = Set(pending.keys).subtracting(next.keys)
        for deviceID in stale {
            pending.removeValue(forKey: deviceID)
            published.removeValue(forKey: deviceID)
        }
        for (deviceID, token) in next {
            pending[deviceID] = token
            if published[deviceID] != token {
                published.removeValue(forKey: deviceID)
            }
        }
        retryAttempt = 0
        burstExhausted = false
        startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
    }

    func noteExternalRecoveryTrigger(
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) {
        guard !pending.isEmpty else { return }
        if burstExhausted {
            retryAttempt = 0
            burstExhausted = false
        }
        startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
    }

    func cancelAllAndWait() async {
        let wake = wakeTask
        wakeTask?.cancel()
        wakeTask = nil
        scheduledFireAt = nil
        pending.removeAll()
        published.removeAll()
        retryAttempt = 0
        burstExhausted = false
        await wake?.value
    }

    func cancelWake() {
        wakeTask?.cancel()
        wakeTask = nil
        scheduledFireAt = nil
    }

    private func startWakeIfNeeded(
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) {
        if burstExhausted {
            wakeTask?.cancel()
            wakeTask = nil
            scheduledFireAt = nil
            return
        }
        let nextFire = pending.values.compactMap { token -> Date? in
            guard published[token.deviceID] != token else { return nil }
            return Self.fireAt(for: token.epoch)
        }.min()
        if nextFire == scheduledFireAt, wakeTask != nil {
            return
        }
        wakeTask?.cancel()
        wakeTask = nil
        scheduledFireAt = nextFire
        guard let fireAt = nextFire else { return }
        wakeTask = Task { [clock, publish] in
            await self.runWake(fireAt: fireAt, virtualClock: virtualClock, clock: clock, publish: publish)
        }
    }

    private func runWake(
        fireAt: Date,
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) async {
        while !Task.isCancelled {
            let now = clock()
            if Task.isCancelled { return }
            if now >= fireAt {
                let finished = await publishDue(
                    now: now,
                    virtualClock: virtualClock,
                    clock: clock,
                    publish: publish
                )
                if finished || Task.isCancelled { return }
                continue
            }
            let remaining = fireAt.timeIntervalSince(now)
            let sleep = virtualClock ? min(0.02, max(remaining, 0.02)) : remaining
            try? await Task.sleep(nanoseconds: UInt64(max(sleep, 0) * 1_000_000_000))
        }
    }

    private func publishDue(
        now: Date,
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) async -> Bool {
        if Task.isCancelled { return true }
        let dueTokens = pending.values.filter { token in
            published[token.deviceID] != token && Self.fireAt(for: token.epoch) <= now
        }
        guard !dueTokens.isEmpty else {
            if !Task.isCancelled {
                startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
            }
            return true
        }
        let proven = await publish(dueTokens)
        if Task.isCancelled { return true }
        if proven.isEmpty {
            return await handleFailedBurst()
        }
        for token in proven {
            guard pending[token.deviceID] == token else { continue }
            published[token.deviceID] = token
        }
        retryAttempt = 0
        burstExhausted = false
        let remainingDue = dueTokens.contains { token in
            pending[token.deviceID] == token && published[token.deviceID] != token
        }
        if remainingDue {
            return await handleFailedBurst()
        }
        scheduledFireAt = nil
        wakeTask = nil
        startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
        return true
    }

    private func handleFailedBurst() async -> Bool {
        if retryAttempt >= Self.retryDelaysNanoseconds.count {
            burstExhausted = true
            wakeTask = nil
            scheduledFireAt = nil
            return true
        }
        let delay = Self.retryDelaysNanoseconds[retryAttempt]
        retryAttempt += 1
        try? await Task.sleep(nanoseconds: delay)
        return Task.isCancelled
    }

    private static func fireAt(for epoch: AhaKeyRuntimeDisconnectEpoch) -> Date {
        epoch.startedAt.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
    }
}
