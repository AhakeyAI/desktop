import CryptoKit
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
                targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
                baseObjectFingerprint: try baseFingerprint(),
                verifiedResources: []
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
                targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
                baseObjectFingerprint: try baseFingerprint(),
                verifiedResources: []
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .pageOperationIncomplete)
        }
    }

    func testBaseObjectFingerprintRequiresCallerDigestAndRejectsEmpty() throws {
        XCTAssertThrowsError(try AhaKeyRuntimeObjectFingerprint.hashing(Data())) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .invalidObjectFingerprint)
        }
        let first = try AhaKeyRuntimeObjectFingerprint.hashing(Data("object-a".utf8))
        let second = try AhaKeyRuntimeObjectFingerprint.hashing(Data("object-b".utf8))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, try AhaKeyRuntimeObjectFingerprint.hashing(Data("object-a".utf8)))
    }

    func testCompatibilityFingerprintDistinguishesActualActionsAndRejectsForbiddenKeys() throws {
        let status = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: screenStatusPlan(),
            profile: .legacyStandard
        )
        let active = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: rhinoActiveOnlyPlan(),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        let (picturePlan, _) = try pictureWritePlan(bytes: Data("gif-a".utf8))
        let picture = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: picturePlan,
            profile: .legacyStandard
        )
        XCTAssertEqual(status.family, .legacyStandard)
        XCTAssertEqual(status.emittedOpcodes, [])
        XCTAssertEqual(status.geometry, .none)
        XCTAssertEqual(status.activation, .none)
        XCTAssertEqual(active.emittedOpcodes, [0x97])
        XCTAssertEqual(active.activation, .setActiveSetOpcode)
        XCTAssertEqual(active.geometry, .none)
        XCTAssertTrue(picture.emittedOpcodes.contains(0x80))
        XCTAssertTrue(picture.emittedOpcodes.contains(0x82))
        XCTAssertEqual(picture.geometry, .oled160x80)
        XCTAssertEqual(picture.physicalSlots, [0])
        XCTAssertNotEqual(status, picture)
        XCTAssertNotEqual(status, active)
        XCTAssertNotEqual(picture, active)
        XCTAssertEqual(try status.canonicalData(), try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: screenStatusPlan(),
            profile: .legacyStandard
        ).canonicalData())

        let encoded = try JSONEncoder().encode(status)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["battery"] = 80
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimeCompatibilityFingerprint.self,
                from: try JSONSerialization.data(withJSONObject: object)
            )
        )
        object.removeValue(forKey: "battery")
        object["sessionUpload"] = true
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimeCompatibilityFingerprint.self,
                from: try JSONSerialization.data(withJSONObject: object)
            )
        )
    }

    func testConfirmationLedgerRejectsIllegalCombinationsAndRequiresPendingExactness() throws {
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let resource = try verifiedGIF(Data("gif".utf8))
        let valid = try AhaKeyRuntimeConfirmationLedger.pending(fieldMask: [field], resources: [resource])
        XCTAssertEqual(valid.entries.count, 2)

        let illegal = Data(
            """
            {"entries":[{"kind":"field","fieldID":null,"resourceID":"x","confirmed":true}]}
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyRuntimeConfirmationLedger.self, from: illegal)
        )

        let extraField = try JSONEncoder().encode(
            AhaKeyRuntimeConfirmationLedger(entries: [
                .pendingField(field),
                .pendingField(.screenFramesPerSecond(modeSlot: 0)),
            ])
        )
        let decodedExtra = try JSONDecoder().decode(AhaKeyRuntimeConfirmationLedger.self, from: extraField)
        XCTAssertThrowsError(
            try decodedExtra.validate(fieldMask: [field], resources: [])
        )
    }

    func testSameLogicalIDDifferentBytesChangesPackageIdentity() throws {
        let operationID = AhaKeyRuntimeOperationID()
        let (planA, resourcesA) = try pictureWritePlan(bytes: Data("gif-one".utf8))
        let (planB, resourcesB) = try pictureWritePlan(bytes: Data("gif-two".utf8))
        let first = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: planA,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: resourcesA,
            operationID: operationID
        )
        let second = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: planB,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: resourcesB,
            operationID: operationID
        )
        XCTAssertEqual(first.operationID, second.operationID)
        XCTAssertEqual(first.resources.first?.logicalIdentifier, second.resources.first?.logicalIdentifier)
        XCTAssertNotEqual(first.resources.first?.sha256, second.resources.first?.sha256)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(String(decoding: first.desiredConfiguration, as: UTF8.self).contains("/tmp/"))
    }

    func testDeviceQueueReportsHeadBlockingWithoutProjectionWrapper() throws {
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let head = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: screenStatusPlan(statusLine: "head"),
            profile: .legacyStandard,
            targetDeviceID: device,
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint("head"),
            verifiedResources: []
        )
        let blocked = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: screenStatusPlan(statusLine: "blocked"),
            profile: .legacyStandard,
            targetDeviceID: device,
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint("blocked"),
            verifiedResources: []
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
        XCTAssertEqual(head.pageOperation?.pageScope, .screen(modeSlot: 0))
        XCTAssertEqual(blocked.pageOperation?.fieldMask, [.screenStatusLine(modeSlot: 0)])
    }

    private func baseFingerprint(_ seed: String = "base-object") throws -> AhaKeyRuntimeObjectFingerprint {
        try AhaKeyRuntimeObjectFingerprint.hashing(Data(seed.utf8))
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

    private func rhinoActiveOnlyPlan() -> AhaKeyStudioScopedWritePlan {
        let field = AhaKeyStudioFieldID.screenActiveSet(modeSlot: 0)
        return AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [field: .integer(1)],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: 1,
            emitsSetActiveSetOpcode: true
        )
    }

    private func verifiedGIF(_ bytes: Data, identifier: String = "mode0-set0-working") throws -> AhaKeyConfigurationResource {
        let digest = SHA256.hash(data: bytes)
        return try AhaKeyConfigurationResource(
            logicalIdentifier: identifier,
            sha256: digest.map { String(format: "%02x", $0) }.joined(),
            byteCount: UInt64(bytes.count),
            mediaType: "image/gif"
        )
    }

    private func pictureWritePlan(
        bytes: Data,
        identifier: String = "mode0-set0-working"
    ) throws -> (AhaKeyStudioScopedWritePlan, [AhaKeyConfigurationResource]) {
        let resource = try verifiedGIF(bytes, identifier: identifier)
        let field = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .working)
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [
                field: .asset(
                    path: nil,
                    framesPerSecond: 10,
                    declaredFrameCount: 1,
                    pixelWidth: 160,
                    pixelHeight: 80
                ),
            ],
            overwriteSemantic: false,
            writeTaskSetA: true,
            writeTaskSetB: false,
            activateTaskSet: 0,
            emitsSetActiveSetOpcode: false,
            resources: [
                AhaKeyStudioResourceInput(
                    logicalIdentifier: resource.logicalIdentifier,
                    fileURL: URL(fileURLWithPath: "/tmp/not-persisted.gif"),
                    declaredFrameCount: 1,
                    pixelWidth: 160,
                    pixelHeight: 80
                ),
            ]
        )
        return (plan, [resource])
    }
}
