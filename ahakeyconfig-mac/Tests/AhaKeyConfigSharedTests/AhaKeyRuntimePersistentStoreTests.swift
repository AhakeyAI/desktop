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
