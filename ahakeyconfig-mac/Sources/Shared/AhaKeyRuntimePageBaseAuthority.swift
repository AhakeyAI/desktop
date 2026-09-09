import CryptoKit
import Foundation

/// C5B：一次页面提交使用哪种 durable base proof。有 whole-object 时冻结 schema=2；
/// 无 object 时只对 exact field mask 做 field-baseline CAS。禁止伪造 whole-object。
public enum AhaKeyRuntimePageBaseAuthority {
    public enum Proof: Equatable, Sendable {
        case objectFingerprint(AhaKeyRuntimeObjectFingerprint)
        case fieldBaselines(AhaKeyRuntimePageFieldBaselineProof)
    }

    public struct Decision: Equatable, Sendable {
        public let schemaVersion: UInt16
        public let proof: Proof

        public var objectFingerprint: AhaKeyRuntimeObjectFingerprint? {
            if case .objectFingerprint(let fingerprint) = proof { return fingerprint }
            return nil
        }

        public var fieldBaselines: AhaKeyRuntimePageFieldBaselineProof? {
            if case .fieldBaselines(let proof) = proof { return proof }
            return nil
        }
    }

    /// Studio / assemble 入口。supportedSchemas 为 nil 时不检查 peer 广告（Runtime 侧）。
    public static func resolve(
        authoritativeObject: Data?,
        overwriteSemantic: Bool,
        deviceID: AhaKeyRuntimeDeviceID,
        pageID: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        liveBaselines: [AhaKeyRuntimeFieldBaseline],
        supportedSchemas: Set<UInt16>? = nil
    ) throws -> Decision {
        if let object = authoritativeObject, !object.isEmpty {
            if let supportedSchemas, !supportedSchemas.contains(
                AhaKeyConfigurationPackage.pageScopedSchemaVersion
            ) {
                throw AhaKeyRuntimePageBaseAuthorityError.unsupportedPeerForPageOperation
            }
            return Decision(
                schemaVersion: AhaKeyConfigurationPackage.pageScopedSchemaVersion,
                proof: .objectFingerprint(try AhaKeyRuntimeObjectFingerprint.hashing(object))
            )
        }
        if let supportedSchemas, !supportedSchemas.contains(
            AhaKeyConfigurationPackage.fieldBaselineSchemaVersion
        ) {
            throw AhaKeyRuntimePageBaseAuthorityError.unsupportedPeerForFirstPageBaseline
        }
        if !overwriteSemantic {
            throw AhaKeyRuntimePageBaseAuthorityError.overwriteConfirmationRequired
        }
        let proof = try AhaKeyRuntimePageFieldBaselineProof.make(
            deviceID: deviceID,
            pageID: pageID,
            fieldMask: fieldMask,
            liveBaselines: liveBaselines
        )
        return Decision(
            schemaVersion: AhaKeyConfigurationPackage.fieldBaselineSchemaVersion,
            proof: .fieldBaselines(proof)
        )
    }

    /// Store 一次事务读出的 durable authority。object nil 表示缺行，空 Data 视为损坏。
    public struct Snapshot: Equatable, Sendable {
        public let confirmedSteps: [AhaKeyRuntimeStepIdentifier]
        public let authoritativeObject: Data?
        public let fieldBaselines: [AhaKeyRuntimeFieldBaseline]

        public init(
            confirmedSteps: [AhaKeyRuntimeStepIdentifier],
            authoritativeObject: Data?,
            fieldBaselines: [AhaKeyRuntimeFieldBaseline]
        ) {
            self.confirmedSteps = confirmedSteps
            self.authoritativeObject = authoritativeObject
            self.fieldBaselines = fieldBaselines
        }

        public var objectFingerprint: AhaKeyRuntimeObjectFingerprint? {
            guard let authoritativeObject, !authoritativeObject.isEmpty else { return nil }
            return try? AhaKeyRuntimeObjectFingerprint.hashing(authoritativeObject)
        }
    }

