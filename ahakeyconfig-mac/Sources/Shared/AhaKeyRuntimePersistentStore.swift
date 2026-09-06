import CryptoKit
import Darwin
import Foundation
import SQLite3

public struct AhaKeyRuntimePersistenceHealth: Equatable, Sendable {
    public let schemaVersion: Int32
    public let journalMode: String
}

public struct AhaKeyRuntimeResourceQuota: Equatable, Sendable {
    public static let `default` = AhaKeyRuntimeResourceQuota(
        maxSingleResourceBytes: 16 * 1_024 * 1_024,
        maxTotalResourceBytes: 128 * 1_024 * 1_024
    )

    public let maxSingleResourceBytes: UInt64
    public let maxTotalResourceBytes: UInt64

    public init(maxSingleResourceBytes: UInt64, maxTotalResourceBytes: UInt64) {
        self.maxSingleResourceBytes = maxSingleResourceBytes
        self.maxTotalResourceBytes = maxTotalResourceBytes
    }
}

public struct AhaKeyRuntimePersistedTransaction: Equatable, Sendable {
    public let operationID: AhaKeyRuntimeOperationID
    public let package: AhaKeyConfigurationPackage
    public let state: AhaKeyRuntimeOperationState
    public let completedSteps: UInt32
    public let totalSteps: UInt32
    public let messageCode: AhaKeyRuntimeEventCode?
    public let failureContext: AhaKeyRuntimeOperationFailureContext?

    public init(
        operationID: AhaKeyRuntimeOperationID,
        package: AhaKeyConfigurationPackage,
        state: AhaKeyRuntimeOperationState,
        completedSteps: UInt32,
        totalSteps: UInt32,
        messageCode: AhaKeyRuntimeEventCode?,
        failureContext: AhaKeyRuntimeOperationFailureContext? = nil
    ) {
        self.operationID = operationID
        self.package = package
        self.state = state
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
        self.messageCode = messageCode
        self.failureContext = failureContext.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct AhaKeyRuntimeStepIdentifier: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 128 else {
            throw AhaKeyRuntimePersistenceError.invalidStepIdentifier
        }
        self.rawValue = normalized
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AhaKeyRuntimeSyncBaseline: Codable, Equatable, Sendable {
    public let deviceID: AhaKeyRuntimeDeviceID
    public let revision: AhaKeyConfigurationRevision
    public let confirmedConfiguration: Data

    public init(
        deviceID: AhaKeyRuntimeDeviceID,
        revision: AhaKeyConfigurationRevision,
        confirmedConfiguration: Data
    ) throws {
        guard !confirmedConfiguration.isEmpty else {
            throw AhaKeyRuntimePersistenceError.emptySyncBaseline
        }
        self.deviceID = deviceID
        self.revision = revision
        self.confirmedConfiguration = confirmedConfiguration
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID, revision, confirmedConfiguration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            deviceID: container.decode(AhaKeyRuntimeDeviceID.self, forKey: .deviceID),
            revision: container.decode(AhaKeyConfigurationRevision.self, forKey: .revision),
            confirmedConfiguration: container.decode(Data.self, forKey: .confirmedConfiguration)
        )
    }
}

/// Domain/device validation remains outside the storage module, but it is mandatory before
/// a package containing resources can be accepted. WBS 5.6 supplies the production planner.
public struct AhaKeyRuntimeResourceValidationInput: Sendable {
    public let resource: AhaKeyConfigurationResource
    public let contents: Data

    public init(resource: AhaKeyConfigurationResource, contents: Data) {
        self.resource = resource
        self.contents = contents
    }
}

public protocol AhaKeyRuntimePackageAcceptanceValidator: Sendable {
    func validate(
        package: AhaKeyConfigurationPackage,
        resources: [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput]
    ) throws
}

public struct AhaKeyRuntimeRejectingResourceValidator: AhaKeyRuntimePackageAcceptanceValidator {
    public init() {}

    public func validate(
        package: AhaKeyConfigurationPackage,
        resources: [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput]
    ) throws {
        guard package.resources.isEmpty, resources.isEmpty else {
            throw AhaKeyRuntimePersistenceError.domainResourceValidationRequired
        }
    }
}

public enum AhaKeyRuntimePersistenceError: Error, Equatable, Sendable {
    case cannotOpenDatabase(String)
    case databaseFailure(String)
    case corruptTransaction
    case operationIdentifierConflict
    case unexpectedResourceFiles
    case missingResourceFile(AhaKeyResourceIdentifier)
    case resourceByteCountMismatch(AhaKeyResourceIdentifier)
    case resourceDigestMismatch(AhaKeyResourceIdentifier)
    case resourceTooLarge(limit: UInt64, attempted: UInt64)
    case resourceQuotaExceeded(limit: UInt64, attempted: UInt64)
    case operationNotFound
    case operationTargetMismatch
    case invalidOperationProgress
    case terminalOperationCannotChange
    case invalidStepIdentifier
    case emptySyncBaseline
    case unsupportedSchemaVersion(Int32)
    case unsafeResourceFile(AhaKeyResourceIdentifier)
    case domainResourceValidationRequired
    case invalidOperationOutcome
    case invalidOutcomeBaseline
    /// 申报元数据与 CAS 实际图片不一致（帧数/尺寸），或图片无法解码。
    case resourceMetadataMismatch(String)
    case blockedByQueueHead(AhaKeyRuntimeOperationID)
    case staleAuthoritativeGeneration
    case corruptAuthoritativeVersion
    case clockRollback
}

/// Store 测试 seam：资源临界区的可控交错钩子。仅在 @testable 测试中注入。
/// `ingestBeforeJournalCommit` / `acceptBeforeCommit` 在 flock 临界区内执行，
/// 只许信号量/原子标志，禁止在钩子内重入任何 Store；
/// `ingestAfterPhase1Staging` 在锁外（flock 之前）执行，用于并发测试的 barrier 对齐。
struct AhaKeyRuntimeStoreTestingHooks {
    /// ingest：BEGIN IMMEDIATE 内、journal 已写、COMMIT 前调用。
    var ingestBeforeJournalCommit: (() -> Void)?
    /// accept：BEGIN IMMEDIATE 内、事务已写、COMMIT 前调用。
    var acceptBeforeCommit: (() -> Void)?
    /// ingest：阶段 1 临时文件全部写完、进入 flock 临界区之前调用（锁外）。
    /// 用于并发测试在「双方都已生成 .staging-* 临时文件」处对齐 barrier，再放行抢锁。
    var ingestAfterPhase1Staging: (() -> Void)?

    init(
        ingestBeforeJournalCommit: (() -> Void)? = nil,
        acceptBeforeCommit: (() -> Void)? = nil,
        ingestAfterPhase1Staging: (() -> Void)? = nil
    ) {
        self.ingestBeforeJournalCommit = ingestBeforeJournalCommit
        self.acceptBeforeCommit = acceptBeforeCommit
        self.ingestAfterPhase1Staging = ingestAfterPhase1Staging
    }
}

/// init 写事务 seam：实例 hooks 在 `init` 返回前无法注入，故用静态钩子交错迁移与终态提交。
enum AhaKeyRuntimeStoreSchemaMigrationTestingHooks {
    private static let lock = NSLock()
    private static var insideWriteTransactionStorage: (() -> Void)?

    /// schema 迁移写事务内、`user_version` 已更新、COMMIT 前调用。
    static var insideWriteTransaction: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return insideWriteTransactionStorage
        }
        set {
            lock.lock()
            insideWriteTransactionStorage = newValue
            lock.unlock()
        }
    }
}

