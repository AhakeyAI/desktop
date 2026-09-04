import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyRuntimePageOperationTests: XCTestCase {
    func testAssembleRejectsEmptyOrCrossPageFieldMask() throws {
        let empty = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [],
            values: [:],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false
        )
        XCTAssertThrowsError(
            try AhaKeyRuntimePageOperationContract.assemble(
                plan: empty,
                profile: .legacyStandard,
                targetDeviceID: AhaKeyRuntimeDeviceID("DEV")
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .pageOperationIncomplete)
        }

        let mixedField = AhaKeyStudioFieldID.lightBrightness(modeSlot: 0)
        let mixed = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [mixedField],
            values: [mixedField: .integer(10)],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false
        )
        XCTAssertThrowsError(
            try AhaKeyRuntimePageOperationContract.assemble(
                plan: mixed,
                profile: .legacyStandard,
                targetDeviceID: AhaKeyRuntimeDeviceID("DEV")
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .pageOperationIncomplete)
        }
    }

    func testCompatibilityFingerprintIsCanonicalAndRejectsForbiddenKeys() throws {
        let first = try AhaKeyRuntimeCompatibilityFingerprint.make(profile: .legacyStandard)
        let second = try AhaKeyRuntimeCompatibilityFingerprint.make(profile: .legacyStandard)
        XCTAssertEqual(first, second)
        XCTAssertEqual(try first.canonicalData(), try second.canonicalData())
        XCTAssertFalse(first.opcodes.isEmpty)
        XCTAssertEqual(first.protocolFamily, "legacy-standard")
        XCTAssertEqual(first.physicalSetCount, 1)
        XCTAssertTrue(first.mapsLogicalBToPhysical0)
        XCTAssertFalse(first.sessionUpload)

        let rhino = try AhaKeyRuntimeCompatibilityFingerprint.make(
            profile: .rhinoDualSet(sessionUploadAdvertised: true)
        )
        XCTAssertNotEqual(first, rhino)
        XCTAssertEqual(rhino.physicalSetCount, 2)
        XCTAssertTrue(rhino.sessionUpload)

        let encoded = try JSONEncoder().encode(first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["battery"] = 80
        let withBattery = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyRuntimeCompatibilityFingerprint.self, from: withBattery)
        )
        object.removeValue(forKey: "battery")
        object["rssi"] = -40
        let withRSSI = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyRuntimeCompatibilityFingerprint.self, from: withRSSI)
        )
        object.removeValue(forKey: "rssi")
        object["localPath"] = "/tmp/picture.gif"
        let withPath = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyRuntimeCompatibilityFingerprint.self, from: withPath)
        )
    }

    func testObjectFingerprintDependsOnPageFieldsAndFamilyOnly() throws {
        let mask: Set<AhaKeyStudioFieldID> = [
            .screenStatusLine(modeSlot: 0),
            .screenFramesPerSecond(modeSlot: 0),
        ]
        let first = try AhaKeyRuntimeObjectFingerprint.make(
            pageScope: .screen(modeSlot: 0),
            fieldMask: mask,
            profile: .legacyStandard
        )
        let reversed = try AhaKeyRuntimeObjectFingerprint.make(
            pageScope: .screen(modeSlot: 0),
            fieldMask: [
                .screenFramesPerSecond(modeSlot: 0),
                .screenStatusLine(modeSlot: 0),
            ],
            profile: .legacyStandard
        )
        XCTAssertEqual(first, reversed)

        let otherPage = try AhaKeyRuntimeObjectFingerprint.make(
            pageScope: .screen(modeSlot: 1),
            fieldMask: [.screenStatusLine(modeSlot: 1)],
            profile: .legacyStandard
        )
        XCTAssertNotEqual(first, otherPage)

        let otherFamily = try AhaKeyRuntimeObjectFingerprint.make(
            pageScope: .screen(modeSlot: 0),
            fieldMask: mask,
            profile: .currentSessionCapable
        )
        XCTAssertNotEqual(first, otherFamily)
    }

    func testConfirmationLedgerCoversFieldMaskWithoutLocalPaths() throws {
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [field: .text("hello")],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            resources: [
                AhaKeyStudioResourceInput(
                    logicalIdentifier: try AhaKeyResourceIdentifier("mode0-set0-working"),
                    fileURL: URL(fileURLWithPath: "/tmp/secret.gif"),
                    declaredFrameCount: 1,
                    pixelWidth: 160,
                    pixelHeight: 80
                ),
            ],
            statusLine: "hello"
        )
        let contract = try AhaKeyRuntimePageOperationContract.assemble(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV")
        )
        XCTAssertEqual(contract.confirmationLedger.fieldIDs, [field])
        XCTAssertEqual(
            contract.confirmationLedger.entries.compactMap(\.resourceID),
            ["mode0-set0-working"]
        )
        let desired = try AhaKeyRuntimeCanonicalPageWrite.encode(plan: plan, contract: contract)
        let desiredText = String(decoding: desired, as: UTF8.self)
        XCTAssertFalse(desiredText.contains("/tmp/secret.gif"))
        XCTAssertFalse(desiredText.contains("battery"))
        XCTAssertTrue(desiredText.contains("mode0-set0-working"))
    }

    func testPageOperationProjectionReportsQueueIndexAndHeadBlocking() throws {
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let head = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: screenStatusPlan(statusLine: "head"),
            profile: .legacyStandard,
            targetDeviceID: device,
            baseRevision: .init(1)
        )
        let blocked = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: screenStatusPlan(statusLine: "blocked"),
            profile: .legacyStandard,
            targetDeviceID: device,
            baseRevision: .init(1)
        )
        let queue = AhaKeyRuntimeDeviceQueue(
            deviceID: device,
            items: [
                AhaKeyRuntimePersistedTransaction(
                    operationID: head.operationID,
                    package: head,
                    state: .paused,
                    completedSteps: 0,
                    totalSteps: 1,
                    messageCode: nil
                ),
                AhaKeyRuntimePersistedTransaction(
                    operationID: blocked.operationID,
                    package: blocked,
                    state: .accepted,
                    completedSteps: 0,
                    totalSteps: 1,
                    messageCode: nil
                ),
            ]
        )
        XCTAssertTrue(queue.isHead(head.operationID))
        XCTAssertTrue(queue.isBlocked(blocked.operationID))
        XCTAssertFalse(queue.isBlocked(head.operationID))

        let headProjection = try XCTUnwrap(
            AhaKeyRuntimePageOperationProjection(package: head, queue: queue)
        )
        XCTAssertEqual(headProjection.queueIndex, 0)
        XCTAssertFalse(headProjection.blockedByHead)
        XCTAssertEqual(headProjection.pageScope, .screen(modeSlot: 0))

        let blockedProjection = try XCTUnwrap(
            AhaKeyRuntimePageOperationProjection(package: blocked, queue: queue)
        )
        XCTAssertEqual(blockedProjection.queueIndex, 1)
        XCTAssertTrue(blockedProjection.blockedByHead)
        XCTAssertEqual(blockedProjection.headOperationID, head.operationID)
    }

    private func screenStatusPlan(statusLine: String) -> AhaKeyStudioScopedWritePlan {
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
}
