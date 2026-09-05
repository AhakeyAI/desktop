import CryptoKit
import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyRuntimePageExecutionTests: XCTestCase {
    private struct AllowingResourceValidator: AhaKeyRuntimePackageAcceptanceValidator {
        func validate(
            package: AhaKeyConfigurationPackage,
            resources: [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput]
        ) throws {}
    }

    private var root: URL!
    private var store: AhaKeyRuntimePersistentStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c3b-page-exec-\(UUID().uuidString)")
        store = try! AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testPagePlanEmitsChunkBindAndLocalIdentitiesWithoutBaseMode() throws {
        let fixture = try pictureFixture(frames: 2)
        let package = try assemble(fixture, profile: .legacyStandard)
        let plan = try AhaKeyRuntimePageSemantic.executionPlan(package: package, userSlotLimit: 64)
        XCTAssertEqual(plan.steps.filter { $0.identity.rawValue.hasPrefix("page:chunk:") }.count, 14)
        XCTAssertEqual(plan.steps.filter { $0.identity.rawValue.hasPrefix("page:bind:") }.count, 1)
        XCTAssertFalse(plan.identities.contains { $0.rawValue.hasPrefix("base:mode:") })
        XCTAssertFalse(plan.identities.contains { $0.rawValue.hasPrefix("resource:") })
        XCTAssertTrue(plan.steps.allSatisfy { step in
            if case .saveConfig = step.program.first { return false }
            return true
        })
        let bind = try XCTUnwrap(plan.steps.first { $0.identity.rawValue.hasPrefix("page:bind:") })
        guard case .bindLegacyTaskPicture = bind.program.first else {
            return XCTFail("Standard bind 必须是 0x93 legacy task picture")
        }
    }

    func testStandardRhinoCurrentOpcodeSequencesMatchFingerprint() throws {
        try assertOpcodeSequence(
            profile: .legacyStandard,
            context: .standard,
            expectSession: false,
            expectLegacyBind: true
        )
        try assertOpcodeSequence(
            profile: .rhinoDualSet(sessionUploadAdvertised: true),
            context: .parsed(rhinoSessionCaps()),
            expectSession: true,
            expectLegacyBind: false
        )
        try assertOpcodeSequence(
            profile: .currentSessionCapable,
            context: .parsed(currentCaps()),
            expectSession: true,
            expectLegacyBind: false
        )
    }

    func testEngineResumeSkipsConfirmedPageChunks() throws {
        let fixture = try pictureFixture(frames: 1)
        let package = try assemble(fixture, profile: .legacyStandard)
        let plan = try AhaKeyRuntimePageSemantic.executionPlan(package: package, userSlotLimit: 64)
        let record = AhaKeyRuntimePersistedTransaction(
            operationID: package.operationID,
            package: package,
            state: .resumablePartial,
            completedSteps: 1,
            totalSteps: UInt32(plan.identities.count),
            messageCode: nil
        )
        let actions = AhaKeyConfigurationTransactionEngine.decide(
            event: .start,
            record: record,
            confirmedSteps: [plan.identities[0]],
            allSteps: plan.identities
        )
        XCTAssertEqual(actions, [.persistState(.running), .executeStep(plan.identities[1])])
    }

    func testWrongDeviceProfileAndBaseCASFailClosedWithZeroWrites() async throws {
        let wrongDevicePackage = try statusPackage(device: "DEV-A", operation: .init(), seed: "device")
        var executed: [String] = []
        let wrongDevice = try await runPage(
            wrongDevicePackage,
            context: .standard,
            preconditions: AhaKeyRuntimePageExecutionPreconditions(
                deviceID: AhaKeyRuntimeDeviceID("DEV-B"),
                profile: .legacyStandard,
                baseObjectFingerprint: try baseFingerprint()
            )
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(wrongDevice, .failedWithoutWrites)
        XCTAssertEqual(executed, [])

        let wrongProfilePackage = try statusPackage(device: "DEV-A", operation: .init(), seed: "profile")
        executed.removeAll()
        let wrongProfile = try await runPage(
            wrongProfilePackage,
            context: .parsed(currentCaps()),
            preconditions: AhaKeyRuntimePageExecutionPreconditions(
                deviceID: AhaKeyRuntimeDeviceID("DEV-A"),
                profile: .currentSessionCapable,
                baseObjectFingerprint: try baseFingerprint()
            )
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(wrongProfile, .failedWithoutWrites)
        XCTAssertEqual(executed, [])

        let wrongCASPackage = try statusPackage(device: "DEV-A", operation: .init(), seed: "cas")
        executed.removeAll()
        let wrongCAS = try await runPage(
            wrongCASPackage,
            context: .standard,
            preconditions: AhaKeyRuntimePageExecutionPreconditions(
                deviceID: AhaKeyRuntimeDeviceID("DEV-A"),
                profile: .legacyStandard,
                baseObjectFingerprint: try baseFingerprint("other-object")
            )
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(wrongCAS, .failedWithoutWrites)
        XCTAssertEqual(executed, [])
        let baseline = try await store.syncBaseline(for: AhaKeyRuntimeDeviceID("DEV-A"))
        XCTAssertNil(baseline)
    }

    func testBaseCASChangeAfterFirstConfirmDoesNotBlockResume() async throws {
        let fixture = try pictureFixture(frames: 1)
        let package = try assemble(fixture, profile: .legacyStandard, device: "DEV-A")
        let files = try writeResources(fixture)
        var first = true
        let paused = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: matchingPreconditions(package, profile: .legacyStandard)
        ) { _ in
            if first {
                first = false
                return .success
            }
            return .retryableFailure
        }
        XCTAssertEqual(paused, .resumablePartial)
        let confirmed = try await store.confirmedSteps(for: package.operationID)
        XCTAssertEqual(confirmed.count, 1)

        var resumed: [String] = []
        let completed = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: AhaKeyRuntimePageExecutionPreconditions(
                deviceID: package.targetDeviceID,
                profile: .legacyStandard,
                baseObjectFingerprint: try baseFingerprint("mutated-after-first-write")
            )
        ) { step in
            resumed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(completed, .completed)
        XCTAssertFalse(resumed.contains(confirmed[0].rawValue), "已确认 chunk 不得重发")
        XCTAssertFalse(resumed.contains { $0.hasPrefix("base:mode:") })
    }

    func testSameDeviceFIFOBlocksNonHeadAndIndependentDevicesProceed() async throws {
        let head = try statusPackage(device: "DEV-A", operation: .init(), seed: "head")
        let blocked = try statusPackage(device: "DEV-A", operation: .init(), seed: "blocked")
        let other = try statusPackage(device: "DEV-B", operation: .init(), seed: "other")
        var first = true
        let paused = try await runPage(
            head,
            context: .standard,
            preconditions: matchingPreconditions(head, profile: .legacyStandard)
        ) { _ in
            if first {
                first = false
                return .retryableFailure
            }
            return .success
        }
        XCTAssertEqual(paused, .paused)

        var blockedExecuted: [String] = []
        let blockedState = try await runPage(
            blocked,
            context: .standard,
            preconditions: matchingPreconditions(blocked, profile: .legacyStandard)
        ) { step in
            blockedExecuted.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(blockedState, .accepted)
        XCTAssertEqual(blockedExecuted, [])

        var otherExecuted: [String] = []
        let otherState = try await runPage(
            other,
            context: .standard,
            preconditions: matchingPreconditions(other, profile: .legacyStandard)
        ) { step in
            otherExecuted.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(otherState, .completed)
        XCTAssertFalse(otherExecuted.isEmpty)
    }

    func testQueuedPageOperationCanBeRemovedWithoutWrites() async throws {
        let package = try statusPackage()
        try await store.accept(package, resourceFiles: [:])
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        try await runner.requestCancel(operationID: package.operationID)
        let settled = try await runner.settleCancellation(operationID: package.operationID)
        XCTAssertEqual(settled, .failedWithoutWrites)
        let record = try await store.transaction(package.operationID)
        XCTAssertEqual(record?.state, .failedWithoutWrites)
        let noSteps = try await store.confirmedSteps(for: package.operationID)
        XCTAssertEqual(noSteps, [])
    }

    func testRunningAndPausedPageOperationsRefuseOrdinaryCancel() async throws {
        let fixture = try pictureFixture(frames: 1)
        let package = try assemble(fixture, profile: .legacyStandard)
        let files = try writeResources(fixture)
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        let gate = CancelGate()
        let task = Task {
            try await self.runPage(
                package,
                files: files,
                context: .standard,
                preconditions: matchingPreconditions(package, profile: .legacyStandard),
                runner: runner
            ) { _ in
                await gate.markEntered()
                await gate.wait()
                return .success
            }
        }
        await gate.waitUntilEntered()
        do {
            try await runner.requestCancel(operationID: package.operationID)
            XCTFail("running schema=2 必须拒绝取消")
        } catch AhaKeyConfigurationCancelError.refusedWhileActive {
            let record = try await store.transaction(package.operationID)
            XCTAssertEqual(record?.state, .running)
            XCTAssertNotEqual(record?.state, .cancellationRequested)
        }
        await gate.release()
        _ = try await task.value

        var first = true
        let pausedPackage = try assemble(
            try pictureFixture(bytes: Data("gif-paused".utf8), frames: 1),
            profile: .legacyStandard,
            device: "DEV-PAUSE"
        )
        let pausedFiles = try writeResources(
            PageFixtureBox(sourceBytes: try pictureFixture(bytes: Data("gif-paused".utf8), frames: 1).sourceBytes)
        )
        let pausedState = try await runPage(
            pausedPackage,
            files: pausedFiles,
            context: .standard,
            preconditions: matchingPreconditions(pausedPackage, profile: .legacyStandard)
        ) { _ in
            if first {
                first = false
                return .retryableFailure
            }
            return .success
        }
        XCTAssertEqual(pausedState, .paused)
        do {
            try await runner.requestCancel(operationID: pausedPackage.operationID)
            XCTFail("paused schema=2 必须拒绝取消")
        } catch AhaKeyConfigurationCancelError.refusedWhileActive {}
    }

    func testDeterministicRejectStopsAtFirstErrorAndKeepsMinimalConfirm() async throws {
        let fixture = try pictureFixture(frames: 1)
        let package = try assemble(fixture, profile: .legacyStandard)
        let files = try writeResources(fixture)
        var executed: [String] = []
        let state = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: matchingPreconditions(package, profile: .legacyStandard)
        ) { step in
            executed.append(step.rawValue)
            if executed.count == 2 {
                return .failure(.init(
                    retryable: false,
                    messageCode: .configurationDeviceRejected,
                    context: .init(failedStepID: step, opcode: 0x80, deviceStatus: 3)
                ))
            }
            return .success
        }
        XCTAssertEqual(state, .failedWithPartialCommit)
        XCTAssertEqual(executed.count, 2)
        let confirmed = try await store.confirmedSteps(for: package.operationID)
        XCTAssertEqual(confirmed.count, 1)
        XCTAssertEqual(confirmed[0].rawValue, executed[0])
        let record = try await store.transaction(package.operationID)
        XCTAssertEqual(record?.messageCode, .configurationDeviceRejected)
    }

    func testPictureDisconnectResumesFromFirstUnconfirmedChunkSameStore() async throws {
        let fixture = try pictureFixture(frames: 2)
        let package = try assemble(fixture, profile: .legacyStandard)
        let files = try writeResources(fixture)
        var seen = 0
        let paused = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: matchingPreconditions(package, profile: .legacyStandard)
        ) { _ in
            seen += 1
            if seen == 4 { return .retryableFailure }
            return .success
        }
        XCTAssertEqual(paused, .resumablePartial)
        let confirmed = try await store.confirmedSteps(for: package.operationID)
        XCTAssertEqual(confirmed.count, 3)

        var resumed: [String] = []
        let reopened = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
        let completed = try await AhaKeyConfigurationTransactionRunner(store: reopened).run(
            package: package,
            resourceFiles: files,
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: matchingPreconditions(package, profile: .legacyStandard)
        ) { step in
            resumed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(completed, .completed)
        XCTAssertFalse(resumed.contains { confirmed.map(\.rawValue).contains($0) })
        XCTAssertTrue(resumed[0].hasPrefix("page:chunk:"))
    }

    func testKeyAndLocalFieldPlansStayOnMask() throws {
        let keyField = AhaKeyStudioFieldID.keyAction(modeSlot: 0, role: .approve)
        let keyPlan = AhaKeyStudioScopedWritePlan(
            pageID: .key(modeSlot: 0, role: .approve),
            fieldMask: [keyField],
            values: [keyField: .keyAction(.shortcut(try AhaKeyDesiredConfiguration.Shortcut(keyCode: 0x04)))],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false
        )
        let keyPackage = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: keyPlan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: []
        )
        let keyExec = try AhaKeyRuntimePageSemantic.executionPlan(package: keyPackage, userSlotLimit: 64)
        XCTAssertEqual(keyExec.identities.count, 1)
        XCTAssertTrue(keyExec.steps[0].writesDevice)
        guard case .setKeyShortcut(_, _, let codes) = keyExec.steps[0].program.first else {
            return XCTFail("key page 必须映射 shortcut 程序")
        }
        XCTAssertEqual(codes, [0x04])

        let status = try statusPackage()
        let local = try AhaKeyRuntimePageSemantic.executionPlan(package: status, userSlotLimit: 64)
        XCTAssertEqual(local.steps.count, 1)
        XCTAssertEqual(local.steps[0].program, [])
        XCTAssertFalse(local.steps[0].writesDevice)
        XCTAssertTrue(local.steps[0].identity.rawValue.hasPrefix("page:local:"))
    }

    func testLightMappingReplaysFrozenNineStateRow() throws {
        let field = AhaKeyStudioFieldID.lightMapping(modeSlot: 0, state: 1)
        let row: [UInt8] = [1, 4, 2, 3, 5, 6, 7, 1, 2]
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .lights(modeSlot: 0),
            fieldMask: [field],
            values: [field: .text("approvalWait")],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            lightMappingRows: [0: row]
        )
        let package = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: []
        )
        let exec = try AhaKeyRuntimePageSemantic.executionPlan(package: package, userSlotLimit: 64)
        XCTAssertEqual(exec.steps.count, 1)
        XCTAssertEqual(exec.steps[0].identity.rawValue, "page:field:lightMapping:0")
        guard case .setLightMapping(let mode, let effects) = exec.steps[0].program.first else {
            return XCTFail("必须发出冻结的 0x84 整行")
        }
        XCTAssertEqual(mode, 0)
        XCTAssertEqual(effects, row)
        XCTAssertEqual(effects[1], 4)
        XCTAssertNotEqual(effects.filter { $0 == 0 }.count, 8)
    }

    func testLocalConfirmDoesNotRelaxBaseCAS() async throws {
        let fps = AhaKeyStudioFieldID.screenFramesPerSecond(modeSlot: 0)
        let status = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [fps, status],
            values: [fps: .integer(12), status: .text("hello")],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            statusLine: "hello",
            framesPerSecond: 12
        )
        let package = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV-A"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: []
        )
        var first = true
        let paused = try await runPage(
            package,
            context: .standard,
            preconditions: matchingPreconditions(package, profile: .legacyStandard)
        ) { _ in
            if first {
                first = false
                return .success
            }
            return .retryableFailure
        }
        XCTAssertEqual(paused, .paused)
        let confirmed = try await store.confirmedSteps(for: package.operationID)
        XCTAssertEqual(confirmed.count, 1)
        XCTAssertTrue(confirmed[0].rawValue.hasPrefix("page:local:"))
        let execPlan = try AhaKeyRuntimePageSemantic.executionPlan(package: package, userSlotLimit: 64)
        XCTAssertFalse(AhaKeyRuntimePageSemantic.hasDeviceWrites(confirmed: confirmed, plan: execPlan))

        var resumed: [String] = []
        let conflicted = try await runPage(
            package,
            context: .standard,
            preconditions: AhaKeyRuntimePageExecutionPreconditions(
                deviceID: package.targetDeviceID,
                profile: .legacyStandard,
                baseObjectFingerprint: try baseFingerprint("mutated-after-local")
            )
        ) { step in
            resumed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(conflicted, .failedWithoutWrites)
        XCTAssertEqual(resumed, [])
    }

    func testLocalPlusWireKeepsCASUntilDeviceConfirm() async throws {
        var fixture = try pictureFixture(frames: 1)
        let status = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        fixture.plan.fieldMask.insert(status)
        fixture.plan.values[status] = .text("hello")
        fixture.plan.statusLine = "hello"
        let package = try assemble(fixture, profile: .legacyStandard, device: "DEV-A")
        let files = try writeResources(fixture)
        let identities = try AhaKeyRuntimePageSemantic.executionPlan(
            package: package,
            userSlotLimit: 64
        ).identities
        XCTAssertTrue(identities.contains { $0.rawValue.hasPrefix("page:local:") })
        XCTAssertTrue(identities.contains { $0.rawValue.hasPrefix("page:chunk:") })

        var seen: [String] = []
        let paused = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: matchingPreconditions(package, profile: .legacyStandard)
        ) { step in
            seen.append(step.rawValue)
            return .retryableFailure
        }
        XCTAssertEqual(paused, .paused)
        let confirmed = try await store.confirmedSteps(for: package.operationID)
        XCTAssertEqual(confirmed, [])
        XCTAssertTrue(seen[0].hasPrefix("page:chunk:"))

        var resumed: [String] = []
        let conflicted = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: AhaKeyRuntimePageExecutionPreconditions(
                deviceID: package.targetDeviceID,
                profile: .legacyStandard,
                baseObjectFingerprint: try baseFingerprint("mutated-before-wire")
            )
        ) { step in
            resumed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(conflicted, .failedWithoutWrites)
        XCTAssertEqual(resumed, [])
    }

    func testDeviceConfirmedResumeAllowsMissingLiveCAS() async throws {
        let fixture = try pictureFixture(frames: 1)
        let package = try assemble(fixture, profile: .legacyStandard, device: "DEV-A")
        let files = try writeResources(fixture)
        var first = true
        let paused = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: matchingPreconditions(package, profile: .legacyStandard)
        ) { _ in
            if first {
                first = false
                return .success
            }
            return .retryableFailure
        }
        XCTAssertEqual(paused, .resumablePartial)
        let confirmed = try await store.confirmedSteps(for: package.operationID)
        XCTAssertEqual(confirmed.count, 1)
        let plan = try AhaKeyRuntimePageSemantic.executionPlan(package: package, userSlotLimit: 64)
        XCTAssertTrue(AhaKeyRuntimePageSemantic.hasDeviceWrites(confirmed: confirmed, plan: plan))

        var resumed: [String] = []
        let completed = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: AhaKeyRuntimePageExecutionPreconditions(
                deviceID: package.targetDeviceID,
                profile: .legacyStandard,
                baseObjectFingerprint: nil
            )
        ) { step in
            resumed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(completed, .completed)
        XCTAssertFalse(resumed.contains(confirmed[0].rawValue))
    }

    func testMappingRejectAndPermanentFailureClassifyByDeviceWrites() async throws {
        let zeroSlot = AhaKeyOLEDCompatibilityContext(
            negotiation: .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: true),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        XCTAssertEqual(zeroSlot.layout.userSlotLimit, 0)

        var executed: [String] = []
        let zeroWriteMap = try statusPackage(device: "DEV-MAP", operation: .init(), seed: "map-zero")
        let mapped = try await runPage(
            zeroWriteMap,
            context: zeroSlot,
            preconditions: matchingPreconditions(zeroWriteMap, profile: .legacyStandard)
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(mapped, .failedWithoutWrites)
        XCTAssertEqual(executed, [])
        let zeroRecord = try await store.transaction(zeroWriteMap.operationID)
        XCTAssertEqual(zeroRecord?.messageCode, .configurationPlanRejected)

        let fixture = try pictureFixture(frames: 1)
        let hasWritePackage = try assemble(fixture, profile: .legacyStandard, device: "DEV-MAP-W")
        let files = try writeResources(fixture)
        var first = true
        let paused = try await runPage(
            hasWritePackage,
            files: files,
            context: .standard,
            preconditions: matchingPreconditions(hasWritePackage, profile: .legacyStandard)
        ) { _ in
            if first {
                first = false
                return .success
            }
            return .retryableFailure
        }
        XCTAssertEqual(paused, .resumablePartial)
        executed.removeAll()
        let mappedWithWrites = try await runPage(
            hasWritePackage,
            files: files,
            context: zeroSlot,
            preconditions: matchingPreconditions(hasWritePackage, profile: .legacyStandard)
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(mappedWithWrites, .failedWithPartialCommit)
        XCTAssertEqual(executed, [])
        let writeRecord = try await store.transaction(hasWritePackage.operationID)
        XCTAssertEqual(writeRecord?.messageCode, .configurationPlanRejected)

        executed.removeAll()
        let localFail = try statusPackage(device: "DEV-PERM", operation: .init(), seed: "perm-local")
        let localPermanent = try await runPage(
            localFail,
            context: .standard,
            preconditions: matchingPreconditions(localFail, profile: .legacyStandard)
        ) { step in
            executed.append(step.rawValue)
            return .permanentFailure
        }
        XCTAssertEqual(localPermanent, .failedWithoutWrites)
        XCTAssertEqual(executed.count, 1)
        let localConfirmed = try await store.confirmedSteps(for: localFail.operationID)
        XCTAssertEqual(localConfirmed, [])

        let fps = AhaKeyStudioFieldID.screenFramesPerSecond(modeSlot: 0)
        let status = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let localPlan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [fps, status],
            values: [fps: .integer(12), status: .text("hello")],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            statusLine: "hello",
            framesPerSecond: 12
        )
        let localThenFail = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: localPlan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV-PERM-2"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: []
        )
        var seenLocal = 0
        let localThenPermanent = try await runPage(
            localThenFail,
            context: .standard,
            preconditions: matchingPreconditions(localThenFail, profile: .legacyStandard)
        ) { _ in
            seenLocal += 1
            if seenLocal == 1 { return .success }
            return .permanentFailure
        }
        XCTAssertEqual(localThenPermanent, .failedWithoutWrites)
        let afterLocal = try await store.confirmedSteps(for: localThenFail.operationID)
        XCTAssertEqual(afterLocal.count, 1)
        XCTAssertFalse(
            AhaKeyRuntimePageSemantic.hasDeviceWrites(
                confirmed: afterLocal,
                plan: try AhaKeyRuntimePageSemantic.executionPlan(
                    package: localThenFail,
                    userSlotLimit: 64
                )
            )
        )
    }

    func testPartialWriteAbandonKeepsConfirmedBaselineAndDropsSealedFieldsFromResidual() async throws {
        let fixture = try pictureFixture(frames: 1)
        let package = try assemble(fixture, profile: .legacyStandard)
        let files = try writeResources(fixture)
        let plan = try AhaKeyRuntimePageSemantic.executionPlan(package: package, userSlotLimit: 64)
        let bind = try XCTUnwrap(plan.steps.first { $0.identity.rawValue.hasPrefix("page:bind:") })
        var current = Date(timeIntervalSince1970: 1_700_000_000)
        let runner = AhaKeyConfigurationTransactionRunner(store: store, now: { current })
        let paused = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: matchingPreconditions(package, profile: .legacyStandard),
            runner: runner
        ) { step in
            if step.rawValue.hasPrefix("page:bind:") {
                return .retryableFailure
            }
            return .success
        }
        XCTAssertEqual(paused, .resumablePartial)
        try await store.confirmPageStep(bind.identity, package: package, plan: plan)
        let baselines = try await store.pageFieldBaselines(
            deviceID: package.targetDeviceID,
            pageID: .screen(modeSlot: 0)
        )
        XCTAssertEqual(baselines.map(\.trust), [.writeConfirmed])
        let confirmed = try await store.confirmedSteps(for: package.operationID)
        let projection = AhaKeyRuntimePageSemantic.confirmationProjection(
            package: package,
            confirmed: confirmed,
            plan: plan
        )
        XCTAssertFalse(projection.residual.fieldIDs.contains(where: { $0 == bind.fieldID }))
        let sealedField = try XCTUnwrap(bind.fieldID)
        XCTAssertTrue(projection.confirmedFieldIDs.contains(sealedField))

        current = current.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
        let abandoned = try await runner.requestAbandon(
            operationID: package.operationID,
            now: current,
            deviceConnected: false
        )
        XCTAssertEqual(abandoned, .abandoned)
        let abandonedState = try await store.transaction(package.operationID)?.state
        XCTAssertEqual(abandonedState, .failedWithPartialCommit)
        let restoredStore = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
        let restoredBaselines = try await restoredStore.pageFieldBaselines(
            deviceID: package.targetDeviceID,
            pageID: .screen(modeSlot: 0)
        )
        XCTAssertEqual(restoredBaselines, baselines)
        let restoredState = try await restoredStore.transaction(package.operationID)?.state
        XCTAssertEqual(restoredState, .failedWithPartialCommit)
    }

    func testChunkProgressDoesNotSealPictureFieldOrResource() async throws {
        let fixture = try pictureFixture(frames: 1)
        let package = try assemble(fixture, profile: .legacyStandard)
        let files = try writeResources(fixture)
        let plan = try AhaKeyRuntimePageSemantic.executionPlan(package: package, userSlotLimit: 64)
        var first = true
        let paused = try await runPage(
            package,
            files: files,
            context: .standard,
            preconditions: matchingPreconditions(package, profile: .legacyStandard)
        ) { _ in
            if first {
                first = false
                return .success
            }
            return .retryableFailure
        }
        XCTAssertEqual(paused, .resumablePartial)
        let chunkBaselines = try await store.pageFieldBaselines(
            deviceID: package.targetDeviceID,
            pageID: .screen(modeSlot: 0)
        )
        XCTAssertTrue(chunkBaselines.isEmpty)
        let confirmed = try await store.confirmedSteps(for: package.operationID)
        let projection = AhaKeyRuntimePageSemantic.confirmationProjection(
            package: package,
            confirmed: confirmed,
            plan: plan
        )
        XCTAssertTrue(projection.confirmedFieldIDs.isEmpty)
        XCTAssertEqual(
            Set(projection.residual.fieldIDs),
            try XCTUnwrap(package.pageOperation).confirmationLedger.fieldIDs
        )
        XCTAssertFalse(projection.residual.resources.isEmpty)
    }

    func testNoWriteAbandonFinishesWithoutDeviceWritesAndReleasesFIFOHead() async throws {
        let head = try statusPackage(device: "DEV-ABANDON", seed: "head-local")
        let queued = try statusPackage(device: "DEV-ABANDON", seed: "queued-local")
        var current = Date(timeIntervalSince1970: 1_700_000_000)
        let runner = AhaKeyConfigurationTransactionRunner(store: store, now: { current })
        var first = true
        let paused = try await runPage(
            head,
            context: .standard,
            preconditions: matchingPreconditions(head, profile: .legacyStandard),
            runner: runner
        ) { _ in
            if first {
                first = false
                return .retryableFailure
            }
            return .success
        }
        XCTAssertEqual(paused, .paused)
        try await store.accept(queued, resourceFiles: [:])
        let tooEarly = try await runner.requestAbandon(
            operationID: head.operationID,
            now: current.addingTimeInterval(30),
            deviceConnected: false
        )
        XCTAssertEqual(tooEarly, .refused)
        current = current.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
        let whileConnected = try await runner.requestAbandon(
            operationID: head.operationID,
            now: current,
            deviceConnected: true
        )
        XCTAssertEqual(whileConnected, .refused)
        let nonHead = try await runner.requestAbandon(
            operationID: queued.operationID,
            now: current,
            deviceConnected: false
        )
        XCTAssertEqual(nonHead, .refused)
        let abandonedHead = try await runner.requestAbandon(
            operationID: head.operationID,
            now: current,
            deviceConnected: false
        )
        XCTAssertEqual(abandonedHead, .abandoned)
        let headState = try await store.transaction(head.operationID)?.state
        XCTAssertEqual(headState, .failedWithoutWrites)
        let queuedState = try await runPage(
            queued,
            context: .standard,
            preconditions: matchingPreconditions(queued, profile: .legacyStandard),
            runner: runner
        ) { _ in .success }
        XCTAssertEqual(queuedState, .completed)
    }

    func testAbandonRejectsClockRollbackAndRunningState() async throws {
        let package = try statusPackage(device: "DEV-ROLL", seed: "running")
        var current = Date(timeIntervalSince1970: 1_700_000_000)
        let runner = AhaKeyConfigurationTransactionRunner(store: store, now: { current })
        let gate = CancelGate()
        let task = Task {
            try await self.runPage(
                package,
                context: .standard,
                preconditions: self.matchingPreconditions(package, profile: .legacyStandard),
                runner: runner
            ) { _ in
                await gate.markEntered()
                await gate.wait()
                return .success
            }
        }
        await gate.waitUntilEntered()
        let runningAbandon = try await runner.requestAbandon(
            operationID: package.operationID,
            now: current.addingTimeInterval(60),
            deviceConnected: false
        )
        XCTAssertEqual(runningAbandon, .refused)
        await gate.release()
        _ = try await task.value
    }

    func testCancelClassifiesLocalConfirmAsZeroDeviceWrites() async throws {
        let package = try statusPackage(device: "DEV-CANCEL", seed: "queued-local")
        try await store.accept(package, resourceFiles: [:])
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        try await runner.requestCancel(operationID: package.operationID)
        let settled = try await runner.settleCancellation(operationID: package.operationID)
        XCTAssertEqual(settled, .failedWithoutWrites)

        let localID = try AhaKeyRuntimeStepIdentifier("page:local:screenStatusLine:0")
        XCTAssertEqual(
            AhaKeyConfigurationTransactionEngine.settleCancellation(
                confirmedSteps: [localID],
                hasWrites: false
            ),
            .commitTerminal(.failedWithoutWrites)
        )
        XCTAssertEqual(
            AhaKeyConfigurationTransactionEngine.settleCancellation(
                confirmedSteps: [try AhaKeyRuntimeStepIdentifier("page:chunk:0")],
                hasWrites: true
            ),
            .persistState(.resumablePartial)
        )
    }

    // MARK: - helpers

    private struct PageFixtureBox {
        var sourceBytes: [AhaKeyResourceIdentifier: Data]
    }

    private actor CancelGate {
        private var didEnter = false
        private var released = false
        private var enterWaiters: [CheckedContinuation<Void, Never>] = []
        private var runWaiters: [CheckedContinuation<Void, Never>] = []

        func waitUntilEntered() async {
            if didEnter { return }
            await withCheckedContinuation { enterWaiters.append($0) }
        }

        func markEntered() {
            didEnter = true
            let pending = enterWaiters
            enterWaiters.removeAll()
            pending.forEach { $0.resume() }
        }

        func wait() async {
            if released { return }
            await withCheckedContinuation { runWaiters.append($0) }
        }

        func release() {
            released = true
            let pending = runWaiters
            runWaiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    @discardableResult
    private func runPage(
        _ package: AhaKeyConfigurationPackage,
        files: [AhaKeyResourceIdentifier: URL] = [:],
        context: AhaKeyOLEDCompatibilityContext,
        preconditions: AhaKeyRuntimePageExecutionPreconditions?,
        runner: AhaKeyConfigurationTransactionRunner? = nil,
        execute: AhaKeyConfigurationTransactionRunner.StepExecutor
    ) async throws -> AhaKeyRuntimeOperationState {
        try await (runner ?? AhaKeyConfigurationTransactionRunner(store: store)).run(
            package: package,
            resourceFiles: files,
            context: context,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: preconditions,
            execute: execute
        )
    }

    private func matchingPreconditions(
        _ package: AhaKeyConfigurationPackage,
        profile: AhaKeyOLEDCompatibilityProfile
    ) throws -> AhaKeyRuntimePageExecutionPreconditions {
        AhaKeyRuntimePageExecutionPreconditions(
            deviceID: package.targetDeviceID,
            profile: profile,
            baseObjectFingerprint: try XCTUnwrap(package.pageOperation?.baseObjectFingerprint)
        )
    }

    private func assertOpcodeSequence(
        profile: AhaKeyOLEDCompatibilityProfile,
        context: AhaKeyOLEDCompatibilityContext,
        expectSession: Bool,
        expectLegacyBind: Bool
    ) throws {
        let fixture = try pictureFixture(frames: 2, logicalSet: 0)
        let package = try assemble(fixture, profile: profile)
        let plan = try AhaKeyRuntimePageSemantic.executionPlan(
            package: package,
            userSlotLimit: context.layout.userSlotLimit
        )
        let fingerprint = try XCTUnwrap(package.pageOperation?.compatibilityFingerprint)
        XCTAssertEqual(fingerprint.prepareStrategy?.opcode == AhaKeyWireFrameBuilder.cmdPrepareSessionWrite, expectSession)
        let prepares = plan.steps.flatMap(\.program).compactMap { step -> Bool? in
            guard case .prepareWrite(let session, _, _) = step else { return nil }
            return session != nil
        }
        XCTAssertFalse(prepares.isEmpty)
        XCTAssertTrue(prepares.allSatisfy { $0 == expectSession })
        let bind = try XCTUnwrap(plan.steps.first { $0.identity.rawValue.hasPrefix("page:bind:") })
        if expectLegacyBind {
            guard case .bindLegacyTaskPicture = bind.program.first else {
                return XCTFail("Standard 必须发出 legacy bind")
            }
        } else {
            guard case .bindTaskPicture = bind.program.first else {
                return XCTFail("Rhino/current 必须发出 0x95 bind")
            }
        }
        XCTAssertNotNil(fingerprint.actions[0].opcode)
        XCTAssertFalse(plan.identities.contains { $0.rawValue.hasPrefix("base:mode:") })
    }

    private func statusPackage(
        device: String = "DEV",
        operation: AhaKeyRuntimeOperationID = .init(),
        seed: String = "base-object"
    ) throws -> AhaKeyConfigurationPackage {
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [field: .text(seed)],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            statusLine: seed
        )
        return try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID(device),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(seed),
            verifiedResources: [],
            operationID: operation
        )
    }

    private func assemble(
        _ fixture: PictureFixture,
        profile: AhaKeyOLEDCompatibilityProfile,
        device: String = "DEV"
    ) throws -> AhaKeyConfigurationPackage {
        try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: fixture.plan,
            profile: profile,
            targetDeviceID: AhaKeyRuntimeDeviceID(device),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: fixture.resources
        )
    }

    private func writeResources(_ fixture: PictureFixture) throws -> [AhaKeyResourceIdentifier: URL] {
        try writeResources(PageFixtureBox(sourceBytes: fixture.sourceBytes))
    }

    private func writeResources(_ box: PageFixtureBox) throws -> [AhaKeyResourceIdentifier: URL] {
        var files: [AhaKeyResourceIdentifier: URL] = [:]
        for (identifier, bytes) in box.sourceBytes {
            let url = root.appendingPathComponent("\(identifier.rawValue).gif")
            try bytes.write(to: url)
            files[identifier] = url
        }
        return files
    }

    private struct PictureFixture {
        var plan: AhaKeyStudioScopedWritePlan
        var resources: [AhaKeyConfigurationResource]
        var sourceBytes: [AhaKeyResourceIdentifier: Data]
    }

    private func pictureFixture(
        bytes: Data = Data("gif-c3b".utf8),
        frames: Int,
        logicalSet: Int = 0
    ) throws -> PictureFixture {
        let profile = AhaKeyOLEDCompatibilityProfile.legacyStandard
        let physical = Int(try AhaKeyRuntimePageSemantic.physicalSlot(profile: profile, logicalSet: logicalSet))
        let identifier = AhaKeyStudioPackageAssembler.taskAssetIdentifier(
            mode: 0,
            set: physical,
            state: .working
        )
        let digest = SHA256.hash(data: bytes)
        let resource = try AhaKeyConfigurationResource(
            logicalIdentifier: identifier,
            sha256: digest.map { String(format: "%02x", $0) }.joined(),
            byteCount: UInt64(bytes.count),
            mediaType: "image/gif"
        )
        let field = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: logicalSet, state: .working)
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [
                field: .asset(
                    path: nil,
                    framesPerSecond: 10,
                    declaredFrameCount: frames,
                    pixelWidth: 160,
                    pixelHeight: 80
                ),
            ],
            overwriteSemantic: false,
            writeTaskSetA: logicalSet == 0,
            writeTaskSetB: false,
            activateTaskSet: logicalSet,
            emitsSetActiveSetOpcode: false,
            resources: [
                AhaKeyStudioResourceInput(
                    logicalIdentifier: resource.logicalIdentifier,
                    fileURL: URL(fileURLWithPath: "/tmp/\(identifier).gif"),
                    declaredFrameCount: frames,
                    pixelWidth: 160,
                    pixelHeight: 80
                ),
            ]
        )
        return PictureFixture(
            plan: plan,
            resources: [resource],
            sourceBytes: [resource.logicalIdentifier: bytes]
        )
    }

    private func baseFingerprint(_ seed: String = "base-object") throws -> AhaKeyRuntimeObjectFingerprint {
        try AhaKeyRuntimeObjectFingerprint.hashing(Data(seed.utf8))
    }

    private func rhinoSessionCaps() -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: 2, stateCount: 4,
            flags: AhaKeyFirmwareCapabilities.sessionUploadFlag,
            maxPacketSize: 200, userSlotLimit: 288, factorySlotBase: 10,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    private func currentCaps() -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: 1, stateCount: 4,
            flags: AhaKeyFirmwareCapabilities.sessionUploadFlag,
            maxPacketSize: 200, userSlotLimit: 288, factorySlotBase: 10,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }
}
