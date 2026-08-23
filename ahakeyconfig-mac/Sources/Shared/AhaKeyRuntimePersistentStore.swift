import CryptoKit
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
}

public actor AhaKeyRuntimePersistentStore {
    public static let schemaVersion: Int32 = 1

    private let database: OpaquePointer
    private let resourcesDirectory: URL
    private let quota: AhaKeyRuntimeResourceQuota
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        rootDirectory: URL,
        quota: AhaKeyRuntimeResourceQuota = .default
    ) throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path)
        let resourcesDirectory = rootDirectory.appendingPathComponent("resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: resourcesDirectory.path)
        let databaseURL = rootDirectory.appendingPathComponent("runtime.sqlite3", isDirectory: false)
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
            throw AhaKeyRuntimePersistenceError.cannotOpenDatabase(message)
        }
        database = handle
        self.resourcesDirectory = resourcesDirectory
        self.quota = quota
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        do {
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
                    message_code TEXT
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
                UPDATE runtime_transactions
                SET state = 'paused'
                WHERE state = 'running'
                """,
                on: handle
            )
            if existingSchemaVersion < Self.schemaVersion {
                try Self.execute("PRAGMA user_version=\(Self.schemaVersion)", on: handle)
            }
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    deinit {
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
        if let existing = try transaction(package.operationID) {
            guard existing.package == package else {
                throw AhaKeyRuntimePersistenceError.operationIdentifierConflict
            }
            try validateManagedResources(for: existing.package)
            return package.operationID
        }

        let expectedIdentifiers = Set(package.resources.map(\.logicalIdentifier))
        guard Set(resourceFiles.keys) == expectedIdentifiers else {
            throw AhaKeyRuntimePersistenceError.unexpectedResourceFiles
        }
        for resource in package.resources {
            guard resource.byteCount <= quota.maxSingleResourceBytes else {
                throw AhaKeyRuntimePersistenceError.resourceTooLarge(
                    limit: quota.maxSingleResourceBytes,
                    attempted: resource.byteCount
                )
            }
            guard let sourceURL = resourceFiles[resource.logicalIdentifier],
                  FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw AhaKeyRuntimePersistenceError.missingResourceFile(resource.logicalIdentifier)
            }
            try validateResourceFile(at: sourceURL, against: resource)
        }

        var newDigests: Set<AhaKeySHA256Digest> = []
        var newBytes: UInt64 = 0
        for resource in package.resources where !newDigests.contains(resource.sha256) {
            if try !resourceExists(resource.sha256) {
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
                        try FileManager.default.copyItem(
                            at: resourceFiles[resource.logicalIdentifier]!,
                            to: temporary
                        )
                        try validateResourceFile(at: temporary, against: resource)
                        try FileManager.default.setAttributes(
                            [.posixPermissions: 0o600],
                            ofItemAtPath: temporary.path
                        )
                        let handle = try FileHandle(forUpdating: temporary)
                        try handle.synchronize()
                        try handle.close()
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

            try Self.execute("BEGIN IMMEDIATE", on: database)
            do {
                try insertTransaction(package)
                for resource in package.resources {
                    try insertResource(resource)
                    try link(resource, to: package.operationID)
                }
                try Self.execute("COMMIT", on: database)
            } catch {
                try? Self.execute("ROLLBACK", on: database)
                throw error
            }
        } catch {
            for url in newlyCreatedFiles { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return package.operationID
    }

    public func resourceURL(for digest: AhaKeySHA256Digest) throws -> URL? {
        let statement = try prepare(
            "SELECT relative_path FROM runtime_resources WHERE digest = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(digest.rawValue, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let relativePath = sqlite3_column_text(statement, 0) else {
            throw databaseError()
        }
        let url = resourcesDirectory.appendingPathComponent(String(cString: relativePath))
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AhaKeyRuntimePersistenceError.corruptTransaction
        }
        return url
    }

    public func resourceStorageUsage() throws -> UInt64 {
        let statement = try prepare("SELECT COALESCE(SUM(byte_count), 0) FROM runtime_resources")
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
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else {
                throw AhaKeyRuntimePersistenceError.corruptTransaction
            }
            steps.append(try .init(String(cString: text)))
        }
        return steps
    }

    public func saveSyncBaseline(_ baseline: AhaKeyRuntimeSyncBaseline) throws {
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
            SELECT package, state, completed_steps, total_steps, message_code
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
        guard summary.completedSteps <= summary.totalSteps else {
            throw AhaKeyRuntimePersistenceError.invalidOperationProgress
        }
        if summary.state == .completed,
           summary.completedSteps != summary.totalSteps {
            throw AhaKeyRuntimePersistenceError.invalidOperationProgress
        }
        if summary.state == .partiallyCompleted,
           (summary.totalSteps == 0 || summary.completedSteps >= summary.totalSteps) {
            throw AhaKeyRuntimePersistenceError.invalidOperationProgress
        }

        let statement = try prepare(
            """
            UPDATE runtime_transactions
            SET state = ?, completed_steps = ?, total_steps = ?, message_code = ?
            WHERE operation_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(summary.state.rawValue, at: 1, to: statement)
        try bind(UInt64(summary.completedSteps), at: 2, to: statement)
        try bind(UInt64(summary.totalSteps), at: 3, to: statement)
        if let messageCode = summary.messageCode {
            try bind(messageCode.rawValue, at: 4, to: statement)
        } else {
            guard sqlite3_bind_null(statement, 4) == SQLITE_OK else { throw databaseError() }
        }
        try bind(summary.id.rawValue.uuidString, at: 5, to: statement)
        try stepDone(statement)
    }

    public func recoveryCandidates() throws -> [AhaKeyRuntimePersistedTransaction] {
        let statement = try prepare(
            """
            SELECT operation_id, package, state, completed_steps, total_steps, message_code
            FROM runtime_transactions ORDER BY rowid
            """
        )
        defer { sqlite3_finalize(statement) }
        var candidates: [AhaKeyRuntimePersistedTransaction] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let operationText = sqlite3_column_text(statement, 0),
                  let operationUUID = UUID(uuidString: String(cString: operationText)) else {
                throw AhaKeyRuntimePersistenceError.corruptTransaction
            }
            let transaction = try decodeTransaction(
                operationID: .init(operationUUID),
                statement: statement,
                columnOffset: 1
            )
            switch transaction.state {
            case .completed, .failedWithoutWrites, .failedWithPartialCommit:
                break
            case .accepted, .running, .paused, .cancellationRequested, .partiallyCompleted:
                try validateManagedResources(for: transaction.package)
                candidates.append(transaction)
            }
        }
        return candidates
    }

    private func decodeTransaction(
        operationID: AhaKeyRuntimeOperationID,
        statement: OpaquePointer,
        columnOffset: Int32 = 0
    ) throws -> AhaKeyRuntimePersistedTransaction {
        guard let packageBytes = sqlite3_column_blob(statement, columnOffset),
              let stateText = sqlite3_column_text(statement, columnOffset + 1),
              let state = AhaKeyRuntimeOperationState(
                  rawValue: String(cString: stateText)
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
        if let value = sqlite3_column_text(statement, columnOffset + 4) {
            messageCode = try AhaKeyRuntimeEventCode(String(cString: value))
        } else {
            messageCode = nil
        }
        return .init(
            operationID: operationID,
            package: package,
            state: state,
            completedSteps: UInt32(completedSteps),
            totalSteps: UInt32(totalSteps),
            messageCode: messageCode
        )
    }

    private func insertTransaction(_ package: AhaKeyConfigurationPackage) throws {
        let statement = try prepare(
            """
            INSERT INTO runtime_transactions
                (operation_id, package, state, completed_steps, total_steps, message_code)
            VALUES (?, ?, ?, 0, 0, NULL)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(package.operationID.rawValue.uuidString, at: 1, to: statement)
        try bind(encoder.encode(package), at: 2, to: statement)
        try bind(AhaKeyRuntimeOperationState.accepted.rawValue, at: 3, to: statement)
        try stepDone(statement)
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

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError()
        }
        return statement
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
