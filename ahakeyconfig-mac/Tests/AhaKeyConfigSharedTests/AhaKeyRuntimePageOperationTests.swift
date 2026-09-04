import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyRuntimePageOperationTests: XCTestCase {
    private struct AllowingResourceValidator: AhaKeyRuntimePackageAcceptanceValidator {
        func validate(
            package: AhaKeyConfigurationPackage,
            resources: [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput]
        ) throws {}
    }
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
        let pictureAFixture = try pictureWritePlan(bytes: Data("gif-a".utf8), logicalSet: 0)
        let pictureA = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: pictureAFixture.plan,
            profile: .legacyStandard,
            verifiedResources: pictureAFixture.resources
        )
        let pictureBFixture = try pictureWritePlan(bytes: Data("gif-a".utf8), logicalSet: 1)
        let pictureB = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: pictureBFixture.plan,
            profile: .legacyStandard,
            verifiedResources: pictureBFixture.resources
        )
        XCTAssertEqual(status.family, .legacyStandard)
        XCTAssertEqual(status.actions.map(\.command), [.screenStatus])
        XCTAssertNil(status.actions[0].opcode)
        XCTAssertNil(status.actions[0].subtype)
        XCTAssertNil(status.prepareStrategy)
        XCTAssertEqual(fps.actions.map(\.command), [.screenFramesPerSecond])
        XCTAssertEqual(key.actions.map(\.command), [.keyShortcut])
        XCTAssertEqual(key.actions[0].opcode, 0x73)
        XCTAssertEqual(key.actions[0].subtype, 0x73)
        XCTAssertEqual(description.actions.map(\.command), [.keyDescription])
        XCTAssertEqual(description.actions[0].opcode, 0x73)
        XCTAssertEqual(description.actions[0].subtype, 0x75)
        XCTAssertEqual(brightness.actions.map(\.command), [.lightBrightness])
        XCTAssertEqual(brightness.actions[0].opcode, 0x85)
        XCTAssertNil(brightness.actions[0].subtype)
        XCTAssertEqual(mapping.actions.map(\.command), [.lightMapping])
        XCTAssertEqual(mapping.actions[0].opcode, 0x84)
        XCTAssertEqual(active.actions.map(\.command), [.setActiveSet])
        XCTAssertEqual(active.actions[0].opcode, 0x97)
        XCTAssertEqual(pictureA.actions[0].logicalSet, 0)
        XCTAssertEqual(pictureA.actions[0].physicalSlot, 0)
        XCTAssertEqual(pictureA.prepareStrategy?.opcode, 0x80)
        XCTAssertEqual(pictureA.prepareStrategy?.perChunk, true)
        XCTAssertEqual(
            try XCTUnwrap(pictureA.prepareStrategy).prepareCount(encodedFrameCount: 1),
            try AhaKeyRuntimePageSemantic.picturePrepareCount(encodedFrameCount: 1)
        )
        XCTAssertEqual(try AhaKeyRuntimePageSemantic.picturePrepareCount(encodedFrameCount: 1), 7)
        XCTAssertEqual(
            try AhaKeyRuntimePageSemantic.physicalSlot(profile: .legacyStandard, logicalSet: 1),
            0
        )
        XCTAssertEqual(
            try AhaKeyRuntimeCompatibilityFingerprint.Family.make(.legacyStandard)
                .physicalSlot(forLogicalSet: 1),
            0
        )
        XCTAssertNil(pictureA.defaultBindOpcode)
        XCTAssertEqual(
            pictureA.actions[0].resourceIdentity,
            AhaKeyRuntimePictureResourceIdentity(
                logicalID: pictureAFixture.resources[0].logicalIdentifier,
                sha256: pictureAFixture.resources[0].sha256,
                byteCount: pictureAFixture.resources[0].byteCount,
                mediaType: pictureAFixture.resources[0].mediaType
            )
        )
        XCTAssertEqual(pictureA.actions[0].encodedFrameCount, 1)
        XCTAssertEqual(pictureB.actions[0].logicalSet, 1)
        XCTAssertEqual(pictureB.actions[0].physicalSlot, 0)
        XCTAssertNotEqual(pictureA, pictureB)
        XCTAssertNotEqual(status, fps)
        XCTAssertNotEqual(key, description)
        XCTAssertNotEqual(brightness, mapping)
        XCTAssertNotEqual(status, pictureA)
        XCTAssertNotEqual(status, active)
        if case .picture(let semantics) = pictureA.actions[0].command {
            XCTAssertEqual(semantics.bindOpcode, 0x93)
            XCTAssertEqual(pictureA.actions[0].opcode, 0x93)
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

    func testPrepareStrategyMatchesProductionUploadForTwoFramesAndTwoResources() throws {
        try assertPrepareIsomorphism(
            profile: .legacyStandard,
            expectedOpcode: AhaKeyWireFrameBuilder.cmdPrepareWrite,
            usesSession: false,
            specs: [
                (bytes: Data("gif-a".utf8), logicalSet: 0, state: .working, frames: 2),
                (bytes: Data("gif-b".utf8), logicalSet: 0, state: .waiting, frames: 2),
            ]
        )
        try assertPrepareIsomorphism(
            profile: .rhinoDualSet(sessionUploadAdvertised: true),
            expectedOpcode: AhaKeyWireFrameBuilder.cmdPrepareSessionWrite,
            usesSession: true,
            specs: [
                (bytes: Data("gif-a".utf8), logicalSet: 0, state: .working, frames: 2),
                (bytes: Data("gif-b".utf8), logicalSet: 1, state: .working, frames: 2),
            ]
        )
        try assertPrepareIsomorphism(
            profile: .currentSessionCapable,
            expectedOpcode: AhaKeyWireFrameBuilder.cmdPrepareSessionWrite,
            usesSession: true,
            specs: [
                (bytes: Data("gif-a".utf8), logicalSet: 0, state: .working, frames: 2),
                (bytes: Data("gif-b".utf8), logicalSet: 1, state: .working, frames: 2),
            ]
        )
    }

    func testPhysicalSlotGenerationAndValidationShareFamilyDescriptor() throws {
        XCTAssertEqual(
            try AhaKeyRuntimePageSemantic.physicalSlot(profile: .legacyStandard, logicalSet: 1),
            try AhaKeyRuntimeCompatibilityFingerprint.Family.make(.legacyStandard)
                .physicalSlot(forLogicalSet: 1)
        )
        XCTAssertEqual(
            try AhaKeyRuntimePageSemantic.physicalSlot(
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                logicalSet: 1
            ),
            try AhaKeyRuntimeCompatibilityFingerprint.Family.make(
                .rhinoDualSet(sessionUploadAdvertised: false)
            ).physicalSlot(forLogicalSet: 1)
        )
        XCTAssertEqual(
            try AhaKeyRuntimePageSemantic.physicalSlot(profile: .currentSessionCapable, logicalSet: 1),
            try AhaKeyRuntimeCompatibilityFingerprint.Family.make(.currentSessionCapable)
                .physicalSlot(forLogicalSet: 1)
        )
    }

    func testStandardThreeStateSameGeometryBindsEachFieldOnce() throws {
        let fixture = try standardThreeStatePlan()
        let package = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: fixture.plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: fixture.resources
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
        let fingerprint = try XCTUnwrap(package.pageOperation?.compatibilityFingerprint)
        XCTAssertEqual(fingerprint.actions.count, 3)
        XCTAssertEqual(fingerprint.prepareStrategy?.opcode, 0x80)
        XCTAssertEqual(fingerprint.prepareStrategy?.perChunk, true)
        XCTAssertEqual(try XCTUnwrap(fingerprint.prepareStrategy).prepareCount(encodedFrameCount: 1), 7)
        XCTAssertNil(fingerprint.defaultBindOpcode)
        XCTAssertEqual(Set(fingerprint.actions.compactMap(\.opcode)), [0x93])
        for action in fingerprint.actions {
            let binding = try XCTUnwrap(bindings.first { $0.fieldID == action.fieldID })
            XCTAssertEqual(action.resourceIdentity, binding.pictureIdentity)
            XCTAssertEqual(action.encodedFrameCount, binding.encodedFrameCount)
        }
    }

    func testRhinoABReuseSameDigestDifferentLogicalIDs() throws {
        let bytes = Data("shared-gif".utf8)
        let fixture = try rhinoABReusePlan(bytes: bytes)
        XCTAssertEqual(fixture.resources[0].sha256, fixture.resources[1].sha256)
        XCTAssertNotEqual(fixture.resources[0].logicalIdentifier, fixture.resources[1].logicalIdentifier)
        let package = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: fixture.plan,
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: fixture.resources
        )
        let actions = try XCTUnwrap(package.pageOperation?.compatibilityFingerprint.actions)
        let bindings = try XCTUnwrap(package.pageOperation?.resourceBindings)
        XCTAssertEqual(actions.map(\.logicalSet), [0, 1])
        XCTAssertEqual(actions.map(\.physicalSlot), [0, 1])
        XCTAssertNotEqual(actions[0], actions[1])
        XCTAssertNotEqual(actions[0].resourceIdentity, actions[1].resourceIdentity)
        for action in actions {
            let binding = try XCTUnwrap(bindings.first { $0.fieldID == action.fieldID })
            XCTAssertEqual(action.resourceIdentity, binding.pictureIdentity)
        }
    }

    func testBindingRejectsMissingDuplicateAndWrongField() throws {
        let fixture = try pictureWritePlan(bytes: Data("gif".utf8), logicalSet: 0)
        var missing = fixture.plan
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
        var wrong = fixture.plan
        let wrongID = try AhaKeyResourceIdentifier("mode0-set1-working")
        wrong.resources[0].logicalIdentifier = wrongID
        var wrongResources = fixture.resources
        wrongResources[0] = try AhaKeyConfigurationResource(
            logicalIdentifier: wrongID.rawValue,
            sha256: fixture.resources[0].sha256.rawValue,
            byteCount: fixture.resources[0].byteCount,
            mediaType: fixture.resources[0].mediaType.rawValue
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
        let extra = fixture.resources + [
            try verifiedGIF(Data("other".utf8), identifier: "mode0-set0-waiting"),
        ]
        var extraPlan = fixture.plan
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

    func testFingerprintDecoderRejectsImpossibleSemanticsAndWALReopen() async throws {
        let fixture = try pictureWritePlan(bytes: Data("gif".utf8), logicalSet: 0)
        let valid = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: fixture.plan,
            profile: .legacyStandard,
            verifiedResources: fixture.resources
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
            root["sessionOpcode"] = 255
        })
        XCTAssertThrowsError(try decodeMutating { root in
            var strategy = try XCTUnwrap(root["prepareStrategy"] as? [String: Any])
            strategy["opcode"] = 255
            root["prepareStrategy"] = strategy
        })
        XCTAssertThrowsError(try decodeMutating { root in
            var strategy = try XCTUnwrap(root["prepareStrategy"] as? [String: Any])
            strategy["perChunk"] = false
            root["prepareStrategy"] = strategy
        })
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
            plan: fixture.plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: fixture.resources
        )
        XCTAssertEqual(package.schemaVersion, AhaKeyConfigurationPackage.pageScopedSchemaVersion)
        let roundTrip = try JSONDecoder().decode(
            AhaKeyConfigurationPackage.self,
            from: try JSONEncoder().encode(package)
        )
        XCTAssertEqual(roundTrip, package)

        let statusAction = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(status.actions[0])) as? [String: Any]
        )
        let threeState = try standardThreeStatePlan()
        let threeStatePackage = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: threeState.plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: threeState.resources
        )
        let rhino = try rhinoABReusePlan(bytes: Data("shared-gif".utf8))
        let rhinoPackage = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: rhino.plan,
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: rhino.resources
        )
        let keyPackage = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: try keyActionPlan(),
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: []
        )

        try await assertSchema2WALReopenFailsClosed(package: package, sourceBytes: fixture.sourceBytes) { root in
            try mutateFingerprintActions(in: &root) { actions in
                var command = try XCTUnwrap(actions[0]["command"] as? [String: Any])
                var picture = try XCTUnwrap(command["picture"] as? [String: Any])
                picture["bindOpcode"] = 255
                command["picture"] = picture
                actions[0]["command"] = command
            }
        }
        try await assertSchema2WALReopenFailsClosed(package: package, sourceBytes: fixture.sourceBytes) { root in
            try mutateFingerprintActions(in: &root) { actions in
                actions[0] = statusAction
            }
        }
        try await assertSchema2WALReopenFailsClosed(package: package, sourceBytes: fixture.sourceBytes) { root in
            try mutateFingerprintActions(in: &root) { actions in
                actions.append(actions[0])
            }
        }
        try await assertSchema2WALReopenFailsClosed(
            package: threeStatePackage,
            sourceBytes: threeState.sourceBytes
        ) { root in
            try mutateFingerprintActions(in: &root) { actions in
                actions.reverse()
            }
        }
        try await assertSchema2WALReopenFailsClosed(package: keyPackage, sourceBytes: [:]) { root in
            try mutateFingerprintActions(in: &root) { actions in
                actions[0]["opcode"] = 0x84
            }
        }
        try await assertSchema2WALReopenFailsClosed(package: package, sourceBytes: fixture.sourceBytes) { root in
            try mutateFingerprintActions(in: &root) { actions in
                actions[0]["logicalSet"] = 1
            }
        }
        try await assertSchema2WALReopenFailsClosed(package: keyPackage, sourceBytes: [:]) { root in
            try mutateFingerprintActions(in: &root) { actions in
                actions[0]["subtype"] = 0x75
            }
        }
        try await assertSchema2WALReopenFailsClosed(
            package: threeStatePackage,
            sourceBytes: threeState.sourceBytes
        ) { root in
            try swapCoordinatedResourceIdentities(in: &root, first: 0, second: 1)
        }
        try await assertSchema2WALReopenFailsClosed(
            package: rhinoPackage,
            sourceBytes: rhino.sourceBytes
        ) { root in
            try swapCoordinatedResourceIdentities(in: &root, first: 0, second: 1)
        }
        try await assertSchema2WALReopenFailsClosed(package: package, sourceBytes: fixture.sourceBytes) { root in
            try mutateFingerprint(in: &root) { fingerprint in
                var strategy = try XCTUnwrap(fingerprint["prepareStrategy"] as? [String: Any])
                strategy["perChunk"] = false
                fingerprint["prepareStrategy"] = strategy
            }
        }
        try await assertSchema2WALReopenFailsClosed(package: package, sourceBytes: fixture.sourceBytes) { root in
            try mutateFingerprint(in: &root) { fingerprint in
                var strategy = try XCTUnwrap(fingerprint["prepareStrategy"] as? [String: Any])
                strategy["opcode"] = 255
                fingerprint["prepareStrategy"] = strategy
            }
        }
        try await assertSchema2WALReopenFailsClosed(package: package, sourceBytes: fixture.sourceBytes) { root in
            try mutateFingerprint(in: &root) { fingerprint in
                var strategy = try XCTUnwrap(fingerprint["prepareStrategy"] as? [String: Any])
                strategy["chunkBytes"] = 1
                fingerprint["prepareStrategy"] = strategy
            }
        }
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
        let fixtureA = try pictureWritePlan(bytes: Data("gif-one".utf8))
        let fixtureB = try pictureWritePlan(bytes: Data("gif-two".utf8))
        let first = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: fixtureA.plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: fixtureA.resources,
            operationID: operationID
        )
        let second = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: fixtureB.plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: fixtureB.resources,
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

    private struct PageFixture {
        let plan: AhaKeyStudioScopedWritePlan
        let resources: [AhaKeyConfigurationResource]
        let sourceBytes: [AhaKeyResourceIdentifier: Data]
    }

    private func assertPrepareIsomorphism(
        profile: AhaKeyOLEDCompatibilityProfile,
        expectedOpcode: UInt8,
        usesSession: Bool,
        specs: [(bytes: Data, logicalSet: Int, state: AhaKeyDesiredConfiguration.TaskDisplayState, frames: Int)]
    ) throws {
        let fixture = try multiPicturePlan(profile: profile, specs: specs)
        let fingerprint = try AhaKeyRuntimeCompatibilityFingerprint.make(
            plan: fixture.plan,
            profile: profile,
            verifiedResources: fixture.resources
        )
        let strategy = try XCTUnwrap(fingerprint.prepareStrategy)
        XCTAssertEqual(strategy.opcode, expectedOpcode)
        XCTAssertEqual(strategy.perChunk, true)
        let package = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: fixture.plan,
            profile: profile,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: fixture.resources
        )
        let pagePlan = try AhaKeyRuntimePageSemantic.executionPlan(
            package: package,
            userSlotLimit: 288
        )
        XCTAssertFalse(pagePlan.identities.contains { $0.rawValue.hasPrefix("base:mode:") })
        var expectedTotal = 0
        var productionPrepares: [(length: Int, address: UInt32, session: Bool)] = []
        var planPrepares: [(length: Int, address: UInt32, session: Bool)] = []
        for (index, binding) in package.pageOperation!.resourceBindings.sorted(by: {
            $0.fieldID < $1.fieldID
        }).enumerated() {
            let frames = Int(binding.encodedFrameCount)
            XCTAssertGreaterThanOrEqual(frames, 2)
            let count = try strategy.prepareCount(encodedFrameCount: frames)
            expectedTotal += count
            let production = try XCTUnwrap(
                AhaKeyConfigurationStepMapper.resourceUploadProgram(
                    digest: binding.sha256,
                    slotIndex: index,
                    encodedFrameCount: frames,
                    usesSessionUpload: usesSession,
                    userSlotLimit: 288
                )
            )
            productionPrepares.append(contentsOf: prepareSignatures(production, usesSession: usesSession))
            let chunkSteps = pagePlan.steps.filter {
                $0.resourceID == binding.logicalID && $0.identity.rawValue.hasPrefix("page:chunk:")
            }
            XCTAssertEqual(chunkSteps.count, count)
            planPrepares.append(contentsOf: prepareSignatures(
                chunkSteps.flatMap(\.program),
                usesSession: usesSession
            ))
        }
        XCTAssertEqual(expectedTotal, 28)
        XCTAssertEqual(productionPrepares.count, 28)
        XCTAssertEqual(planPrepares.count, productionPrepares.count)
        for (planStep, productionStep) in zip(planPrepares, productionPrepares) {
            XCTAssertEqual(planStep.length, productionStep.length)
            XCTAssertEqual(planStep.address, productionStep.address)
            XCTAssertEqual(planStep.session, productionStep.session)
        }
        XCTAssertEqual(strategy.opcode == AhaKeyWireFrameBuilder.cmdPrepareWrite, !usesSession)
        XCTAssertEqual(strategy.opcode == AhaKeyWireFrameBuilder.cmdPrepareSessionWrite, usesSession)
    }

    private func prepareSignatures(
        _ steps: [AhaKeyDeviceProgramStep],
        usesSession: Bool
    ) -> [(length: Int, address: UInt32, session: Bool)] {
        steps.compactMap { step in
            guard case .prepareWrite(let sessionID, let length, let address) = step else { return nil }
            XCTAssertEqual(sessionID != nil, usesSession)
            return (length: length, address: address, session: sessionID != nil)
        }
    }

    private func multiPicturePlan(
        profile: AhaKeyOLEDCompatibilityProfile,
        specs: [(bytes: Data, logicalSet: Int, state: AhaKeyDesiredConfiguration.TaskDisplayState, frames: Int)]
    ) throws -> PageFixture {
        var values: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue] = [:]
        var resources: [AhaKeyConfigurationResource] = []
        var inputs: [AhaKeyStudioResourceInput] = []
        var sourceBytes: [AhaKeyResourceIdentifier: Data] = [:]
        var writeA = false
        var writeB = false
        for spec in specs {
            let physical = Int(try AhaKeyRuntimePageSemantic.physicalSlot(
                profile: profile,
                logicalSet: spec.logicalSet
            ))
            if spec.logicalSet == 0 { writeA = true }
            if spec.logicalSet == 1 && physical == 1 { writeB = true }
            let field = AhaKeyStudioFieldID.screenTaskAsset(
                modeSlot: 0,
                setIndex: spec.logicalSet,
                state: spec.state
            )
            values[field] = .asset(
                path: nil,
                framesPerSecond: 10,
                declaredFrameCount: spec.frames,
                pixelWidth: 160,
                pixelHeight: 80
            )
            let identifier = AhaKeyStudioPackageAssembler.taskAssetIdentifier(
                mode: 0,
                set: physical,
                state: spec.state
            )
            let resource = try verifiedGIF(spec.bytes, identifier: identifier)
            resources.append(resource)
            sourceBytes[resource.logicalIdentifier] = spec.bytes
            inputs.append(
                AhaKeyStudioResourceInput(
                    logicalIdentifier: resource.logicalIdentifier,
                    fileURL: URL(fileURLWithPath: "/tmp/\(identifier).gif"),
                    declaredFrameCount: spec.frames,
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
            writeTaskSetA: writeA,
            writeTaskSetB: writeB,
            activateTaskSet: 0,
            emitsSetActiveSetOpcode: false,
            resources: inputs
        )
        return PageFixture(plan: plan, resources: resources, sourceBytes: sourceBytes)
    }

    private func pictureWritePlan(
        bytes: Data,
        identifier: String? = nil,
        logicalSet: Int = 0
    ) throws -> PageFixture {
        let physical = Int(try AhaKeyRuntimePageSemantic.physicalSlot(profile: .legacyStandard, logicalSet: logicalSet))
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
        return PageFixture(
            plan: plan,
            resources: [resource],
            sourceBytes: [resource.logicalIdentifier: bytes]
        )
    }

    private func standardThreeStatePlan() throws -> PageFixture {
        let states: [AhaKeyDesiredConfiguration.TaskDisplayState] = [.working, .waiting, .done]
        var values: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue] = [:]
        var resources: [AhaKeyConfigurationResource] = []
        var inputs: [AhaKeyStudioResourceInput] = []
        var sourceBytes: [AhaKeyResourceIdentifier: Data] = [:]
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
            let bytes = Data("gif-\(state.rawValue)".utf8)
            let resource = try verifiedGIF(bytes, identifier: identifier)
            resources.append(resource)
            sourceBytes[resource.logicalIdentifier] = bytes
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
        return PageFixture(plan: plan, resources: resources, sourceBytes: sourceBytes)
    }

    private func rhinoABReusePlan(
        bytes: Data
    ) throws -> PageFixture {
        let digest = SHA256.hash(data: bytes)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        var values: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue] = [:]
        var resources: [AhaKeyConfigurationResource] = []
        var inputs: [AhaKeyStudioResourceInput] = []
        var sourceBytes: [AhaKeyResourceIdentifier: Data] = [:]
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
            sourceBytes[resource.logicalIdentifier] = bytes
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
        return PageFixture(plan: plan, resources: resources, sourceBytes: sourceBytes)
    }

    private func mutateFingerprint(
        in root: inout [String: Any],
        _ body: (inout [String: Any]) throws -> Void
    ) throws {
        var pageOperation = try XCTUnwrap(root["pageOperation"] as? [String: Any])
        var fingerprint = try XCTUnwrap(pageOperation["compatibilityFingerprint"] as? [String: Any])
        try body(&fingerprint)
        pageOperation["compatibilityFingerprint"] = fingerprint
        root["pageOperation"] = pageOperation
    }

    private func mutateFingerprintActions(
        in root: inout [String: Any],
        _ body: (inout [[String: Any]]) throws -> Void
    ) throws {
        try mutateFingerprint(in: &root) { fingerprint in
            var actions = try XCTUnwrap(fingerprint["actions"] as? [[String: Any]])
            try body(&actions)
            fingerprint["actions"] = actions
        }
    }

    private func swapCoordinatedResourceIdentities(
        in root: inout [String: Any],
        first: Int,
        second: Int
    ) throws {
        var pageOperation = try XCTUnwrap(root["pageOperation"] as? [String: Any])
        var bindings = try XCTUnwrap(pageOperation["resourceBindings"] as? [[String: Any]])
        var fingerprint = try XCTUnwrap(pageOperation["compatibilityFingerprint"] as? [String: Any])
        var actions = try XCTUnwrap(fingerprint["actions"] as? [[String: Any]])
        let firstField = try XCTUnwrap(bindings[first]["fieldID"] as? String)
        let secondField = try XCTUnwrap(bindings[second]["fieldID"] as? String)
        var firstBinding = bindings[first]
        var secondBinding = bindings[second]
        swapIdentityPayload(&firstBinding, &secondBinding)
        bindings[first] = firstBinding
        bindings[second] = secondBinding
        let firstAction = try XCTUnwrap(actions.firstIndex { ($0["fieldID"] as? String) == firstField })
        let secondAction = try XCTUnwrap(actions.firstIndex { ($0["fieldID"] as? String) == secondField })
        var firstIdentity = try XCTUnwrap(actions[firstAction]["resourceIdentity"] as? [String: Any])
        var secondIdentity = try XCTUnwrap(actions[secondAction]["resourceIdentity"] as? [String: Any])
        swapIdentityPayload(&firstIdentity, &secondIdentity)
        actions[firstAction]["resourceIdentity"] = firstIdentity
        actions[secondAction]["resourceIdentity"] = secondIdentity
        fingerprint["actions"] = actions
        pageOperation["resourceBindings"] = bindings
        pageOperation["compatibilityFingerprint"] = fingerprint
        root["pageOperation"] = pageOperation
    }

    private func swapIdentityPayload(_ first: inout [String: Any], _ second: inout [String: Any]) {
        for key in ["logicalID", "sha256", "byteCount", "mediaType"] {
            let temporary = first[key]
            first[key] = second[key]
            second[key] = temporary
        }
    }

    private func assertSchema2WALReopenFailsClosed(
        package: AhaKeyConfigurationPackage,
        sourceBytes: [AhaKeyResourceIdentifier: Data],
        mutate: (inout [String: Any]) throws -> Void
    ) async throws {
        XCTAssertEqual(package.schemaVersion, AhaKeyConfigurationPackage.pageScopedSchemaVersion)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("c3ar4-wal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        var resourceFiles: [AhaKeyResourceIdentifier: URL] = [:]
        for (identifier, bytes) in sourceBytes {
            let file = storeRoot.appendingPathComponent("res-\(identifier.rawValue).bin")
            try bytes.write(to: file)
            resourceFiles[identifier] = file
        }
        do {
            let store = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeRoot,
                acceptanceValidator: AllowingResourceValidator()
            )
            _ = try await store.accept(package, resourceFiles: resourceFiles)
            let queue = try await store.durableDeviceQueue(package.targetDeviceID)
            XCTAssertEqual(queue.items.count, 1)
            XCTAssertEqual(queue.items.first?.package.schemaVersion, 2)
        }
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(package)) as? [String: Any]
        )
        try mutate(&object)
        let tampered = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(AhaKeyConfigurationPackage.self, from: tampered))
        try replacePackageBlob(root: storeRoot, operationID: package.operationID, blob: tampered)
        let reopened = try AhaKeyRuntimePersistentStore(
            rootDirectory: storeRoot,
            acceptanceValidator: AllowingResourceValidator()
        )
        let health = try await reopened.health()
        XCTAssertEqual(health.journalMode, "wal")
        do {
            _ = try await reopened.recoveryCandidates()
            XCTFail("篡改后的 schema=2 WAL 重开必须 fail-closed")
        } catch {
            XCTAssertNotNil(error)
        }
        do {
            _ = try await reopened.durableDeviceQueue(package.targetDeviceID)
            XCTFail("篡改 WAL 不得投影出队列项")
        } catch {
            XCTAssertNotNil(error)
        }
        do {
            _ = try await reopened.transaction(package.operationID)
            XCTFail("篡改 WAL 不得读出伪造 transaction")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    private func replacePackageBlob(
        root: URL,
        operationID: AhaKeyRuntimeOperationID,
        blob: Data
    ) throws {
        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                "UPDATE runtime_transactions SET package = ? WHERE operation_id = ?",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(statement) }
        blob.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(
                statement,
                1,
                bytes.baseAddress,
                Int32(blob.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }
        let operationIDText = operationID.rawValue.uuidString
        _ = operationIDText.withCString {
            sqlite3_bind_text(statement, 2, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        XCTAssertEqual(sqlite3_changes(database), 1)
    }
}