    public static func evaluateLiveCompatibility(
        package: AhaKeyConfigurationPackage,
        deviceID: AhaKeyRuntimeDeviceID,
        profile: AhaKeyOLEDCompatibilityProfile
    ) throws {
        guard let contract = package.pageOperation, package.usesPageRunner else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        guard deviceID == package.targetDeviceID, deviceID == contract.targetDeviceID else {
            throw AhaKeyRuntimePageExecutionPreflightError.deviceMismatch
        }
        let liveFamily = try AhaKeyRuntimeCompatibilityFingerprint.Family.make(profile)
        guard liveFamily == contract.compatibilityFingerprint.family else {
            throw AhaKeyRuntimePageExecutionPreflightError.compatibilityMismatch
        }
    }

    public static func requireLiveCompatibility(
        package: AhaKeyConfigurationPackage,
        preconditions: AhaKeyRuntimePageExecutionPreconditions?
    ) throws {
        guard let preconditions else {
            throw AhaKeyRuntimePageExecutionPreflightError.missingPreconditions
        }
        try evaluateLiveCompatibility(
            package: package,
            deviceID: preconditions.deviceID,
            profile: preconditions.profile
        )
    }

    /// 与 FIFO 队首转 running / schema=3 accept 共用的 durable CAS。读失败不得在此变成 absent。
    public static func evaluateDurableCAS(
        package: AhaKeyConfigurationPackage,
        snapshot: Snapshot,
        hasDeviceWrites: Bool
    ) throws {
        guard let contract = package.pageOperation, package.usesPageRunner else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        if let object = snapshot.authoritativeObject, object.isEmpty {
            throw AhaKeyRuntimePageExecutionPreflightError.missingPreconditions
        }
        if hasDeviceWrites {
            return
        }
        switch package.schemaVersion {
        case AhaKeyConfigurationPackage.pageScopedSchemaVersion:
            guard let frozen = contract.baseObjectFingerprint else {
                throw AhaKeyRuntimePageExecutionPreflightError.missingPreconditions
            }
            guard let liveObject = snapshot.authoritativeObject, !liveObject.isEmpty else {
                throw AhaKeyRuntimePageExecutionPreflightError.missingPreconditions
            }
            let live = try AhaKeyRuntimeObjectFingerprint.hashing(liveObject)
            guard live == frozen else {
                throw AhaKeyRuntimePageExecutionPreflightError.baseObjectConflict
            }
        case AhaKeyConfigurationPackage.fieldBaselineSchemaVersion:
            guard let frozen = contract.fieldBaselines else {
                throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
            }
            if snapshot.authoritativeObject != nil {
                throw AhaKeyRuntimePageExecutionPreflightError.baseObjectConflict
            }
            try frozen.matchLive(
                snapshot.fieldBaselines,
                deviceID: package.targetDeviceID,
                pageID: contract.pageScope,
                operationID: package.operationID
            )
        default:
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
    }

    public static func evaluatePreflight(
        package: AhaKeyConfigurationPackage,
        preconditions: AhaKeyRuntimePageExecutionPreconditions?,
        snapshot: Snapshot,
        hasDeviceWrites: Bool
    ) throws {
        guard let preconditions else {
            throw AhaKeyRuntimePageExecutionPreflightError.missingPreconditions
        }
        try evaluateLiveCompatibility(
            package: package,
            deviceID: preconditions.deviceID,
            profile: preconditions.profile
        )
        try evaluateDurableCAS(
            package: package,
            snapshot: snapshot,
            hasDeviceWrites: hasDeviceWrites
        )
    }
}

public enum AhaKeyRuntimePageBaseAuthorityError: Error, Equatable, Sendable {
    case overwriteConfirmationRequired
    case unsupportedPeerForPageOperation
    case unsupportedPeerForFirstPageBaseline
    case fieldBaselineConflict
    case invalidFieldBaselineProof
}

/// schema=3 field-baseline CAS 的冻结 proof：page + canonical mask + 有序 expectation + digest。
public struct AhaKeyRuntimePageFieldBaselineProof: Codable, Equatable, Sendable {
    public let pageID: AhaKeyStudioPageID
    public let fieldMask: [AhaKeyStudioFieldID]
    public let expectations: [AhaKeyRuntimePageFieldExpectation]
    public let digest: AhaKeySHA256Digest

