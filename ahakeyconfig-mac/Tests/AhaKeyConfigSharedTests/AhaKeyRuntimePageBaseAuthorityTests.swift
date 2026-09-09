import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyRuntimePageBaseAuthorityTests: XCTestCase {
    private struct AllowingResourceValidator: AhaKeyRuntimePackageAcceptanceValidator {
        func validate(
            package: AhaKeyConfigurationPackage,
            resources: [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput]
        ) throws {}
    }

    func testAdvertisedSchemasIncludeFieldBaselineFromSingleSource() {
        XCTAssertEqual(
            AhaKeyConfigurationPackage.advertisedSchemaVersions,
            [1, 2, 3]
        )
        XCTAssertTrue(AhaKeyConfigurationPackage.isPageScopedSchema(2))
        XCTAssertTrue(AhaKeyConfigurationPackage.isPageScopedSchema(3))
        XCTAssertFalse(AhaKeyConfigurationPackage.isPageScopedSchema(1))
    }

    func testObjectPresentFreezesSchema2AndDoesNotUseFieldProof() throws {
        let object = Data("whole-object".utf8)
        let decision = try AhaKeyRuntimePageBaseAuthority.resolve(
            authoritativeObject: object,
            overwriteSemantic: false,
            deviceID: try AhaKeyRuntimeDeviceID("DEV"),
            pageID: .screen(modeSlot: 0),
            fieldMask: [.screenStatusLine(modeSlot: 0)],
            liveBaselines: [],
            supportedSchemas: AhaKeyConfigurationPackage.advertisedSchemaVersions
        )
        XCTAssertEqual(decision.schemaVersion, 2)
        XCTAssertEqual(
            decision.objectFingerprint,
            try AhaKeyRuntimeObjectFingerprint.hashing(object)
        )
        XCTAssertNil(decision.fieldBaselines)
    }

    func testEmptyObjectDoesNotBecomeSentinelFingerprint() throws {
        XCTAssertThrowsError(
            try AhaKeyRuntimePageBaseAuthority.resolve(
                authoritativeObject: Data(),
                overwriteSemantic: false,
                deviceID: try AhaKeyRuntimeDeviceID("DEV"),
                pageID: .screen(modeSlot: 0),
                fieldMask: [.screenStatusLine(modeSlot: 0)],
                liveBaselines: [],
                supportedSchemas: AhaKeyConfigurationPackage.advertisedSchemaVersions
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyRuntimePageBaseAuthorityError,
                .overwriteConfirmationRequired
            )
        }
    }

    func testAbsentFieldsWithoutOverwriteStayConfirmation() throws {
        XCTAssertThrowsError(
            try AhaKeyRuntimePageBaseAuthority.resolve(
                authoritativeObject: nil,
                overwriteSemantic: false,
                deviceID: try AhaKeyRuntimeDeviceID("DEV"),
                pageID: .screen(modeSlot: 0),
                fieldMask: [.screenStatusLine(modeSlot: 0)],
                liveBaselines: [],
                supportedSchemas: AhaKeyConfigurationPackage.advertisedSchemaVersions
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyRuntimePageBaseAuthorityError,
                .overwriteConfirmationRequired
            )
        }
    }

    func testOldPeerWithoutSchema3FailsClosed() throws {
        XCTAssertThrowsError(
            try AhaKeyRuntimePageBaseAuthority.resolve(
                authoritativeObject: nil,
                overwriteSemantic: true,
                deviceID: try AhaKeyRuntimeDeviceID("DEV"),
                pageID: .screen(modeSlot: 0),
                fieldMask: [.screenStatusLine(modeSlot: 0)],
                liveBaselines: [],
                supportedSchemas: [1, 2]
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyRuntimePageBaseAuthorityError,
                .unsupportedPeerForFirstPageBaseline
            )
        }
    }

    func testOverwriteOnAbsentFieldsProducesExactAbsentProof() throws {
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let decision = try AhaKeyRuntimePageBaseAuthority.resolve(
            authoritativeObject: nil,
            overwriteSemantic: true,
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            liveBaselines: [],
            supportedSchemas: AhaKeyConfigurationPackage.advertisedSchemaVersions
        )
        XCTAssertEqual(decision.schemaVersion, 3)
        let proof = try XCTUnwrap(decision.fieldBaselines)
        XCTAssertEqual(proof.fieldMask, [field])
        XCTAssertEqual(proof.expectations.count, 1)
        XCTAssertEqual(proof.expectations[0].kind, .absent)
        XCTAssertNil(proof.expectations[0].trust)
        XCTAssertTrue(proof.requiresOverwriteConfirmation)
    }

    func testUnknownRowIsNotAbsent() throws {
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let unknown = AhaKeyRuntimeFieldBaseline(
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldID: field,
            value: .text("ghost"),
            trust: .unknown,
            provenance: .writeConfirmation
        )
        let decision = try AhaKeyRuntimePageBaseAuthority.resolve(
            authoritativeObject: nil,
            overwriteSemantic: true,
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            liveBaselines: [unknown]
        )
        let proof = try XCTUnwrap(decision.fieldBaselines)
        XCTAssertEqual(proof.expectations[0].kind, .baseline)
        XCTAssertEqual(proof.expectations[0].trust, .unknown)
        XCTAssertEqual(proof.expectations[0].value, .text("ghost"))
        XCTAssertTrue(proof.requiresOverwriteConfirmation)
    }

    func testDurableFieldsDoNotRequireOverwrite() throws {
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let confirmed = AhaKeyRuntimeFieldBaseline(
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldID: field,
            value: .text("kept"),
            trust: .writeConfirmed,
            provenance: .writeConfirmation,
            operationID: .init()
        )
        let decision = try AhaKeyRuntimePageBaseAuthority.resolve(
            authoritativeObject: nil,
            overwriteSemantic: false,
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            liveBaselines: [confirmed]
        )
        XCTAssertEqual(decision.schemaVersion, 3)
        XCTAssertFalse(try XCTUnwrap(decision.fieldBaselines).requiresOverwriteConfirmation)
    }

    func testSchema2PackageRoundTripOmitsFieldBaselines() throws {
        let package = try statusPackage(overwrite: false, objectSeed: "base-object")
        XCTAssertEqual(package.schemaVersion, 2)
        XCTAssertNotNil(package.pageOperation?.baseObjectFingerprint)
        XCTAssertNil(package.pageOperation?.fieldBaselines)
        let encoded = try JSONEncoder().encode(package)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let page = try XCTUnwrap(object["pageOperation"] as? [String: Any])
        XCTAssertNotNil(page["baseObjectFingerprint"])
        XCTAssertNil(page["fieldBaselines"])
        let decoded = try JSONDecoder().decode(AhaKeyConfigurationPackage.self, from: encoded)
        XCTAssertEqual(decoded, package)
        XCTAssertEqual(decoded.schemaVersion, 2)
    }

    func testSchema3PackageRejectsObjectFingerprintAndWrongOneOf() throws {
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let proof = try AhaKeyRuntimePageFieldBaselineProof.make(
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            liveBaselines: []
        )
        let package = try AhaKeyConfigurationPackage.assemblePageFieldBaseline(
            plan: statusPlan(overwrite: true),
            profile: .legacyStandard,
            targetDeviceID: device,
            baseRevision: .init(0),
            fieldBaselines: proof,
            verifiedResources: []
        )
        XCTAssertEqual(package.schemaVersion, 3)
        XCTAssertTrue(package.usesPageRunner)
        XCTAssertNil(package.pageOperation?.baseObjectFingerprint)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(package)) as? [String: Any]
        )
        var page = try XCTUnwrap(object["pageOperation"] as? [String: Any])
        page["baseObjectFingerprint"] = String(repeating: "ab", count: 32)
        object["pageOperation"] = page
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyConfigurationPackage.self,
                from: try JSONSerialization.data(withJSONObject: object)
            )
        )
        XCTAssertThrowsError(
            try AhaKeyConfigurationPackage(
                schemaVersion: 3,
                targetDeviceID: device,
                baseRevision: .init(0),
                desiredConfiguration: Data("configuration".utf8),
                resources: [],
                pageOperation: package.pageOperation
            )
        )
    }

    func testCorruptFieldProofFailsDecodeAndWALReopen() async throws {
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let package = try fieldPackage(device: device, overwrite: true)
        try await assertWALReopenFailsClosed(package: package) { root in
            var page = try XCTUnwrap(root["pageOperation"] as? [String: Any])
            var proof = try XCTUnwrap(page["fieldBaselines"] as? [String: Any])
            proof["digest"] = String(repeating: "0", count: 64)
            page["fieldBaselines"] = proof
            root["pageOperation"] = page
        }
        try await assertWALReopenFailsClosed(package: package) { root in
            var page = try XCTUnwrap(root["pageOperation"] as? [String: Any])
            var proof = try XCTUnwrap(page["fieldBaselines"] as? [String: Any])
            var expectations = try XCTUnwrap(proof["expectations"] as? [[String: Any]])
            expectations[0]["kind"] = "baseline"
            proof["expectations"] = expectations
            page["fieldBaselines"] = proof
            root["pageOperation"] = page
        }
        try await assertWALReopenFailsClosed(package: package) { root in
            var page = try XCTUnwrap(root["pageOperation"] as? [String: Any])
            var proof = try XCTUnwrap(page["fieldBaselines"] as? [String: Any])
            var mask = try XCTUnwrap(proof["fieldMask"] as? [String])
            mask.append(mask[0])
            proof["fieldMask"] = mask
            page["fieldBaselines"] = proof
            root["pageOperation"] = page
        }
        try await assertWALReopenFailsClosed(package: package) { root in
            var page = try XCTUnwrap(root["pageOperation"] as? [String: Any])
            var proof = try XCTUnwrap(page["fieldBaselines"] as? [String: Any])
            proof["unknownKey"] = "nope"
            page["fieldBaselines"] = proof
            root["pageOperation"] = page
        }
        try await assertWALReopenFailsClosed(package: package) { root in
            var page = try XCTUnwrap(root["pageOperation"] as? [String: Any])
            var proof = try XCTUnwrap(page["fieldBaselines"] as? [String: Any])
            var expectations = try XCTUnwrap(proof["expectations"] as? [[String: Any]])
            expectations.append(expectations[0])
            proof["expectations"] = expectations
            page["fieldBaselines"] = proof
            root["pageOperation"] = page
        }
    }

    func testFieldCASConflictBeforeFirstDeviceWrite() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5b-cas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let package = try fieldPackage(device: device, overwrite: true)
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        var executed: [String] = []
        let mutated = AhaKeyRuntimeFieldBaseline(
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldID: .screenStatusLine(modeSlot: 0),
            value: .text("raced"),
            trust: .writeConfirmed,
            provenance: .writeConfirmation,
            operationID: .init()
        )
        let raced = AhaKeyRuntimePageExecutionPreconditions(
            deviceID: device,
            profile: .legacyStandard,
            baseObjectFingerprint: nil,
            fieldBaselines: [mutated]
        )
        let state = try await runner.run(
            package: package,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: raced
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(state, .failedWithoutWrites)
        XCTAssertEqual(executed, [])
        let record = try await store.transaction(package.operationID)
        XCTAssertEqual(record?.messageCode, .configurationFieldBaselineConflict)
        let object = try await store.authoritativeObjectContent(for: device)
        XCTAssertNil(object)
        let baselines = try await store.pageFieldBaselines(deviceID: device)
        XCTAssertEqual(baselines, [])
    }

    func testSuccessfulFieldWriteDoesNotCreateAuthoritativeObject() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5b-complete-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let package = try fieldPackage(device: device, overwrite: true, seed: "first")
        let matching = AhaKeyRuntimePageExecutionPreconditions(
            deviceID: device,
            profile: .legacyStandard,
            baseObjectFingerprint: nil,
            fieldBaselines: []
        )
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: matching
        ) { _ in .success }
        XCTAssertEqual(state, .completed)
        let object = try await store.authoritativeObjectContent(for: device)
        XCTAssertNil(object)
        let reopened = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
        let reopenedObject = try await reopened.authoritativeObjectContent(for: device)
        XCTAssertNil(reopenedObject)
        let reopenedRecord = try await reopened.transaction(package.operationID)
        XCTAssertEqual(reopenedRecord?.state, .completed)
    }

    func testDisjointPagesDoNotFalseConflict() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5b-disjoint-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let screen = try fieldPackage(device: device, overwrite: true, seed: "screen")
        let lightsField = AhaKeyStudioFieldID.lightBrightness(modeSlot: 0)
        let lightsPlan = AhaKeyStudioScopedWritePlan(
            pageID: .lights(modeSlot: 0),
            fieldMask: [lightsField],
            values: [lightsField: .integer(8)],
            overwriteSemantic: true,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false
        )
        let lightsProof = try AhaKeyRuntimePageFieldBaselineProof.make(
            deviceID: device,
            pageID: .lights(modeSlot: 0),
            fieldMask: [lightsField],
            liveBaselines: []
        )
        let lights = try AhaKeyConfigurationPackage.assemblePageFieldBaseline(
            plan: lightsPlan,
            profile: .legacyStandard,
            targetDeviceID: device,
            baseRevision: .init(0),
            fieldBaselines: lightsProof,
            verifiedResources: []
        )
        let empty = AhaKeyRuntimePageExecutionPreconditions(
            deviceID: device,
            profile: .legacyStandard,
            baseObjectFingerprint: nil,
            fieldBaselines: []
        )
        let first = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: screen,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: empty
        ) { _ in .success }
        XCTAssertEqual(first, .completed)
        let second = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: lights,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: empty
        ) { _ in .success }
        XCTAssertEqual(second, .completed)
        let object = try await store.authoritativeObjectContent(for: device)
        XCTAssertNil(object)
    }

    func testPicturePartialResumeDoesNotFallBackToFirstWrite() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5b-partial-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
        let fixture = try pictureFixture(frames: 1)
        var plan = fixture.plan
        plan.overwriteSemantic = true
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let proof = try AhaKeyRuntimePageFieldBaselineProof.make(
            deviceID: device,
            pageID: plan.pageID,
            fieldMask: plan.fieldMask,
            liveBaselines: []
        )
        let package = try AhaKeyConfigurationPackage.assemblePageFieldBaseline(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: device,
            baseRevision: .init(0),
            fieldBaselines: proof,
            verifiedResources: fixture.resources
        )
        var files: [AhaKeyResourceIdentifier: URL] = [:]
        for (identifier, bytes) in fixture.sourceBytes {
            let url = root.appendingPathComponent("\(identifier.rawValue).gif")
            try bytes.write(to: url)
            files[identifier] = url
        }
        let matching = AhaKeyRuntimePageExecutionPreconditions(
            deviceID: device,
            profile: .legacyStandard,
            baseObjectFingerprint: nil,
            fieldBaselines: []
        )
        var first = true
        let paused = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package,
            resourceFiles: files,
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: matching
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
        XCTAssertTrue(
            AhaKeyRuntimePageSemantic.hasDeviceWrites(
                confirmed: confirmed,
                plan: try AhaKeyRuntimePageSemantic.executionPlan(package: package, userSlotLimit: 64)
            )
        )
        var resumed: [String] = []
        let completed = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package,
            resourceFiles: files,
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: AhaKeyRuntimePageExecutionPreconditions(
                deviceID: device,
                profile: .legacyStandard,
                baseObjectFingerprint: nil,
                fieldBaselines: []
            )
        ) { step in
            resumed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(completed, .completed)
        XCTAssertFalse(resumed.contains(confirmed[0].rawValue))
        let object = try await store.authoritativeObjectContent(for: device)
        XCTAssertNil(object)
        let reopened = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
        let reopenedObject = try await reopened.authoritativeObjectContent(for: device)
        XCTAssertNil(reopenedObject)
        let reopenedRecord = try await reopened.transaction(package.operationID)
        XCTAssertEqual(reopenedRecord?.state, .completed)
    }

    func testStandardDoesNotEmitSetActiveSet() throws {
        let fixture = try pictureFixture(frames: 1)
        var plan = fixture.plan
        plan.overwriteSemantic = true
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let proof = try AhaKeyRuntimePageFieldBaselineProof.make(
            deviceID: device,
            pageID: plan.pageID,
            fieldMask: plan.fieldMask,
            liveBaselines: []
        )
        let package = try AhaKeyConfigurationPackage.assemblePageFieldBaseline(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: device,
            baseRevision: .init(0),
            fieldBaselines: proof,
            verifiedResources: fixture.resources
        )
        let execution = try AhaKeyRuntimePageSemantic.executionPlan(package: package, userSlotLimit: 64)
        XCTAssertFalse(execution.identities.contains { $0.rawValue.contains("setActiveSet") })
        XCTAssertFalse(
            package.pageOperation?.compatibilityFingerprint.actions.contains {
                if case .setActiveSet = $0.command { return true }
                return false
            } ?? true
        )
    }

    private func statusPlan(overwrite: Bool, seed: String = "hello") -> AhaKeyStudioScopedWritePlan {
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        return AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [field: .text(seed)],
            overwriteSemantic: overwrite,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            statusLine: seed
        )
    }

    private func statusPackage(
        overwrite: Bool,
        objectSeed: String
    ) throws -> AhaKeyConfigurationPackage {
        try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: statusPlan(overwrite: overwrite, seed: objectSeed),
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("DEV"),
            baseRevision: .init(1),
            baseObjectFingerprint: try AhaKeyRuntimeObjectFingerprint.hashing(Data(objectSeed.utf8)),
            verifiedResources: []
        )
    }

    private func fieldPackage(
        device: AhaKeyRuntimeDeviceID,
        overwrite: Bool,
        seed: String = "hello"
    ) throws -> AhaKeyConfigurationPackage {
        let plan = statusPlan(overwrite: overwrite, seed: seed)
        let proof = try AhaKeyRuntimePageFieldBaselineProof.make(
            deviceID: device,
            pageID: plan.pageID,
            fieldMask: plan.fieldMask,
            liveBaselines: []
        )
        return try AhaKeyConfigurationPackage.assemblePageFieldBaseline(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: device,
            baseRevision: .init(0),
            fieldBaselines: proof,
            verifiedResources: []
        )
    }

    private func pictureFixture(
        bytes: Data = Data("gif-c5b".utf8),
        frames: Int
    ) throws -> (plan: AhaKeyStudioScopedWritePlan, resources: [AhaKeyConfigurationResource], sourceBytes: [AhaKeyResourceIdentifier: Data]) {
        let profile = AhaKeyOLEDCompatibilityProfile.legacyStandard
        let physical = Int(try AhaKeyRuntimePageSemantic.physicalSlot(profile: profile, logicalSet: 0))
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
        let field = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .working)
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
            overwriteSemantic: true,
            writeTaskSetA: true,
            writeTaskSetB: false,
            activateTaskSet: 0,
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
        return (plan, [resource], [resource.logicalIdentifier: bytes])
    }

    private func assertWALReopenFailsClosed(
        package: AhaKeyConfigurationPackage,
        mutate: (inout [String: Any]) throws -> Void
    ) async throws {
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5b-wal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: storeRoot,
            acceptanceValidator: AllowingResourceValidator()
        )
        _ = try await store.accept(package, resourceFiles: [:])
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
