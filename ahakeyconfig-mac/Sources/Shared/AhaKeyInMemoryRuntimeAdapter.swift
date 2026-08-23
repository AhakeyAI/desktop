import Foundation

/// Contract-test adapter for Studio and Runtime development. It deliberately models
/// acceptance, event replay, optimistic revision checks and cancellation, but performs no I/O.
public actor AhaKeyInMemoryRuntimeAdapter: AhaKeyRuntimeClient {
    private var currentSnapshot: AhaKeyRuntimeSnapshot
    private var acceptedPackages: [AhaKeyRuntimeOperationID: AhaKeyConfigurationPackage] = [:]
    private var retainedEvents: [AhaKeyRuntimeEvent] = []
    private var eventContinuations: [UUID: AsyncThrowingStream<AhaKeyRuntimeEvent, Error>.Continuation] = [:]
    private let eventRetentionLimit: Int

    public init(snapshot: AhaKeyRuntimeSnapshot, eventRetentionLimit: Int = 256) {
        currentSnapshot = snapshot
        self.eventRetentionLimit = max(1, eventRetentionLimit)
    }

    public func snapshot() async throws -> AhaKeyRuntimeSnapshot {
        currentSnapshot
    }

    public func events(
        after sequence: AhaKeyRuntimeEventSequence?
    ) async -> AsyncThrowingStream<AhaKeyRuntimeEvent, Error> {
        let subscriberID = UUID()
        var capturedContinuation: AsyncThrowingStream<AhaKeyRuntimeEvent, Error>.Continuation?
        let stream = AsyncThrowingStream<AhaKeyRuntimeEvent, Error> { continuation in
            capturedContinuation = continuation
        }
        guard let continuation = capturedContinuation else { return stream }

        if let sequence,
           let firstRetained = retainedEvents.first?.sequence,
           sequence.rawValue + 1 < firstRetained.rawValue {
            continuation.yield(
                AhaKeyRuntimeEvent(
                    sequence: currentSnapshot.latestEventSequence,
                    payload: .snapshotInvalidated
                )
            )
        } else {
            for event in retainedEvents where sequence == nil || event.sequence > sequence! {
                continuation.yield(event)
            }
        }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(subscriberID) }
        }
        eventContinuations[subscriberID] = continuation
        return stream
    }

    public func apply(_ package: AhaKeyConfigurationPackage) async throws -> AhaKeyRuntimeOperationID {
        guard currentSnapshot.lifecycleState == .running else {
            throw AhaKeyRuntimeContractError.runtimeUnavailable
        }
        if let existing = acceptedPackages[package.operationID] {
            guard existing == package else {
                throw AhaKeyRuntimeContractError.operationIdentifierConflict
            }
            return package.operationID
        }
        guard currentSnapshot.supportedConfigurationSchemaVersions.contains(package.schemaVersion) else {
            throw AhaKeyRuntimeContractError.unsupportedConfigurationSchema(package.schemaVersion)
        }
        guard currentSnapshot.activeDeviceID == package.targetDeviceID else {
            throw AhaKeyRuntimeContractError.targetDeviceMismatch
        }
        guard currentSnapshot.configurationRevision == package.baseRevision else {
            throw AhaKeyRuntimeContractError.staleConfigurationRevision(
                expected: currentSnapshot.configurationRevision,
                received: package.baseRevision
            )
        }
        acceptedPackages[package.operationID] = package
        let summary = AhaKeyRuntimeOperationSummary(
            id: package.operationID,
            targetDeviceID: package.targetDeviceID,
            state: .accepted
        )
        replaceOperation(summary)
        publish(.operationChanged(summary), context: eventContext(for: summary))
        return package.operationID
    }

    public func requestCancellation(
        of operation: AhaKeyRuntimeOperationID
    ) async throws -> AhaKeyRuntimeCancellationDisposition {
        guard let summary = currentSnapshot.operations.first(where: { $0.id == operation }) else {
            return .notFound
        }
        guard !summary.state.isTerminal else { return .alreadyFinished }
        let updated = AhaKeyRuntimeOperationSummary(
            id: summary.id,
            targetDeviceID: summary.targetDeviceID,
            state: .cancellationRequested,
            completedSteps: summary.completedSteps,
            totalSteps: summary.totalSteps,
            messageCode: summary.messageCode
        )
        replaceOperation(updated)
        publish(.operationChanged(updated), context: eventContext(for: updated))
        return .requested
    }

    public func updatePolicy(_ policy: AhaKeyRuntimePolicy) async throws {
        guard policy != currentSnapshot.policy else { return }
        rebuildSnapshot(policy: policy, keepAliveReasons: policy.keepAliveReasons)
        publish(.policyChanged(policy))
    }

    /// Test-only execution hook used to model the Runtime confirming a terminal result.
    public func complete(
        operation: AhaKeyRuntimeOperationID,
        state: AhaKeyRuntimeOperationState,
        completedSteps: UInt32? = nil,
        totalSteps: UInt32? = nil,
        messageCode: AhaKeyRuntimeEventCode? = nil
    ) throws {
        guard state.isTerminal else { throw AhaKeyInMemoryRuntimeAdapterError.nonTerminalCompletion }
        guard let summary = currentSnapshot.operations.first(where: { $0.id == operation }) else {
            throw AhaKeyInMemoryRuntimeAdapterError.operationNotFound
        }
        let resolvedTotalSteps = totalSteps ?? summary.totalSteps
        let resolvedCompletedSteps = completedSteps ?? resolvedTotalSteps
        guard resolvedCompletedSteps <= resolvedTotalSteps else {
            throw AhaKeyInMemoryRuntimeAdapterError.invalidStepProgress
        }
        let updated = AhaKeyRuntimeOperationSummary(
            id: summary.id,
            targetDeviceID: summary.targetDeviceID,
            state: state,
            completedSteps: resolvedCompletedSteps,
            totalSteps: resolvedTotalSteps,
            messageCode: messageCode
        )
        replaceOperation(updated)
        if state == .completed {
            rebuildSnapshot(
                configurationRevision: AhaKeyConfigurationRevision(
                    currentSnapshot.configurationRevision.rawValue + 1
                )
            )
        }
        publish(.operationChanged(updated), context: eventContext(for: updated))
    }

    public func recordResumablePartial(
        operation: AhaKeyRuntimeOperationID,
        completedSteps: UInt32,
        totalSteps: UInt32,
        messageCode: AhaKeyRuntimeEventCode? = nil
    ) throws {
        guard completedSteps < totalSteps else {
            throw AhaKeyInMemoryRuntimeAdapterError.invalidStepProgress
        }
        guard let summary = currentSnapshot.operations.first(where: { $0.id == operation }) else {
            throw AhaKeyInMemoryRuntimeAdapterError.operationNotFound
        }
        let updated = AhaKeyRuntimeOperationSummary(
            id: summary.id,
            targetDeviceID: summary.targetDeviceID,
            state: .resumablePartial,
            completedSteps: completedSteps,
            totalSteps: totalSteps,
            messageCode: messageCode
        )
        replaceOperation(updated)
        publish(.operationChanged(updated), context: eventContext(for: updated))
    }

    private func replaceOperation(_ operation: AhaKeyRuntimeOperationSummary) {
        var operations = currentSnapshot.operations.filter { $0.id != operation.id }
        operations.append(operation)
        rebuildSnapshot(operations: operations)
    }

    private func eventContext(for operation: AhaKeyRuntimeOperationSummary) -> AhaKeyRuntimeEventContext {
        let device = currentSnapshot.devices.first { $0.id == operation.targetDeviceID }
        return AhaKeyRuntimeEventContext(
            operationID: operation.id,
            deviceID: operation.targetDeviceID,
            sessionGeneration: device?.sessionGeneration,
            transportGeneration: device?.transportGeneration
        )
    }

    private func publish(
        _ payload: AhaKeyRuntimeEventPayload,
        context: AhaKeyRuntimeEventContext = .init()
    ) {
        let sequence = AhaKeyRuntimeEventSequence(currentSnapshot.latestEventSequence.rawValue + 1)
        let event = AhaKeyRuntimeEvent(sequence: sequence, context: context, payload: payload)
        retainedEvents.append(event)
        if retainedEvents.count > eventRetentionLimit {
            retainedEvents.removeFirst(retainedEvents.count - eventRetentionLimit)
        }
        rebuildSnapshot(latestEventSequence: sequence)
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func rebuildSnapshot(
        configurationRevision: AhaKeyConfigurationRevision? = nil,
        operations: [AhaKeyRuntimeOperationSummary]? = nil,
        policy: AhaKeyRuntimePolicy? = nil,
        permissions: AhaKeyRuntimePermissionSnapshot? = nil,
        keepAliveReasons: Set<AhaKeyRuntimeKeepAliveReason>? = nil,
        latestEventSequence: AhaKeyRuntimeEventSequence? = nil
    ) {
        currentSnapshot = AhaKeyRuntimeSnapshot(
            runtimeVersion: currentSnapshot.runtimeVersion,
            interfaceVersion: currentSnapshot.interfaceVersion,
            supportedConfigurationSchemaVersions: currentSnapshot.supportedConfigurationSchemaVersions,
            lifecycleState: currentSnapshot.lifecycleState,
            devices: currentSnapshot.devices,
            activeDeviceID: currentSnapshot.activeDeviceID,
            configurationRevision: configurationRevision ?? currentSnapshot.configurationRevision,
            operations: operations ?? currentSnapshot.operations,
            policy: policy ?? currentSnapshot.policy,
            permissions: permissions ?? currentSnapshot.permissions,
            keepAliveReasons: keepAliveReasons ?? currentSnapshot.keepAliveReasons,
            latestEventSequence: latestEventSequence ?? currentSnapshot.latestEventSequence
        )
    }

    private func removeSubscriber(_ id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }
}

public enum AhaKeyInMemoryRuntimeAdapterError: Error, Equatable, Sendable {
    case operationNotFound
    case nonTerminalCompletion
    case invalidStepProgress
}