public actor AhaKeyRuntimePersistentStore {
    public static let schemaVersion: Int32 = 7
    /// Snapshot 合并的终态窗口，与 Agent `projectionTerminalOrder` 64 上限对齐。
    public static let snapshotProjectionTerminalLimit = 64
    /// 旧 v3 writer 只更新既有列、不写 `terminal_order`。迁移后该 trigger 仅在
    /// 状态进入终态且 order 仍为 NULL 时分配 MAX+1；显式写入的 v4 order 不被覆盖。
    static let terminalOrderCompatibilityTriggerSQL = """
        CREATE TRIGGER IF NOT EXISTS runtime_transactions_assign_terminal_order
        AFTER UPDATE OF state ON runtime_transactions
        FOR EACH ROW
        WHEN NEW.state IN ('completed', 'failedWithoutWrites', 'failedWithPartialCommit')
         AND NEW.terminal_order IS NULL
        BEGIN
            UPDATE runtime_transactions
            SET terminal_order = (
                SELECT COALESCE(MAX(terminal_order), 0) FROM runtime_transactions
            ) + 1
            WHERE operation_id = NEW.operation_id
              AND terminal_order IS NULL;
        END
        """

    private let database: OpaquePointer
    private let resourcesDirectory: URL
    private let quota: AhaKeyRuntimeResourceQuota
    private let acceptanceValidator: any AhaKeyRuntimePackageAcceptanceValidator
    /// 同一 persistence root 的跨 Store/跨进程 advisory 锁（flock）。init reconciliation/prune、
    /// ingest admission+install+journal、accept 转正都在该临界区内；进程崩溃由 OS 释放锁。
    private let lockFileDescriptor: Int32
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    /// 测试 seam：资源临界区内的可控交错钩子（仅 @testable；钩子在锁内执行，禁止重入 Store）。
    var testingHooks = AhaKeyRuntimeStoreTestingHooks()

    func setTestingHooks(_ hooks: AhaKeyRuntimeStoreTestingHooks) {
        testingHooks = hooks
    }

    /// 临界区辅助：flock LOCK_EX/UN 成对，返回值受校验（EINTR/EBADF 不得当作已加锁）。
    private static func withExclusiveLock<T>(_ fd: Int32, _ body: () throws -> T) throws -> T {
        guard flock(fd, LOCK_EX) == 0 else {
            throw AhaKeyRuntimePersistenceError.databaseFailure("flock LOCK_EX failed: errno=\(errno)")
        }
        do {
            let result = try body()
            guard flock(fd, LOCK_UN) == 0 else {
                throw AhaKeyRuntimePersistenceError.databaseFailure("flock LOCK_UN failed: errno=\(errno)")
            }
            return result
        } catch {
            // body 抛错时尽力解锁（失败无可恢复手段，进程退出由 OS 回收）。
            _ = flock(fd, LOCK_UN)
            throw error
        }
    }

    public init(
        rootDirectory: URL,
        quota: AhaKeyRuntimeResourceQuota = .default,
        acceptanceValidator: any AhaKeyRuntimePackageAcceptanceValidator = AhaKeyRuntimeRejectingResourceValidator()
    ) throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path)
        let resourcesDirectory = rootDirectory.appendingPathComponent("resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: resourcesDirectory.path)
        let databaseURL = rootDirectory.appendingPathComponent("runtime.sqlite3", isDirectory: false)
        // 先拿锁文件：init 的 reconciliation/prune 必须与其他 Store 的 ingest/accept 互斥。
        let lockURL = rootDirectory.appendingPathComponent(".runtime-store.lock", isDirectory: false)
        let lockFD = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else {
            throw AhaKeyRuntimePersistenceError.databaseFailure("cannot open store lock file: errno=\(errno)")
        }
        lockFileDescriptor = lockFD
        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
            if let handle { sqlite3_close(handle) }
            close(lockFD)
            throw AhaKeyRuntimePersistenceError.cannotOpenDatabase(message)
        }
        database = handle
        self.resourcesDirectory = resourcesDirectory
        self.quota = quota
        self.acceptanceValidator = acceptanceValidator
        do {
            // 数据库文件权限设置纳入 do/catch：此处失败必须走统一清理（close lockFD +
            // sqlite3_close handle），不得在 handle/fd 已建立后裸抛造成泄漏。
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
            // 整个 init 临界区（pragma/建表/reconcile/prune）都在 flock 内：与其他 Store 的
            // ingest/accept 写事务互斥，避免 schema 写入撞上 BEGIN IMMEDIATE（SQLITE_BUSY）。
            try Self.withExclusiveLock(lockFD) {
            try Self.execute("PRAGMA journal_mode=WAL", on: handle)
            try Self.execute("PRAGMA synchronous=FULL", on: handle)
            try Self.execute("PRAGMA foreign_keys=ON", on: handle)
            let existingSchemaVersion = try Self.userVersion(on: handle)
            guard existingSchemaVersion <= Self.schemaVersion else {
                throw AhaKeyRuntimePersistenceError.unsupportedSchemaVersion(existingSchemaVersion)
            }
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_transactions (
                    operation_id TEXT PRIMARY KEY NOT NULL,
                    package BLOB NOT NULL,
                    state TEXT NOT NULL,
                    completed_steps INTEGER NOT NULL,
                    total_steps INTEGER NOT NULL,
                    message_code TEXT,
                    queue_order INTEGER
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_resources (
                    digest TEXT PRIMARY KEY NOT NULL,
                    byte_count INTEGER NOT NULL,
                    media_type TEXT NOT NULL,
                    relative_path TEXT NOT NULL
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_staged_resources (
                    digest TEXT PRIMARY KEY NOT NULL,
                    byte_count INTEGER NOT NULL,
                    media_type TEXT NOT NULL,
                    logical_identifier TEXT NOT NULL,
                    relative_path TEXT NOT NULL
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_transaction_resources (
                    operation_id TEXT NOT NULL REFERENCES runtime_transactions(operation_id) ON DELETE CASCADE,
                    logical_identifier TEXT NOT NULL,
                    digest TEXT NOT NULL REFERENCES runtime_resources(digest),
                    PRIMARY KEY (operation_id, logical_identifier)
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value BLOB NOT NULL
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_confirmed_steps (
                    operation_id TEXT NOT NULL REFERENCES runtime_transactions(operation_id) ON DELETE CASCADE,
                    step_id TEXT NOT NULL,
                    PRIMARY KEY (operation_id, step_id)
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_sync_baselines (
                    device_id TEXT PRIMARY KEY NOT NULL,
                    revision TEXT NOT NULL,
                    confirmed_configuration BLOB NOT NULL
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_page_field_baselines (
                    device_id TEXT NOT NULL,
                    page_id TEXT NOT NULL,
                    field_id TEXT NOT NULL,
                    value BLOB NOT NULL,
                    trust TEXT NOT NULL,
                    provenance TEXT NOT NULL,
                    operation_id TEXT,
                    authority_generation INTEGER,
                    authority_version BLOB,
                    PRIMARY KEY (device_id, page_id, field_id)
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_disconnect_epochs (
                    operation_id TEXT PRIMARY KEY NOT NULL
                        REFERENCES runtime_transactions(operation_id) ON DELETE CASCADE,
                    epoch BLOB NOT NULL
                )
                """,
                on: handle
            )
            try Self.execute("DROP TABLE IF EXISTS remapped_running", on: handle)
            try Self.execute(
                """
                CREATE TEMP TABLE remapped_running AS
                SELECT operation_id FROM runtime_transactions WHERE state = 'running'
                """,
                on: handle
            )
            try Self.execute(
                """
                UPDATE runtime_transactions
                SET state = 'paused'
                WHERE state = 'running'
                """,
                on: handle
            )
            try Self.execute("DROP TABLE remapped_running", on: handle)
            // 资源目录 reconcile 与 staged prune 由外层 init 临界区覆盖，直接执行
            // （不得再嵌套 withExclusiveLock：同 fd 内层 LOCK_UN 会提前放锁）。
            try Self.reconcileResourceDirectory(resourcesDirectory, with: handle)
            try Self.pruneStagedJournalMissingFiles(resourcesDirectory, with: handle)
            if existingSchemaVersion < Self.schemaVersion {
                // ALTER / 回填 / user_version 必须同一写事务：否则已打开的连接可在
                // 回填后、版本更新前提交终态，留下 terminal_order = NULL 并永久被窗口排除。
                try Self.execute("BEGIN IMMEDIATE", on: handle)
                do {
                    if existingSchemaVersion < 3 {
                        if try !Self.table(handle, "runtime_transactions", hasColumn: "failure_context") {
                            try Self.execute(
                                "ALTER TABLE runtime_transactions ADD COLUMN failure_context TEXT",
                                on: handle
                            )
                        }
                    }
                    if existingSchemaVersion < 4 {
                        if try !Self.table(handle, "runtime_transactions", hasColumn: "terminal_order") {
                            try Self.execute(
                                "ALTER TABLE runtime_transactions ADD COLUMN terminal_order INTEGER",
                                on: handle
                            )
                        }
                        // 历史终态没有进入终态时刻；只能按受理 rowid 回填，之后的提交用严格单调序号。
                        try Self.execute(
                            """
                            CREATE TEMP TABLE terminal_order_backfill AS
                            SELECT operation_id,
                                   ROW_NUMBER() OVER (ORDER BY rowid) AS assigned
                            FROM runtime_transactions
                            WHERE state IN (
                                'completed', 'failedWithoutWrites', 'failedWithPartialCommit'
                            )
                              AND terminal_order IS NULL
                            """,
                            on: handle
                        )
                        try Self.execute(
                            """
                            UPDATE runtime_transactions
                            SET terminal_order = (
                                SELECT assigned FROM terminal_order_backfill
                                WHERE terminal_order_backfill.operation_id = runtime_transactions.operation_id
                            )
                            WHERE operation_id IN (SELECT operation_id FROM terminal_order_backfill)
                            """,
                            on: handle
                        )
                        try Self.execute("DROP TABLE terminal_order_backfill", on: handle)
                        try Self.execute(Self.terminalOrderCompatibilityTriggerSQL, on: handle)
                    }
                    if existingSchemaVersion < 5 {
                        if try !Self.table(handle, "runtime_transactions", hasColumn: "queue_order") {
                            try Self.execute(
                                "ALTER TABLE runtime_transactions ADD COLUMN queue_order INTEGER",
                                on: handle
                            )
                        }
                        try Self.execute(
                            """
                            UPDATE runtime_transactions
                            SET queue_order = rowid
                            WHERE queue_order IS NULL
                            """,
                            on: handle
                        )
                    }
                    if existingSchemaVersion < 7 {
                        if try !Self.table(handle, "runtime_page_field_baselines", hasColumn: "authority_version") {
                            try Self.execute(
                                "ALTER TABLE runtime_page_field_baselines ADD COLUMN authority_version BLOB",
                                on: handle
                            )
                        }
                        try Self.execute("DROP TABLE IF EXISTS runtime_disconnect_clocks", on: handle)
                        try Self.execute(
                            """
                            CREATE TABLE IF NOT EXISTS runtime_disconnect_epochs (
                                operation_id TEXT PRIMARY KEY NOT NULL
                                    REFERENCES runtime_transactions(operation_id) ON DELETE CASCADE,
                                epoch BLOB NOT NULL
                            )
                            """,
                            on: handle
                        )
                    }
                    try Self.execute("PRAGMA user_version=\(Self.schemaVersion)", on: handle)
                    AhaKeyRuntimeStoreSchemaMigrationTestingHooks.insideWriteTransaction?()
                    try Self.execute("COMMIT", on: handle)
                } catch {
                    try? Self.execute("ROLLBACK", on: handle)
                    throw error
                }
            } else {
                try Self.execute(Self.terminalOrderCompatibilityTriggerSQL, on: handle)
            }
            }
        } catch {
            close(lockFD)
            sqlite3_close(handle)
            throw error
        }
    }

    deinit {
        close(lockFileDescriptor)
        sqlite3_close(database)
    }

    public func health() throws -> AhaKeyRuntimePersistenceHealth {
        let journalMode = try scalarText("PRAGMA journal_mode")
        let schema = try scalarInt32("PRAGMA user_version")
        return .init(schemaVersion: schema, journalMode: journalMode.lowercased())
    }

    @discardableResult
    public func accept(
        _ package: AhaKeyConfigurationPackage,
        resourceFiles: [AhaKeyResourceIdentifier: URL]
    ) throws -> AhaKeyRuntimeOperationID {
        // 整个 accept（含命中已有事务的早退校验）都在资源临界区内：与 init/ingest 互斥。
        return try Self.withExclusiveLock(lockFileDescriptor) {
        if let existing = try transaction(package.operationID) {
            guard existing.package == package else {
                throw AhaKeyRuntimePersistenceError.operationIdentifierConflict
            }
            try validateManagedResources(for: existing.package)
            return package.operationID
        }

        let expectedIdentifiers = Set(package.resources.map(\.logicalIdentifier))
        let providedIdentifiers = Set(resourceFiles.keys)
        if !providedIdentifiers.isEmpty {
            guard providedIdentifiers == expectedIdentifiers else {
                throw AhaKeyRuntimePersistenceError.unexpectedResourceFiles
            }
        }
        for resource in package.resources {
            guard resource.byteCount <= quota.maxSingleResourceBytes else {
                throw AhaKeyRuntimePersistenceError.resourceTooLarge(
                    limit: quota.maxSingleResourceBytes,
                    attempted: resource.byteCount
                )
            }
            if let sourceURL = resourceFiles[resource.logicalIdentifier] {
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    throw AhaKeyRuntimePersistenceError.missingResourceFile(resource.logicalIdentifier)
                }
                try validateResourceFile(at: sourceURL, against: resource)
            } else {
                let destination = managedResourceURL(for: resource.sha256)
                guard FileManager.default.fileExists(atPath: destination.path) else {
                    throw AhaKeyRuntimePersistenceError.missingResourceFile(resource.logicalIdentifier)
                }
                try validateManagedFile(at: destination, digest: resource.sha256, byteCount: resource.byteCount)
            }
        }

        var newDigests: Set<AhaKeySHA256Digest> = []
        var newBytes: UInt64 = 0
        for resource in package.resources where !newDigests.contains(resource.sha256) {
            // staged journal 已计入 resourceStorageUsage()，不再作为 newBytes 重复计配额。
            let alreadyCounted = try resourceExists(resource.sha256)
                || stagedResourceByteCount(resource.sha256) != nil
            if !alreadyCounted {
                newDigests.insert(resource.sha256)
                let (sum, overflow) = newBytes.addingReportingOverflow(resource.byteCount)
                guard !overflow else {
                    throw AhaKeyRuntimePersistenceError.resourceQuotaExceeded(
                        limit: quota.maxTotalResourceBytes,
                        attempted: UInt64.max
                    )
                }
                newBytes = sum
            }
        }
        let currentBytes = try resourceStorageUsage()
        let (attemptedBytes, overflow) = currentBytes.addingReportingOverflow(newBytes)
        guard !overflow, attemptedBytes <= quota.maxTotalResourceBytes else {
            throw AhaKeyRuntimePersistenceError.resourceQuotaExceeded(
                limit: quota.maxTotalResourceBytes,
                attempted: overflow ? UInt64.max : attemptedBytes
            )
        }

        var newlyCreatedFiles: [URL] = []
        do {
            for resource in package.resources {
                let destination = managedResourceURL(for: resource.sha256)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    let temporary = resourcesDirectory.appendingPathComponent(".staging-\(UUID().uuidString)")
                    do {
                        guard let sourceURL = resourceFiles[resource.logicalIdentifier] else {
                            throw AhaKeyRuntimePersistenceError.missingResourceFile(resource.logicalIdentifier)
                        }
                        try FileManager.default.copyItem(
                            at: sourceURL,
                            to: temporary
                        )
                        try validateResourceFile(at: temporary, against: resource)
                        try FileManager.default.setAttributes(
                            [.posixPermissions: 0o600],
                            ofItemAtPath: temporary.path
                        )
                        let handle = try FileHandle(forUpdating: temporary)
                        do {
                            try handle.synchronize()
                            try handle.close()
                        } catch {
                            try? handle.close()
                            throw error
                        }
                        try FileManager.default.moveItem(at: temporary, to: destination)
                    } catch {
                        try? FileManager.default.removeItem(at: temporary)
                        throw error
                    }
                    newlyCreatedFiles.append(destination)
                } else {
                    try validateResourceFile(at: destination, against: resource)
                }
            }

            let validationInputs = try Dictionary(
                uniqueKeysWithValues: package.resources.map {
                    let url = managedResourceURL(for: $0.sha256)
                    return (
                        $0.logicalIdentifier,
                        AhaKeyRuntimeResourceValidationInput(
                            resource: $0,
                            contents: try Data(contentsOf: url, options: [.mappedIfSafe])
                        )
                    )
                }
            )
            try acceptanceValidator.validate(
                package: package,
                resources: validationInputs
            )
            try validateManagedResources(for: package)
            try Self.synchronizeDirectory(resourcesDirectory)

            try Self.execute("BEGIN IMMEDIATE", on: database)
            do {
                try insertTransaction(package)
                for resource in package.resources {
                    try insertResource(resource)
                    try link(resource, to: package.operationID)
                    // 转正：staged journal 同事务删除，资源从预上传变为正式资源。
                    try deleteStagedResource(resource.sha256)
                }
                // 测试 seam：锁内 COMMIT 前的可控交错点（仅 @testable 注入）。
                testingHooks.acceptBeforeCommit?()
                try Self.execute("COMMIT", on: database)
            } catch {
                try? Self.execute("ROLLBACK", on: database)
                throw error
            }
        } catch {
            for url in newlyCreatedFiles { try? FileManager.default.removeItem(at: url) }
            try? Self.synchronizeDirectory(resourcesDirectory)
            throw error
        }
        return package.operationID
        }
    }

    /// 将资源数据写入 CAS（managed storage），不创建事务。
    /// 用于 XPC 预上传：Studio 先 ingest，再发 apply。
    public func ingestResources(_ items: [AhaKeyXPCResourceIngestionItem]) throws {
        for item in items {
            guard item.byteCount <= quota.maxSingleResourceBytes else {
                throw AhaKeyRuntimePersistenceError.resourceTooLarge(
                    limit: quota.maxSingleResourceBytes,
                    attempted: item.byteCount
                )
            }
        }

        // 批内一致性先于去重（Codex 14:40 finding #3）：同 digest 的所有 item 必须
        // byteCount 与 data 完全一致，任一冲突立即拒绝，不做静默去重。
        var uniqueByDigest: [AhaKeySHA256Digest: AhaKeyXPCResourceIngestionItem] = [:]
        for item in items {
            if let first = uniqueByDigest[item.sha256] {
                guard first.byteCount == item.byteCount, first.data == item.data else {
                    throw AhaKeyRuntimePersistenceError.resourceByteCountMismatch(item.logicalIdentifier)
                }
            } else {
                uniqueByDigest[item.sha256] = item
            }
        }

        // 阶段 1（锁外允许）：把数据写入 .staging- 临时文件并 fsync。崩溃残留由启动
        // prune 按龄期（>1h）回收；并发 reconcile 在锁内执行且跳过点前缀文件，不会误删。
        var stagingFiles: [AhaKeySHA256Digest: URL] = [:]
        do {
            for item in uniqueByDigest.values {
                let destination = managedResourceURL(for: item.sha256)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    let temporary = resourcesDirectory.appendingPathComponent(".staging-\(UUID().uuidString)")
                    let resource = AhaKeyConfigurationResource(
                        logicalIdentifier: item.logicalIdentifier,
                        sha256: item.sha256,
                        byteCount: item.byteCount,
                        mediaType: try AhaKeyMediaType("application/octet-stream")
                    )
                    try item.data.write(to: temporary, options: .atomic)
                    try validateResourceFile(at: temporary, against: resource)
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o600],
                        ofItemAtPath: temporary.path
                    )
                    let handle = try FileHandle(forUpdating: temporary)
                    do {
                        try handle.synchronize()
                        try handle.close()
                    } catch {
                        try? handle.close()
                        throw error
                    }
                    stagingFiles[item.sha256] = temporary
                } else {
                    let resource = AhaKeyConfigurationResource(
                        logicalIdentifier: item.logicalIdentifier,
                        sha256: item.sha256,
                        byteCount: item.byteCount,
                        mediaType: try AhaKeyMediaType("application/octet-stream")
                    )
                    try validateResourceFile(at: destination, against: resource)
                }
            }
        } catch {
            for (_, temporary) in stagingFiles { try? FileManager.default.removeItem(at: temporary) }
            throw error
        }

        // 测试 seam：阶段 1 完成、进入 flock 前的锁外对齐点（仅 @testable 注入）。
        testingHooks.ingestAfterPhase1Staging?()

        // 阶段 2（flock 临界区，file-before-WAL）：BEGIN IMMEDIATE → 冲突/配额 admission →
        // 安装 final + 父目录 fsync → 写 journal → COMMIT。init 的 reconcile/prune 与其他
        // Store 的 ingest/accept 都在同一把锁内，不存在「清理撞安装」窗口（14:40 #1/#2）。
        do {
            try Self.withExclusiveLock(lockFileDescriptor) {
                try Self.execute("BEGIN IMMEDIATE", on: database)
                var installedFinals: [URL] = []
                do {
                    // 先读既有用量（本批尚未插入，不会把新行双计进 newBytes）。
                    let existingBytes = try resourceStorageUsage()
                    var pendingInserts: [AhaKeyXPCResourceIngestionItem] = []
                    var newBytes: UInt64 = 0
                    for item in uniqueByDigest.values.sorted(by: { $0.sha256.rawValue < $1.sha256.rawValue }) {
                        // 冲突检测：同一 digest 已 journal（staged 或正式）且字节数不同 → 拒绝
                        if let stagedBytes = try stagedResourceByteCount(item.sha256) {
                            guard stagedBytes == item.byteCount else {
                                throw AhaKeyRuntimePersistenceError.resourceByteCountMismatch(item.logicalIdentifier)
                            }
                            continue // 已 journal，幂等
                        }
                        if let acceptedBytes = try journaledResourceByteCount(item.sha256) {
                            guard acceptedBytes == item.byteCount else {
                                throw AhaKeyRuntimePersistenceError.resourceByteCountMismatch(item.logicalIdentifier)
                            }
                            continue // 已转正，幂等
                        }
                        let (sum, sumOverflow) = newBytes.addingReportingOverflow(item.byteCount)
                        guard !sumOverflow else {
                            throw AhaKeyRuntimePersistenceError.resourceQuotaExceeded(
                                limit: quota.maxTotalResourceBytes,
                                attempted: UInt64.max
                            )
                        }
                        newBytes = sum
                        pendingInserts.append(item)
                    }

                    let (attemptedBytes, quotaOverflow) = existingBytes.addingReportingOverflow(newBytes)
                    guard !quotaOverflow, attemptedBytes <= quota.maxTotalResourceBytes else {
                        throw AhaKeyRuntimePersistenceError.resourceQuotaExceeded(
                            limit: quota.maxTotalResourceBytes,
                            attempted: quotaOverflow ? UInt64.max : attemptedBytes
                        )
                    }

                    // file-before-WAL：先安装 final 并同步父目录，再写 journal，最后 COMMIT。
                    // 崩溃于 COMMIT 前：journal 回滚、final 文件由下次启动 reconcile 按 orphan 清理。
                    for item in pendingInserts {
                        let destination = managedResourceURL(for: item.sha256)
                        if !FileManager.default.fileExists(atPath: destination.path) {
                            guard let temporary = stagingFiles[item.sha256] else {
                                throw AhaKeyRuntimePersistenceError.missingResourceFile(item.logicalIdentifier)
                            }
                            try FileManager.default.moveItem(at: temporary, to: destination)
                            installedFinals.append(destination)
                        }
                        try insertStagedResource(item)
                    }
                    try Self.synchronizeDirectory(resourcesDirectory)

                    // 测试 seam：锁内 COMMIT 前的可控交错点（仅 @testable 注入）。
                    testingHooks.ingestBeforeJournalCommit?()

                    try Self.execute("COMMIT", on: database)
                } catch {
                    try? Self.execute("ROLLBACK", on: database)
                    // 撤销未随 journal 提交的 final 安装；临时文件由外层 catch 清理。
                    for url in installedFinals { try? FileManager.default.removeItem(at: url) }
                    try? Self.synchronizeDirectory(resourcesDirectory)
                    throw error
                }
            }
        } catch {
            for (_, temporary) in stagingFiles { try? FileManager.default.removeItem(at: temporary) }
            throw error
        }
        // 成功路径同样清理：幂等 skip（已 journal/已转正）的 item 可能留下 phase-1 临时文件。
        for (_, temporary) in stagingFiles { try? FileManager.default.removeItem(at: temporary) }
    }

    public func resourceURL(for digest: AhaKeySHA256Digest) throws -> URL? {
        let statement = try prepare(
            "SELECT relative_path, byte_count FROM runtime_resources WHERE digest = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(digest.rawValue, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let relativePath = sqlite3_column_text(statement, 0),
              String(cString: relativePath) == digest.rawValue else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let byteCount = sqlite3_column_int64(statement, 1)
        guard byteCount >= 0 else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let url = managedResourceURL(for: digest)
        try validateManagedFile(at: url, digest: digest, byteCount: UInt64(byteCount))
        return url
    }

    public func resourceStorageUsage() throws -> UInt64 {
        // 配额核算 = 正式资源 + staged journal（未 apply 的预上传同样占配额，防绕过）。
        let statement = try prepare("""
            SELECT
                (SELECT COALESCE(SUM(byte_count), 0) FROM runtime_resources) +
                (SELECT COALESCE(SUM(byte_count), 0) FROM runtime_staged_resources)
            """)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        let value = sqlite3_column_int64(statement, 0)
        guard value >= 0 else { throw AhaKeyRuntimePersistenceError.corruptTransaction }
        return UInt64(value)
    }

    public func savePolicy(_ policy: AhaKeyRuntimePolicy) throws {
        try upsertMetadata(key: "runtime_policy", value: encoder.encode(policy))
    }

    public func loadPolicy() throws -> AhaKeyRuntimePolicy? {
        guard let data = try metadataValue(for: "runtime_policy") else { return nil }
        return try decoder.decode(AhaKeyRuntimePolicy.self, from: data)
    }

    /// 权威对象 canonical content 的 live CAS。只从 deviceChanged / schema=1 baseline 投影读写。
    public func authoritativeObjectFingerprint(
        for deviceID: AhaKeyRuntimeDeviceID
    ) throws -> AhaKeyRuntimeObjectFingerprint? {
        guard let content = try authoritativeObjectContent(for: deviceID) else {
            return nil
        }
        return try AhaKeyRuntimeObjectFingerprint.hashing(content)
    }

    /// 已提交的 canonical content。生产 deviceChanged 只投影该对象，不把 page baseline 当作权威对象。
    public func authoritativeObjectContent(
        for deviceID: AhaKeyRuntimeDeviceID
    ) throws -> Data? {
        try metadataValue(for: Self.authoritativeObjectKey(deviceID))
    }

    /// 已提交的 typed authority version。损坏 metadata fail-closed。
    public func authoritativeVersion(
        for deviceID: AhaKeyRuntimeDeviceID
    ) throws -> AhaKeyRuntimeAuthoritativeVersion? {
        try storedAuthoritativeVersion(for: deviceID)
    }

    /// 为当前 Agent 进程原子分配一次 store-global writer lease，高于全部既有 device version。
    public func allocateAuthoritativeWriterLease() throws -> AhaKeyRuntimeAuthoritativeWriterLease {
        try Self.withExclusiveLock(lockFileDescriptor) {
            try Self.execute("BEGIN IMMEDIATE", on: database)
            do {
                let highest = try highestStoredWriterLease()
                let next = highest + 1
                guard next > highest else {
                    throw AhaKeyRuntimePersistenceError.databaseFailure("authoritative writer lease exhausted")
                }
                let lease = try AhaKeyRuntimeAuthoritativeWriterLease(next)
                try upsertMetadata(
                    key: Self.authoritativeWriterLeaseKey,
                    value: try encoder.encode(lease)
                )
                try Self.execute("COMMIT", on: database)
                return lease
            } catch {
                try? Self.execute("ROLLBACK", on: database)
                throw error
            }
        }
    }

    /// `deviceChanged` 权威快照投影：只接受当前 store-global writer lease，同 lease 完整比较 connection/source。
    @discardableResult
    public func persistProjectedAuthoritativeObject(
        _ canonicalContent: Data,
        version: AhaKeyRuntimeAuthoritativeVersion
    ) throws -> AhaKeyRuntimeAuthoritativeVersion {
        try Self.withExclusiveLock(lockFileDescriptor) {
            try Self.execute("BEGIN IMMEDIATE", on: database)
            do {
                let committed = try persistProjectedAuthoritativeObjectUnlocked(
                    canonicalContent,
                    version: version
                )
                try Self.execute("COMMIT", on: database)
                return committed
            } catch {
                try? Self.execute("ROLLBACK", on: database)
                throw error
            }
        }
    }

    private func persistProjectedAuthoritativeObjectUnlocked(
        _ canonicalContent: Data,
        version: AhaKeyRuntimeAuthoritativeVersion
    ) throws -> AhaKeyRuntimeAuthoritativeVersion {
        guard let incomingLease = version.writerLease else {
            throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
        }
        let currentLease = try currentAuthoritativeWriterLeaseUnlocked()
        guard incomingLease == currentLease else {
            throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
        }
        let digest = try AhaKeyRuntimeObjectFingerprint.hashing(canonicalContent)
        guard digest == version.sourceDigest else {
            throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
        }
        let stored = try storedAuthoritativeVersion(for: version.deviceID)
        if let stored, Self.isStale(incoming: version, incomingLease: incomingLease, stored: stored) {
            throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
        }
        let committed = AhaKeyRuntimeAuthoritativeVersion(
            deviceID: version.deviceID,
            writerLease: incomingLease,
            sessionGeneration: version.sessionGeneration,
            transportGeneration: version.transportGeneration,
            sourceRevision: version.sourceRevision,
            sourceDigest: digest
        )
        try persistAuthoritativeObjectUnlocked(canonicalContent, for: version.deviceID)
        try persistAuthoritativeVersionUnlocked(committed)
        return committed
    }

    private func persistAuthoritativeObjectUnlocked(
        _ canonicalContent: Data,
        for deviceID: AhaKeyRuntimeDeviceID
    ) throws {
        try upsertMetadata(key: Self.authoritativeObjectKey(deviceID), value: canonicalContent)
    }

    private func persistAuthoritativeSourceUnlocked(
        _ canonicalContent: Data,
        for deviceID: AhaKeyRuntimeDeviceID
    ) throws {
        let digest = try AhaKeyRuntimeObjectFingerprint.hashing(canonicalContent)
        try persistAuthoritativeObjectUnlocked(canonicalContent, for: deviceID)
        if let existing = try storedAuthoritativeVersion(for: deviceID) {
            try persistAuthoritativeVersionUnlocked(
                AhaKeyRuntimeAuthoritativeVersion(
                    deviceID: existing.deviceID,
                    writerLease: existing.writerLease,
                    sessionGeneration: existing.sessionGeneration,
                    transportGeneration: existing.transportGeneration,
                    sourceRevision: try existing.sourceRevision.advanced(),
                    sourceDigest: digest
                )
            )
        } else {
            try persistAuthoritativeVersionUnlocked(
                AhaKeyRuntimeAuthoritativeVersion(
                    deviceID: deviceID,
                    writerLease: nil,
                    sessionGeneration: .init(0),
                    transportGeneration: .init(0),
                    sourceRevision: .first,
                    sourceDigest: digest
                )
            )
        }
    }

    private func persistAuthoritativeVersionUnlocked(
        _ version: AhaKeyRuntimeAuthoritativeVersion
    ) throws {
        try upsertMetadata(
            key: Self.authoritativeVersionKey(version.deviceID),
            value: try encoder.encode(version)
        )
    }

    private static func authoritativeObjectKey(_ deviceID: AhaKeyRuntimeDeviceID) -> String {
        "authoritative-object:\(deviceID.rawValue)"
    }

    private static func authoritativeVersionKey(_ deviceID: AhaKeyRuntimeDeviceID) -> String {
        "authoritative-version:\(deviceID.rawValue)"
    }

    private static let authoritativeWriterLeaseKey = "authoritative-writer-lease"

    private static func disconnectFenceKey(_ deviceID: AhaKeyRuntimeDeviceID) -> String {
        "disconnect-generation-fence:\(deviceID.rawValue)"
    }

    private func storedAuthoritativeVersion(
        for deviceID: AhaKeyRuntimeDeviceID
    ) throws -> AhaKeyRuntimeAuthoritativeVersion? {
        guard let data = try metadataValue(for: Self.authoritativeVersionKey(deviceID)) else {
            return nil
        }
        do {
            return try decoder.decode(AhaKeyRuntimeAuthoritativeVersion.self, from: data)
        } catch {
            throw AhaKeyRuntimePersistenceError.corruptAuthoritativeVersion
        }
    }

    private func currentAuthoritativeWriterLeaseUnlocked() throws -> AhaKeyRuntimeAuthoritativeWriterLease {
        guard let data = try metadataValue(for: Self.authoritativeWriterLeaseKey) else {
            throw AhaKeyRuntimePersistenceError.corruptAuthoritativeVersion
        }
        do {
            return try decoder.decode(AhaKeyRuntimeAuthoritativeWriterLease.self, from: data)
        } catch {
            throw AhaKeyRuntimePersistenceError.corruptAuthoritativeVersion
        }
    }

    private func highestStoredWriterLease() throws -> UInt64 {
        var highest: UInt64 = 0
        if let data = try metadataValue(for: Self.authoritativeWriterLeaseKey) {
            do {
                let global = try decoder.decode(AhaKeyRuntimeAuthoritativeWriterLease.self, from: data)
                highest = max(highest, global.rawValue)
            } catch {
                throw AhaKeyRuntimePersistenceError.corruptAuthoritativeVersion
            }
        }
        let statement = try prepare(
            "SELECT value FROM runtime_metadata WHERE key LIKE 'authoritative-version:%'"
        )
        defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else {
                throw AhaKeyRuntimePersistenceError.corruptAuthoritativeVersion
            }
            let data = Data(bytes: bytes, count: count)
            let version: AhaKeyRuntimeAuthoritativeVersion
            do {
                version = try decoder.decode(AhaKeyRuntimeAuthoritativeVersion.self, from: data)
            } catch {
                throw AhaKeyRuntimePersistenceError.corruptAuthoritativeVersion
            }
            if let lease = version.writerLease {
                highest = max(highest, lease.rawValue)
            }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw databaseError() }
        return highest
    }

    private static func isStale(
        incoming: AhaKeyRuntimeAuthoritativeVersion,
        incomingLease: AhaKeyRuntimeAuthoritativeWriterLease,
        stored: AhaKeyRuntimeAuthoritativeVersion
    ) -> Bool {
        if incoming.deviceID != stored.deviceID { return true }
        if let storedLease = stored.writerLease, incomingLease < storedLease {
            return true
        }
        if incoming.sourceRevision < stored.sourceRevision { return true }
        if incoming.sourceRevision == stored.sourceRevision,
           incoming.sourceDigest != stored.sourceDigest {
            return true
        }
        // 新进程 lease（或首次写入 schema=1 seed）可接管更低 generation，但仍须通过 source 检查。
        if stored.writerLease.map({ incomingLease > $0 }) ?? true {
            return false
        }
        if incoming.sessionGeneration < stored.sessionGeneration { return true }
        if incoming.sessionGeneration == stored.sessionGeneration,
           incoming.transportGeneration < stored.transportGeneration {
            return true
        }
        return false
    }

    public func reserveEventSequence() throws -> AhaKeyRuntimeEventSequence {
        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            let current: UInt64
            if let data = try metadataValue(for: "event_sequence"),
               let text = String(data: data, encoding: .utf8),
               let stored = UInt64(text) {
                current = stored
            } else {
                current = 0
            }
            guard current < UInt64.max else {
                throw AhaKeyRuntimePersistenceError.databaseFailure("event sequence exhausted")
            }
            let next = current + 1
            try upsertMetadata(key: "event_sequence", value: Data(String(next).utf8))
            try Self.execute("COMMIT", on: database)
            return .init(next)
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    public func confirmStep(
        _ step: AhaKeyRuntimeStepIdentifier,
        for operationID: AhaKeyRuntimeOperationID
    ) throws {
        guard try transaction(operationID) != nil else {
            throw AhaKeyRuntimePersistenceError.operationNotFound
        }
        try insertConfirmedStepUnlocked(step, for: operationID)
    }

    /// schema=2：step confirmation 与完整 field 的 writeConfirmed baseline 同一写事务。
    /// chunk 不密封；不得在此写入 verified。
    public func confirmPageStep(
        _ step: AhaKeyRuntimeStepIdentifier,
        package: AhaKeyConfigurationPackage,
        plan: AhaKeyRuntimePageExecutionPlan
    ) throws {
        guard try transaction(package.operationID) != nil else {
            throw AhaKeyRuntimePersistenceError.operationNotFound
        }
        var baseline: AhaKeyRuntimeFieldBaseline?
        if let planned = plan.step(for: step),
           AhaKeyRuntimePageSemantic.sealsCompleteField(planned),
           let field = planned.fieldID,
           let pageID = package.pageOperation?.pageScope {
            baseline = AhaKeyRuntimeFieldBaseline(
                deviceID: package.targetDeviceID,
                pageID: pageID,
                fieldID: field,
                value: try AhaKeyRuntimePageSemantic.baselineValue(for: field, package: package),
                trust: .writeConfirmed,
                provenance: .writeConfirmation,
                operationID: package.operationID
            )
        }
        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            try insertConfirmedStepUnlocked(step, for: package.operationID)
            if let baseline {
                try upsertPageFieldBaselineUnlocked(baseline)
            }
            try Self.execute("COMMIT", on: database)
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    public func pageFieldBaselines(
        deviceID: AhaKeyRuntimeDeviceID,
        pageID: AhaKeyStudioPageID? = nil
    ) throws -> [AhaKeyRuntimeFieldBaseline] {
        let statement = try prepare(
            """
            SELECT device_id, page_id, field_id, value, trust, provenance, operation_id, authority_version
            FROM runtime_page_field_baselines
            WHERE device_id = ?
            ORDER BY page_id, field_id
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(deviceID.rawValue, at: 1, to: statement)
        var rows: [AhaKeyRuntimeFieldBaseline] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            let baseline = try decodeFieldBaseline(statement)
            if pageID == nil || baseline.pageID == pageID {
                rows.append(baseline)
            }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw databaseError() }
        return rows
    }

    public func applyAuthoritativeFieldReadback(
        deviceID: AhaKeyRuntimeDeviceID,
        pageID: AhaKeyStudioPageID,
        fieldID: AhaKeyStudioFieldID,
        value: AhaKeyRuntimeBaselineValue,
        version: AhaKeyRuntimeAuthoritativeVersion
    ) throws {
        guard version.deviceID == deviceID else {
            throw AhaKeyRuntimePersistenceError.operationTargetMismatch
        }
        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            let globalLease = try currentAuthoritativeWriterLeaseUnlocked()
            guard version.writerLease == globalLease else {
                throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
            }
            guard let current = try storedAuthoritativeVersion(for: deviceID),
                  version == current else {
                throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
            }
            let existing = try pageFieldBaselines(deviceID: deviceID, pageID: pageID)
                .first { $0.fieldID == fieldID }
            let next = try nextAuthoritativeBaseline(
                existing: existing,
                currentStoreAuthority: current,
                deviceID: deviceID,
                pageID: pageID,
                fieldID: fieldID,
                value: value,
                version: version
            )
            if next != existing {
                try upsertPageFieldBaselineUnlocked(next)
            }
            try Self.execute("COMMIT", on: database)
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    private func nextAuthoritativeBaseline(
        existing: AhaKeyRuntimeFieldBaseline?,
        currentStoreAuthority: AhaKeyRuntimeAuthoritativeVersion?,
        deviceID: AhaKeyRuntimeDeviceID,
        pageID: AhaKeyStudioPageID,
        fieldID: AhaKeyStudioFieldID,
        value: AhaKeyRuntimeBaselineValue,
        version: AhaKeyRuntimeAuthoritativeVersion
    ) throws -> AhaKeyRuntimeFieldBaseline {
        let verified = AhaKeyRuntimeFieldBaseline(
            deviceID: deviceID,
            pageID: pageID,
            fieldID: fieldID,
            value: value,
            trust: .verified,
            provenance: .deviceReadback,
            operationID: existing?.operationID,
            authorityVersion: version
        )
        guard let existing else { return verified }
        if existing.trust == .unknown {
            return verified
        }
        guard let stored = existing.authorityVersion else {
            let promoted = existing.trust == .writeConfirmed && existing.value == value
            return AhaKeyRuntimeFieldBaseline(
                deviceID: deviceID,
                pageID: pageID,
                fieldID: fieldID,
                value: promoted ? existing.value : value,
                trust: .verified,
                provenance: .deviceReadback,
                operationID: existing.operationID,
                authorityVersion: version
            )
        }
        if version == stored {
            guard existing.value == value, existing.trust == .verified else {
                throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
            }
            return existing
        }
        guard currentStoreAuthority == version else {
            throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
        }
        return verified
    }

    /// 仅真实 device-disconnect 铸造 epoch。旧代不得覆盖新代；同 identity 保持原 startedAt。
    public func mintDisconnectEpoch(
        _ operationID: AhaKeyRuntimeOperationID,
        epoch: AhaKeyRuntimeDisconnectEpoch
    ) throws {
        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            try mintDisconnectEpochUnlocked(operationID, epoch: epoch)
            try Self.execute("COMMIT", on: database)
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    private func mintDisconnectEpochUnlocked(
        _ operationID: AhaKeyRuntimeOperationID,
        epoch: AhaKeyRuntimeDisconnectEpoch
    ) throws {
        guard let record = try transaction(operationID) else {
            throw AhaKeyRuntimePersistenceError.operationNotFound
        }
        guard record.package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion else {
            return
        }
        guard record.package.targetDeviceID == epoch.identity.deviceID else {
            throw AhaKeyRuntimePersistenceError.operationTargetMismatch
        }
        guard epoch.identity.writerLease != nil else {
            return
        }
        switch record.state {
        case .paused, .resumablePartial, .running:
            break
        default:
            return
        }
        if let existing = try disconnectEpoch(operationID) {
            if epoch.identity == existing.identity { return }
            if epoch.identity.isOlder(than: existing.identity) { return }
            guard existing.identity.isOlder(than: epoch.identity) else { return }
        }
        if let fence = try disconnectFence(for: epoch.identity.deviceID),
           epoch.identity.isOlder(than: fence) {
            return
        }
        let statement = try prepare(
            """
            INSERT INTO runtime_disconnect_epochs (operation_id, epoch)
            VALUES (?, ?)
            ON CONFLICT(operation_id) DO UPDATE SET epoch = excluded.epoch
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(operationID.rawValue.uuidString, at: 1, to: statement)
        try bind(try encoder.encode(epoch), at: 2, to: statement)
        try stepDone(statement)
    }

    public func clearDisconnectEpochs(succeeding identity: AhaKeyRuntimeConnectionIdentity) throws {
        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            try persistDisconnectFenceUnlocked(identity)
            for candidate in try recoveryCandidates() where candidate.package.targetDeviceID == identity.deviceID {
                guard let stored = try disconnectEpoch(candidate.operationID) else { continue }
                guard stored.identity.deviceID == identity.deviceID,
                      stored.identity.isOlder(than: identity) else {
                    continue
                }
                try deleteDisconnectEpochUnlocked(candidate.operationID)
            }
            try Self.execute("COMMIT", on: database)
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    private func persistDisconnectFenceUnlocked(_ identity: AhaKeyRuntimeConnectionIdentity) throws {
        guard identity.writerLease != nil else {
            throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
        }
        if let existing = try disconnectFence(for: identity.deviceID) {
            if identity == existing {
                return
            }
            if identity.isOlder(than: existing) || !existing.isOlder(than: identity) {
                throw AhaKeyRuntimePersistenceError.staleAuthoritativeGeneration
            }
        }
        try upsertMetadata(
            key: Self.disconnectFenceKey(identity.deviceID),
            value: try encoder.encode(identity)
        )
    }

    private func disconnectFence(
        for deviceID: AhaKeyRuntimeDeviceID
    ) throws -> AhaKeyRuntimeConnectionIdentity? {
        guard let data = try metadataValue(for: Self.disconnectFenceKey(deviceID)) else {
            return nil
        }
        do {
            return try decoder.decode(AhaKeyRuntimeConnectionIdentity.self, from: data)
        } catch {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
    }

    public func disconnectEpoch(
        _ operationID: AhaKeyRuntimeOperationID
    ) throws -> AhaKeyRuntimeDisconnectEpoch? {
        let statement = try prepare(
            "SELECT epoch FROM runtime_disconnect_epochs WHERE operation_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(operationID.rawValue.uuidString, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw databaseError() }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        do {
            return try decoder.decode(
                AhaKeyRuntimeDisconnectEpoch.self,
                from: Data(bytes: bytes, count: count)
            )
        } catch {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
    }

    /// 单事务重核资格、confirmed ledger、终态和 clock 消费，并闭合当前连接 generation。
    public func commitAbandon(
        operationID: AhaKeyRuntimeOperationID,
        now: Date,
        connection: AhaKeyRuntimeConnectionPresence
    ) throws -> AhaKeyRuntimeAbandonDisposition {
        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            let disposition = try commitAbandonUnlocked(
                operationID: operationID,
                now: now,
                connection: connection
            )
            try Self.execute("COMMIT", on: database)
            checkpointWal()
            return disposition
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    private func commitAbandonUnlocked(
        operationID: AhaKeyRuntimeOperationID,
        now: Date,
        connection: AhaKeyRuntimeConnectionPresence
    ) throws -> AhaKeyRuntimeAbandonDisposition {
        guard let record = try transaction(operationID) else { return .notFound }
        guard !record.state.isTerminal else { return .alreadyFinished }
        guard record.package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion else {
            return .refused
        }
        switch record.state {
        case .paused, .resumablePartial:
            break
        default:
            return .refused
        }
        if try durableDeviceQueue(record.package.targetDeviceID).isBlocked(operationID) {
            return .refused
        }
        if case .connected = connection {
            return .refused
        }
        guard case .disconnected(let observed) = connection else {
            return .refused
        }
        guard let epoch = try disconnectEpoch(operationID), epoch == observed else {
            return .refused
        }
        guard epoch.identity.deviceID == record.package.targetDeviceID else {
            return .refused
        }
        let elapsed = now.timeIntervalSince(epoch.startedAt)
        if elapsed < 0 {
            throw AhaKeyRuntimePersistenceError.clockRollback
        }
        if elapsed < AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration {
            return .refused
        }
        let confirmed = try confirmedSteps(for: operationID)
        let plan = try? AhaKeyRuntimePageSemantic.executionPlan(
            package: record.package,
            userSlotLimit: AhaKeyOLEDCompatibilityContext.standardUserSlotLimit
        )
        let hasWrites = AhaKeyRuntimePageSemantic.hasDeviceWrites(confirmed: confirmed, plan: plan)
        let summary = AhaKeyRuntimeOperationSummary(
            id: operationID,
            targetDeviceID: record.package.targetDeviceID,
            state: hasWrites ? .failedWithPartialCommit : .failedWithoutWrites,
            completedSteps: record.completedSteps,
            totalSteps: record.totalSteps,
            messageCode: .configurationDisconnected
        )
        try validateProgress(summary)
        try enforceDeviceFIFO(record, nextState: summary.state)
        try updateOperationRow(summary, terminalOrder: try allocateTerminalOrder())
        try deleteDisconnectEpochUnlocked(operationID)
        return .abandoned
    }

    private func deleteDisconnectEpochUnlocked(_ operationID: AhaKeyRuntimeOperationID) throws {
        let statement = try prepare(
            "DELETE FROM runtime_disconnect_epochs WHERE operation_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(operationID.rawValue.uuidString, at: 1, to: statement)
        try stepDone(statement)
    }

    private func insertConfirmedStepUnlocked(
        _ step: AhaKeyRuntimeStepIdentifier,
        for operationID: AhaKeyRuntimeOperationID
    ) throws {
        let statement = try prepare(
            """
            INSERT OR IGNORE INTO runtime_confirmed_steps (operation_id, step_id)
            VALUES (?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(operationID.rawValue.uuidString, at: 1, to: statement)
        try bind(step.rawValue, at: 2, to: statement)
        try stepDone(statement)
    }

    public func confirmedSteps(
        for operationID: AhaKeyRuntimeOperationID
    ) throws -> [AhaKeyRuntimeStepIdentifier] {
        guard try transaction(operationID) != nil else {
            throw AhaKeyRuntimePersistenceError.operationNotFound
        }
        let statement = try prepare(
            """
            SELECT step_id FROM runtime_confirmed_steps
            WHERE operation_id = ? ORDER BY rowid
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(operationID.rawValue.uuidString, at: 1, to: statement)
        var steps: [AhaKeyRuntimeStepIdentifier] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else {
                throw AhaKeyRuntimePersistenceError.corruptTransaction
            }
            steps.append(try .init(String(cString: text)))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw databaseError() }
        return steps
    }

    private func upsertSyncBaseline(_ baseline: AhaKeyRuntimeSyncBaseline) throws {
        let statement = try prepare(
            """
            INSERT INTO runtime_sync_baselines
                (device_id, revision, confirmed_configuration)
            VALUES (?, ?, ?)
            ON CONFLICT(device_id) DO UPDATE SET
                revision = excluded.revision,
                confirmed_configuration = excluded.confirmed_configuration
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(baseline.deviceID.rawValue, at: 1, to: statement)
        try bind(String(baseline.revision.rawValue), at: 2, to: statement)
        try bind(baseline.confirmedConfiguration, at: 3, to: statement)
        try stepDone(statement)
    }

    public func syncBaseline(
        for deviceID: AhaKeyRuntimeDeviceID
    ) throws -> AhaKeyRuntimeSyncBaseline? {
        let statement = try prepare(
            """
            SELECT revision, confirmed_configuration
            FROM runtime_sync_baselines WHERE device_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(deviceID.rawValue, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let revisionText = sqlite3_column_text(statement, 0),
              let revision = UInt64(String(cString: revisionText)) else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let count = Int(sqlite3_column_bytes(statement, 1))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 1) else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        return try .init(
            deviceID: deviceID,
            revision: .init(revision),
            confirmedConfiguration: Data(bytes: bytes, count: count)
        )
    }

    public func transaction(
        _ operationID: AhaKeyRuntimeOperationID
    ) throws -> AhaKeyRuntimePersistedTransaction? {
        let statement = try prepare(
            """
            SELECT package, state, completed_steps, total_steps, message_code, failure_context
            FROM runtime_transactions WHERE operation_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(operationID.rawValue.uuidString, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw databaseError() }
        return try decodeTransaction(operationID: operationID, statement: statement)
    }

    /// C4R2：只读 WAL 队列/终态序号。投影用，不改变 mint/CAS。
    public func operationOrdering(
        _ operationID: AhaKeyRuntimeOperationID
    ) throws -> (queueOrder: UInt64?, terminalOrder: UInt64?) {
        let statement = try prepare(
            """
            SELECT queue_order, terminal_order FROM runtime_transactions WHERE operation_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(operationID.rawValue.uuidString, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return (nil, nil) }
        guard result == SQLITE_ROW else { throw databaseError() }
        return (optionalUInt64(statement, 0), optionalUInt64(statement, 1))
    }

    private func optionalUInt64(_ statement: OpaquePointer, _ column: Int32) -> UInt64? {
        if sqlite3_column_type(statement, column) == SQLITE_NULL { return nil }
        let value = sqlite3_column_int64(statement, column)
        guard value >= 0 else { return nil }
        return UInt64(value)
    }

    public func updateOperation(_ summary: AhaKeyRuntimeOperationSummary) throws {
        guard let existing = try transaction(summary.id) else {
            throw AhaKeyRuntimePersistenceError.operationNotFound
        }
        guard existing.package.targetDeviceID == summary.targetDeviceID else {
            throw AhaKeyRuntimePersistenceError.operationTargetMismatch
        }
        guard !existing.state.isTerminal else {
            throw AhaKeyRuntimePersistenceError.terminalOperationCannotChange
        }
        guard !summary.state.isTerminal else {
            throw AhaKeyRuntimePersistenceError.invalidOperationOutcome
        }
        try validateProgress(summary)
        try enforceDeviceFIFO(existing, nextState: summary.state)
        try updateOperationRow(summary)
    }

    public func commitOperationOutcome(
        _ summary: AhaKeyRuntimeOperationSummary,
        syncBaseline: AhaKeyRuntimeSyncBaseline?
    ) throws {
        guard summary.state.isTerminal else {
            throw AhaKeyRuntimePersistenceError.invalidOperationOutcome
        }
        guard let existing = try transaction(summary.id) else {
            throw AhaKeyRuntimePersistenceError.operationNotFound
        }
        guard existing.package.targetDeviceID == summary.targetDeviceID else {
            throw AhaKeyRuntimePersistenceError.operationTargetMismatch
        }
        guard !existing.state.isTerminal else {
            throw AhaKeyRuntimePersistenceError.terminalOperationCannotChange
        }
        try validateProgress(summary)
        try validateCompletedClearsFailure(summary)
        try enforceDeviceFIFO(existing, nextState: summary.state)

        if summary.state == .completed {
            let expectedRevision = existing.package.baseRevision.rawValue.addingReportingOverflow(1)
            guard !expectedRevision.overflow,
                  let syncBaseline,
                  syncBaseline.deviceID == existing.package.targetDeviceID,
                  syncBaseline.revision.rawValue == expectedRevision.partialValue,
                  syncBaseline.confirmedConfiguration == existing.package.desiredConfiguration else {
                throw AhaKeyRuntimePersistenceError.invalidOutcomeBaseline
            }
        } else if syncBaseline != nil {
            throw AhaKeyRuntimePersistenceError.invalidOutcomeBaseline
        }

        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            try updateOperationRow(summary, terminalOrder: try allocateTerminalOrder())
            if let syncBaseline {
                try upsertSyncBaseline(syncBaseline)
                if existing.package.schemaVersion != AhaKeyConfigurationPackage.pageScopedSchemaVersion {
                    try persistAuthoritativeSourceUnlocked(
                        syncBaseline.confirmedConfiguration,
                        for: syncBaseline.deviceID
                    )
                }
            }
            try Self.execute("COMMIT", on: database)
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    private func validateProgress(_ summary: AhaKeyRuntimeOperationSummary) throws {
        guard summary.completedSteps <= summary.totalSteps else {
            throw AhaKeyRuntimePersistenceError.invalidOperationProgress
        }
        if summary.state == .completed,
           summary.completedSteps != summary.totalSteps {
            throw AhaKeyRuntimePersistenceError.invalidOperationProgress
        }
        if summary.state == .resumablePartial,
           (summary.totalSteps == 0 || summary.completedSteps >= summary.totalSteps) {
            throw AhaKeyRuntimePersistenceError.invalidOperationProgress
        }
    }

    /// 成功终态不得把失败字段写进 WAL；其它调用者不得绕过 runner 留下陈旧 context。
    private func validateCompletedClearsFailure(_ summary: AhaKeyRuntimeOperationSummary) throws {
        guard summary.state == .completed else { return }
        if summary.messageCode != nil || summary.failureContext != nil {
            throw AhaKeyRuntimePersistenceError.invalidOperationOutcome
        }
    }

    private func allocateTerminalOrder() throws -> UInt64 {
        let statement = try prepare(
            "SELECT COALESCE(MAX(terminal_order), 0) FROM runtime_transactions"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        let current = sqlite3_column_int64(statement, 0)
        guard current >= 0, current < Int64.max else {
            throw AhaKeyRuntimePersistenceError.databaseFailure("terminal order exhausted")
        }
        return UInt64(current) + 1
    }

    private func updateOperationRow(
        _ summary: AhaKeyRuntimeOperationSummary,
        terminalOrder: UInt64? = nil
    ) throws {
        let statement = try prepare(
            """
            UPDATE runtime_transactions
            SET state = ?, completed_steps = ?, total_steps = ?, message_code = ?, failure_context = ?,
                terminal_order = ?
            WHERE operation_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(summary.state.compatibleRawValue, at: 1, to: statement)
        try bind(UInt64(summary.completedSteps), at: 2, to: statement)
        try bind(UInt64(summary.totalSteps), at: 3, to: statement)
        if let messageCode = summary.messageCode {
            try bind(messageCode.rawValue, at: 4, to: statement)
        } else {
            try bindNull(at: 4, to: statement)
        }
        if let failureContext = summary.failureContext, !failureContext.isEmpty {
            try bind(try encoder.encode(failureContext), at: 5, to: statement)
        } else {
            try bindNull(at: 5, to: statement)
        }
        if let terminalOrder {
            try bind(terminalOrder, at: 6, to: statement)
        } else {
            try bindNull(at: 6, to: statement)
        }
        try bind(summary.id.rawValue.uuidString, at: 7, to: statement)
        try stepDone(statement)
    }

    public func recoveryCandidates() throws -> [AhaKeyRuntimePersistedTransaction] {
        let statement = try prepare(
            """
            SELECT operation_id, package, state, completed_steps, total_steps, message_code, failure_context
            FROM runtime_transactions ORDER BY COALESCE(queue_order, rowid), rowid
            """
        )
        defer { sqlite3_finalize(statement) }
        var candidates: [AhaKeyRuntimePersistedTransaction] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let operationText = sqlite3_column_text(statement, 0),
                  let operationUUID = UUID(uuidString: String(cString: operationText)) else {
                throw AhaKeyRuntimePersistenceError.corruptTransaction
            }
            let transaction = try decodeTransaction(
                operationID: .init(operationUUID),
                statement: statement,
                columnOffset: 1
            )
            if transaction.state.isRecoveryCandidate {
                try validateManagedResources(for: transaction.package)
                candidates.append(transaction)
            }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw databaseError() }
        return candidates
    }

    /// C3A：同设备非终态 FIFO。顺序由 durable `queue_order` 决定，崩溃重开不变。
    public func durableDeviceQueue(
        _ deviceID: AhaKeyRuntimeDeviceID
    ) throws -> AhaKeyRuntimeDeviceQueue {
        let items = try recoveryCandidates().filter { $0.package.targetDeviceID == deviceID }
        return AhaKeyRuntimeDeviceQueue(deviceID: deviceID, items: items)
    }

    /// 同设备 FIFO：非 head 不得开始执行或提交“已写入”终态。
    /// 排队项仍可 `cancellationRequested` / `failedWithoutWrites` 离队，不得越过队首 running/paused/resumable/completed/partial-commit。
    private func enforceDeviceFIFO(
        _ existing: AhaKeyRuntimePersistedTransaction,
        nextState: AhaKeyRuntimeOperationState
    ) throws {
        switch nextState {
        case .accepted, .cancellationRequested, .failedWithoutWrites:
            return
        case .running, .paused, .resumablePartial, .completed, .failedWithPartialCommit:
            break
        }
        let queue = try durableDeviceQueue(existing.package.targetDeviceID)
        if queue.isBlocked(existing.operationID), let head = queue.head {
            throw AhaKeyRuntimePersistenceError.blockedByQueueHead(head.operationID)
        }
    }

    /// 投影入口：枚举最近终态行。`recoveryCandidates()` 排除 terminal，Agent 重启后
    /// 内存缓存为空时必须靠本 API 把失败 context 并入 snapshot。窗口与投影淘汰上限对齐。
    public func recentTerminalTransactions(
        limit: Int = AhaKeyRuntimePersistentStore.snapshotProjectionTerminalLimit
    ) throws -> [AhaKeyRuntimePersistedTransaction] {
        let bounded = max(0, limit)
        let statement = try prepare(
            """
            SELECT operation_id, package, state, completed_steps, total_steps, message_code, failure_context
            FROM runtime_transactions
            WHERE terminal_order IS NOT NULL
            ORDER BY terminal_order DESC
            LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(UInt64(bounded), at: 1, to: statement)
        var terminals: [AhaKeyRuntimePersistedTransaction] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let operationText = sqlite3_column_text(statement, 0),
                  let operationUUID = UUID(uuidString: String(cString: operationText)) else {
                throw AhaKeyRuntimePersistenceError.corruptTransaction
            }
            terminals.append(
                try decodeTransaction(
                    operationID: .init(operationUUID),
                    statement: statement,
                    columnOffset: 1
                )
            )
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw databaseError() }
        return terminals.reversed()
    }

    private func decodeTransaction(
        operationID: AhaKeyRuntimeOperationID,
        statement: OpaquePointer,
        columnOffset: Int32 = 0
    ) throws -> AhaKeyRuntimePersistedTransaction {
        guard let packageBytes = sqlite3_column_blob(statement, columnOffset),
              let stateText = sqlite3_column_text(statement, columnOffset + 1),
              let state = AhaKeyRuntimeOperationState(
                  compatibleRawValue: String(cString: stateText)
              ) else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let packageLength = Int(sqlite3_column_bytes(statement, columnOffset))
        let package = try decoder.decode(
            AhaKeyConfigurationPackage.self,
            from: Data(bytes: packageBytes, count: packageLength)
        )
        guard package.operationID == operationID else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let completedSteps = sqlite3_column_int64(statement, columnOffset + 2)
        let totalSteps = sqlite3_column_int64(statement, columnOffset + 3)
        guard completedSteps >= 0, completedSteps <= UInt32.max,
              totalSteps >= 0, totalSteps <= UInt32.max else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let messageCode: AhaKeyRuntimeEventCode?
        if sqlite3_column_type(statement, columnOffset + 4) != SQLITE_NULL,
           let value = sqlite3_column_text(statement, columnOffset + 4) {
            messageCode = try AhaKeyRuntimeEventCode(String(cString: value))
        } else {
            messageCode = nil
        }
        let failureContext = try decodeFailureContext(statement, column: columnOffset + 5)
        return .init(
            operationID: operationID,
            package: package,
            state: state,
            completedSteps: UInt32(completedSteps),
            totalSteps: UInt32(totalSteps),
            messageCode: messageCode,
            failureContext: failureContext
        )
    }

    private func decodeFailureContext(
        _ statement: OpaquePointer,
        column: Int32
    ) throws -> AhaKeyRuntimeOperationFailureContext? {
        let type = sqlite3_column_type(statement, column)
        guard type != SQLITE_NULL else { return nil }
        let payload: Data
        if type == SQLITE_BLOB, let bytes = sqlite3_column_blob(statement, column) {
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count > 0 else { return nil }
            payload = Data(bytes: bytes, count: count)
        } else if let text = sqlite3_column_text(statement, column) {
            let string = String(cString: text)
            guard !string.isEmpty else { return nil }
            payload = Data(string.utf8)
        } else {
            return nil
        }
        do {
            let decoded = try decoder.decode(AhaKeyRuntimeOperationFailureContext.self, from: payload)
            return decoded.isEmpty ? nil : decoded
        } catch {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
    }

    private func insertTransaction(_ package: AhaKeyConfigurationPackage) throws {
        let queueOrder = try allocateQueueOrder()
        let statement = try prepare(
            """
            INSERT INTO runtime_transactions
                (operation_id, package, state, completed_steps, total_steps, message_code, queue_order)
            VALUES (?, ?, ?, 0, 0, NULL, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(package.operationID.rawValue.uuidString, at: 1, to: statement)
        try bind(encoder.encode(package), at: 2, to: statement)
        try bind(AhaKeyRuntimeOperationState.accepted.compatibleRawValue, at: 3, to: statement)
        try bind(queueOrder, at: 4, to: statement)
        try stepDone(statement)
    }

    private func allocateQueueOrder() throws -> UInt64 {
        let statement = try prepare(
            "SELECT COALESCE(MAX(queue_order), 0) FROM runtime_transactions"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        let current = sqlite3_column_int64(statement, 0)
        guard current >= 0, current < Int64.max else {
            throw AhaKeyRuntimePersistenceError.databaseFailure("queue order exhausted")
        }
        return UInt64(current) + 1
    }

    private func insertResource(_ resource: AhaKeyConfigurationResource) throws {
        let statement = try prepare(
            """
            INSERT OR IGNORE INTO runtime_resources
                (digest, byte_count, media_type, relative_path)
            VALUES (?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(resource.sha256.rawValue, at: 1, to: statement)
        try bind(resource.byteCount, at: 2, to: statement)
        try bind(resource.mediaType.rawValue, at: 3, to: statement)
        try bind(resource.sha256.rawValue, at: 4, to: statement)
        try stepDone(statement)
    }

    private func link(
        _ resource: AhaKeyConfigurationResource,
        to operationID: AhaKeyRuntimeOperationID
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO runtime_transaction_resources
                (operation_id, logical_identifier, digest)
            VALUES (?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(operationID.rawValue.uuidString, at: 1, to: statement)
        try bind(resource.logicalIdentifier.rawValue, at: 2, to: statement)
        try bind(resource.sha256.rawValue, at: 3, to: statement)
        try stepDone(statement)
    }

    private func managedResourceURL(for digest: AhaKeySHA256Digest) -> URL {
        resourcesDirectory.appendingPathComponent(digest.rawValue, isDirectory: false)
    }

    private func resourceExists(_ digest: AhaKeySHA256Digest) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM runtime_resources WHERE digest = ?")
        defer { sqlite3_finalize(statement) }
        try bind(digest.rawValue, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw databaseError()
    }

    /// staged journal 中该 digest 的申报字节数；无记录返回 nil。
    private func stagedResourceByteCount(_ digest: AhaKeySHA256Digest) throws -> UInt64? {
        let statement = try prepare(
            "SELECT byte_count FROM runtime_staged_resources WHERE digest = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(digest.rawValue, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw databaseError() }
        let byteCount = sqlite3_column_int64(statement, 0)
        guard byteCount >= 0 else { throw AhaKeyRuntimePersistenceError.corruptTransaction }
        return UInt64(byteCount)
    }

    /// 正式资源表中该 digest 的字节数；无记录返回 nil。
    private func journaledResourceByteCount(_ digest: AhaKeySHA256Digest) throws -> UInt64? {
        let statement = try prepare(
            "SELECT byte_count FROM runtime_resources WHERE digest = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(digest.rawValue, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw databaseError() }
        let byteCount = sqlite3_column_int64(statement, 0)
        guard byteCount >= 0 else { throw AhaKeyRuntimePersistenceError.corruptTransaction }
        return UInt64(byteCount)
    }

    /// 写入 staged journal：已是正式资源的 digest 无需 staged 记录；其余按 digest 幂等。
    private func insertStagedResource(_ item: AhaKeyXPCResourceIngestionItem) throws {

        let statement = try prepare(
            """
            INSERT INTO runtime_staged_resources
                (digest, byte_count, media_type, logical_identifier, relative_path)
            VALUES (?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(item.sha256.rawValue, at: 1, to: statement)
        try bind(item.byteCount, at: 2, to: statement)
        try bind("application/octet-stream", at: 3, to: statement)
        try bind(item.logicalIdentifier.rawValue, at: 4, to: statement)
        try bind(item.sha256.rawValue, at: 5, to: statement)
        try stepDone(statement)
    }

    /// accept 转正后删除 staged journal（同事务，保证原子切换）。
    private func deleteStagedResource(_ digest: AhaKeySHA256Digest) throws {
        let statement = try prepare(
            "DELETE FROM runtime_staged_resources WHERE digest = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(digest.rawValue, at: 1, to: statement)
        try stepDone(statement)
    }

    private func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func validateManagedResources(for package: AhaKeyConfigurationPackage) throws {
        for resource in package.resources {
            let url = managedResourceURL(for: resource.sha256)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AhaKeyRuntimePersistenceError.missingResourceFile(resource.logicalIdentifier)
            }
            try validateResourceFile(at: url, against: resource)
        }
    }

    private func validateManagedFile(
        at url: URL,
        digest expectedDigest: AhaKeySHA256Digest,
        byteCount expectedByteCount: UInt64
    ) throws {
        let standardizedRoot = resourcesDirectory.standardizedFileURL.path + "/"
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.path.hasPrefix(standardizedRoot),
              standardizedURL.deletingLastPathComponent() == resourcesDirectory.standardizedFileURL else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let values = try standardizedURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: standardizedURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.uint64Value == expectedByteCount,
              try digest(of: standardizedURL) == expectedDigest.rawValue else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
    }

    private func validateResourceFile(
        at url: URL,
        against resource: AhaKeyConfigurationResource
    ) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw AhaKeyRuntimePersistenceError.unsafeResourceFile(resource.logicalIdentifier)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.uint64Value == resource.byteCount else {
                throw AhaKeyRuntimePersistenceError.resourceByteCountMismatch(resource.logicalIdentifier)
            }
            guard try digest(of: url) == resource.sha256.rawValue else {
                throw AhaKeyRuntimePersistenceError.resourceDigestMismatch(resource.logicalIdentifier)
            }
    }

    private func metadataValue(for key: String) throws -> Data? {
        let statement = try prepare("SELECT value FROM runtime_metadata WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw databaseError() }
        let count = Int(sqlite3_column_bytes(statement, 0))
        if count == 0 { return Data() }
        guard let bytes = sqlite3_column_blob(statement, 0) else { throw databaseError() }
        return Data(bytes: bytes, count: count)
    }

    private func upsertMetadata(key: String, value: Data) throws {
        let statement = try prepare(
            """
            INSERT INTO runtime_metadata (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, to: statement)
        try bind(value, at: 2, to: statement)
        try stepDone(statement)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "sqlite execution failed"
            sqlite3_free(errorMessage)
            throw AhaKeyRuntimePersistenceError.databaseFailure(message)
        }
    }

    private static func userVersion(on database: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AhaKeyRuntimePersistenceError.databaseFailure(
                String(cString: sqlite3_errmsg(database))
            )
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw AhaKeyRuntimePersistenceError.databaseFailure(
                String(cString: sqlite3_errmsg(database))
            )
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func reconcileResourceDirectory(
        _ directory: URL,
        with database: OpaquePointer
    ) throws {
        var statement: OpaquePointer?
        // staged journal（runtime_staged_resources）与正式资源同样构成清理保护：
        // 已 journal 的预上传文件不是 orphan，重启清理不得删除。
        guard sqlite3_prepare_v2(
            database,
            "SELECT digest FROM runtime_resources UNION SELECT digest FROM runtime_staged_resources",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw AhaKeyRuntimePersistenceError.databaseFailure(
                String(cString: sqlite3_errmsg(database))
            )
        }
        defer { sqlite3_finalize(statement) }
        var referenced: Set<String> = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else {
                throw AhaKeyRuntimePersistenceError.corruptTransaction
            }
            referenced.insert(String(cString: text))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            throw AhaKeyRuntimePersistenceError.databaseFailure(
                String(cString: sqlite3_errmsg(database))
            )
        }

        var removedAny = false
        for url in try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ) where !referenced.contains(url.lastPathComponent) && !url.lastPathComponent.hasPrefix(".") {
            try FileManager.default.removeItem(at: url)
            removedAny = true
        }
        if removedAny { try synchronizeDirectory(directory) }
    }

    /// 启动清理（journal-first 契约的另一半，Codex 12:42 finding #1 的崩溃窗口）：
    /// 1. staged journal 已提交但 final 文件从未落盘（崩溃于 COMMIT 与 move 之间）→ 删除该
    ///    journal 行，释放配额，apply 会重新要求 ingest；
    /// 2. 超过 1 小时的 `.staging-` 临时文件视为崩溃残留删除（1 小时内可能正被并发 ingest
    ///    使用，保留；reconcile 对点前缀文件一律跳过）。
    private static func pruneStagedJournalMissingFiles(
        _ directory: URL,
        with database: OpaquePointer
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT digest FROM runtime_staged_resources",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw AhaKeyRuntimePersistenceError.databaseFailure(
                String(cString: sqlite3_errmsg(database))
            )
        }
        var stagedDigests: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
                sqlite3_finalize(statement)
                throw AhaKeyRuntimePersistenceError.corruptTransaction
            }
            stagedDigests.append(String(cString: text))
        }
        sqlite3_finalize(statement)

        var prunedAny = false
        for digest in stagedDigests {
            let fileURL = directory.appendingPathComponent(digest, isDirectory: false)
            guard !FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            var delete: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "DELETE FROM runtime_staged_resources WHERE digest = ?",
                -1,
                &delete,
                nil
            ) == SQLITE_OK, let delete else {
                throw AhaKeyRuntimePersistenceError.databaseFailure(
                    String(cString: sqlite3_errmsg(database))
                )
            }
            _ = sqlite3_bind_text(delete, 1, digest, -1, Self.sqliteTransient)
            guard sqlite3_step(delete) == SQLITE_DONE else {
                sqlite3_finalize(delete)
                throw AhaKeyRuntimePersistenceError.databaseFailure(
                    String(cString: sqlite3_errmsg(database))
                )
            }
            sqlite3_finalize(delete)
            prunedAny = true
        }

        // 崩溃残留的 .staging- 临时文件按龄期回收（>1 小时）。
        let cutoff = Date().addingTimeInterval(-3600)
        for url in try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) where url.lastPathComponent.hasPrefix(".staging-") {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? FileManager.default.removeItem(at: url)
                prunedAny = true
            }
        }
        if prunedAny { try? synchronizeDirectory(directory) }
    }

    private static func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw AhaKeyRuntimePersistenceError.databaseFailure(
                "cannot open resource directory for synchronization: \(errno)"
            )
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw AhaKeyRuntimePersistenceError.databaseFailure(
                "cannot synchronize resource directory: \(errno)"
            )
        }
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        guard let text = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw AhaKeyRuntimePersistenceError.databaseFailure("cannot encode json token")
        }
        return text
    }

    private func upsertPageFieldBaselineUnlocked(_ baseline: AhaKeyRuntimeFieldBaseline) throws {
        let statement = try prepare(
            """
            INSERT INTO runtime_page_field_baselines
                (device_id, page_id, field_id, value, trust, provenance, operation_id, authority_version)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(device_id, page_id, field_id) DO UPDATE SET
                value = excluded.value,
                trust = excluded.trust,
                provenance = excluded.provenance,
                operation_id = excluded.operation_id,
                authority_version = excluded.authority_version
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(baseline.deviceID.rawValue, at: 1, to: statement)
        try bind(try jsonString(baseline.pageID), at: 2, to: statement)
        try bind(try jsonString(baseline.fieldID), at: 3, to: statement)
        try bind(try encoder.encode(baseline.value), at: 4, to: statement)
        try bind(baseline.trust.rawValue, at: 5, to: statement)
        try bind(baseline.provenance.rawValue, at: 6, to: statement)
        if let operationID = baseline.operationID {
            try bind(operationID.rawValue.uuidString, at: 7, to: statement)
        } else {
            try bindNull(at: 7, to: statement)
        }
        if let version = baseline.authorityVersion {
            try bind(try encoder.encode(version), at: 8, to: statement)
        } else {
            try bindNull(at: 8, to: statement)
        }
        try stepDone(statement)
    }

    private func decodeFieldBaseline(_ statement: OpaquePointer) throws -> AhaKeyRuntimeFieldBaseline {
        guard let deviceText = sqlite3_column_text(statement, 0),
              let pageText = sqlite3_column_text(statement, 1),
              let fieldText = sqlite3_column_text(statement, 2),
              let trustText = sqlite3_column_text(statement, 4),
              let provenanceText = sqlite3_column_text(statement, 5),
              let trust = AhaKeyRuntimeBaselineTrust(rawValue: String(cString: trustText)),
              let provenance = AhaKeyRuntimeBaselineProvenance(rawValue: String(cString: provenanceText)) else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let valueCount = Int(sqlite3_column_bytes(statement, 3))
        guard valueCount > 0, let valueBytes = sqlite3_column_blob(statement, 3) else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let value: AhaKeyRuntimeBaselineValue
        do {
            value = try decoder.decode(
                AhaKeyRuntimeBaselineValue.self,
                from: Data(bytes: valueBytes, count: valueCount)
            )
        } catch {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let operationID: AhaKeyRuntimeOperationID?
        if sqlite3_column_type(statement, 6) == SQLITE_NULL {
            operationID = nil
        } else if let operationText = sqlite3_column_text(statement, 6),
                  let uuid = UUID(uuidString: String(cString: operationText)) {
            operationID = .init(uuid)
        } else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        let authorityVersion: AhaKeyRuntimeAuthoritativeVersion?
        if sqlite3_column_type(statement, 7) == SQLITE_NULL {
            authorityVersion = nil
        } else {
            let count = Int(sqlite3_column_bytes(statement, 7))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 7) else {
                throw AhaKeyRuntimePersistenceError.corruptTransaction
            }
            do {
                authorityVersion = try decoder.decode(
                    AhaKeyRuntimeAuthoritativeVersion.self,
                    from: Data(bytes: bytes, count: count)
                )
            } catch {
                throw AhaKeyRuntimePersistenceError.corruptTransaction
            }
        }
        return AhaKeyRuntimeFieldBaseline(
            deviceID: try AhaKeyRuntimeDeviceID(String(cString: deviceText)),
            pageID: try decoder.decode(AhaKeyStudioPageID.self, from: Data(String(cString: pageText).utf8)),
            fieldID: try decoder.decode(AhaKeyStudioFieldID.self, from: Data(String(cString: fieldText).utf8)),
            value: value,
            trust: trust,
            provenance: provenance,
            operationID: operationID,
            authorityVersion: authorityVersion
        )
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError()
        }
        return statement
    }

    private static func table(
        _ database: OpaquePointer,
        _ table: String,
        hasColumn column: String
    ) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AhaKeyRuntimePersistenceError.databaseFailure(
                String(cString: sqlite3_errmsg(database))
            )
        }
        defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1),
               String(cString: name) == column {
                return true
            }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            throw AhaKeyRuntimePersistenceError.databaseFailure(
                String(cString: sqlite3_errmsg(database))
            )
        }
        return false
    }

    private func bindNull(at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else { throw databaseError() }
    }

    private func bind(_ value: Double, at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else { throw databaseError() }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient) == SQLITE_OK else {
            throw databaseError()
        }
    }

    private func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) throws {
        let result = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.sqliteTransient)
        }
        guard result == SQLITE_OK else { throw databaseError() }
    }

    private func bind(_ value: UInt64, at index: Int32, to statement: OpaquePointer) throws {
        guard value <= UInt64(Int64.max),
              sqlite3_bind_int64(statement, index, Int64(value)) == SQLITE_OK else {
            throw databaseError()
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    private func checkpointWal() {
        _ = sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_FULL, nil, nil)
    }

    private func scalarText(_ sql: String) throws -> String {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            throw databaseError()
        }
        return String(cString: text)
    }

    private func scalarInt32(_ sql: String) throws -> Int32 {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return sqlite3_column_int(statement, 0)
    }

    private func databaseError() -> AhaKeyRuntimePersistenceError {
        .databaseFailure(String(cString: sqlite3_errmsg(database)))
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
