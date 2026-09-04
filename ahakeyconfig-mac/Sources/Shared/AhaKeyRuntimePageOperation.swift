import CryptoKit
import Foundation

/// C3A：页面 operation 的稳定 contract。只编码 page scope、field mask、设备、
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
        confirmationLedger: AhaKeyRuntimeConfirmationLedger
    ) throws {
        try Self.validate(
            pageScope: pageScope,
            fieldMask: fieldMask,
            targetDeviceID: targetDeviceID,
            confirmationLedger: confirmationLedger
        )
        self.pageScope = pageScope
        self.fieldMask = fieldMask
        self.targetDeviceID = targetDeviceID
        self.baseObjectFingerprint = baseObjectFingerprint
        self.compatibilityFingerprint = compatibilityFingerprint
        self.confirmationLedger = confirmationLedger
    }

    public func validate(matchingDevice deviceID: AhaKeyRuntimeDeviceID) throws {
        guard targetDeviceID == deviceID else {
            throw AhaKeyRuntimeContractError.pageOperationDeviceMismatch
        }
        try Self.validate(
            pageScope: pageScope,
            fieldMask: fieldMask,
            targetDeviceID: targetDeviceID,
            confirmationLedger: confirmationLedger
        )
    }

    private static func validate(
        pageScope: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        confirmationLedger: AhaKeyRuntimeConfirmationLedger
    ) throws {
        guard !fieldMask.isEmpty else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        guard fieldMask.allSatisfy({ AhaKeyStudioFieldOwnership.page(for: $0) == pageScope }) else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        _ = targetDeviceID
        guard confirmationLedger.fieldIDs == fieldMask else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
    }

    /// 由 C2 scoped plan 组装；资源只记 logical identifier，不带本地路径。
    public static func assemble(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile,
        targetDeviceID: AhaKeyRuntimeDeviceID
    ) throws -> AhaKeyRuntimePageOperationContract {
        guard plan.fieldMask == Set(plan.values.keys), !plan.fieldMask.isEmpty else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        let resourceIDs = plan.resources.map(\.logicalIdentifier.rawValue)
        let ledger = AhaKeyRuntimeConfirmationLedger(
            fields: plan.fieldMask.sorted().map { .pendingField($0) },
            resources: resourceIDs.sorted().map { .pendingResource($0) }
        )
        return try AhaKeyRuntimePageOperationContract(
            pageScope: plan.pageID,
            fieldMask: plan.fieldMask,
            targetDeviceID: targetDeviceID,
            baseObjectFingerprint: .make(
                pageScope: plan.pageID,
                fieldMask: plan.fieldMask,
                profile: profile
            ),
            compatibilityFingerprint: .make(profile: profile),
            confirmationLedger: ledger
        )
    }
}

/// 页面写的 canonical desired payload：含冻结值与 ledger，不含本地路径。
public enum AhaKeyRuntimeCanonicalPageWrite {
    public static func encode(
        plan: AhaKeyStudioScopedWritePlan,
        contract: AhaKeyRuntimePageOperationContract
    ) throws -> Data {
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
            resourceIDs: plan.resources.map(\.logicalIdentifier.rawValue).sorted(),
            values: plan.fieldMask.sorted().map { field in
                FieldValue(id: WireFieldID(field), value: CanonicalValue(plan.values[field]))
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
        var resourceIDs: [String]
        var values: [FieldValue]
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
        case taskAsset(framesPerSecond: Int, declaredFrameCount: Int?, pixelWidth: Int?, pixelHeight: Int?)
        case missing

        init(_ value: AhaKeyStudioFieldValue?) {
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
                self = .taskAsset(
                    framesPerSecond: asset.framesPerSecond,
                    declaredFrameCount: asset.declaredFrameCount,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight
                )
            case nil:
                self = .missing
            }
        }
    }
}

extension AhaKeyConfigurationPackage {
    public static func assemblePageScoped(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        baseRevision: AhaKeyConfigurationRevision,
        operationID: AhaKeyRuntimeOperationID = .init()
    ) throws -> AhaKeyConfigurationPackage {
        let contract = try AhaKeyRuntimePageOperationContract.assemble(
            plan: plan,
            profile: profile,
            targetDeviceID: targetDeviceID
        )
        return try AhaKeyConfigurationPackage(
            operationID: operationID,
            targetDeviceID: targetDeviceID,
            baseRevision: baseRevision,
            desiredConfiguration: AhaKeyRuntimeCanonicalPageWrite.encode(plan: plan, contract: contract),
            resources: [],
            pageOperation: contract
        )
    }
}

