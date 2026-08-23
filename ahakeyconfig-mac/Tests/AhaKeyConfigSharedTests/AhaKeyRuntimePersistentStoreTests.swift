import Foundation
import SQLite3
import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyRuntimePersistentStoreTests: XCTestCase {
    private struct AllowingResourceValidator: AhaKeyRuntimePackageAcceptanceValidator {
        func validate(
            package: AhaKeyConfigurationPackage,
            resources: [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput]
        ) throws {}
    }

    func testAcceptedTransactionIsRecoverableAfterStoreReopens() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let package = try makePackage()
        do {
            let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
            let health = try await store.health()
            let acceptedOperationID = try await store.accept(package, resourceFiles: [:])
            XCTAssertEqual(health.journalMode, "wal")
            XCTAssertEqual(acceptedOperationID, package.operationID)
        }

        let reopened = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        let candidates = try await reopened.recoveryCandidates()
        XCTAssertEqual(candidates.map(\.operationID), [package.operationID])
        XCTAssertEqual(candidates.first?.package, package)
        XCTAssertEqual(candidates.first?.state, .accepted)
    }

    func testAcceptedResourceIsCopiedAndAddressedByVerifiedDigest() async throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("studio-temporary-resource")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("resource-one".utf8).write(to: source)

        let resource = try AhaKeyConfigurationResource(
            logicalIdentifier: "mode1-working",
            sha256: "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be",
            byteCount: 12,
            mediaType: "image/gif"
        )
        let package = try makePackage(resources: [resource])
        let store = try resourceStore(rootDirectory: root)
        _ = try await store.accept(
            package,
            resourceFiles: [resource.logicalIdentifier: source]
        )
        try FileManager.default.removeItem(at: source)

        let managedURL = try await store.resourceURL(for: resource.sha256)
        let managedData = try managedURL.map { try Data(contentsOf: $0) }
        XCTAssertEqual(managedData, Data("resource-one".utf8))
    }

    func testQuotaCountsUniqueContentOnlyAndRejectsNewContentBeyondLimit() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstSource = root.appendingPathComponent("first")
        let secondSource = root.appendingPathComponent("second")
        try Data("resource-one".utf8).write(to: firstSource)
        try Data("resource-two-is-larger".utf8).write(to: secondSource)

        let first = try resource(
            identifier: "first",
            digest: "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be",
            byteCount: 12
        )
        let duplicateContent = try resource(
            identifier: "duplicate-content",
            digest: first.sha256.rawValue,
            byteCount: 12
        )
        let second = try resource(
            identifier: "second",
            digest: "a49df6264aac97259550659f2d7ede6c30689e36881c4a37b31db3a4a2c199a6",
            byteCount: 22
        )
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            quota: .init(maxSingleResourceBytes: 32, maxTotalResourceBytes: 20),
            acceptanceValidator: AllowingResourceValidator()
        )

        _ = try await store.accept(
            makePackage(resources: [first]),
            resourceFiles: [first.logicalIdentifier: firstSource]
        )
        _ = try await store.accept(
            makePackage(resources: [duplicateContent]),
            resourceFiles: [duplicateContent.logicalIdentifier: firstSource]
        )
        let storageUsage = try await store.resourceStorageUsage()
        XCTAssertEqual(storageUsage, 12)

        do {
            _ = try await store.accept(
                makePackage(resources: [second]),
                resourceFiles: [second.logicalIdentifier: secondSource]
            )
            XCTFail("Expected total resource quota rejection")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .resourceQuotaExceeded(limit: 20, attempted: 34)
            )
        }
    }

    func testProgressAndTerminalOutcomeSurviveRestartWithoutReplayingCompletedWork() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage()
        let completedBaseline = try AhaKeyRuntimeSyncBaseline(
            deviceID: package.targetDeviceID,
            revision: .init(8),
            confirmedConfiguration: package.desiredConfiguration
        )

        do {
            let store = try resourceStore(rootDirectory: root)
            _ = try await store.accept(package, resourceFiles: [:])
            try await store.updateOperation(
                .init(
                    id: package.operationID,
                    targetDeviceID: package.targetDeviceID,
                    state: .running,
                    completedSteps: 2,
                    totalSteps: 5
                )
            )
        }

        do {
            let reopened = try AhaKeyRuntimePersistentStore(rootDirectory: root)
            let recovered = try await reopened.recoveryCandidates()
            XCTAssertEqual(recovered.first?.state, .paused)
            XCTAssertEqual(recovered.first?.completedSteps, 2)
            XCTAssertEqual(recovered.first?.totalSteps, 5)
            try await reopened.commitOperationOutcome(
                .init(
                    id: package.operationID,
                    targetDeviceID: package.targetDeviceID,
                    state: .completed,
                    completedSteps: 5,
                    totalSteps: 5
                ),
                syncBaseline: completedBaseline
            )
        }

        let finalStore = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        let remainingCandidates = try await finalStore.recoveryCandidates()
        let completedTransaction = try await finalStore.transaction(package.operationID)
        let persistedBaseline = try await finalStore.syncBaseline(for: package.targetDeviceID)
        XCTAssertTrue(remainingCandidates.isEmpty)
        XCTAssertEqual(completedTransaction?.state, .completed)
        XCTAssertEqual(persistedBaseline, completedBaseline)
    }

    func testPolicyAndEventSequencePersistAcrossRestart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = AhaKeyRuntimePolicy(
            aiHooks: .init(
                enabledTools: [.kimi],
                approvalPolicy: .followLever(automaticPosition: .up)
            ),
            powerProtectionEnabled: true
        )

        do {
            let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
            try await store.savePolicy(policy)
            let first = try await store.reserveEventSequence()
            let second = try await store.reserveEventSequence()
            XCTAssertEqual(first, .init(1))
            XCTAssertEqual(second, .init(2))
        }

        let reopened = try resourceStore(rootDirectory: root)
        let recoveredPolicy = try await reopened.loadPolicy()
        let third = try await reopened.reserveEventSequence()
        XCTAssertEqual(recoveredPolicy, policy)
        XCTAssertEqual(third, .init(3))
    }

    func testConfirmedStepsAndDeviceSyncBaselinePersistAcrossRestart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage()
        let uploadStep = try AhaKeyRuntimeStepIdentifier("upload-image-03c9f206")
        do {
            let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
            _ = try await store.accept(package, resourceFiles: [:])
            try await store.confirmStep(uploadStep, for: package.operationID)
            try await store.confirmStep(uploadStep, for: package.operationID)
        }

        let reopened = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        let confirmedSteps = try await reopened.confirmedSteps(for: package.operationID)
        XCTAssertEqual(confirmedSteps, [uploadStep])
    }

    func testRecoveryRejectsAResourceThatChangedAfterAcceptance() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source")
        try Data("resource-one".utf8).write(to: source)
        let resource = try resource(
            identifier: "working-image",
            digest: "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be",
            byteCount: 12
        )
        let package = try makePackage(resources: [resource])

        do {
            let store = try resourceStore(rootDirectory: root)
            _ = try await store.accept(
                package,
                resourceFiles: [resource.logicalIdentifier: source]
            )
            let resolvedURL = try await store.resourceURL(for: resource.sha256)
            let managedURL = try XCTUnwrap(resolvedURL)
            try Data("tampered!!!!".utf8).write(to: managedURL)
        }

        let reopened = try resourceStore(rootDirectory: root)
        do {
            _ = try await reopened.recoveryCandidates()
            XCTFail("Expected corrupt managed resource rejection")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .resourceDigestMismatch(resource.logicalIdentifier)
            )
        }
    }

    func testStoreRefusesToDowngradeANewerSchema() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA user_version=999", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        XCTAssertThrowsError(try AhaKeyRuntimePersistentStore(rootDirectory: root)) { error in
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .unsupportedSchemaVersion(999)
            )
        }
    }

    func testLegacyPartialStateInJournalRecoversAsResumablePartial() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage()
        do {
            let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
            _ = try await store.accept(package, resourceFiles: [:])
        }

        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let sql = """
        UPDATE runtime_transactions
        SET state='partiallyCompleted', completed_steps=2, total_steps=5
        WHERE operation_id='\(package.operationID.rawValue.uuidString)'
        """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let reopened = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        let candidates = try await reopened.recoveryCandidates()
        XCTAssertEqual(candidates.first?.state, .resumablePartial)
        XCTAssertEqual(candidates.first?.completedSteps, 2)
    }

    func testAcceptanceRejectsSymbolicLinkResourceSources() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let realSource = root.appendingPathComponent("real-source")
        let linkedSource = root.appendingPathComponent("linked-source")
        try Data("resource-one".utf8).write(to: realSource)
        try FileManager.default.createSymbolicLink(at: linkedSource, withDestinationURL: realSource)
        let resource = try resource(
            identifier: "linked",
            digest: "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be",
            byteCount: 12
        )
        let store = try resourceStore(rootDirectory: root)

        do {
            _ = try await store.accept(
                makePackage(resources: [resource]),
                resourceFiles: [resource.logicalIdentifier: linkedSource]
            )
            XCTFail("Expected symbolic-link resource rejection")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .unsafeResourceFile(resource.logicalIdentifier)
            )
        }
    }

    func testPartiallyCompletedOperationCanResumeWithoutAdvancingBaseline() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage()
        let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        _ = try await store.accept(package, resourceFiles: [:])
        try await store.updateOperation(
            .init(
                id: package.operationID,
                targetDeviceID: package.targetDeviceID,
                state: .resumablePartial,
                completedSteps: 2,
                totalSteps: 5
            )
        )
        try await store.updateOperation(
            .init(
                id: package.operationID,
                targetDeviceID: package.targetDeviceID,
                state: .running,
                completedSteps: 2,
                totalSteps: 5
            )
        )

        let resumed = try await store.transaction(package.operationID)
        let baseline = try await store.syncBaseline(for: package.targetDeviceID)
        XCTAssertEqual(resumed?.state, .running)
        XCTAssertNil(baseline)
    }

    func testReopeningRemovesUnjournaledCASFilesBeforeQuotaAccounting() async throws {
        let root = temporaryDirectory()
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let orphan = resources.appendingPathComponent(
            "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"
        )
        try Data("resource-one".utf8).write(to: orphan)

        let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        let usage = try await store.resourceStorageUsage()
        XCTAssertEqual(usage, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AhaKeyRuntimePersistentStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makePackage(
        operationID: AhaKeyRuntimeOperationID = .init(),
        resources: [AhaKeyConfigurationResource] = []
    ) throws -> AhaKeyConfigurationPackage {
        try AhaKeyConfigurationPackage(
            operationID: operationID,
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            baseRevision: .init(7),
            desiredConfiguration: Data("configuration-v1".utf8),
            resources: resources
        )
    }

    private func resource(
        identifier: String,
        digest: String,
        byteCount: UInt64
    ) throws -> AhaKeyConfigurationResource {
        try AhaKeyConfigurationResource(
            logicalIdentifier: identifier,
            sha256: digest,
            byteCount: byteCount,
            mediaType: "image/gif"
        )
    }

    private func resourceStore(rootDirectory: URL) throws -> AhaKeyRuntimePersistentStore {
        try AhaKeyRuntimePersistentStore(
            rootDirectory: rootDirectory,
            acceptanceValidator: AllowingResourceValidator()
        )
    }
}
