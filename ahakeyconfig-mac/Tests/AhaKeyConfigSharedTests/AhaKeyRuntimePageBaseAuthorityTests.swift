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

    func testDurableFieldsStillRequireOverwrite() throws {
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
        XCTAssertThrowsError(
            try AhaKeyRuntimePageBaseAuthority.resolve(
                authoritativeObject: nil,
                overwriteSemantic: false,
                deviceID: device,
                pageID: .screen(modeSlot: 0),
                fieldMask: [field],
                liveBaselines: [confirmed]
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyRuntimePageBaseAuthorityError,
                .overwriteConfirmationRequired
            )
        }
        let allowed = try AhaKeyRuntimePageBaseAuthority.resolve(
            authoritativeObject: nil,
            overwriteSemantic: true,
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            liveBaselines: [confirmed]
        )
        XCTAssertEqual(allowed.schemaVersion, 3)
        XCTAssertEqual(try XCTUnwrap(allowed.fieldBaselines).expectations[0].kind, .baseline)
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
        _ = try await store.accept(package, resourceFiles: [:])
        try await store.upsertPageFieldBaselineForTesting(mutated)
        let state = try await runner.run(
            package: package,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: livePreconditions(device)
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
        XCTAssertEqual(baselines, [mutated])
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
        let baselines = try await store.pageFieldBaselines(deviceID: device)
        XCTAssertEqual(baselines.map(\.trust), [.writeConfirmed])
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

    func testAbsentExpectationRejectsBaselineKeysEvenWhenNull() throws {
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let json: [String: Any] = [
            "kind": "absent",
            "deviceID": device.rawValue,
            "pageID": try jsonObject(AhaKeyStudioPageID.screen(modeSlot: 0)),
            "fieldID": try jsonObject(field),
            "value": NSNull(),
        ]
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimePageFieldExpectation.self,
                from: try JSONSerialization.data(withJSONObject: json)
            )
        )
    }

    func testBaselineExpectationRequiresNullableKeys() throws {
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let row = AhaKeyRuntimeFieldBaseline(
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldID: field,
            value: .text("kept"),
            trust: .writeConfirmed,
            provenance: .writeConfirmation,
            operationID: nil
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(AhaKeyRuntimePageFieldExpectation.baseline(row))
            ) as? [String: Any]
        )
        object.removeValue(forKey: "operationID")
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimePageFieldExpectation.self,
                from: try JSONSerialization.data(withJSONObject: object)
            )
        )
        object["operationID"] = NSNull()
        let decoded = try JSONDecoder().decode(
            AhaKeyRuntimePageFieldExpectation.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.kind, .baseline)
        XCTAssertNil(decoded.operationID)
    }

    func testAcceptThenMutateBaselineConflictsBeforeRunning() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br1-race-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let package = try fieldPackage(device: device, overwrite: true)
        _ = try await store.accept(package, resourceFiles: [:])
        try await store.upsertPageFieldBaselineForTesting(
            AhaKeyRuntimeFieldBaseline(
                deviceID: device,
                pageID: .screen(modeSlot: 0),
                fieldID: .screenStatusLine(modeSlot: 0),
                value: .text("raced"),
                trust: .writeConfirmed,
                provenance: .writeConfirmation,
                operationID: .init()
            )
        )
        var executed: [String] = []
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: livePreconditions(device)
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(state, .failedWithoutWrites)
        XCTAssertEqual(executed, [])
        let record = try await store.transaction(package.operationID)
        XCTAssertEqual(record?.messageCode, .configurationFieldBaselineConflict)
        XCTAssertEqual(record?.state, .failedWithoutWrites)
    }

    func testStartSnapshotMutationConflictsBeforeRunningCommit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br1-hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let package = try fieldPackage(device: device, overwrite: true)
        _ = try await store.accept(package, resourceFiles: [:])
        let raced = AhaKeyRuntimeFieldBaseline(
            deviceID: device,
            pageID: .screen(modeSlot: 0),
            fieldID: .screenStatusLine(modeSlot: 0),
            value: .text("hooked"),
            trust: .writeConfirmed,
            provenance: .writeConfirmation,
            operationID: .init()
        )
        await store.setTestingHooks(.init(pageStartFieldBaseline: raced))
        var executed: [String] = []
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: livePreconditions(device)
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(state, .failedWithoutWrites)
        XCTAssertEqual(executed, [])
        let code = try await store.transaction(package.operationID)?.messageCode
        XCTAssertEqual(code, .configurationFieldBaselineConflict)
    }

    func testMissingLivePreconditionsFailClosedWithoutWrites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br2-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let package = try fieldPackage(device: device, overwrite: true)
        var executed: [String] = []
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(state, .failedWithoutWrites)
        XCTAssertEqual(executed, [])
        let record = try await store.transaction(package.operationID)
        XCTAssertEqual(record?.messageCode, .configurationPreflightConflict)
        XCTAssertNotEqual(record?.state, .running)
        let object = try await store.authoritativeObjectContent(for: device)
        XCTAssertNil(object)
    }

    func testIngestStaleFieldProofFailsClosedBeforeJournal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br2-stale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let fixture = try pictureFixture(frames: 1)
        let package = try pictureFieldPackage(device: device, fixture: fixture)
        let items = try ingestionItems(fixture)
        let field = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .working)
        try await store.upsertPageFieldBaselineForTesting(
            AhaKeyRuntimeFieldBaseline(
                deviceID: device,
                pageID: .screen(modeSlot: 0),
                fieldID: field,
                value: .text("raced"),
                trust: .writeConfirmed,
                provenance: .writeConfirmation,
                operationID: .init()
            )
        )
        do {
            try await store.ingestResources(
                items,
                scopedProof: try AhaKeyRuntimeScopedResourceIngestionProof.make(package: package),
                targetDeviceID: device
            )
            XCTFail("stale field proof must fail before resource journal")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .pageFieldBaselineConflict)
        }
        try await assertZeroResourceJournal(store: store, root: root, items: items)
    }

    func testForeignDeviceAbsentProofCannotAuthorizeTargetJournal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br2-foreign-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let target = try AhaKeyRuntimeDeviceID("DEV-A")
        let foreign = try AhaKeyRuntimeDeviceID("DEV-B")
        let fixture = try pictureFixture(frames: 1)
        let foreignPackage = try pictureFieldPackage(device: foreign, fixture: fixture)
        let items = try ingestionItems(fixture)
        do {
            try await store.ingestResources(
                items,
                scopedProof: try AhaKeyRuntimeScopedResourceIngestionProof.make(package: foreignPackage),
                targetDeviceID: target
            )
            XCTFail("foreign-device absent proof must not write target journal")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .pageFieldBaselineConflict)
        }
        try await assertZeroResourceJournal(store: store, root: root, items: items)
        let wal = try await store.transaction(foreignPackage.operationID)
        XCTAssertNil(wal)
    }

    func testUnrelatedPageProofCannotAuthorizePictureJournal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br2-unrelated-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let fixture = try pictureFixture(frames: 1)
        let items = try ingestionItems(fixture)
        let unrelated = try fieldPackage(device: device, overwrite: true)
        do {
            try await store.ingestResources(
                items,
                scopedProof: try AhaKeyRuntimeScopedResourceIngestionProof.make(package: unrelated),
                targetDeviceID: device
            )
            XCTFail("unrelated page proof must not write picture journal")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .pageFieldBaselineConflict)
        }
        try await assertZeroResourceJournal(store: store, root: root, items: items)
    }

    func testIngestItemsMustBijectionWithScopedBindings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br2-mismatch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let fixture = try pictureFixture(frames: 1)
        let package = try pictureFieldPackage(device: device, fixture: fixture)
        let scoped = try AhaKeyRuntimeScopedResourceIngestionProof.make(package: package)
        var items = try ingestionItems(fixture)
        items[0] = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("unrelated-logical"),
            sha256: items[0].sha256,
            byteCount: items[0].byteCount,
            data: items[0].data
        )
        do {
            try await store.ingestResources(
                items,
                scopedProof: scoped,
                targetDeviceID: device
            )
            XCTFail("items must bijection with resource bindings")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .pageFieldBaselineConflict)
        }
        try await assertZeroResourceJournal(store: store, root: root, items: items)
    }

    func testNilProofWithoutObjectFailsClosedBeforeJournal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br2-nil-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let fixture = try pictureFixture(frames: 1)
        let items = try ingestionItems(fixture)
        do {
            try await store.ingestResources(items, targetDeviceID: device)
            XCTFail("nil proof on no-object device must not write journal")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .pageBaseAuthorityUnreadable)
        }
        try await assertZeroResourceJournal(store: store, root: root, items: items)
    }

    func testLegalSchema3PicturePackageStillIngestsAndApplies() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br2-legal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let fixture = try pictureFixture(frames: 1)
        let package = try pictureFieldPackage(device: device, fixture: fixture)
        let items = try ingestionItems(fixture)
        try await store.ingestResources(
            items,
            scopedProof: try AhaKeyRuntimeScopedResourceIngestionProof.make(package: package),
            targetDeviceID: device
        )
        let staged = try await store.stagedResourceByteCountForTesting(items[0].sha256)
        XCTAssertEqual(staged, items[0].byteCount)
        var files: [AhaKeyResourceIdentifier: URL] = [:]
        for (identifier, bytes) in fixture.sourceBytes {
            let url = root.appendingPathComponent("\(identifier.rawValue).gif")
            try bytes.write(to: url)
            files[identifier] = url
        }
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package,
            resourceFiles: files,
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: livePreconditions(device)
        ) { _ in .success }
        XCTAssertEqual(state, .completed)
        let object = try await store.authoritativeObjectContent(for: device)
        XCTAssertNil(object)
        let baselines = try await store.pageFieldBaselines(deviceID: device)
        XCTAssertEqual(baselines.map(\.trust), [.writeConfirmed])
    }

    func testSchema3AssembleRejectsOverwriteFalse() throws {
        XCTAssertThrowsError(
            try fieldPackage(device: try AhaKeyRuntimeDeviceID("DEV"), overwrite: false)
        )
    }

    func testSchema1ObjectInterleavedWithSchema3Conflicts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br1-obj-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let package = try fieldPackage(device: device, overwrite: true)
        _ = try await store.accept(package, resourceFiles: [:])
        try await store.seedAuthoritativeObjectForTesting(deviceID: device, content: Data("schema1".utf8))
        var executed: [String] = []
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: livePreconditions(device)
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(state, .failedWithoutWrites)
        XCTAssertEqual(executed, [])
        let code = try await store.transaction(package.operationID)?.messageCode
        XCTAssertEqual(code, .configurationPreflightConflict)
    }

    func testStoreBaselineReadErrorFailsClosedInsteadOfAbsent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br1-read-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let package = try fieldPackage(device: device, overwrite: true)
        _ = try await store.accept(package, resourceFiles: [:])
        await store.setTestingHooks(.init(pageBaselineReadShouldFail: true))
        var executed: [String] = []
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: livePreconditions(device)
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(state, .failedWithoutWrites)
        XCTAssertEqual(executed, [])
        let object = try await store.authoritativeObjectContent(for: device)
        XCTAssertNil(object)
    }

    func testOverlappingFieldMaskSecondHeadConflictsAfterFirstWrite() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5br1-overlap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root: root)
        let device = try AhaKeyRuntimeDeviceID("DEV")
        let first = try fieldPackage(device: device, overwrite: true, seed: "one")
        let second = try fieldPackage(device: device, overwrite: true, seed: "two")
        _ = try await store.accept(first, resourceFiles: [:])
        _ = try await store.accept(second, resourceFiles: [:])
        let firstState = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: first,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: livePreconditions(device)
        ) { _ in .success }
        XCTAssertEqual(firstState, .completed)
        var executed: [String] = []
        let secondState = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: second,
            resourceFiles: [:],
            context: .standard,
            release: .picturesUnrestrictedForTests,
            pagePreconditions: livePreconditions(device)
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(secondState, .failedWithoutWrites)
        XCTAssertEqual(executed, [])
        let code = try await store.transaction(second.operationID)?.messageCode
        XCTAssertEqual(code, .configurationFieldBaselineConflict)
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

    private func makeStore(root: URL) throws -> AhaKeyRuntimePersistentStore {
        try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator(
                schema1: AllowingResourceValidator()
            )
        )
    }

    private func livePreconditions(
        _ device: AhaKeyRuntimeDeviceID
    ) -> AhaKeyRuntimePageExecutionPreconditions {
        AhaKeyRuntimePageExecutionPreconditions(
            deviceID: device,
            profile: .legacyStandard,
            baseObjectFingerprint: nil,
            fieldBaselines: []
        )
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(value),
            options: [.fragmentsAllowed]
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

    private func pictureFieldPackage(
        device: AhaKeyRuntimeDeviceID,
        fixture: (plan: AhaKeyStudioScopedWritePlan, resources: [AhaKeyConfigurationResource], sourceBytes: [AhaKeyResourceIdentifier: Data])
    ) throws -> AhaKeyConfigurationPackage {
        var plan = fixture.plan
        plan.overwriteSemantic = true
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
            verifiedResources: fixture.resources
        )
    }

    private func ingestionItems(
        _ fixture: (plan: AhaKeyStudioScopedWritePlan, resources: [AhaKeyConfigurationResource], sourceBytes: [AhaKeyResourceIdentifier: Data])
    ) throws -> [AhaKeyXPCResourceIngestionItem] {
        try fixture.resources.map { resource in
            let data = try XCTUnwrap(fixture.sourceBytes[resource.logicalIdentifier])
            return AhaKeyXPCResourceIngestionItem(
                logicalIdentifier: resource.logicalIdentifier,
                sha256: resource.sha256,
                byteCount: resource.byteCount,
                data: data
            )
        }
    }

    private func assertZeroResourceJournal(
        store: AhaKeyRuntimePersistentStore,
        root: URL,
        items: [AhaKeyXPCResourceIngestionItem]
    ) async throws {
        for item in items {
            let accepted = try await store.resourceURL(for: item.sha256)
            XCTAssertNil(accepted)
            let staged = try await store.stagedResourceByteCountForTesting(item.sha256)
            XCTAssertNil(staged)
            let final = root
                .appendingPathComponent("resources", isDirectory: true)
                .appendingPathComponent(item.sha256.rawValue)
            XCTAssertFalse(FileManager.default.fileExists(atPath: final.path))
        }
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
