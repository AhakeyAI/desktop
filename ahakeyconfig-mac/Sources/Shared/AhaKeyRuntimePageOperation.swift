import CryptoKit
import Foundation

/// C3A/C3AR1：页面 operation 的稳定 contract。只编码 page scope、field mask、设备、
/// 对象/兼容 fingerprint 与最小确认 ledger；禁止电量、通道、RSSI、进度或本地路径。
public struct AhaKeyRuntimePageOperationContract: Codable, Equatable, Sendable {
    public let pageScope: AhaKeyStudioPageID
    public let fieldMask: Set<AhaKeyStudioFieldID>
    public let targetDeviceID: AhaKeyRuntimeDeviceID
    public let baseObjectFingerprint: AhaKeyRuntimeObjectFingerprint
    public let compatibilityFingerprint: AhaKeyRuntimeCompatibilityFingerprint
    public let confirmationLedger: AhaKeyRuntimeConfirmationLedger

    public init(
        pageScope: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        baseObjectFingerprint: AhaKeyRuntimeObjectFingerprint,
        compatibilityFingerprint: AhaKeyRuntimeCompatibilityFingerprint,
        confirmationLedger: AhaKeyRuntimeConfirmationLedger,
        resources: [AhaKeyConfigurationResource] = []
    ) throws {
        try Self.validate(
            pageScope: pageScope,
            fieldMask: fieldMask,
            targetDeviceID: targetDeviceID,
            confirmationLedger: confirmationLedger,
            resources: resources
        )
        self.pageScope = pageScope
        self.fieldMask = fieldMask
        self.targetDeviceID = targetDeviceID
        self.baseObjectFingerprint = baseObjectFingerprint
        self.compatibilityFingerprint = compatibilityFingerprint
        self.confirmationLedger = confirmationLedger
    }

    public func validate(
        matchingDevice deviceID: AhaKeyRuntimeDeviceID,
        resources: [AhaKeyConfigurationResource]
    ) throws {
        guard targetDeviceID == deviceID else {
            throw AhaKeyRuntimeContractError.pageOperationDeviceMismatch
        }
        try Self.validate(
            pageScope: pageScope,
            fieldMask: fieldMask,
            targetDeviceID: targetDeviceID,
            confirmationLedger: confirmationLedger,
            resources: resources
        )
    }

    private static func validate(
        pageScope: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        confirmationLedger: AhaKeyRuntimeConfirmationLedger,
        resources: [AhaKeyConfigurationResource]
    ) throws {
        guard !fieldMask.isEmpty else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        guard fieldMask.allSatisfy({ AhaKeyStudioFieldOwnership.page(for: $0) == pageScope }) else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        _ = targetDeviceID
        try confirmationLedger.validate(fieldMask: fieldMask, resources: resources)
    }

    /// 由 C2 scoped plan 组装。资源摘要必须已验证；base fingerprint 由调用方提供。
    public static func assemble(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        baseObjectFingerprint: AhaKeyRuntimeObjectFingerprint,
        verifiedResources: [AhaKeyConfigurationResource]
    ) throws -> AhaKeyRuntimePageOperationContract {
        guard plan.fieldMask == Set(plan.values.keys), !plan.fieldMask.isEmpty else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        let planIDs = plan.resources.map(\.logicalIdentifier)
        let verifiedIDs = verifiedResources.map(\.logicalIdentifier)
        guard planIDs == verifiedIDs else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        guard Set(verifiedIDs).count == verifiedIDs.count else {
            throw AhaKeyRuntimeContractError.duplicateResourceIdentifier
        }
        let ledger = try AhaKeyRuntimeConfirmationLedger.pending(
            fieldMask: plan.fieldMask,
            resources: verifiedResources
        )
        return try AhaKeyRuntimePageOperationContract(
            pageScope: plan.pageID,
            fieldMask: plan.fieldMask,
            targetDeviceID: targetDeviceID,
            baseObjectFingerprint: baseObjectFingerprint,
            compatibilityFingerprint: .make(plan: plan, profile: profile),
            confirmationLedger: ledger,
            resources: verifiedResources
        )
    }
}

