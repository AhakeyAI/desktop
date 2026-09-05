import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyRuntimeContractTests: XCTestCase {
    func testPackageRejectsUnsafeOrDuplicateResourceIdentifiers() throws {
        let digest = String(repeating: "a", count: 64)
        XCTAssertThrowsError(
            try AhaKeyConfigurationResource(
                logicalIdentifier: "../image.gif",
                sha256: digest,
                byteCount: 10,
                mediaType: "image/gif"
            )
        )

        let resource = try AhaKeyConfigurationResource(
            logicalIdentifier: "mode1-setA-working",
            sha256: digest,
            byteCount: 10,
            mediaType: "image/gif"
        )
        XCTAssertThrowsError(
            try package(resources: [resource, resource])
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .duplicateResourceIdentifier)
        }
    }

    func testCodableDecodingCannotBypassContractValidation() throws {
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyRuntimeDeviceID.self, from: Data("\"   \"".utf8))
        )

        let invalidResource = Data(
            """
            {"logicalIdentifier":"../escape","sha256":"bad","byteCount":1,"mediaType":"image/gif"}
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyConfigurationResource.self, from: invalidResource)
        )

        let validPackage = try package()
        let encoded = try JSONEncoder().encode(validPackage)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["desiredConfiguration"] = ""
        let invalidPackage = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyConfigurationPackage.self, from: invalidPackage)
        )
    }

    func testApplyIsIdempotentButRejectsOperationIDReuseWithDifferentContent() async throws {
        let adapter = try makeAdapter()
        let operationID = AhaKeyRuntimeOperationID()
        let first = try package(operationID: operationID, desiredConfiguration: Data("one".utf8))

        let firstAcceptance = try await adapter.apply(first)
        let repeatedAcceptance = try await adapter.apply(first)
        XCTAssertEqual(firstAcceptance, operationID)
        XCTAssertEqual(repeatedAcceptance, operationID)

        let conflicting = try package(operationID: operationID, desiredConfiguration: Data("two".utf8))
        do {
            _ = try await adapter.apply(conflicting)
            XCTFail("Expected operation identifier conflict")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .operationIdentifierConflict)
        }
    }

    func testApplyRejectsStaleRevisionAndWrongTargetDevice() async throws {
        let adapter = try makeAdapter(revision: 3)

        do {
            _ = try await adapter.apply(package(baseRevision: 2))
            XCTFail("Expected stale revision")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimeContractError,
                .staleConfigurationRevision(expected: .init(3), received: .init(2))
            )
        }

        do {
            _ = try await adapter.apply(package(targetDeviceID: "OTHER", baseRevision: 3))
            XCTFail("Expected target mismatch")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .targetDeviceMismatch)
        }
    }

    func testSubscriberReceivesAcceptedOperationAndCanReplayIt() async throws {
        let adapter = try makeAdapter()
        let stream = await adapter.events(after: nil)
        let package = try package()
        _ = try await adapter.apply(package)

        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.sequence, .init(1))
        XCTAssertEqual(first?.context.operationID, package.operationID)
        XCTAssertEqual(first?.context.deviceID, package.targetDeviceID)
        XCTAssertEqual(first?.context.sessionGeneration, .init(4))
        XCTAssertEqual(first?.context.transportGeneration, .init(9))
        XCTAssertEqual(
            first?.payload,
            .operationChanged(
                AhaKeyRuntimeOperationSummary(
                    id: package.operationID,
                    targetDeviceID: package.targetDeviceID,
                    state: .accepted
                )
            )
        )

        let replay = await adapter.events(after: .init(0))
        var replayIterator = replay.makeAsyncIterator()
        let replayedEvent = try await replayIterator.next()
        XCTAssertEqual(replayedEvent, first)
    }

    func testCompletionAdvancesRevisionAndCancellationDoesNot() async throws {
        let adapter = try makeAdapter(revision: 7)
        let first = try package(baseRevision: 7)
        _ = try await adapter.apply(first)
        let cancellation = try await adapter.requestCancellation(of: first.operationID)
        let revisionAfterCancellation = try await adapter.snapshot().configurationRevision
        XCTAssertEqual(cancellation, .requested)
        XCTAssertEqual(revisionAfterCancellation, .init(7))

        let second = try package(baseRevision: 7)
        _ = try await adapter.apply(second)
        try await adapter.complete(operation: second.operationID, state: .completed)
        let completedRevision = try await adapter.snapshot().configurationRevision
        let completedCancellation = try await adapter.requestCancellation(of: second.operationID)
        XCTAssertEqual(completedRevision, .init(8))
        XCTAssertEqual(completedCancellation, .alreadyFinished)
    }

    func testPartialCompletionDoesNotConfirmTargetRevision() async throws {
        let adapter = try makeAdapter(revision: 11)
        let package = try package(baseRevision: 11)
        _ = try await adapter.apply(package)

        try await adapter.recordResumablePartial(
            operation: package.operationID,
            completedSteps: 2,
            totalSteps: 5
        )

        let snapshot = try await adapter.snapshot()
        XCTAssertEqual(snapshot.configurationRevision, .init(11))
        XCTAssertEqual(snapshot.operations.first?.state, .resumablePartial)
        XCTAssertEqual(snapshot.operations.first?.completedSteps, 2)
        XCTAssertEqual(snapshot.operations.first?.totalSteps, 5)
    }

    func testCompletedOperationCanBeReplayedIdempotentlyAfterRevisionAdvances() async throws {
        let adapter = try makeAdapter(revision: 2)
        let package = try package(baseRevision: 2)
        _ = try await adapter.apply(package)
        try await adapter.complete(operation: package.operationID, state: .completed)

        let replayedID = try await adapter.apply(package)
        let replayedSnapshot = try await adapter.snapshot()

        XCTAssertEqual(replayedID, package.operationID)
        XCTAssertEqual(replayedSnapshot.configurationRevision, .init(3))
    }

    func testPolicyKeepsRuntimeOnlyForComputerSideEnhancements() {
        XCTAssertFalse(AhaKeyRuntimePolicy().requiresPersistentRuntime)
        XCTAssertTrue(
            AhaKeyRuntimePolicy(
                aiHooks: .init(enabledTools: [.codex], approvalPolicy: .manual)
            ).requiresPersistentRuntime
        )
        XCTAssertTrue(
            AhaKeyRuntimePolicy(
                ahaType: .init(enabled: true, trigger: .f18)
            ).requiresPersistentRuntime
        )
        XCTAssertTrue(
            AhaKeyRuntimePolicy(voiceRouting: .latestActionableSession).requiresPersistentRuntime
        )
        XCTAssertFalse(AhaKeyRuntimePolicy().requiresDeviceConnection)
        XCTAssertTrue(
            AhaKeyRuntimePolicy(
                aiHooks: .init(
                    enabledTools: [.kimi],
                    approvalPolicy: .followLever(automaticPosition: .up)
                )
            ).requiresDeviceConnection
        )
        XCTAssertTrue(
            AhaKeyRuntimePolicy(
                devicePresentation: .init(ledEnabled: true, oledEnabled: false)
            ).requiresDeviceConnection
        )
    }

    func testEquivalentPolicyUpdateDoesNotPublishRuntimeState() async throws {
        let adapter = try makeAdapter()

        try await adapter.updatePolicy(.init())
        let unchangedSnapshot = try await adapter.snapshot()
        XCTAssertEqual(unchangedSnapshot.latestEventSequence, .init(0))

        let changed = AhaKeyRuntimePolicy(voiceRouting: .latestActionableSession)
        try await adapter.updatePolicy(changed)
        let changedSnapshot = try await adapter.snapshot()
        XCTAssertEqual(changedSnapshot.latestEventSequence, .init(1))
        XCTAssertEqual(changedSnapshot.policy, changed)
        XCTAssertEqual(changedSnapshot.keepAliveReasons, [.sessionRouting])
    }

    func testRuntimePolicyRoundTripPreservesTriggerApprovalRoutingAndDiagnostics() throws {
        let policy = AhaKeyRuntimePolicy(
            ahaType: .init(
                enabled: true,
                trigger: .init(hidUsage: 0x6D, modifiers: [.function])
            ),
            aiHooks: .init(
                enabledTools: [.claude, .codex, .cursor, .kimi],
                approvalPolicy: .followLever(automaticPosition: .up)
            ),
            voiceRouting: .latestActionableSession,
            devicePresentation: .init(ledEnabled: true, oledEnabled: true),
            powerProtectionEnabled: true,
            diagnostics: .init(verboseProtocolLoggingUntil: Date(timeIntervalSince1970: 1_800))
        )

        let encoded = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(AhaKeyRuntimePolicy.self, from: encoded)

        XCTAssertEqual(decoded, policy)
        XCTAssertTrue(decoded.requiresPersistentRuntime)
        XCTAssertTrue(decoded.requiresDeviceConnection)
        XCTAssertEqual(
            decoded.keepAliveReasons,
            [.ahaType, .aiHooks, .dynamicDeviceState, .sessionRouting, .powerProtection, .temporaryDiagnostics]
        )
    }

    func testSnapshotCodableRoundTripPreservesRuntimeAndDeviceDiagnostics() async throws {
        let adapter = try makeAdapter()
        let snapshot = try await adapter.snapshot()
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AhaKeyRuntimeSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.runtimeVersion, .init(major: 0, minor: 1, patch: 0, buildMetadata: "development"))
        XCTAssertEqual(decoded.permissions[.microphone], .notDetermined)
        XCTAssertEqual(decoded.devices.first?.capabilities, [.configurationV4, .usbConfiguration])
        XCTAssertEqual(decoded.devices.first?.sessionGeneration, .init(4))
        XCTAssertEqual(decoded.devices.first?.transportGeneration, .init(9))
        XCTAssertEqual(decoded.devices.first?.state.leverPosition, .middle)
        XCTAssertEqual(
            decoded.devices.first?.state.activeTaskPictureSets,
            [.init(2): .init(1)]
        )
    }

    func testStructuredDiagnosticAndSecurityEventsRoundTrip() throws {
        let events = [
            AhaKeyRuntimeEvent(
                sequence: .init(1),
                payload: .diagnostic(.init(code: try .init("transport-timeout"), severity: .warning))
            ),
            AhaKeyRuntimeEvent(
                sequence: .init(2),
                payload: .security(.init(code: try .init("hook-rate-limited"), severity: .error))
            ),
        ]

        let encoded = try JSONEncoder().encode(events)
        XCTAssertEqual(try JSONDecoder().decode([AhaKeyRuntimeEvent].self, from: encoded), events)
    }

    func testPermanentFailureStatesDistinguishWhetherDeviceWasModified() throws {
        XCTAssertTrue(AhaKeyRuntimeOperationState.failedWithoutWrites.isTerminal)
        XCTAssertTrue(AhaKeyRuntimeOperationState.failedWithPartialCommit.isTerminal)
        XCTAssertTrue(AhaKeyRuntimeOperationState.resumablePartial.isRecoveryCandidate)
        XCTAssertFalse(AhaKeyRuntimeOperationState.resumablePartial.isTerminal)
        let legacyWireValue = Data("\"partiallyCompleted\"".utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(AhaKeyRuntimeOperationState.self, from: legacyWireValue),
            .resumablePartial
        )
        XCTAssertEqual(
            try JSONEncoder().encode(AhaKeyRuntimeOperationState.resumablePartial),
            legacyWireValue
        )
        XCTAssertNotEqual(
            AhaKeyRuntimeOperationState.failedWithoutWrites,
            AhaKeyRuntimeOperationState.failedWithPartialCommit
        )
    }

    func testOperationSummaryOldJSONDecodesNewFieldsAsNil() throws {
        // C-2R1：旧→新必须用 literal v1.1 JSON，不能靠同提交里新声明的 encoder 形状。
        let oldJSON = Data("""
        {"id":{"rawValue":"00000000-0000-4000-8000-000000000001"},"targetDeviceID":"TEST-DEVICE","state":"running","completedSteps":0,"totalSteps":7}
        """.utf8)
        let decoded = try JSONDecoder().decode(AhaKeyRuntimeOperationSummary.self, from: oldJSON)
        XCTAssertEqual(decoded.id.rawValue, UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
        XCTAssertEqual(decoded.targetDeviceID.rawValue, "TEST-DEVICE")
        XCTAssertEqual(decoded.state, .running)
        XCTAssertEqual(decoded.completedSteps, 0)
        XCTAssertEqual(decoded.totalSteps, 7)
        XCTAssertNil(decoded.messageCode)
        XCTAssertNil(decoded.completedBytes)
        XCTAssertNil(decoded.totalBytes)
        XCTAssertNil(decoded.currentStepID)
        XCTAssertNil(decoded.failureContext)
        let object = try JSONSerialization.jsonObject(with: oldJSON) as! [String: Any]
        XCTAssertNil(object["completedBytes"])
        XCTAssertNil(object["totalBytes"])
        XCTAssertNil(object["currentStepID"])
        XCTAssertNil(object["failureContext"])
    }

    func testOperationSummaryNewJSONIsIgnoredByFrozenV11Decoder() throws {
        let newJSON = Data("""
        {"id":{"rawValue":"00000000-0000-4000-8000-000000000002"},"targetDeviceID":"TEST-DEVICE","state":"running","completedSteps":1,"totalSteps":7,"completedBytes":1200,"totalBytes":4800,"currentStepID":"resource:mode1-set0-working","messageCode":"configuration.device-rejected","failureContext":{"failedStepID":"base:mode:0","opcode":151,"deviceStatus":3}}
        """.utf8)
        let frozen = try JSONDecoder().decode(FrozenV11OperationSummary.self, from: newJSON)
        XCTAssertEqual(frozen.id.rawValue, UUID(uuidString: "00000000-0000-4000-8000-000000000002"))
        XCTAssertEqual(frozen.targetDeviceID.rawValue, "TEST-DEVICE")
        XCTAssertEqual(frozen.state, .running)
        XCTAssertEqual(frozen.completedSteps, 1)
        XCTAssertEqual(frozen.totalSteps, 7)
        XCTAssertEqual(frozen.messageCode?.rawValue, "configuration.device-rejected")
        XCTAssertEqual(try JSONDecoder().decode(AhaKeyRuntimeInterfaceVersion.self, from: Data("{\"major\":1,\"minor\":1}".utf8)), .current)
        let current = try JSONDecoder().decode(AhaKeyRuntimeOperationSummary.self, from: newJSON)
        XCTAssertEqual(current.failureContext?.failedStepID?.rawValue, "base:mode:0")
        XCTAssertEqual(current.failureContext?.opcode, 0x97)
        XCTAssertEqual(current.failureContext?.deviceStatus, 3)
    }

    func testOperationSummaryOmitsNilByteKeys() throws {
        let summary = AhaKeyRuntimeOperationSummary(
            id: AhaKeyRuntimeOperationID(),
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            state: .accepted
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as! [String: Any]
        XCTAssertNil(object["completedBytes"])
        XCTAssertNil(object["totalBytes"])
        XCTAssertNil(object["currentStepID"])
        XCTAssertNil(object["failureContext"])
        XCTAssertNil(object["messageCode"])
    }

    func testOperationSummaryOmitsNilFailureContextInnerKeys() throws {
        let summary = AhaKeyRuntimeOperationSummary(
            id: AhaKeyRuntimeOperationID(),
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            state: .failedWithoutWrites,
            messageCode: .configurationDeviceRejected,
            failureContext: AhaKeyRuntimeOperationFailureContext(
                failedStepID: try AhaKeyRuntimeStepIdentifier("base:mode:0")
            )
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as! [String: Any]
        let context = try XCTUnwrap(object["failureContext"] as? [String: Any])
        XCTAssertEqual(context["failedStepID"] as? String, "base:mode:0")
        XCTAssertNil(context["opcode"])
        XCTAssertNil(context["deviceStatus"])
    }

    private func makeAdapter(revision: UInt64 = 0) throws -> AhaKeyInMemoryRuntimeAdapter {
        let id = try AhaKeyRuntimeDeviceID("505c")
        let device = AhaKeyRuntimeDeviceSnapshot(
            id: id,
            displayName: "AhaKey 505C",
            protocolState: .currentReady,
            preferredTransport: .usb,
            usbAttached: true,
            bluetoothConnected: false,
            capabilities: [.configurationV4, .usbConfiguration],
            sessionGeneration: .init(4),
            transportGeneration: .init(9),
            state: .init(
                batteryLevel: try .init(85),
                workMode: .init(2),
                lightMode: .init(1),
                leverPosition: .middle,
                brightness: try .init(35),
                firmwareVersion: "3.0",
                activeTaskPictureSets: [.init(2): .init(1)]
            )
        )
        return AhaKeyInMemoryRuntimeAdapter(
            snapshot: AhaKeyRuntimeSnapshot(
                lifecycleState: .running,
                devices: [device],
                activeDeviceID: id,
                configurationRevision: .init(revision),
                operations: [],
                policy: .init(),
                permissions: .init(states: [.microphone: .notDetermined]),
                keepAliveReasons: [],
                latestEventSequence: .init(0)
            )
        )
    }

    func testLegacyPackageJSONOmitsPageOperationAndRoundTrips() throws {
        let original = try package()
        let encoded = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["pageOperation"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        let decoded = try JSONDecoder().decode(AhaKeyConfigurationPackage.self, from: encoded)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.pageOperation)
        XCTAssertEqual(decoded.schemaVersion, AhaKeyConfigurationPackage.currentSchemaVersion)
    }

    func testPageScopedPackageRoundTripsAndRejectsIncompleteSchema2() throws {
        let assembled = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: screenStatusPlan(),
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("505C"),
            baseRevision: .init(0),
            baseObjectFingerprint: try AhaKeyRuntimeObjectFingerprint.hashing(Data("base".utf8)),
            verifiedResources: []
        )
        XCTAssertEqual(assembled.schemaVersion, AhaKeyConfigurationPackage.pageScopedSchemaVersion)
        XCTAssertNotNil(assembled.pageOperation)
        let encoded = try JSONEncoder().encode(assembled)
        let decoded = try JSONDecoder().decode(AhaKeyConfigurationPackage.self, from: encoded)
        XCTAssertEqual(decoded, assembled)
        XCTAssertEqual(decoded.pageOperation?.pageScope, .screen(modeSlot: 0))
        XCTAssertEqual(
            decoded.pageOperation?.fieldMask,
            [.screenStatusLine(modeSlot: 0)]
        )

        XCTAssertThrowsError(
            try AhaKeyConfigurationPackage(
                schemaVersion: AhaKeyConfigurationPackage.pageScopedSchemaVersion,
                targetDeviceID: AhaKeyRuntimeDeviceID("505C"),
                baseRevision: .init(0),
                desiredConfiguration: Data("configuration".utf8),
                resources: []
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .pageOperationIncomplete)
        }
    }

    func testPageOperationDoesNotRewriteMismatchedSchema() throws {
        let contract = try AhaKeyRuntimePageOperationContract.assemble(
            plan: screenStatusPlan(),
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("505C"),
            baseObjectFingerprint: try AhaKeyRuntimeObjectFingerprint.hashing(Data("base".utf8)),
            verifiedResources: []
        )
        XCTAssertThrowsError(
            try AhaKeyConfigurationPackage(
                schemaVersion: 0,
                targetDeviceID: AhaKeyRuntimeDeviceID("505C"),
                baseRevision: .init(0),
                desiredConfiguration: Data("configuration".utf8),
                resources: [],
                pageOperation: contract
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .unsupportedConfigurationSchema(0))
        }
        XCTAssertThrowsError(
            try AhaKeyConfigurationPackage(
                schemaVersion: 1,
                targetDeviceID: AhaKeyRuntimeDeviceID("505C"),
                baseRevision: .init(0),
                desiredConfiguration: Data("configuration".utf8),
                resources: [],
                pageOperation: contract
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .invalidSchemaVersion)
        }
        XCTAssertThrowsError(
            try AhaKeyConfigurationPackage(
                schemaVersion: 999,
                targetDeviceID: AhaKeyRuntimeDeviceID("505C"),
                baseRevision: .init(0),
                desiredConfiguration: Data("configuration".utf8),
                resources: [],
                pageOperation: contract
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .unsupportedConfigurationSchema(999))
        }
    }

    func testTypedRuntimeFactsRejectUnknownKeysAndWrongBaselineShape() throws {
        let device = try AhaKeyRuntimeDeviceID("TEST-DEVICE")
        let lease = try AhaKeyRuntimeAuthoritativeWriterLease(1)
        let version = AhaKeyRuntimeAuthoritativeVersion(
            deviceID: device,
            writerLease: lease,
            sessionGeneration: .init(1),
            transportGeneration: .init(0),
            sourceRevision: .first,
            sourceDigest: try AhaKeyRuntimeObjectFingerprint.hashing(Data("authority".utf8))
        )
        try assertCorruptRuntimeFact(version, extraKey: "unexpected")

        let identity = AhaKeyRuntimeConnectionIdentity(
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(0),
            writerLease: lease
        )
        try assertCorruptRuntimeFact(identity, extraKey: "unexpected")

        let epoch = AhaKeyRuntimeDisconnectEpoch(identity: identity, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try assertCorruptRuntimeFact(epoch, extraKey: "unexpected")

        try assertCorruptRuntimeFact(AhaKeyRuntimeBaselineValue.text("hello"), extraKey: "integer")
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimeBaselineValue.self,
                from: Data("{\"text\":\"a\",\"integer\":1}".utf8)
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }

        let asset = AhaKeyRuntimeBaselineValue.taskAsset(
            sha256: try AhaKeySHA256Digest("03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"),
            byteCount: 4,
            mediaType: try AhaKeyMediaType("image/gif"),
            framesPerSecond: 10,
            declaredFrameCount: 1
        )
        let encodedAsset = try JSONEncoder().encode(asset)
        var assetObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedAsset) as? [String: Any])
        var nested = try XCTUnwrap(assetObject["taskAsset"] as? [String: Any])
        nested["extra"] = "nope"
        assetObject["taskAsset"] = nested
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimeBaselineValue.self,
                from: try JSONSerialization.data(withJSONObject: assetObject)
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }
    }

    private func assertCorruptRuntimeFact<T: Codable>(_ value: T, extraKey: String) throws {
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object[extraKey] = true
        XCTAssertThrowsError(
            try JSONDecoder().decode(T.self, from: try JSONSerialization.data(withJSONObject: object))
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }
    }

    func testPageScopedPackageRejectsDeviceMismatch() throws {
        let contract = try AhaKeyRuntimePageOperationContract.assemble(
            plan: screenStatusPlan(),
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-A"),
            baseObjectFingerprint: try AhaKeyRuntimeObjectFingerprint.hashing(Data("base".utf8)),
            verifiedResources: []
        )
        XCTAssertThrowsError(
            try AhaKeyConfigurationPackage(
                schemaVersion: AhaKeyConfigurationPackage.pageScopedSchemaVersion,
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-B"),
                baseRevision: .init(0),
                desiredConfiguration: Data("configuration".utf8),
                resources: [],
                pageOperation: contract
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .pageOperationDeviceMismatch)
        }
    }

    func testSameOperationIDDifferentPageContentIsNotEqual() throws {
        let operationID = AhaKeyRuntimeOperationID()
        let first = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: screenStatusPlan(statusLine: "one"),
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("505C"),
            baseRevision: .init(0),
            baseObjectFingerprint: try AhaKeyRuntimeObjectFingerprint.hashing(Data("base".utf8)),
            verifiedResources: [],
            operationID: operationID
        )
        let second = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: screenStatusPlan(statusLine: "two"),
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("505C"),
            baseRevision: .init(0),
            baseObjectFingerprint: try AhaKeyRuntimeObjectFingerprint.hashing(Data("base".utf8)),
            verifiedResources: [],
            operationID: operationID
        )
        XCTAssertEqual(first.operationID, second.operationID)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first.desiredConfiguration, second.desiredConfiguration)
    }

    private func screenStatusPlan(statusLine: String = "hello") -> AhaKeyStudioScopedWritePlan {
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        return AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [field: .text(statusLine)],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            statusLine: statusLine
        )
    }

    private func package(
        operationID: AhaKeyRuntimeOperationID = .init(),
        targetDeviceID: String = "505C",
        baseRevision: UInt64 = 0,
        desiredConfiguration: Data = Data("configuration".utf8),
        resources: [AhaKeyConfigurationResource] = []
    ) throws -> AhaKeyConfigurationPackage {
        try AhaKeyConfigurationPackage(
            operationID: operationID,
            targetDeviceID: AhaKeyRuntimeDeviceID(targetDeviceID),
            baseRevision: .init(baseRevision),
            desiredConfiguration: desiredConfiguration,
            resources: resources
        )
    }
}

/// 冻结的 v1.1 summary 形状：没有字节进度键。用于证明新 payload 可被旧解码器忽略多余键。
private struct FrozenV11OperationSummary: Codable, Equatable {
    let id: AhaKeyRuntimeOperationID
    let targetDeviceID: AhaKeyRuntimeDeviceID
    let state: AhaKeyRuntimeOperationState
    let completedSteps: UInt32
    let totalSteps: UInt32
    let messageCode: AhaKeyRuntimeEventCode?
}