/// Studio 只读投影：page scope、field mask 与 FIFO 位置，不含 UI 锁。
public struct AhaKeyRuntimePageOperationProjection: Equatable, Sendable {
    public let pageScope: AhaKeyStudioPageID
    public let fieldMask: Set<AhaKeyStudioFieldID>
    public let targetDeviceID: AhaKeyRuntimeDeviceID
    public let operationID: AhaKeyRuntimeOperationID
    public let queueIndex: Int?
    public let blockedByHead: Bool
    public let headOperationID: AhaKeyRuntimeOperationID?

    public init?(package: AhaKeyConfigurationPackage, queue: AhaKeyRuntimeDeviceQueue) {
        guard let contract = package.pageOperation else { return nil }
        self.pageScope = contract.pageScope
        self.fieldMask = contract.fieldMask
        self.targetDeviceID = contract.targetDeviceID
        self.operationID = package.operationID
        if let index = queue.items.firstIndex(where: { $0.operationID == package.operationID }) {
            self.queueIndex = index
            self.blockedByHead = index > 0
        } else {
            self.queueIndex = nil
            self.blockedByHead = true
        }
        self.headOperationID = queue.head?.operationID
    }
}

/// 页面对象级 fingerprint：只含 page/field/profile 几何，不含路径或动态用量。
public struct AhaKeyRuntimeObjectFingerprint: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count == 64, normalized.allSatisfy({ $0.isHexDigit }) else {
            throw AhaKeyRuntimeContractError.invalidObjectFingerprint
        }
        self.rawValue = normalized
    }

    public static func make(
        pageScope: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        profile: AhaKeyOLEDCompatibilityProfile
    ) throws -> AhaKeyRuntimeObjectFingerprint {
        let payload = CanonicalObjectPayload(
            page: WirePageID(pageScope),
            fields: fieldMask.sorted().map(WireFieldID.init),
            family: AhaKeyRuntimeCompatibilityFingerprint.familyName(profile)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(payload))
        return try AhaKeyRuntimeObjectFingerprint(digest.map { String(format: "%02x", $0) }.joined())
    }

    private struct CanonicalObjectPayload: Codable {
        var page: WirePageID
        var fields: [WireFieldID]
        var family: String
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 兼容语义 fingerprint：协议族、实际 opcode、物理槽几何、session、激活语义。
public struct AhaKeyRuntimeCompatibilityFingerprint: Codable, Equatable, Hashable, Sendable {
    public static let forbiddenKeys: Set<String> = [
        "battery", "batteryLevel", "rssi", "channel", "transport",
        "progress", "capacity", "path", "fileURL", "localPath",
    ]

    public let protocolFamily: String
    public let opcodes: [UInt8]
    public let physicalSetCount: Int
    public let mapsLogicalBToPhysical0: Bool
    public let sessionUpload: Bool
    public let activationSemantic: String

    public init(
        protocolFamily: String,
        opcodes: [UInt8],
        physicalSetCount: Int,
        mapsLogicalBToPhysical0: Bool,
        sessionUpload: Bool,
        activationSemantic: String
    ) throws {
        let family = protocolFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        let activation = activationSemantic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["legacy-standard", "rhino-dual-set", "current-session"].contains(family) else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard ["implicit", "opcode-0x97", "none"].contains(activation) else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard (1...2).contains(physicalSetCount) else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        self.protocolFamily = family
        self.opcodes = Array(Set(opcodes)).sorted()
        self.physicalSetCount = physicalSetCount
        self.mapsLogicalBToPhysical0 = mapsLogicalBToPhysical0
        self.sessionUpload = sessionUpload
        self.activationSemantic = activation
    }

    public static func make(profile: AhaKeyOLEDCompatibilityProfile) throws -> AhaKeyRuntimeCompatibilityFingerprint {
        switch profile {
        case .unsupported:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        case .legacyStandard:
            return try AhaKeyRuntimeCompatibilityFingerprint(
                protocolFamily: "legacy-standard",
                opcodes: opcodeSet(for: profile),
                physicalSetCount: 1,
                mapsLogicalBToPhysical0: true,
                sessionUpload: false,
                activationSemantic: "implicit"
            )
        case .rhinoDualSet(let session):
            return try AhaKeyRuntimeCompatibilityFingerprint(
                protocolFamily: "rhino-dual-set",
                opcodes: opcodeSet(for: profile),
                physicalSetCount: 2,
                mapsLogicalBToPhysical0: false,
                sessionUpload: session,
                activationSemantic: "opcode-0x97"
            )
        case .currentSessionCapable:
            return try AhaKeyRuntimeCompatibilityFingerprint(
                protocolFamily: "current-session",
                opcodes: opcodeSet(for: profile),
                physicalSetCount: 2,
                mapsLogicalBToPhysical0: false,
                sessionUpload: true,
                activationSemantic: "opcode-0x97"
            )
        }
    }

    public static func familyName(_ profile: AhaKeyOLEDCompatibilityProfile) -> String {
        switch profile {
        case .legacyStandard: return "legacy-standard"
        case .rhinoDualSet: return "rhino-dual-set"
        case .currentSessionCapable: return "current-session"
        case .unsupported: return "unsupported"
        }
    }

    public static func opcodeSet(for profile: AhaKeyOLEDCompatibilityProfile) -> [UInt8] {
        let policy = profile.pictureOpcodes
        var codes: [UInt8] = []
        if policy.allowsPrepareWrite { codes.append(0x80) }
        if policy.allowsBindLegacyTaskPicture { codes.append(0x82) }
        if policy.allowsBindDefaultPicture { codes.append(0x93) }
        if policy.allowsBindTaskPicture { codes.append(0x95) }
        if policy.allowsSetActiveSet { codes.append(0x97) }
        if policy.allowsFinishTaskPicture { codes.append(0x98) }
        if policy.allowsSessionPrepare { codes.append(0x9B) }
        if policy.allowsSessionAbort { codes.append(0x9A) }
        return codes.sorted()
    }

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolFamily, opcodes, physicalSetCount, mapsLogicalBToPhysical0
        case sessionUpload, activationSemantic
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
        try self.init(
            protocolFamily: container.decode(String.self, forKey: .protocolFamily),
            opcodes: container.decode([UInt8].self, forKey: .opcodes),
            physicalSetCount: container.decode(Int.self, forKey: .physicalSetCount),
            mapsLogicalBToPhysical0: container.decode(Bool.self, forKey: .mapsLogicalBToPhysical0),
            sessionUpload: container.decode(Bool.self, forKey: .sessionUpload),
            activationSemantic: container.decode(String.self, forKey: .activationSemantic)
        )
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

/// 逐字段 / 逐资源最小确认 ledger。C3A 只持久化结构，不推进 baseline。
public struct AhaKeyRuntimeConfirmationLedger: Codable, Equatable, Sendable {
    public let entries: [Entry]

    public init(fields: [Entry], resources: [Entry]) {
        self.entries = (fields + resources).sorted()
    }

    public init(entries: [Entry]) {
        self.entries = entries.sorted()
    }

    public var fieldIDs: Set<AhaKeyStudioFieldID> {
        Set(entries.compactMap(\.fieldID))
    }

    public struct Entry: Codable, Equatable, Hashable, Comparable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case field
            case resource
        }

        public let kind: Kind
        public let fieldID: AhaKeyStudioFieldID?
        public let resourceID: String?
        public let confirmed: Bool

        public static func pendingField(_ id: AhaKeyStudioFieldID) -> Entry {
            Entry(kind: .field, fieldID: id, resourceID: nil, confirmed: false)
        }

        public static func pendingResource(_ id: String) -> Entry {
            Entry(kind: .resource, fieldID: nil, resourceID: id, confirmed: false)
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.kind.rawValue != rhs.kind.rawValue {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            let left = lhs.fieldID.map(WireFieldID.init)?.rawValue ?? lhs.resourceID ?? ""
            let right = rhs.fieldID.map(WireFieldID.init)?.rawValue ?? rhs.resourceID ?? ""
            return left < right
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

    /// paused/accepted/running/resumable 的队首阻塞后项越过。
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
