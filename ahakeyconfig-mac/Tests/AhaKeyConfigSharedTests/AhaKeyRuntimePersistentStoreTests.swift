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

    func testAcceptWithEmptyResourceFilesSucceedsWhenDigestInCAS() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let resource = try AhaKeyConfigurationResource(
            logicalIdentifier: "mode1-working",
            sha256: "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be",
            byteCount: 12,
            mediaType: "image/gif"
        )
        let package = try makePackage(resources: [resource])
        let store = try resourceStore(rootDirectory: root)

        // 先通过 ingestResources 把资源写入 CAS
        try await store.ingestResources([
            AhaKeyXPCResourceIngestionItem(
                logicalIdentifier: resource.logicalIdentifier,
                sha256: resource.sha256,
                byteCount: resource.byteCount,
                data: Data("resource-one".utf8)
            )
        ])

        // 空 resourceFiles + digest 已在库 → accept 成功
        let acceptedID = try await store.accept(package, resourceFiles: [:])
        XCTAssertEqual(acceptedID, package.operationID)
    }

    func testAcceptWithEmptyResourceFilesFailsWhenDigestNotInCAS() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let resource = try AhaKeyConfigurationResource(
            logicalIdentifier: "mode1-working",
            sha256: "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be",
            byteCount: 12,
            mediaType: "image/gif"
        )
        let package = try makePackage(resources: [resource])
        let store = try resourceStore(rootDirectory: root)

        do {
            _ = try await store.accept(package, resourceFiles: [:])
            XCTFail("Expected missingResourceFile when digest not in CAS")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .missingResourceFile(resource.logicalIdentifier)
            )
        }
    }

    func testIngestResourcesPutsDataIntoCAS() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let store = try resourceStore(rootDirectory: root)
        let item = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("idle"),
            sha256: try AhaKeySHA256Digest("03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"),
            byteCount: 12,
            data: Data("resource-one".utf8)
        )
        try await store.ingestResources([item])

        let expectedPath = root.appendingPathComponent("resources/\(item.sha256.rawValue)")
        let exists = FileManager.default.fileExists(atPath: expectedPath.path)
        XCTAssertTrue(exists)
        let data = try Data(contentsOf: expectedPath)
        XCTAssertEqual(data, Data("resource-one".utf8))
    }

    func testIngestResourcesRejectsInvalidDigest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let store = try resourceStore(rootDirectory: root)
        let item = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("idle"),
            sha256: try AhaKeySHA256Digest("03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"),
            byteCount: 12,
            data: Data("wrong-data".utf8)
        )
        do {
            try await store.ingestResources([item])
            XCTFail("Expected validation failure")
        } catch {
            XCTAssertTrue(error is AhaKeyRuntimePersistenceError)
        }
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

    func testV2StoreMigratesInPlaceAndReadsHistoricalFailureContextAsNil() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let package = try makePackage()
        let packageData = try JSONEncoder().encode(package)
        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let sql = """
        PRAGMA user_version=2;
        CREATE TABLE runtime_transactions (
            operation_id TEXT PRIMARY KEY NOT NULL,
            package BLOB NOT NULL,
            state TEXT NOT NULL,
            completed_steps INTEGER NOT NULL,
            total_steps INTEGER NOT NULL,
            message_code TEXT
        );
        """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                "INSERT INTO runtime_transactions (operation_id, package, state, completed_steps, total_steps, message_code) VALUES (?, ?, 'failedWithoutWrites', 0, 2, NULL)",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        let operationID = package.operationID.rawValue.uuidString
        operationID.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        packageData.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(packageData.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
        sqlite3_close(database)

        do {
            let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
            let health = try await store.health()
            XCTAssertEqual(health.schemaVersion, 4)
            let record = try await store.transaction(package.operationID)
            XCTAssertEqual(record?.state, .failedWithoutWrites)
            XCTAssertNil(record?.messageCode)
            XCTAssertNil(record?.failureContext)
        }

        let reopened = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        let reopenedHealth = try await reopened.health()
        XCTAssertEqual(reopenedHealth.schemaVersion, 4)
        let reopenedRecord = try await reopened.transaction(package.operationID)
        XCTAssertEqual(reopenedRecord?.state, .failedWithoutWrites)
        XCTAssertNil(reopenedRecord?.messageCode)
        XCTAssertNil(reopenedRecord?.failureContext)
    }

    func testFailureContextRoundTripsAfterReopen() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage()
        let context = AhaKeyRuntimeOperationFailureContext(
            failedStepID: try AhaKeyRuntimeStepIdentifier("base:mode:0"),
            opcode: 0x97,
            deviceStatus: 3
        )
        do {
            let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
            _ = try await store.accept(package, resourceFiles: [:])
            try await store.commitOperationOutcome(
                AhaKeyRuntimeOperationSummary(
                    id: package.operationID,
                    targetDeviceID: package.targetDeviceID,
                    state: .failedWithoutWrites,
                    completedSteps: 0,
                    totalSteps: 2,
                    messageCode: .configurationDeviceRejected,
                    failureContext: context
                ),
                syncBaseline: nil
            )
        }

        let reopened = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        let record = try await reopened.transaction(package.operationID)
        XCTAssertEqual(record?.messageCode, .configurationDeviceRejected)
        XCTAssertEqual(record?.failureContext, context)
        XCTAssertEqual(record?.state, .failedWithoutWrites)
        let recovered = try await reopened.recoveryCandidates()
        XCTAssertTrue(recovered.isEmpty)
        let terminals = try await reopened.recentTerminalTransactions()
        XCTAssertEqual(terminals.map(\.operationID), [package.operationID])
        XCTAssertEqual(terminals.first?.failureContext, context)
    }

    func testCommitCompletedRejectsFailureContextAtOutcomeBoundary() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage()
        let completedBaseline = try AhaKeyRuntimeSyncBaseline(
            deviceID: package.targetDeviceID,
            revision: .init(8),
            confirmedConfiguration: package.desiredConfiguration
        )
        let context = AhaKeyRuntimeOperationFailureContext(
            failedStepID: try AhaKeyRuntimeStepIdentifier("base:mode:0"),
            opcode: 0x97,
            deviceStatus: 3
        )
        let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        _ = try await store.accept(package, resourceFiles: [:])

        do {
            try await store.commitOperationOutcome(
                AhaKeyRuntimeOperationSummary(
                    id: package.operationID,
                    targetDeviceID: package.targetDeviceID,
                    state: .completed,
                    completedSteps: 2,
                    totalSteps: 2,
                    messageCode: .configurationDeviceRejected,
                    failureContext: context
                ),
                syncBaseline: completedBaseline
            )
            XCTFail("completed 不得携带失败字段")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .invalidOperationOutcome)
        }

        let record = try await store.transaction(package.operationID)
        XCTAssertEqual(record?.state, .accepted)
        XCTAssertNil(record?.messageCode)
        XCTAssertNil(record?.failureContext)
        let remaining = try await store.recoveryCandidates()
        XCTAssertEqual(remaining.map(\.operationID), [package.operationID])
    }

    func testRecentTerminalsFollowTransitionOrderNotAcceptanceOrder() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let window = AhaKeyRuntimePersistentStore.snapshotProjectionTerminalLimit
        let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
        var packages: [AhaKeyConfigurationPackage] = []
        for _ in 0..<(window + 1) {
            let package = try makePackage()
            _ = try await store.accept(package, resourceFiles: [:])
            packages.append(package)
        }
        for package in packages.reversed() {
            try await store.commitOperationOutcome(
                AhaKeyRuntimeOperationSummary(
                    id: package.operationID,
                    targetDeviceID: package.targetDeviceID,
                    state: .failedWithoutWrites,
                    completedSteps: 0,
                    totalSteps: 0
                ),
                syncBaseline: nil
            )
        }
        let terminals = try await store.recentTerminalTransactions()
        XCTAssertEqual(terminals.count, window)
        XCTAssertEqual(terminals.last?.operationID, packages[0].operationID)
        XCTAssertFalse(
            terminals.contains { $0.operationID == packages[window].operationID },
            "最先进入终态的最近受理行必须被 64 窗口淘汰"
        )
        XCTAssertTrue(terminals.contains { $0.operationID == packages[0].operationID })
    }

    func testV4MigrationAndConcurrentOutcomeShareOneWriteTransaction() async throws {
        final class GateBox: @unchecked Sendable {
            private let lock = NSLock()
            private var acquiredAtStorage: Date?
            private var userVersionStorage: Int32 = -1
            private var beginResultStorage: Int32 = -1
            private var updateResultStorage: Int32 = -1
            var acquiredAt: Date? {
                lock.lock(); defer { lock.unlock() }
                return acquiredAtStorage
            }
            var userVersion: Int32 {
                lock.lock(); defer { lock.unlock() }
                return userVersionStorage
            }
            var beginResult: Int32 {
                lock.lock(); defer { lock.unlock() }
                return beginResultStorage
            }
            var updateResult: Int32 {
                lock.lock(); defer { lock.unlock() }
                return updateResultStorage
            }
            func mark(beginResult: Int32, userVersion: Int32, updateResult: Int32) {
                lock.lock()
                acquiredAtStorage = Date()
                beginResultStorage = beginResult
                userVersionStorage = userVersion
                updateResultStorage = updateResult
                lock.unlock()
            }
        }

        let root = temporaryDirectory()
        defer {
            AhaKeyRuntimeStoreSchemaMigrationTestingHooks.insideWriteTransaction = nil
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let historical = try makePackage()
        let accepted = try makePackage()
        try seedV3Transactions(
            root: root,
            rows: [
                (historical, "failedWithoutWrites"),
                (accepted, "accepted")
            ]
        )

        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var preexisting: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &preexisting), SQLITE_OK)
        let preexistingHandle = try XCTUnwrap(preexisting)
        defer { sqlite3_close(preexistingHandle) }
        sqlite3_busy_timeout(preexistingHandle, 10_000)

        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        AhaKeyRuntimeStoreSchemaMigrationTestingHooks.insideWriteTransaction = {
            entered.signal()
            _ = release.wait(timeout: .now() + 10)
        }

        let initTask = Task.detached {
            try AhaKeyRuntimePersistentStore(rootDirectory: root)
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)

        let gate = GateBox()
        let acceptedID = accepted.operationID.rawValue.uuidString
        let concurrentTask = Task.detached {
            let begin = sqlite3_exec(preexistingHandle, "BEGIN IMMEDIATE", nil, nil, nil)
            var version: Int32 = -1
            var updateResult: Int32 = -1
            if begin == SQLITE_OK {
                var versionStatement: OpaquePointer?
                if sqlite3_prepare_v2(preexistingHandle, "PRAGMA user_version", -1, &versionStatement, nil) == SQLITE_OK {
                    if sqlite3_step(versionStatement) == SQLITE_ROW {
                        version = sqlite3_column_int(versionStatement, 0)
                    }
                    sqlite3_finalize(versionStatement)
                }
                var update: OpaquePointer?
                if sqlite3_prepare_v2(
                    preexistingHandle,
                    """
                    UPDATE runtime_transactions
                    SET state = 'failedWithoutWrites',
                        completed_steps = 0,
                        total_steps = 2,
                        message_code = NULL,
                        failure_context = NULL
                    WHERE operation_id = ?
                    """,
                    -1,
                    &update,
                    nil
                ) == SQLITE_OK {
                    acceptedID.withCString {
                        sqlite3_bind_text(update, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    }
                    updateResult = sqlite3_step(update)
                    sqlite3_finalize(update)
                }
                sqlite3_exec(preexistingHandle, "COMMIT", nil, nil, nil)
            }
            gate.mark(beginResult: begin, userVersion: version, updateResult: updateResult)
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(gate.acquiredAt, "迁移写事务未提交时已打开的 v3 connection 不得提交终态")
        let releaseTime = Date()
        release.signal()
        let store = try await initTask.value
        await concurrentTask.value
        XCTAssertGreaterThan(gate.acquiredAt ?? .distantPast, releaseTime)
        XCTAssertEqual(gate.beginResult, SQLITE_OK)
        XCTAssertEqual(gate.userVersion, AhaKeyRuntimePersistentStore.schemaVersion)
        XCTAssertEqual(gate.updateResult, SQLITE_DONE)

        let health = try await store.health()
        XCTAssertEqual(health.schemaVersion, 4)
        XCTAssertTrue(try terminalOrderTriggerExists(root: root))
        let historicalOrder = try XCTUnwrap(try terminalOrder(root: root, operationID: historical.operationID))
        let migratedLegacyOrder = try XCTUnwrap(try terminalOrder(root: root, operationID: accepted.operationID))
        XCTAssertGreaterThan(migratedLegacyOrder, historicalOrder)

        let explicit = try makePackage()
        _ = try await store.accept(explicit, resourceFiles: [:])
        try await store.commitOperationOutcome(
            AhaKeyRuntimeOperationSummary(
                id: explicit.operationID,
                targetDeviceID: explicit.targetDeviceID,
                state: .failedWithoutWrites,
                completedSteps: 0,
                totalSteps: 2
            ),
            syncBaseline: nil
        )
        let explicitOrder = try XCTUnwrap(try terminalOrder(root: root, operationID: explicit.operationID))
        XCTAssertEqual(explicitOrder, migratedLegacyOrder + 1, "v4 显式 order 不得被兼容 trigger 二次改写")

        let terminals = try await store.recentTerminalTransactions()
        XCTAssertEqual(
            Set(terminals.map(\.operationID)),
            [historical.operationID, accepted.operationID, explicit.operationID]
        )
        XCTAssertEqual(try nullTerminalOrderCount(root: root), 0)
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

    // MARK: - Staged resource journal（XPC ingest → 跨请求 apply 契约）

    /// store A ingest → 销毁 → store B accept：真实 XPC 两步路径（Codex 12:10 必补）。
    func testIngestThenAcceptAcrossStoreReopen() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resource = try resource(
            identifier: "mode1-working",
            digest: "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be",
            byteCount: 12
        )
        let package = try makePackage(resources: [resource])

        do {
            let storeA = try resourceStore(rootDirectory: root)
            try await storeA.ingestResources([
                AhaKeyXPCResourceIngestionItem(
                    logicalIdentifier: resource.logicalIdentifier,
                    sha256: resource.sha256,
                    byteCount: resource.byteCount,
                    data: Data("resource-one".utf8)
                )
            ])
        }

        let storeB = try resourceStore(rootDirectory: root)
        let acceptedID = try await storeB.accept(package, resourceFiles: [:])
        XCTAssertEqual(acceptedID, package.operationID)
        let url = try await storeB.resourceURL(for: resource.sha256)
        XCTAssertEqual(try url.map { try Data(contentsOf: $0) }, Data("resource-one".utf8))
    }

    /// 重启后 staged 资源存活且计入配额；清理不得删已 journal 的 staged 文件。
    func testStagedResourceSurvivesRestartAndReconcile() async throws {
        let root = temporaryDirectory()
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let digest = try AhaKeySHA256Digest(
            "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"
        )

        do {
            let storeA = try resourceStore(rootDirectory: root)
            try await storeA.ingestResources([
                AhaKeyXPCResourceIngestionItem(
                    logicalIdentifier: try AhaKeyResourceIdentifier("idle"),
                    sha256: digest, byteCount: 12, data: Data("resource-one".utf8)
                )
            ])
        }

        // 重开触发启动 reconciliation：staged 文件必须存活（不视为 orphan）。
        let storeB = try resourceStore(rootDirectory: root)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: resources.appendingPathComponent(digest.rawValue).path
        ))
        // 未 apply 的 ingest 也计入配额核算。
        let usageAfterReopen = try await storeB.resourceStorageUsage()
        XCTAssertEqual(usageAfterReopen, 12)
    }

    /// 配额：staged 占用 + 新 ingest 合计超限拒绝；重复 digest 去重不双计。
    func testStagedQuotaAccountingAndDedup() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            quota: .init(maxSingleResourceBytes: 32, maxTotalResourceBytes: 20),
            acceptanceValidator: AllowingResourceValidator()
        )
        let first = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("first"),
            sha256: try AhaKeySHA256Digest("03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"),
            byteCount: 12, data: Data("resource-one".utf8)
        )
        try await store.ingestResources([first])
        // 重复 ingest 同 digest：去重，不双计配额。
        try await store.ingestResources([first])
        let usageAfterDup = try await store.resourceStorageUsage()
        XCTAssertEqual(usageAfterDup, 12)

        let second = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("second"),
            sha256: try AhaKeySHA256Digest("a49df6264aac97259550659f2d7ede6c30689e36881c4a37b31db3a4a2c199a6"),
            byteCount: 22, data: Data("resource-two-is-larger".utf8)
        )
        do {
            try await store.ingestResources([second])
            XCTFail("Expected total quota rejection counting staged bytes")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .resourceQuotaExceeded(limit: 20, attempted: 34)
            )
        }
    }

    /// 元数据冲突：同 digest 不同申报字节数，拒绝而非静默忽略。
    func testIngestRejectsConflictingByteCountForSameDigest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try resourceStore(rootDirectory: root)
        let digest = try AhaKeySHA256Digest(
            "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"
        )
        try await store.ingestResources([
            AhaKeyXPCResourceIngestionItem(
                logicalIdentifier: try AhaKeyResourceIdentifier("idle"),
                sha256: digest, byteCount: 12, data: Data("resource-one".utf8)
            )
        ])
        do {
            try await store.ingestResources([
                AhaKeyXPCResourceIngestionItem(
                    logicalIdentifier: try AhaKeyResourceIdentifier("idle-2"),
                    sha256: digest, byteCount: 13, data: Data("resource-one".utf8)
                )
            ])
            XCTFail("Expected metadata conflict rejection")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .resourceByteCountMismatch(try AhaKeyResourceIdentifier("idle-2"))
            )
        }
    }

    /// accept 转正后 staged journal 清除，配额不双计；跨 store 仍可见正式资源。
    func testAcceptPromotesStagedResourceAtomically() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resource = try resource(
            identifier: "mode1-working",
            digest: "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be",
            byteCount: 12
        )
        let store = try resourceStore(rootDirectory: root)
        try await store.ingestResources([
            AhaKeyXPCResourceIngestionItem(
                logicalIdentifier: resource.logicalIdentifier,
                sha256: resource.sha256, byteCount: 12, data: Data("resource-one".utf8)
            )
        ])
        let usageStaged = try await store.resourceStorageUsage()
        XCTAssertEqual(usageStaged, 12)
        _ = try await store.accept(try makePackage(resources: [resource]), resourceFiles: [:])
        // 转正后仍是 12（staged 删除 + 正式插入，同事务），不是 24。
        let usagePromoted = try await store.resourceStorageUsage()
        XCTAssertEqual(usagePromoted, 12)

        let reopened = try resourceStore(rootDirectory: root)
        let usageReopened = try await reopened.resourceStorageUsage()
        XCTAssertEqual(usageReopened, 12)
        let promotedURL = try await reopened.resourceURL(for: resource.sha256)
        XCTAssertNotNil(promotedURL)
    }

    /// 批内重复 digest：单次 ingest 两个同 digest item，配额只计一次（Codex 12:42 finding #4）。
    func testSingleBatchDuplicateDigestCountsOnce() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try resourceStore(rootDirectory: root)
        let digest = try AhaKeySHA256Digest(
            "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"
        )
        let item = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("idle"),
            sha256: digest, byteCount: 12, data: Data("resource-one".utf8)
        )
        let duplicate = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("idle-copy"),
            sha256: digest, byteCount: 12, data: Data("resource-one".utf8)
        )
        try await store.ingestResources([item, duplicate])
        let usage = try await store.resourceStorageUsage()
        XCTAssertEqual(usage, 12)
    }

    /// 崩溃窗口：journal 已提交但 final 文件缺失（commit 与 move 之间崩溃），
    /// 下次启动 prune 删除该 journal 行并释放配额（Codex 12:42 finding #1 的反向窗口）。
    func testStartupPrunesStagedJournalRowWithMissingFile() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let orphanDigest = "1111111111111111111111111111111111111111111111111111111111111111"

        do {
            // 首次初始化建表。
            let storeA = try resourceStore(rootDirectory: root)
            _ = try await storeA.health()
        }

        // 模拟崩溃残留：journal 行存在，final 文件从未落盘。
        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let insert = """
        INSERT INTO runtime_staged_resources
            (digest, byte_count, media_type, logical_identifier, relative_path)
        VALUES ('\(orphanDigest)', 64, 'application/octet-stream', 'orphan', '\(orphanDigest)')
        """
        XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let storeB = try resourceStore(rootDirectory: root)
        let usage = try await storeB.resourceStorageUsage()
        XCTAssertEqual(usage, 0)

        // prune 后该行不再保护配额，也不影响后续同 digest 重新 ingest。
        var verify: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &verify), SQLITE_OK)
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(
            verify, "SELECT COUNT(*) FROM runtime_staged_resources WHERE digest = '\(orphanDigest)'",
            -1, &stmt, nil
        ), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(stmt, 0), 0)
        sqlite3_finalize(stmt)
        sqlite3_close(verify)
    }

    // MARK: - 真并发临界区测试（hook + semaphore 制造可控交错，非顺序代理）

    /// finding #1：ingest 持锁期间，并发 Store init 的 reconcile/prune 必须阻塞，
    /// 不得删除正在提交的 staged journal；用时间戳证明 B 完成于放行之后（非超时假绿）。
    func testInitReconcileBlocksBehindIngestCriticalSection() async throws {
        final class CompletionBox: @unchecked Sendable {
            private let lock = NSLock()
            private var finishedAtStorage: Date?
            var finishedAt: Date? { lock.lock(); defer { lock.unlock() }; return finishedAtStorage }
            func mark() { lock.lock(); finishedAtStorage = Date(); lock.unlock() }
            var isFinished: Bool { finishedAt != nil }
        }

        let root = temporaryDirectory()
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let digest = try AhaKeySHA256Digest(
            "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"
        )
        let storeA = try resourceStore(rootDirectory: root)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        await storeA.setTestingHooks(.init(ingestBeforeJournalCommit: {
            entered.signal()
            _ = release.wait(timeout: .now() + 10)
        }))

        let ingestTask = Task {
            try await storeA.ingestResources([
                AhaKeyXPCResourceIngestionItem(
                    logicalIdentifier: try AhaKeyResourceIdentifier("idle"),
                    sha256: digest, byteCount: 12, data: Data("resource-one".utf8)
                )
            ])
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)

        // A 持锁停在 COMMIT 前；并发初始化 storeB（其 pragma/建表/reconcile/prune 全在锁内）。
        let box = CompletionBox()
        let storeBTask = Task {
            defer { box.mark() }
            return try resourceStore(rootDirectory: root)
        }
        // 500ms 探活：锁生效时 B 的 init 必然未完成（不等待 B，避免与 hook 死锁）。
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(box.isFinished, "storeB init 在 ingest 临界区内完成，flock 未生效")
        let releaseTime = Date()
        release.signal()
        try await ingestTask.value
        _ = try await storeBTask.value
        // B 完成时刻必须在放行之后（真实命中阻塞，而非 10s 超时假绿）。
        XCTAssertGreaterThan(box.finishedAt ?? .distantPast, releaseTime)

        // journal 与 final 文件都完好，未被并发 prune 删除。
        let usage = try await storeA.resourceStorageUsage()
        XCTAssertEqual(usage, 12)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: resources.appendingPathComponent(digest.rawValue).path
        ))
    }

    /// finding #2：两个 Store 并发 ingest 同 digest 被锁串行化，幂等成功、
    /// 配额只计一次、无 loser 临时文件残留。
    /// barrier 对齐在「双方 phase-1 均已写出 .staging-* 临时文件、尚未进 flock」处，
    /// 再放行抢锁——真实覆盖「双方都先生成临时文件再争锁」的 loser temp 路径。
    func testConcurrentIngestSameDigestIsSerializedAndIdempotent() async throws {
        let root = temporaryDirectory()
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let digest = try AhaKeySHA256Digest(
            "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"
        )
        let item = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("idle"),
            sha256: digest, byteCount: 12, data: Data("resource-one".utf8)
        )
        let storeA = try resourceStore(rootDirectory: root)
        let storeB = try resourceStore(rootDirectory: root)
        // phase-1 barrier：双方都写出临时文件后由主线程统一放行，随后并发抢 flock。
        let staged = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        let phase1Hook: () -> Void = {
            staged.signal()
            _ = gate.wait(timeout: .now() + 10)
        }
        await storeA.setTestingHooks(.init(ingestAfterPhase1Staging: phase1Hook))
        await storeB.setTestingHooks(.init(ingestAfterPhase1Staging: phase1Hook))

        let taskA = Task { try await storeA.ingestResources([item]) }
        let taskB = Task { try await storeB.ingestResources([item]) }
        // 等待双方都完成 phase-1（临时文件都已存在），再双双放行抢锁。
        XCTAssertEqual(staged.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(staged.wait(timeout: .now() + 5), .success)
        gate.signal()
        gate.signal()
        try await taskA.value
        try await taskB.value

        let usage = try await storeA.resourceStorageUsage()
        XCTAssertEqual(usage, 12)
        // 无 loser 的 .staging- 临时文件残留（赢方安装 final，输方幂等 skip 后成功路径清理）。
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: resources.path)
            .filter { $0.hasPrefix(".staging-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    /// finding #2 配额面：并发 ingest 的 admission 被锁串行化——A(12B) 提交后，
    /// B(22B) 在锁内重算用量并拒绝（合计 34 > 20），不能双双越过总配额。
    func testConcurrentQuotaAdmissionIsSerialized() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let quota = AhaKeyRuntimeResourceQuota(maxSingleResourceBytes: 32, maxTotalResourceBytes: 20)
        let storeA = try AhaKeyRuntimePersistentStore(
            rootDirectory: root, quota: quota, acceptanceValidator: AllowingResourceValidator()
        )
        let storeB = try AhaKeyRuntimePersistentStore(
            rootDirectory: root, quota: quota, acceptanceValidator: AllowingResourceValidator()
        )
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        await storeA.setTestingHooks(.init(ingestBeforeJournalCommit: {
            entered.signal()
            _ = release.wait(timeout: .now() + 10)
        }))

        let taskA = Task {
            try await storeA.ingestResources([
                AhaKeyXPCResourceIngestionItem(
                    logicalIdentifier: try AhaKeyResourceIdentifier("first"),
                    sha256: try AhaKeySHA256Digest("03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"),
                    byteCount: 12, data: Data("resource-one".utf8)
                )
            ])
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        let taskB = Task {
            try await storeB.ingestResources([
                AhaKeyXPCResourceIngestionItem(
                    logicalIdentifier: try AhaKeyResourceIdentifier("second"),
                    sha256: try AhaKeySHA256Digest("a49df6264aac97259550659f2d7ede6c30689e36881c4a37b31db3a4a2c199a6"),
                    byteCount: 22, data: Data("resource-two-is-larger".utf8)
                )
            ])
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        release.signal()
        try await taskA.value
        do {
            try await taskB.value
            XCTFail("B 必须在锁内 admission 时被配额拒绝")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .resourceQuotaExceeded(limit: 20, attempted: 34)
            )
        }
    }

    /// 跨 Store 并发元数据冲突：预置 staged 行（byteCount=99）后，并发 B 的同 digest
    /// 真实数据（byteCount=12）必须在 flock 临界区内被冲突检测拒绝
    /// （digest 由数据决定，无法用真实数据构造「同 digest 不同字节数」，故用 raw sqlite
    /// 预置不一致的 staged 行，使冲突真实抵达锁内检测而非锁外自校验）。
    func testConcurrentConflictingByteCountRejectedInsideCriticalSection() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let digest = try AhaKeySHA256Digest(
            "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"
        )
        let storeA = try resourceStore(rootDirectory: root)
        let storeB = try resourceStore(rootDirectory: root)

        // raw sqlite 预置：digest 已有 staged 行，byteCount=99（与真实数据的 12 冲突）。
        var seed: OpaquePointer?
        XCTAssertEqual(sqlite3_open(
            root.appendingPathComponent("runtime.sqlite3").path, &seed
        ), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(seed, """
            INSERT INTO runtime_staged_resources
                (digest, byte_count, media_type, logical_identifier, relative_path)
            VALUES ('\(digest.rawValue)', 99, 'application/octet-stream', 'idle-seed', '\(digest.rawValue)')
            """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(seed)

        // A 持锁停在 COMMIT 前（ingest 一个无关 digest），证明 B 的拒绝发生在进锁之后。
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        await storeA.setTestingHooks(.init(ingestBeforeJournalCommit: {
            entered.signal()
            _ = release.wait(timeout: .now() + 10)
        }))
        let taskA = Task {
            try await storeA.ingestResources([
                AhaKeyXPCResourceIngestionItem(
                    logicalIdentifier: try AhaKeyResourceIdentifier("other"),
                    sha256: try AhaKeySHA256Digest("a49df6264aac97259550659f2d7ede6c30689e36881c4a37b31db3a4a2c199a6"),
                    byteCount: 22, data: Data("resource-two-is-larger".utf8)
                )
            ])
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)

        // B 的真实数据（12 bytes）与预置 staged 行（99）冲突：phase-1 自校验通过，
        // 进锁后在 staged 冲突检测处被拒绝。
        let taskB = Task {
            try await storeB.ingestResources([
                AhaKeyXPCResourceIngestionItem(
                    logicalIdentifier: try AhaKeyResourceIdentifier("idle-conflict"),
                    sha256: digest, byteCount: 12, data: Data("resource-one".utf8)
                )
            ])
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        release.signal()
        try await taskA.value
        do {
            try await taskB.value
            XCTFail("并发冲突声明必须被拒绝")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .resourceByteCountMismatch(try AhaKeyResourceIdentifier("idle-conflict"))
            )
        }
        // 预置 staged 行不受影响；用量 = 预置 99 + A 的 22。
        let usage = try await storeA.resourceStorageUsage()
        XCTAssertEqual(usage, 121)
    }

    /// accept seam 接线验证：临界区 COMMIT 前钩子被真实调用（配合 ingest seam 覆盖两个入口）。
    func testAcceptInvokesBeforeCommitHookInsideCriticalSection() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try resourceStore(rootDirectory: root)
        let hookFired = DispatchSemaphore(value: 0)
        await store.setTestingHooks(.init(acceptBeforeCommit: { hookFired.signal() }))
        _ = try await store.accept(try makePackage(), resourceFiles: [:])
        XCTAssertEqual(hookFired.wait(timeout: .now() + 1), .success)
    }

    /// finding #3：批内同 digest 冲突（byteCount/data 不一致）在去重前拒绝，不得静默吞掉。
    func testBatchDuplicateDigestConflictRejectedBeforeDedup() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try resourceStore(rootDirectory: root)
        let digest = try AhaKeySHA256Digest(
            "03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"
        )
        let first = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("idle"),
            sha256: digest, byteCount: 12, data: Data("resource-one".utf8)
        )
        let conflicting = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("idle-conflict"),
            sha256: digest, byteCount: 13, data: Data("resource-one".utf8)
        )
        do {
            try await store.ingestResources([first, conflicting])
            XCTFail("批内冲突必须在去重前拒绝")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimePersistenceError,
                .resourceByteCountMismatch(try AhaKeyResourceIdentifier("idle-conflict"))
            )
        }
        // 拒绝后无任何 journal/文件残留。
        let usage = try await store.resourceStorageUsage()
        XCTAssertEqual(usage, 0)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AhaKeyRuntimePersistentStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func seedV3Transactions(
        root: URL,
        rows: [(AhaKeyConfigurationPackage, String)]
    ) throws {
        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let sql = """
        PRAGMA user_version=3;
        CREATE TABLE runtime_transactions (
            operation_id TEXT PRIMARY KEY NOT NULL,
            package BLOB NOT NULL,
            state TEXT NOT NULL,
            completed_steps INTEGER NOT NULL,
            total_steps INTEGER NOT NULL,
            message_code TEXT,
            failure_context TEXT
        );
        """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        let encoder = JSONEncoder()
        for (package, state) in rows {
            let packageData = try encoder.encode(package)
            var statement: OpaquePointer?
            XCTAssertEqual(
                sqlite3_prepare_v2(
                    database,
                    "INSERT INTO runtime_transactions (operation_id, package, state, completed_steps, total_steps, message_code) VALUES (?, ?, ?, 0, 2, NULL)",
                    -1,
                    &statement,
                    nil
                ),
                SQLITE_OK
            )
            let operationID = package.operationID.rawValue.uuidString
            operationID.withCString {
                sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            packageData.withUnsafeBytes { bytes in
                _ = sqlite3_bind_blob(
                    statement,
                    2,
                    bytes.baseAddress,
                    Int32(packageData.count),
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                )
            }
            state.withCString {
                sqlite3_bind_text(statement, 3, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_finalize(statement)
        }
    }

    private func nullTerminalOrderCount(root: URL) throws -> Int {
        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT COUNT(*) FROM runtime_transactions
                WHERE state IN ('completed', 'failedWithoutWrites', 'failedWithPartialCommit')
                  AND terminal_order IS NULL
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return Int(sqlite3_column_int(statement, 0))
    }

    private func terminalOrderTriggerExists(root: URL) throws -> Bool {
        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT COUNT(*) FROM sqlite_master
                WHERE type = 'trigger'
                  AND name = 'runtime_transactions_assign_terminal_order'
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return sqlite3_column_int(statement, 0) == 1
    }

    private func terminalOrder(
        root: URL,
        operationID: AhaKeyRuntimeOperationID
    ) throws -> Int64? {
        let databaseURL = root.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                "SELECT terminal_order FROM runtime_transactions WHERE operation_id = ?",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(statement) }
        let raw = operationID.rawValue.uuidString
        raw.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(statement, 0)
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
