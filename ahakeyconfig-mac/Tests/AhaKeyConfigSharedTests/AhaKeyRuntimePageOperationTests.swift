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
        let fps = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: screenFPSPlan(),
            profile: .legacyStandard
        )
        let key = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: try keyActionPlan(),
            profile: .legacyStandard
        )
        let description = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: keyDescriptionPlan(),
            profile: .legacyStandard
        )
        let brightness = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: lightBrightnessPlan(),
            profile: .legacyStandard
        )
        let mapping = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: lightMappingPlan(),
            profile: .legacyStandard
        )
        let active = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: rhinoActiveOnlyPlan(),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        let (picturePlan, _) = try pictureWritePlan(bytes: Data("gif-a".utf8), logicalSet: 0)
        let pictureA = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: picturePlan,
            profile: .legacyStandard
        )
        let (pictureBPlan, _) = try pictureWritePlan(bytes: Data("gif-a".utf8), logicalSet: 1)
        let pictureB = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: pictureBPlan,
            profile: .legacyStandard
        )
        XCTAssertEqual(status.family, .legacyStandard)
        XCTAssertEqual(status.actions.map(\.command), [.screenStatus])
        XCTAssertEqual(fps.actions.map(\.command), [.screenFramesPerSecond])
        XCTAssertEqual(key.actions.map(\.command), [.keyShortcut])
        XCTAssertEqual(description.actions.map(\.command), [.keyDescription])
        XCTAssertEqual(brightness.actions.map(\.command), [.lightBrightness])
        XCTAssertEqual(mapping.actions.map(\.command), [.lightMapping])
        XCTAssertEqual(active.actions.map(\.command), [.setActiveSet])
        XCTAssertEqual(pictureA.actions[0].logicalSet, 0)
        XCTAssertEqual(pictureA.actions[0].physicalSlot, 0)
        XCTAssertEqual(pictureB.actions[0].logicalSet, 1)
        XCTAssertEqual(pictureB.actions[0].physicalSlot, 0)
        XCTAssertNotEqual(pictureA, pictureB)
        XCTAssertNotEqual(status, fps)
        XCTAssertNotEqual(key, description)
        XCTAssertNotEqual(brightness, mapping)
        XCTAssertNotEqual(status, pictureA)
        XCTAssertNotEqual(status, active)
        if case .picture(let semantics) = pictureA.actions[0].command {
            XCTAssertEqual(semantics.prepareOpcode, 0x80)
            XCTAssertEqual(semantics.bindOpcode, 0x93)
        } else {
            XCTFail("picture-write 必须编码 bind opcode")
        }
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

    func testStandardThreeStateSameGeometryBindsEachFieldOnce() throws {
        let (plan, resources) = try standardThreeStatePlan()
        let package = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: resources
        )
        let bindings = try XCTUnwrap(package.pageOperation?.resourceBindings)
        XCTAssertEqual(bindings.count, 3)
        XCTAssertEqual(Set(bindings.map(\.fieldID)).count, 3)
        XCTAssertEqual(Set(bindings.map(\.logicalID)).count, 3)
        XCTAssertEqual(
            Set(bindings.map(\.logicalID.rawValue)),
            ["mode0-set0-working", "mode0-set0-waiting", "mode0-set0-done"]
        )
        let desired = String(decoding: package.desiredConfiguration, as: UTF8.self)
        XCTAssertFalse(desired.contains("/tmp/"))
        XCTAssertEqual(package.pageOperation?.compatibilityFingerprint.actions.count, 3)
    }

    func testRhinoABReuseSameDigestDifferentLogicalIDs() throws {
        let bytes = Data("shared-gif".utf8)
        let (plan, resources) = try rhinoABReusePlan(bytes: bytes)
        XCTAssertEqual(resources[0].sha256, resources[1].sha256)
        XCTAssertNotEqual(resources[0].logicalIdentifier, resources[1].logicalIdentifier)
        let package = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: plan,
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: resources
        )
        let actions = try XCTUnwrap(package.pageOperation?.compatibilityFingerprint.actions)
        XCTAssertEqual(actions.map(\.logicalSet), [0, 1])
        XCTAssertEqual(actions.map(\.physicalSlot), [0, 1])
        XCTAssertNotEqual(actions[0], actions[1])
    }

    func testBindingRejectsMissingDuplicateAndWrongField() throws {
        let (plan, resources) = try pictureWritePlan(bytes: Data("gif".utf8), logicalSet: 0)
        var missing = plan
        missing.resources = []
        XCTAssertThrowsError(
            try AhaKeyRuntimePageOperationContract.assemble(
                plan: missing,
                profile: .legacyStandard,
                targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
                baseObjectFingerprint: try baseFingerprint(),
                verifiedResources: []
            )
        )
        var wrong = plan
        let wrongID = try AhaKeyResourceIdentifier("mode0-set1-working")
        wrong.resources[0].logicalIdentifier = wrongID
        var wrongResources = resources
        wrongResources[0] = try AhaKeyConfigurationResource(
            logicalIdentifier: wrongID.rawValue,
            sha256: resources[0].sha256.rawValue,
            byteCount: resources[0].byteCount,
            mediaType: resources[0].mediaType.rawValue
        )
        XCTAssertThrowsError(
            try AhaKeyRuntimePageOperationContract.assemble(
                plan: wrong,
                profile: .legacyStandard,
                targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
                baseObjectFingerprint: try baseFingerprint(),
                verifiedResources: wrongResources
            )
        )
        let extra = resources + [
            try verifiedGIF(Data("other".utf8), identifier: "mode0-set0-waiting"),
        ]
        var extraPlan = plan
        extraPlan.resources.append(
            AhaKeyStudioResourceInput(
                logicalIdentifier: extra[1].logicalIdentifier,
                fileURL: URL(fileURLWithPath: "/tmp/waiting.gif"),
                declaredFrameCount: 1,
                pixelWidth: 160,
                pixelHeight: 80
            )
        )
        XCTAssertThrowsError(
            try AhaKeyRuntimePageOperationContract.assemble(
                plan: extraPlan,
                profile: .legacyStandard,
                targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
                baseObjectFingerprint: try baseFingerprint(),
                verifiedResources: extra
            )
        )
    }

    func testFingerprintDecoderRejectsImpossibleSemanticsAndWALReopen() throws {
        let (plan, resources) = try pictureWritePlan(bytes: Data("gif".utf8), logicalSet: 0)
        let valid = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: plan,
            profile: .legacyStandard
        )
        let encoded = try JSONEncoder().encode(valid)
        func decodeMutating(_ mutate: (inout [String: Any]) throws -> Void) throws {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            try mutate(&object)
            _ = try JSONDecoder().decode(
                AhaKeyRuntimeCompatibilityFingerprint.self,
                from: try JSONSerialization.data(withJSONObject: object)
            )
        }
        XCTAssertThrowsError(try decodeMutating { root in
            var actions = try XCTUnwrap(root["actions"] as? [[String: Any]])
            var command = try XCTUnwrap(actions[0]["command"] as? [String: Any])
            var picture = try XCTUnwrap(command["picture"] as? [String: Any])
            picture["prepareOpcode"] = 255
            command["picture"] = picture
            actions[0]["command"] = command
            root["actions"] = actions
        })
        XCTAssertThrowsError(try decodeMutating { root in
            var actions = try XCTUnwrap(root["actions"] as? [[String: Any]])
            actions[0]["physicalSlot"] = 2
            root["actions"] = actions
        })
        XCTAssertThrowsError(try decodeMutating { root in
            var actions = try XCTUnwrap(root["actions"] as? [[String: Any]])
            actions[0]["physicalSlot"] = NSNull()
            root["actions"] = actions
        })
        let status = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: screenStatusPlan(),
            profile: .legacyStandard
        )
        let statusEncoded = try JSONEncoder().encode(status)
        var statusObject = try XCTUnwrap(JSONSerialization.jsonObject(with: statusEncoded) as? [String: Any])
        var statusActions = try XCTUnwrap(statusObject["actions"] as? [[String: Any]])
        statusActions[0]["physicalSlot"] = 0
        statusObject["actions"] = statusActions
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimeCompatibilityFingerprint.self,
                from: try JSONSerialization.data(withJSONObject: statusObject)
            )
        )
        XCTAssertThrowsError(try decodeMutating { root in
            var actions = try XCTUnwrap(root["actions"] as? [[String: Any]])
            actions[0]["activation"] = "none"
            root["actions"] = actions
        })

        let package = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: resources
        )
        var packageObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(package)) as? [String: Any]
        )
        var pageOperation = try XCTUnwrap(packageObject["pageOperation"] as? [String: Any])
        var fingerprint = try XCTUnwrap(pageOperation["compatibilityFingerprint"] as? [String: Any])
        var actions = try XCTUnwrap(fingerprint["actions"] as? [[String: Any]])
        var command = try XCTUnwrap(actions[0]["command"] as? [String: Any])
        var picture = try XCTUnwrap(command["picture"] as? [String: Any])
        picture["bindOpcode"] = 255
        command["picture"] = picture
        actions[0]["command"] = command
        fingerprint["actions"] = actions
        pageOperation["compatibilityFingerprint"] = fingerprint
        packageObject["pageOperation"] = pageOperation
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyConfigurationPackage.self,
                from: try JSONSerialization.data(withJSONObject: packageObject)
            )
        )
        let roundTrip = try JSONDecoder().decode(
            AhaKeyConfigurationPackage.self,
            from: try JSONEncoder().encode(package)
        )
        XCTAssertEqual(roundTrip, package)
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

    private func screenFPSPlan() -> AhaKeyStudioScopedWritePlan {
        let field = AhaKeyStudioFieldID.screenFramesPerSecond(modeSlot: 0)
        return AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [field: .integer(12)],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            framesPerSecond: 12
        )
    }

    private func keyActionPlan() throws -> AhaKeyStudioScopedWritePlan {
        let field = AhaKeyStudioFieldID.keyAction(modeSlot: 0, role: .approve)
        return AhaKeyStudioScopedWritePlan(
            pageID: .key(modeSlot: 0, role: .approve),
            fieldMask: [field],
            values: [field: .keyAction(.shortcut(try AhaKeyDesiredConfiguration.Shortcut(keyCode: 0x04)))],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false
        )
    }

    private func keyDescriptionPlan() -> AhaKeyStudioScopedWritePlan {
        let field = AhaKeyStudioFieldID.keyDescription(modeSlot: 0, role: .approve)
        return AhaKeyStudioScopedWritePlan(
            pageID: .key(modeSlot: 0, role: .approve),
            fieldMask: [field],
            values: [field: .text("ok")],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false
        )
    }

    private func lightBrightnessPlan() -> AhaKeyStudioScopedWritePlan {
        let field = AhaKeyStudioFieldID.lightBrightness(modeSlot: 0)
        return AhaKeyStudioScopedWritePlan(
            pageID: .lights(modeSlot: 0),
            fieldMask: [field],
            values: [field: .integer(40)],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false
        )
    }

    private func lightMappingPlan() -> AhaKeyStudioScopedWritePlan {
        let field = AhaKeyStudioFieldID.lightMapping(modeSlot: 0, state: 1)
        return AhaKeyStudioScopedWritePlan(
            pageID: .lights(modeSlot: 0),
            fieldMask: [field],
            values: [field: .text("solid")],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false
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
        identifier: String? = nil,
        logicalSet: Int = 0
    ) throws -> (AhaKeyStudioScopedWritePlan, [AhaKeyConfigurationResource]) {
        let physical = AhaKeyOLEDSyncPlan.physicalTaskSetIndex(profile: .legacyStandard, logicalSet: logicalSet)
        let resolvedID = identifier ?? AhaKeyStudioPackageAssembler.taskAssetIdentifier(
            mode: 0,
            set: physical,
            state: .working
        )
        let resource = try verifiedGIF(bytes, identifier: resolvedID)
        let field = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: logicalSet, state: .working)
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
            writeTaskSetA: logicalSet == 0 || physical == 0,
            writeTaskSetB: logicalSet == 1 && physical == 1,
            activateTaskSet: logicalSet,
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

    private func standardThreeStatePlan() throws -> (AhaKeyStudioScopedWritePlan, [AhaKeyConfigurationResource]) {
        let states: [AhaKeyDesiredConfiguration.TaskDisplayState] = [.working, .waiting, .done]
        var values: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue] = [:]
        var resources: [AhaKeyConfigurationResource] = []
        var inputs: [AhaKeyStudioResourceInput] = []
        for state in states {
            let field = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: 0, state: state)
            values[field] = .asset(
                path: nil,
                framesPerSecond: 10,
                declaredFrameCount: 1,
                pixelWidth: 160,
                pixelHeight: 80
            )
            let identifier = AhaKeyStudioPackageAssembler.taskAssetIdentifier(mode: 0, set: 0, state: state)
            let resource = try verifiedGIF(Data("gif-\(state.rawValue)".utf8), identifier: identifier)
            resources.append(resource)
            inputs.append(
                AhaKeyStudioResourceInput(
                    logicalIdentifier: resource.logicalIdentifier,
                    fileURL: URL(fileURLWithPath: "/tmp/\(identifier).gif"),
                    declaredFrameCount: 1,
                    pixelWidth: 160,
                    pixelHeight: 80
                )
            )
        }
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: Set(values.keys),
            values: values,
            overwriteSemantic: true,
            writeTaskSetA: true,
            writeTaskSetB: false,
            activateTaskSet: 0,
            emitsSetActiveSetOpcode: false,
            resources: inputs
        )
        return (plan, resources)
    }

    private func rhinoABReusePlan(
        bytes: Data
    ) throws -> (AhaKeyStudioScopedWritePlan, [AhaKeyConfigurationResource]) {
        let digest = SHA256.hash(data: bytes)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        var values: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue] = [:]
        var resources: [AhaKeyConfigurationResource] = []
        var inputs: [AhaKeyStudioResourceInput] = []
        for logicalSet in [0, 1] {
            let field = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: logicalSet, state: .working)
            values[field] = .asset(
                path: nil,
                framesPerSecond: 10,
                declaredFrameCount: 1,
                pixelWidth: 160,
                pixelHeight: 80
            )
            let identifier = AhaKeyStudioPackageAssembler.taskAssetIdentifier(
                mode: 0,
                set: logicalSet,
                state: .working
            )
            let resource = try AhaKeyConfigurationResource(
                logicalIdentifier: identifier,
                sha256: hex,
                byteCount: UInt64(bytes.count),
                mediaType: "image/gif"
            )
            resources.append(resource)
            inputs.append(
                AhaKeyStudioResourceInput(
                    logicalIdentifier: resource.logicalIdentifier,
                    fileURL: URL(fileURLWithPath: "/tmp/\(identifier).gif"),
                    declaredFrameCount: 1,
                    pixelWidth: 160,
                    pixelHeight: 80
                )
            )
        }
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: Set(values.keys),
            values: values,
            overwriteSemantic: false,
            writeTaskSetA: true,
            writeTaskSetB: true,
            activateTaskSet: 0,
            emitsSetActiveSetOpcode: false,
            resources: inputs
        )
        return (plan, resources)
    }
}
