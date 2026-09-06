import Foundation
import AhaKeyConfigShared

/// C4R6：到期发布的完整身份。消费前必须同时匹配 operation、设备与 epoch。
struct AhaKeyAbandonDeadlineToken: Equatable, Sendable {
    var operationID: AhaKeyRuntimeOperationID
    var deviceID: AhaKeyRuntimeDeviceID
    var epoch: AhaKeyRuntimeDisconnectEpoch
}

/// 完整 deadline 状态机：pending/published/wake/fireAt/retry 全部隔离在本 actor 内。
/// retry/exhaustion 按 device 隔离，A 耗尽不得停掉 B。
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
    private var retryAttemptByDevice: [AhaKeyRuntimeDeviceID: Int] = [:]
    private var exhaustedDevices: Set<AhaKeyRuntimeDeviceID> = []
    private var retryWaitDevices: Set<AhaKeyRuntimeDeviceID> = []
    private var retryGenerationByDevice: [AhaKeyRuntimeDeviceID: UInt64] = [:]
    private var retryTasks: [AhaKeyRuntimeDeviceID: Task<Void, Never>] = [:]

    func pendingToken(for deviceID: AhaKeyRuntimeDeviceID) -> AhaKeyAbandonDeadlineToken? {
        pending[deviceID]
    }

    func retryWaitContains(_ deviceID: AhaKeyRuntimeDeviceID) -> Bool {
        retryWaitDevices.contains(deviceID)
    }

    func retryTaskCount() -> Int {
        retryTasks.count
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
        resetRetry(for: token.deviceID)
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
        resetRetry(for: deviceID)
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
            resetRetry(for: deviceID)
        }
        for (deviceID, token) in next {
            pending[deviceID] = token
            if published[deviceID] != token {
                published.removeValue(forKey: deviceID)
                resetRetry(for: deviceID)
            }
        }
        startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
    }

    func noteExternalRecoveryTrigger(
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) {
        guard !pending.isEmpty else { return }
        exhaustedDevices.removeAll()
        retryAttemptByDevice.removeAll()
        retryWaitDevices.removeAll()
        invalidateAllRetryTasks()
        startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
    }

    func cancelAllAndWait() async {
        let wake = wakeTask
        wakeTask?.cancel()
        wakeTask = nil
        scheduledFireAt = nil
        pending.removeAll()
        published.removeAll()
        retryAttemptByDevice.removeAll()
        exhaustedDevices.removeAll()
        retryWaitDevices.removeAll()
        retryGenerationByDevice.removeAll()
        let retries = Array(retryTasks.values)
        retryTasks.removeAll()
        for task in retries {
            task.cancel()
        }
        await wake?.value
        for task in retries {
            await task.value
        }
    }

    func cancelWake() {
        wakeTask?.cancel()
        wakeTask = nil
        scheduledFireAt = nil
    }

    private func resetRetry(for deviceID: AhaKeyRuntimeDeviceID) {
        retryAttemptByDevice[deviceID] = 0
        exhaustedDevices.remove(deviceID)
        retryWaitDevices.remove(deviceID)
        invalidateRetryTask(for: deviceID)
    }

    private func invalidateRetryTask(for deviceID: AhaKeyRuntimeDeviceID) {
        retryGenerationByDevice[deviceID, default: 0] &+= 1
        retryTasks[deviceID]?.cancel()
        retryTasks[deviceID] = nil
    }

    private func invalidateAllRetryTasks() {
        for deviceID in Set(retryTasks.keys).union(retryGenerationByDevice.keys) {
            retryGenerationByDevice[deviceID, default: 0] &+= 1
        }
        let retries = Array(retryTasks.values)
        retryTasks.removeAll()
        for task in retries {
            task.cancel()
        }
    }

    private func startWakeIfNeeded(
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) {
        let nextFire = pending.values.compactMap { token -> Date? in
            guard published[token.deviceID] != token else { return nil }
            guard !exhaustedDevices.contains(token.deviceID) else { return nil }
            guard !retryWaitDevices.contains(token.deviceID) else { return nil }
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
                await publishDue(
                    now: now,
                    virtualClock: virtualClock,
                    clock: clock,
                    publish: publish
                )
                return
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
    ) async {
        if Task.isCancelled { return }
        let dueTokens = pending.values.filter { token in
            published[token.deviceID] != token
                && !exhaustedDevices.contains(token.deviceID)
                && !retryWaitDevices.contains(token.deviceID)
                && Self.fireAt(for: token.epoch) <= now
        }
        guard !dueTokens.isEmpty else {
            if !Task.isCancelled {
                startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
            }
            return
        }
        let proven = await publish(dueTokens)
        if Task.isCancelled { return }
        var failed: [AhaKeyRuntimeDeviceID] = []
        for token in dueTokens {
            if proven.contains(token), pending[token.deviceID] == token {
                published[token.deviceID] = token
                resetRetry(for: token.deviceID)
            } else if pending[token.deviceID] == token, published[token.deviceID] != token {
                failed.append(token.deviceID)
            }
        }
        for deviceID in failed {
            scheduleDeviceRetry(
                deviceID,
                virtualClock: virtualClock,
                clock: clock,
                publish: publish
            )
        }
        scheduledFireAt = nil
        wakeTask = nil
        startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
    }

    private func scheduleDeviceRetry(
        _ deviceID: AhaKeyRuntimeDeviceID,
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) {
        let attempt = retryAttemptByDevice[deviceID] ?? 0
        if attempt >= Self.retryDelaysNanoseconds.count {
            exhaustedDevices.insert(deviceID)
            retryWaitDevices.remove(deviceID)
            invalidateRetryTask(for: deviceID)
            return
        }
        guard let token = pending[deviceID] else { return }
        retryAttemptByDevice[deviceID] = attempt + 1
        retryWaitDevices.insert(deviceID)
        retryTasks[deviceID]?.cancel()
        let generation = retryGenerationByDevice[deviceID, default: 0] &+ 1
        retryGenerationByDevice[deviceID] = generation
        let delay = Self.retryDelaysNanoseconds[attempt]
        let task = Task {
            try? await Task.sleep(nanoseconds: delay)
            await self.finishDeviceRetry(
                token,
                generation: generation,
                virtualClock: virtualClock,
                clock: clock,
                publish: publish
            )
        }
        retryTasks[deviceID] = task
    }

    private func finishDeviceRetry(
        _ token: AhaKeyAbandonDeadlineToken,
        generation: UInt64,
        virtualClock: Bool,
        clock: @escaping @Sendable () -> Date,
        publish: @escaping @Sendable ([AhaKeyAbandonDeadlineToken]) async -> [AhaKeyAbandonDeadlineToken]
    ) async {
        guard retryGenerationByDevice[token.deviceID] == generation else { return }
        retryWaitDevices.remove(token.deviceID)
        retryTasks[token.deviceID] = nil
        guard pending[token.deviceID] == token, published[token.deviceID] != token else { return }
        guard !exhaustedDevices.contains(token.deviceID) else { return }
        startWakeIfNeeded(virtualClock: virtualClock, clock: clock, publish: publish)
    }

    private static func fireAt(for epoch: AhaKeyRuntimeDisconnectEpoch) -> Date {
        epoch.startedAt.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
    }
}