    public var fieldMaskSet: Set<AhaKeyStudioFieldID> { Set(fieldMask) }

    public var requiresOverwriteConfirmation: Bool {
        expectations.contains { $0.requiresOverwriteConfirmation }
    }

    public init(
        pageID: AhaKeyStudioPageID,
        fieldMask: [AhaKeyStudioFieldID],
        expectations: [AhaKeyRuntimePageFieldExpectation],
        digest: AhaKeySHA256Digest
    ) throws {
        try Self.validate(
            pageID: pageID,
            fieldMask: fieldMask,
            expectations: expectations,
            digest: digest
        )
        self.pageID = pageID
        self.fieldMask = fieldMask
        self.expectations = expectations
        self.digest = digest
    }

    public static func make(
        deviceID: AhaKeyRuntimeDeviceID,
        pageID: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        liveBaselines: [AhaKeyRuntimeFieldBaseline]
    ) throws -> Self {
        guard !fieldMask.isEmpty else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        let canonical = fieldMask.sorted()
        let scoped = liveBaselines.filter { $0.deviceID == deviceID && $0.pageID == pageID }
        var byField: [AhaKeyStudioFieldID: AhaKeyRuntimeFieldBaseline] = [:]
        for row in scoped {
            guard byField[row.fieldID] == nil else {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
            byField[row.fieldID] = row
        }
        let expectations: [AhaKeyRuntimePageFieldExpectation] = try canonical.map { field in
            if let row = byField[field] {
                guard row.deviceID == deviceID, row.pageID == pageID, row.fieldID == field else {
                    throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
                }
                return try AhaKeyRuntimePageFieldExpectation.baseline(row)
            }
            return try AhaKeyRuntimePageFieldExpectation.absent(
                deviceID: deviceID,
                pageID: pageID,
                fieldID: field
            )
        }
        let digest = try digest(pageID: pageID, fieldMask: canonical, expectations: expectations)
        return try Self(
            pageID: pageID,
            fieldMask: canonical,
            expectations: expectations,
            digest: digest
        )
    }

    public func validate(
        pageID: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        deviceID: AhaKeyRuntimeDeviceID
    ) throws {
        guard self.pageID == pageID else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        guard Set(self.fieldMask) == fieldMask else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        try Self.validate(
            pageID: self.pageID,
            fieldMask: self.fieldMask,
            expectations: expectations,
            digest: digest
        )
        for expectation in expectations {
            guard expectation.deviceID == deviceID, expectation.pageID == pageID else {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
        }
    }

    public func matchLive(
        _ liveBaselines: [AhaKeyRuntimeFieldBaseline],
        deviceID: AhaKeyRuntimeDeviceID,
        pageID: AhaKeyStudioPageID,
        operationID: AhaKeyRuntimeOperationID
    ) throws {
        guard self.pageID == pageID else {
            throw AhaKeyRuntimePageExecutionPreflightError.fieldBaselineConflict
        }
        var liveByField: [AhaKeyStudioFieldID: AhaKeyRuntimeFieldBaseline] = [:]
        for row in liveBaselines where row.deviceID == deviceID && row.pageID == pageID {
            guard liveByField[row.fieldID] == nil else {
                throw AhaKeyRuntimePageExecutionPreflightError.fieldBaselineConflict
            }
            liveByField[row.fieldID] = row
        }
        for expectation in expectations {
            guard expectation.deviceID == deviceID, expectation.pageID == pageID else {
                throw AhaKeyRuntimePageExecutionPreflightError.fieldBaselineConflict
            }
            let live = liveByField[expectation.fieldID]
            if let live, live.operationID == operationID {
                continue
            }
            try expectation.match(live: live)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case pageID, fieldMask, expectations, digest
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .invalidFieldBaselineProof
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            pageID: try container.decode(AhaKeyStudioPageID.self, forKey: .pageID),
            fieldMask: try container.decode([AhaKeyStudioFieldID].self, forKey: .fieldMask),
            expectations: try container.decode([AhaKeyRuntimePageFieldExpectation].self, forKey: .expectations),
            digest: try container.decode(AhaKeySHA256Digest.self, forKey: .digest)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pageID, forKey: .pageID)
        try container.encode(fieldMask, forKey: .fieldMask)
        try container.encode(expectations, forKey: .expectations)
        try container.encode(digest, forKey: .digest)
    }

    private static func validate(
        pageID: AhaKeyStudioPageID,
        fieldMask: [AhaKeyStudioFieldID],
        expectations: [AhaKeyRuntimePageFieldExpectation],
        digest: AhaKeySHA256Digest
    ) throws {
        guard !fieldMask.isEmpty, fieldMask.count == Set(fieldMask).count else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        guard fieldMask == fieldMask.sorted() else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        guard fieldMask.allSatisfy({ AhaKeyStudioFieldOwnership.page(for: $0) == pageID }) else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        guard expectations.count == fieldMask.count else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        for (index, expectation) in expectations.enumerated() {
            guard expectation.pageID == pageID,
                  expectation.fieldID == fieldMask[index] else {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
        }
        let expected = try Self.digest(
            pageID: pageID,
            fieldMask: fieldMask,
            expectations: expectations
        )
        guard digest == expected, digest.rawValue != String(repeating: "0", count: 64) else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
    }

    private static func digest(
        pageID: AhaKeyStudioPageID,
        fieldMask: [AhaKeyStudioFieldID],
        expectations: [AhaKeyRuntimePageFieldExpectation]
    ) throws -> AhaKeySHA256Digest {
        struct Body: Encodable {
            var pageID: AhaKeyStudioPageID
            var fieldMask: [AhaKeyStudioFieldID]
            var expectations: [AhaKeyRuntimePageFieldExpectation]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(
            Body(pageID: pageID, fieldMask: fieldMask, expectations: expectations)
        )
        guard !data.isEmpty else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hex != String(repeating: "0", count: 64) else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        return try AhaKeySHA256Digest(hex)
    }
}

/// 完整 baseline 行或显式 absent。缺失行与 `.unknown` 必须区分。
public struct AhaKeyRuntimePageFieldExpectation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case absent
        case baseline
    }

    public let kind: Kind
    public let deviceID: AhaKeyRuntimeDeviceID
    public let pageID: AhaKeyStudioPageID
    public let fieldID: AhaKeyStudioFieldID
    public let value: AhaKeyRuntimeBaselineValue?
    public let trust: AhaKeyRuntimeBaselineTrust?
    public let provenance: AhaKeyRuntimeBaselineProvenance?
    public let operationID: AhaKeyRuntimeOperationID?
    public let authorityVersion: AhaKeyRuntimeAuthoritativeVersion?

    public var requiresOverwriteConfirmation: Bool {
        switch kind {
        case .absent:
            return true
        case .baseline:
            return trust == .unknown
        }
    }

    public static func absent(
        deviceID: AhaKeyRuntimeDeviceID,
        pageID: AhaKeyStudioPageID,
        fieldID: AhaKeyStudioFieldID
    ) throws -> Self {
        try Self(
            kind: .absent,
            deviceID: deviceID,
            pageID: pageID,
            fieldID: fieldID,
            value: nil,
            trust: nil,
            provenance: nil,
            operationID: nil,
            authorityVersion: nil
        )
    }

    public static func baseline(_ row: AhaKeyRuntimeFieldBaseline) throws -> Self {
        try Self(
            kind: .baseline,
            deviceID: row.deviceID,
            pageID: row.pageID,
            fieldID: row.fieldID,
            value: row.value,
            trust: row.trust,
            provenance: row.provenance,
            operationID: row.operationID,
            authorityVersion: row.authorityVersion
        )
    }

    public func match(live: AhaKeyRuntimeFieldBaseline?) throws {
        switch kind {
        case .absent:
            guard live == nil else {
                throw AhaKeyRuntimePageExecutionPreflightError.fieldBaselineConflict
            }
        case .baseline:
            guard let live,
                  live.deviceID == deviceID,
                  live.pageID == pageID,
                  live.fieldID == fieldID,
                  live.value == value,
                  live.trust == trust,
                  live.provenance == provenance,
                  live.operationID == operationID,
                  live.authorityVersion == authorityVersion else {
                throw AhaKeyRuntimePageExecutionPreflightError.fieldBaselineConflict
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, deviceID, pageID, fieldID, value, trust, provenance, operationID, authorityVersion
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .invalidFieldBaselineProof
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let deviceID = try container.decode(AhaKeyRuntimeDeviceID.self, forKey: .deviceID)
        let pageID = try container.decode(AhaKeyStudioPageID.self, forKey: .pageID)
        let fieldID = try container.decode(AhaKeyStudioFieldID.self, forKey: .fieldID)
        let identityKeys: Set<CodingKeys> = [.kind, .deviceID, .pageID, .fieldID]
        let baselineKeys: Set<CodingKeys> = [.value, .trust, .provenance, .operationID, .authorityVersion]
        switch kind {
        case .absent:
            for key in baselineKeys where container.contains(key) {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
            try self.init(
                kind: .absent,
                deviceID: deviceID,
                pageID: pageID,
                fieldID: fieldID,
                value: nil,
                trust: nil,
                provenance: nil,
                operationID: nil,
                authorityVersion: nil
            )
        case .baseline:
            for key in identityKeys.union(baselineKeys) where !container.contains(key) {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
            try self.init(
                kind: .baseline,
                deviceID: deviceID,
                pageID: pageID,
                fieldID: fieldID,
                value: try container.decode(AhaKeyRuntimeBaselineValue.self, forKey: .value),
                trust: try container.decode(AhaKeyRuntimeBaselineTrust.self, forKey: .trust),
                provenance: try container.decode(AhaKeyRuntimeBaselineProvenance.self, forKey: .provenance),
                operationID: try container.decode(AhaKeyRuntimeOperationID?.self, forKey: .operationID),
                authorityVersion: try container.decode(
                    AhaKeyRuntimeAuthoritativeVersion?.self,
                    forKey: .authorityVersion
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(pageID, forKey: .pageID)
        try container.encode(fieldID, forKey: .fieldID)
        switch kind {
        case .absent:
            break
        case .baseline:
            try container.encode(value, forKey: .value)
            try container.encode(trust, forKey: .trust)
            try container.encode(provenance, forKey: .provenance)
            try container.encode(operationID, forKey: .operationID)
            try container.encode(authorityVersion, forKey: .authorityVersion)
        }
    }

    fileprivate init(
        kind: Kind,
        deviceID: AhaKeyRuntimeDeviceID,
        pageID: AhaKeyStudioPageID,
        fieldID: AhaKeyStudioFieldID,
        value: AhaKeyRuntimeBaselineValue?,
        trust: AhaKeyRuntimeBaselineTrust?,
        provenance: AhaKeyRuntimeBaselineProvenance?,
        operationID: AhaKeyRuntimeOperationID?,
        authorityVersion: AhaKeyRuntimeAuthoritativeVersion?
    ) throws {
        switch kind {
        case .absent:
            guard value == nil, trust == nil, provenance == nil,
                  operationID == nil, authorityVersion == nil else {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
        case .baseline:
            guard value != nil, trust != nil, provenance != nil else {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
        }
        self.kind = kind
        self.deviceID = deviceID
        self.pageID = pageID
        self.fieldID = fieldID
        self.value = value
        self.trust = trust
        self.provenance = provenance
        self.operationID = operationID
        self.authorityVersion = authorityVersion
    }
}

/// 页面资源 ingest 的冻结闭包：完整 page package/contract，复用单一 validator。
public struct AhaKeyRuntimeScopedResourceIngestionProof: Codable, Equatable, Sendable {
    public let package: AhaKeyConfigurationPackage

    public var schemaVersion: UInt16 { package.schemaVersion }
    public var deviceID: AhaKeyRuntimeDeviceID { package.targetDeviceID }

    public init(package: AhaKeyConfigurationPackage) throws {
        try Self.validateContract(package)
        self.package = package
    }

    public static func make(package: AhaKeyConfigurationPackage) throws -> Self {
        try Self(package: package)
    }

    public func validate(
        items: [AhaKeyXPCResourceIngestionItem],
        targetDeviceID: AhaKeyRuntimeDeviceID
    ) throws {
        try Self.validateContract(package)
        guard package.targetDeviceID == targetDeviceID else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        try Self.validateItems(items, package: package)
    }

    public func requireFieldBaselines() throws -> AhaKeyRuntimePageFieldBaselineProof {
        guard let contract = package.pageOperation else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        return try contract.requireFieldBaselines()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case package
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .invalidFieldBaselineProof
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.package) else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        try self.init(package: try container.decode(AhaKeyConfigurationPackage.self, forKey: .package))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(package, forKey: .package)
    }

    private static func validateContract(_ package: AhaKeyConfigurationPackage) throws {
        guard package.usesPageRunner, let contract = package.pageOperation else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        try contract.validate(matchingDevice: package.targetDeviceID, resources: package.resources)
        switch package.schemaVersion {
        case AhaKeyConfigurationPackage.fieldBaselineSchemaVersion:
            try contract.validateFieldBaselineProof(matchingDevice: package.targetDeviceID)
        case AhaKeyConfigurationPackage.pageScopedSchemaVersion:
            guard contract.baseObjectFingerprint != nil, contract.fieldBaselines == nil else {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
        default:
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
    }

    private static func validateItems(
        _ items: [AhaKeyXPCResourceIngestionItem],
        package: AhaKeyConfigurationPackage
    ) throws {
        guard let contract = package.pageOperation else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        struct Identity: Hashable {
            var logicalID: AhaKeyResourceIdentifier
            var sha256: AhaKeySHA256Digest
            var byteCount: UInt64
            var mediaType: AhaKeyMediaType
            var encodedFrameCount: UInt16
        }
        let itemIDs = items.map(\.logicalIdentifier)
        guard itemIDs.count == Set(itemIDs).count else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        let resourcesByID = Dictionary(
            uniqueKeysWithValues: package.resources.map { ($0.logicalIdentifier, $0) }
        )
        let bindingsByID = Dictionary(
            uniqueKeysWithValues: contract.resourceBindings.map { ($0.logicalID, $0) }
        )
        guard items.count == package.resources.count,
              items.count == contract.resourceBindings.count,
              Set(itemIDs) == Set(package.resources.map(\.logicalIdentifier)),
              Set(itemIDs) == Set(contract.resourceBindings.map(\.logicalID)) else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
        var itemIdentities = Set<Identity>()
        for item in items {
            let digest = SHA256.hash(data: item.data).map { String(format: "%02x", $0) }.joined()
            guard digest == item.sha256.rawValue, item.byteCount == UInt64(item.data.count) else {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
            guard let resource = resourcesByID[item.logicalIdentifier],
                  let binding = bindingsByID[item.logicalIdentifier],
                  resource.sha256 == item.sha256,
                  resource.byteCount == item.byteCount,
                  resource.sha256 == binding.sha256,
                  resource.byteCount == binding.byteCount,
                  resource.mediaType == binding.mediaType,
                  binding.encodedFrameCount > 0 else {
                throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
            }
            itemIdentities.insert(
                Identity(
                    logicalID: item.logicalIdentifier,
                    sha256: item.sha256,
                    byteCount: item.byteCount,
                    mediaType: resource.mediaType,
                    encodedFrameCount: binding.encodedFrameCount
                )
            )
        }
        let boundIdentities = Set(contract.resourceBindings.map {
            Identity(
                logicalID: $0.logicalID,
                sha256: $0.sha256,
                byteCount: $0.byteCount,
                mediaType: $0.mediaType,
                encodedFrameCount: $0.encodedFrameCount
            )
        })
        guard itemIdentities == boundIdentities else {
            throw AhaKeyRuntimeContractError.invalidFieldBaselineProof
        }
    }
}