/// 页面写的 canonical desired payload：含冻结值、资源摘要与 ledger，不含本地路径。
public enum AhaKeyRuntimeCanonicalPageWrite {
    public static func encode(
        plan: AhaKeyStudioScopedWritePlan,
        contract: AhaKeyRuntimePageOperationContract,
        resources: [AhaKeyConfigurationResource]
    ) throws -> Data {
        let byID = Dictionary(uniqueKeysWithValues: resources.map { ($0.logicalIdentifier, $0) })
        let payload = Payload(
            contract: contract,
            overwriteSemantic: plan.overwriteSemantic,
            writeTaskSetA: plan.writeTaskSetA,
            writeTaskSetB: plan.writeTaskSetB,
            activateTaskSet: plan.activateTaskSet,
            emitsSetActiveSetOpcode: plan.emitsSetActiveSetOpcode,
            bindsDefaultAnimation: plan.bindsDefaultAnimation,
            statusLine: plan.statusLine,
            framesPerSecond: plan.framesPerSecond,
            resources: resources
                .sorted { $0.logicalIdentifier.rawValue < $1.logicalIdentifier.rawValue }
                .map(ResourceDigest.init),
            values: try plan.fieldMask.sorted().map { field in
                FieldValue(
                    id: WireFieldID(field),
                    value: try CanonicalValue(plan.values[field], resourcesByID: byID, plan: plan)
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private struct Payload: Codable {
        var contract: AhaKeyRuntimePageOperationContract
        var overwriteSemantic: Bool
        var writeTaskSetA: Bool
        var writeTaskSetB: Bool
        var activateTaskSet: Int?
        var emitsSetActiveSetOpcode: Bool
        var bindsDefaultAnimation: Bool
        var statusLine: String?
        var framesPerSecond: Int?
        var resources: [ResourceDigest]
        var values: [FieldValue]
    }

    private struct ResourceDigest: Codable, Equatable {
        var logicalIdentifier: String
        var sha256: String
        var byteCount: UInt64
        var mediaType: String

        init(_ resource: AhaKeyConfigurationResource) {
            logicalIdentifier = resource.logicalIdentifier.rawValue
            sha256 = resource.sha256.rawValue
            byteCount = resource.byteCount
            mediaType = resource.mediaType.rawValue
        }
    }

    private struct FieldValue: Codable {
        var id: WireFieldID
        var value: CanonicalValue
    }

    private enum CanonicalValue: Codable, Equatable {
        case text(String)
        case optionalText(String?)
        case integer(Int)
        case keyAction(AhaKeyDesiredConfiguration.KeyAction)
        case taskAsset(
            sha256: String,
            byteCount: UInt64,
            mediaType: String,
            framesPerSecond: Int,
            declaredFrameCount: Int?,
            pixelWidth: Int?,
            pixelHeight: Int?
        )

        init(
            _ value: AhaKeyStudioFieldValue?,
            resourcesByID: [AhaKeyResourceIdentifier: AhaKeyConfigurationResource],
            plan: AhaKeyStudioScopedWritePlan
        ) throws {
            switch value {
            case .text(let text):
                self = .text(text)
            case .optionalText(let text):
                self = .optionalText(text)
            case .integer(let number):
                self = .integer(number)
            case .keyAction(let action):
                self = .keyAction(action)
            case .taskAsset(let asset):
                let match = try Self.matchingResource(for: asset, plan: plan, resourcesByID: resourcesByID)
                self = .taskAsset(
                    sha256: match.sha256.rawValue,
                    byteCount: match.byteCount,
                    mediaType: match.mediaType.rawValue,
                    framesPerSecond: asset.framesPerSecond,
                    declaredFrameCount: asset.declaredFrameCount,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight
                )
            case nil:
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
        }

        private static func matchingResource(
            for asset: AhaKeyStudioTaskAssetDescriptor,
            plan: AhaKeyStudioScopedWritePlan,
            resourcesByID: [AhaKeyResourceIdentifier: AhaKeyConfigurationResource]
        ) throws -> AhaKeyConfigurationResource {
            let matches = plan.resources.compactMap { input -> AhaKeyConfigurationResource? in
                guard let resource = resourcesByID[input.logicalIdentifier] else { return nil }
                if let width = asset.pixelWidth, width != input.pixelWidth { return nil }
                if let height = asset.pixelHeight, height != input.pixelHeight { return nil }
                if let frames = asset.declaredFrameCount, frames != input.declaredFrameCount { return nil }
                return resource
            }
            guard matches.count == 1 else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            return matches[0]
        }
    }
}

extension AhaKeyConfigurationPackage {
    public static func assemblePageScoped(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        baseRevision: AhaKeyConfigurationRevision,
        baseObjectFingerprint: AhaKeyRuntimeObjectFingerprint,
        verifiedResources: [AhaKeyConfigurationResource],
        operationID: AhaKeyRuntimeOperationID = .init()
    ) throws -> AhaKeyConfigurationPackage {
        let contract = try AhaKeyRuntimePageOperationContract.assemble(
            plan: plan,
            profile: profile,
            targetDeviceID: targetDeviceID,
            baseObjectFingerprint: baseObjectFingerprint,
            verifiedResources: verifiedResources
        )
        return try AhaKeyConfigurationPackage(
            schemaVersion: AhaKeyConfigurationPackage.pageScopedSchemaVersion,
            operationID: operationID,
            targetDeviceID: targetDeviceID,
            baseRevision: baseRevision,
            desiredConfiguration: AhaKeyRuntimeCanonicalPageWrite.encode(
                plan: plan,
                contract: contract,
                resources: verifiedResources
            ),
            resources: verifiedResources,
            pageOperation: contract
        )
    }
}

/// 开始前对象的 canonical content / CAS digest。必须由调用方提供，不得用 page/mask/profile 冒充。
public struct AhaKeyRuntimeObjectFingerprint: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count == 64, normalized.allSatisfy({ $0.isHexDigit }) else {
            throw AhaKeyRuntimeContractError.invalidObjectFingerprint
        }
        self.rawValue = normalized
    }

    public init(digest: AhaKeySHA256Digest) throws {
        try self.init(digest.rawValue)
    }

    public static func hashing(_ data: Data) throws -> AhaKeyRuntimeObjectFingerprint {
        guard !data.isEmpty else {
            throw AhaKeyRuntimeContractError.invalidObjectFingerprint
        }
        let digest = SHA256.hash(data: data)
        return try AhaKeyRuntimeObjectFingerprint(digest.map { String(format: "%02x", $0) }.joined())
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 兼容语义 fingerprint：由本次 plan 的实际 opcode、槽映射、160×80 几何、session 与激活语义构成。
public struct AhaKeyRuntimeCompatibilityFingerprint: Codable, Equatable, Hashable, Sendable {
    public static let forbiddenKeys: Set<String> = [
        "battery", "batteryLevel", "rssi", "channel", "transport",
        "progress", "capacity", "path", "fileURL", "localPath",
    ]

    public let family: Family
    public let emittedOpcodes: [UInt8]
    public let physicalSlots: [UInt8]
    public let geometry: Geometry
    public let activation: Activation

    public enum Family: Equatable, Hashable, Sendable {
        case legacyStandard
        case rhinoDualSet(sessionUpload: Bool)
        case currentSession
    }

    public enum Geometry: String, Codable, Equatable, Hashable, Sendable {
        case none
        case oled160x80 = "oled-160x80"
    }

    public enum Activation: String, Codable, Equatable, Hashable, Sendable {
        case none
        case implicit
        case setActiveSetOpcode = "opcode-0x97"
    }

    public init(
        family: Family,
        emittedOpcodes: [UInt8],
        physicalSlots: [UInt8],
        geometry: Geometry,
        activation: Activation
    ) throws {
        let opcodes = Array(Set(emittedOpcodes)).sorted()
        let slots = Array(Set(physicalSlots)).sorted()
        try Self.validate(
            family: family,
            emittedOpcodes: opcodes,
            physicalSlots: slots,
            geometry: geometry,
            activation: activation
        )
        self.family = family
        self.emittedOpcodes = opcodes
        self.physicalSlots = slots
        self.geometry = geometry
        self.activation = activation
    }

    public static func make(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile
    ) throws -> AhaKeyRuntimeCompatibilityFingerprint {
        let family = try Family.make(profile)
        let writingPictures = writesPictures(plan)
        let opcodes = emittedOpcodes(plan: plan, profile: profile, writingPictures: writingPictures)
        let slots = physicalSlots(plan: plan, profile: profile, writingPictures: writingPictures)
        let geometry: Geometry = writingPictures ? .oled160x80 : .none
        if writingPictures {
            for resource in plan.resources {
                guard resource.pixelWidth == 160, resource.pixelHeight == 80 else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
            }
        }
        let activation = activationSemantic(
            profile: profile,
            writingPictures: writingPictures,
            emitsSetActiveSet: plan.emitsSetActiveSetOpcode
        )
        return try AhaKeyRuntimeCompatibilityFingerprint(
            family: family,
            emittedOpcodes: opcodes,
            physicalSlots: slots,
            geometry: geometry,
            activation: activation
        )
    }

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    private static func writesPictures(_ plan: AhaKeyStudioScopedWritePlan) -> Bool {
        if plan.writeTaskSetA || plan.writeTaskSetB || !plan.resources.isEmpty {
            return true
        }
        return plan.values.values.contains { value in
            if case .taskAsset = value { return true }
            return false
        }
    }

    private static func emittedOpcodes(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile,
        writingPictures: Bool
    ) -> [UInt8] {
        let policy = profile.pictureOpcodes
        var codes: [UInt8] = []
        if writingPictures {
            if policy.allowsPrepareWrite { codes.append(0x80) }
            if policy.allowsSessionPrepare { codes.append(0x9B) }
            if policy.allowsBindLegacyTaskPicture { codes.append(0x82) }
            if policy.allowsBindTaskPicture { codes.append(0x95) }
            if plan.bindsDefaultAnimation, policy.allowsBindDefaultPicture { codes.append(0x93) }
            if policy.allowsFinishTaskPicture { codes.append(0x98) }
        }
        if plan.emitsSetActiveSetOpcode, policy.allowsSetActiveSet {
            codes.append(0x97)
        }
        return Array(Set(codes)).sorted()
    }

    private static func physicalSlots(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile,
        writingPictures: Bool
    ) -> [UInt8] {
        guard writingPictures else { return [] }
        var slots: [UInt8] = []
        if plan.writeTaskSetA {
            slots.append(UInt8(AhaKeyOLEDSyncPlan.physicalTaskSetIndex(profile: profile, logicalSet: 0)))
        }
        if plan.writeTaskSetB {
            slots.append(UInt8(AhaKeyOLEDSyncPlan.physicalTaskSetIndex(profile: profile, logicalSet: 1)))
        }
        return Array(Set(slots)).sorted()
    }

    private static func activationSemantic(
        profile: AhaKeyOLEDCompatibilityProfile,
        writingPictures: Bool,
        emitsSetActiveSet: Bool
    ) -> Activation {
        switch profile {
        case .legacyStandard:
            return writingPictures ? .implicit : .none
        case .rhinoDualSet, .currentSessionCapable:
            if emitsSetActiveSet { return .setActiveSetOpcode }
            return .none
        case .unsupported:
            return .none
        }
    }

    private static func validate(
        family: Family,
        emittedOpcodes: [UInt8],
        physicalSlots: [UInt8],
        geometry: Geometry,
        activation: Activation
    ) throws {
        let opcodeSet = Set(emittedOpcodes)
        switch family {
        case .legacyStandard:
            if opcodeSet.contains(where: { [UInt8(0x95), 0x97, 0x9A, 0x9B].contains($0) }) {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            if activation == .setActiveSetOpcode {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            if physicalSlots.contains(where: { $0 != 0 }) {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        case .rhinoDualSet(let sessionUpload):
            if !sessionUpload, opcodeSet.contains(where: { [UInt8(0x9A), 0x9B].contains($0) }) {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            if activation == .implicit {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        case .currentSession:
            if activation == .implicit {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        }
        if activation == .setActiveSetOpcode, !opcodeSet.contains(0x97) {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        if activation == .implicit, opcodeSet.contains(0x97) {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        let writingPictures = opcodeSet.contains(where: { [UInt8(0x80), 0x82, 0x93, 0x95, 0x98, 0x9B].contains($0) })
        if writingPictures, geometry != .oled160x80 {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        if !writingPictures, geometry == .oled160x80 {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case family, sessionUpload, emittedOpcodes, physicalSlots, geometry, activation
    }

    public init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: ForbiddenAwareKey.self)
        let names = Set(dynamic.allKeys.map(\.stringValue))
        if !names.isDisjoint(with: Self.forbiddenKeys) {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        if !names.subtracting(allowed).isEmpty {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let familyWire = try container.decode(String.self, forKey: .family)
        let sessionUpload = try container.decodeIfPresent(Bool.self, forKey: .sessionUpload)
        let family: Family
        switch familyWire {
        case "legacy-standard":
            guard sessionUpload == nil else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            family = .legacyStandard
        case "rhino-dual-set":
            guard let sessionUpload else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            family = .rhinoDualSet(sessionUpload: sessionUpload)
        case "current-session":
            guard sessionUpload == nil else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            family = .currentSession
        default:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        try self.init(
            family: family,
            emittedOpcodes: container.decode([UInt8].self, forKey: .emittedOpcodes),
            physicalSlots: container.decode([UInt8].self, forKey: .physicalSlots),
            geometry: container.decode(Geometry.self, forKey: .geometry),
            activation: container.decode(Activation.self, forKey: .activation)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch family {
        case .legacyStandard:
            try container.encode("legacy-standard", forKey: .family)
        case .rhinoDualSet(let sessionUpload):
            try container.encode("rhino-dual-set", forKey: .family)
            try container.encode(sessionUpload, forKey: .sessionUpload)
        case .currentSession:
            try container.encode("current-session", forKey: .family)
        }
        try container.encode(emittedOpcodes, forKey: .emittedOpcodes)
        try container.encode(physicalSlots, forKey: .physicalSlots)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(activation, forKey: .activation)
    }

    private struct ForbiddenAwareKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            self.intValue = intValue
            stringValue = String(intValue)
        }
    }
}

extension AhaKeyRuntimeCompatibilityFingerprint.Family {
    static func make(_ profile: AhaKeyOLEDCompatibilityProfile) throws -> Self {
        switch profile {
        case .legacyStandard:
            return .legacyStandard
        case .rhinoDualSet(let session):
            return .rhinoDualSet(sessionUpload: session)
        case .currentSessionCapable:
            return .currentSession
        case .unsupported:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
    }
}

/// 逐字段 / 逐资源最小确认 ledger。只允许 pending 的合法组合。
public struct AhaKeyRuntimeConfirmationLedger: Codable, Equatable, Sendable {
    public let entries: [Entry]

    public static func pending(
        fieldMask: Set<AhaKeyStudioFieldID>,
        resources: [AhaKeyConfigurationResource]
    ) throws -> AhaKeyRuntimeConfirmationLedger {
        let ledger = AhaKeyRuntimeConfirmationLedger(
            entries: fieldMask.sorted().map { .pendingField($0) }
                + resources
                    .sorted { $0.logicalIdentifier.rawValue < $1.logicalIdentifier.rawValue }
                    .map { .pendingResource(logicalID: $0.logicalIdentifier, sha256: $0.sha256) }
        )
        try ledger.validate(fieldMask: fieldMask, resources: resources)
        return ledger
    }

    public init(entries: [Entry]) {
        self.entries = entries.sorted()
    }

    public var fieldIDs: Set<AhaKeyStudioFieldID> {
        Set(entries.compactMap(\.fieldID))
    }

    public func validate(
        fieldMask: Set<AhaKeyStudioFieldID>,
        resources: [AhaKeyConfigurationResource]
    ) throws {
        let fieldEntries = entries.compactMap(\.fieldID)
        let resourceEntries = entries.compactMap(\.resourceIdentity)
        guard fieldEntries.count == Set(fieldEntries).count else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        var seenResources = Set<String>()
        for identity in resourceEntries {
            let key = "\(identity.logicalID.rawValue)|\(identity.sha256.rawValue)"
            guard seenResources.insert(key).inserted else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
        }
        guard Set(fieldEntries) == fieldMask else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        let expectedResources: [String] = resources.map { resource in
            "\(resource.logicalIdentifier.rawValue)|\(resource.sha256.rawValue)"
        }.sorted()
        let actualResources: [String] = resourceEntries.map {
            "\($0.logicalID.rawValue)|\($0.sha256.rawValue)"
        }.sorted()
        guard actualResources == expectedResources else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        guard entries.count == fieldMask.count + resources.count else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
    }

    public enum Entry: Codable, Equatable, Hashable, Comparable, Sendable {
        case pendingField(AhaKeyStudioFieldID)
        case pendingResource(logicalID: AhaKeyResourceIdentifier, sha256: AhaKeySHA256Digest)

        public struct ResourceIdentity: Equatable, Hashable, Sendable {
            public let logicalID: AhaKeyResourceIdentifier
            public let sha256: AhaKeySHA256Digest
        }

        public var fieldID: AhaKeyStudioFieldID? {
            if case .pendingField(let id) = self { return id }
            return nil
        }

        public var resourceIdentity: ResourceIdentity? {
            if case .pendingResource(let logicalID, let sha256) = self {
                return ResourceIdentity(logicalID: logicalID, sha256: sha256)
            }
            return nil
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.pendingField(let left), .pendingField(let right)):
                return left < right
            case (.pendingResource(let leftID, let leftDigest), .pendingResource(let rightID, let rightDigest)):
                if leftID.rawValue != rightID.rawValue { return leftID.rawValue < rightID.rawValue }
                return leftDigest.rawValue < rightDigest.rawValue
            case (.pendingField, .pendingResource):
                return true
            case (.pendingResource, .pendingField):
                return false
            }
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case pendingField, pendingResource
        }

        public init(from decoder: Decoder) throws {
            let dynamic = try decoder.container(keyedBy: DynamicKey.self)
            let names = Set(dynamic.allKeys.map(\.stringValue))
            let allowed = Set(CodingKeys.allCases.map(\.rawValue))
            guard names.count == 1, names.isSubset(of: allowed) else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.pendingField) {
                self = .pendingField(try container.decode(AhaKeyStudioFieldID.self, forKey: .pendingField))
            } else {
                let payload = try container.decode(ResourcePayload.self, forKey: .pendingResource)
                self = .pendingResource(logicalID: payload.logicalID, sha256: payload.sha256)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .pendingField(let fieldID):
                try container.encode(fieldID, forKey: .pendingField)
            case .pendingResource(let logicalID, let sha256):
                try container.encode(
                    ResourcePayload(logicalID: logicalID, sha256: sha256),
                    forKey: .pendingResource
                )
            }
        }

        private struct ResourcePayload: Codable {
            var logicalID: AhaKeyResourceIdentifier
            var sha256: AhaKeySHA256Digest
        }

        private struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int?

            init?(stringValue: String) {
                self.stringValue = stringValue
                intValue = nil
            }

            init?(intValue: Int) {
                self.intValue = intValue
                stringValue = String(intValue)
            }
        }
    }
}

/// 同设备 durable FIFO 的只读投影。
public struct AhaKeyRuntimeDeviceQueue: Equatable, Sendable {
    public let deviceID: AhaKeyRuntimeDeviceID
    public let items: [AhaKeyRuntimePersistedTransaction]

    public var head: AhaKeyRuntimePersistedTransaction? { items.first }

    public func isHead(_ operationID: AhaKeyRuntimeOperationID) -> Bool {
        head?.operationID == operationID
    }

    /// 非队首不得开始执行。排队取消/无写入离队不走此判定。
    public func isBlocked(_ operationID: AhaKeyRuntimeOperationID) -> Bool {
        guard let index = items.firstIndex(where: { $0.operationID == operationID }) else {
            return true
        }
        return index > 0
    }
}

extension AhaKeyStudioPageID: Codable {
    public init(from decoder: Decoder) throws {
        self = try WirePageID(from: decoder).pageID
    }

    public func encode(to encoder: Encoder) throws {
        try WirePageID(self).encode(to: encoder)
    }
}

extension AhaKeyStudioFieldID: Codable {
    public init(from decoder: Decoder) throws {
        self = try WireFieldID(from: decoder).fieldID
    }

    public func encode(to encoder: Encoder) throws {
        try WireFieldID(self).encode(to: encoder)
    }
}

extension AhaKeyStudioFieldID: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        WireFieldID(lhs).rawValue < WireFieldID(rhs).rawValue
    }
}

private struct WirePageID: Codable, Equatable {
    var kind: String
    var modeSlot: UInt8?
    var role: UInt8?

    init(_ page: AhaKeyStudioPageID) {
        switch page {
        case .key(let slot, let role):
            kind = "key"
            modeSlot = slot
            self.role = role.rawValue
        case .lights(let slot):
            kind = "lights"
            modeSlot = slot
            role = nil
        case .screen(let slot):
            kind = "screen"
            modeSlot = slot
            role = nil
        case .lever:
            kind = "lever"
            modeSlot = nil
            role = nil
        case .power:
            kind = "power"
            modeSlot = nil
            role = nil
        }
    }

    var pageID: AhaKeyStudioPageID {
        get throws {
            switch kind {
            case "key":
                guard let modeSlot, let role,
                      let keyRole = AhaKeyDesiredConfiguration.KeyRole(rawValue: role) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .key(modeSlot: modeSlot, role: keyRole)
            case "lights":
                guard let modeSlot else { throw AhaKeyRuntimeContractError.pageOperationIncomplete }
                return .lights(modeSlot: modeSlot)
            case "screen":
                guard let modeSlot else { throw AhaKeyRuntimeContractError.pageOperationIncomplete }
                return .screen(modeSlot: modeSlot)
            case "lever":
                return .lever
            case "power":
                return .power
            default:
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
        }
    }
}

private struct WireFieldID: Codable, Equatable {
    var rawValue: String

    init(_ id: AhaKeyStudioFieldID) {
        switch id {
        case .keyAction(let slot, let role):
            rawValue = "keyAction:\(slot):\(role.rawValue)"
        case .keyDescription(let slot, let role):
            rawValue = "keyDescription:\(slot):\(role.rawValue)"
        case .keyVoicePreset(let slot, let role):
            rawValue = "keyVoicePreset:\(slot):\(role.rawValue)"
        case .lightBrightness(let slot):
            rawValue = "lightBrightness:\(slot)"
        case .lightMapping(let slot, let state):
            rawValue = "lightMapping:\(slot):\(state)"
        case .screenStatusLine(let slot):
            rawValue = "screenStatusLine:\(slot)"
        case .screenFramesPerSecond(let slot):
            rawValue = "screenFramesPerSecond:\(slot)"
        case .screenTaskAsset(let slot, let setIndex, let state):
            rawValue = "screenTaskAsset:\(slot):\(setIndex):\(state.rawValue)"
        case .screenActiveSet(let slot):
            rawValue = "screenActiveSet:\(slot)"
        case .leverMacro:
            rawValue = "leverMacro"
        case .powerAction:
            rawValue = "powerAction"
        }
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
        _ = try fieldID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var fieldID: AhaKeyStudioFieldID {
        get throws {
            let parts = rawValue.split(separator: ":").map(String.init)
            switch parts.first {
            case "keyAction":
                guard parts.count == 3, let slot = UInt8(parts[1]), let roleRaw = UInt8(parts[2]),
                      let role = AhaKeyDesiredConfiguration.KeyRole(rawValue: roleRaw) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .keyAction(modeSlot: slot, role: role)
            case "keyDescription":
                guard parts.count == 3, let slot = UInt8(parts[1]), let roleRaw = UInt8(parts[2]),
                      let role = AhaKeyDesiredConfiguration.KeyRole(rawValue: roleRaw) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .keyDescription(modeSlot: slot, role: role)
            case "keyVoicePreset":
                guard parts.count == 3, let slot = UInt8(parts[1]), let roleRaw = UInt8(parts[2]),
                      let role = AhaKeyDesiredConfiguration.KeyRole(rawValue: roleRaw) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .keyVoicePreset(modeSlot: slot, role: role)
            case "lightBrightness":
                guard parts.count == 2, let slot = UInt8(parts[1]) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .lightBrightness(modeSlot: slot)
            case "lightMapping":
                guard parts.count == 3, let slot = UInt8(parts[1]), let state = UInt8(parts[2]) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .lightMapping(modeSlot: slot, state: state)
            case "screenStatusLine":
                guard parts.count == 2, let slot = UInt8(parts[1]) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .screenStatusLine(modeSlot: slot)
            case "screenFramesPerSecond":
                guard parts.count == 2, let slot = UInt8(parts[1]) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .screenFramesPerSecond(modeSlot: slot)
            case "screenTaskAsset":
                guard parts.count == 4, let slot = UInt8(parts[1]), let setIndex = Int(parts[2]),
                      let stateRaw = UInt8(parts[3]),
                      let state = AhaKeyDesiredConfiguration.TaskDisplayState(rawValue: stateRaw) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .screenTaskAsset(modeSlot: slot, setIndex: setIndex, state: state)
            case "screenActiveSet":
                guard parts.count == 2, let slot = UInt8(parts[1]) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
                return .screenActiveSet(modeSlot: slot)
            case "leverMacro":
                return .leverMacro
            case "powerAction":
                return .powerAction
            default:
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
        }
    }
}
