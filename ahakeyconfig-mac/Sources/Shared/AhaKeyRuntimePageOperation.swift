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
    public let resourceBindings: [AhaKeyRuntimeFieldResourceBinding]

    public init(
        pageScope: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        baseObjectFingerprint: AhaKeyRuntimeObjectFingerprint,
        compatibilityFingerprint: AhaKeyRuntimeCompatibilityFingerprint,
        confirmationLedger: AhaKeyRuntimeConfirmationLedger,
        resourceBindings: [AhaKeyRuntimeFieldResourceBinding] = [],
        resources: [AhaKeyConfigurationResource] = []
    ) throws {
        try Self.validate(
            pageScope: pageScope,
            fieldMask: fieldMask,
            targetDeviceID: targetDeviceID,
            compatibilityFingerprint: compatibilityFingerprint,
            confirmationLedger: confirmationLedger,
            resourceBindings: resourceBindings,
            resources: resources
        )
        self.pageScope = pageScope
        self.fieldMask = fieldMask
        self.targetDeviceID = targetDeviceID
        self.baseObjectFingerprint = baseObjectFingerprint
        self.compatibilityFingerprint = compatibilityFingerprint
        self.confirmationLedger = confirmationLedger
        self.resourceBindings = resourceBindings
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
            compatibilityFingerprint: compatibilityFingerprint,
            confirmationLedger: confirmationLedger,
            resourceBindings: resourceBindings,
            resources: resources
        )
    }

    private static func validate(
        pageScope: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        compatibilityFingerprint: AhaKeyRuntimeCompatibilityFingerprint,
        confirmationLedger: AhaKeyRuntimeConfirmationLedger,
        resourceBindings: [AhaKeyRuntimeFieldResourceBinding],
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
        try validateBindings(resourceBindings, fieldMask: fieldMask, resources: resources)
        try validateFingerprintContract(
            compatibilityFingerprint,
            pageScope: pageScope,
            fieldMask: fieldMask,
            resourceBindings: resourceBindings
        )
    }

    /// Fingerprint actions 与冻结 fieldMask 精确双射；同一 field 的 picture action
    /// 与 binding 必须共享完整 resource identity（logicalID/digest/byteCount/mediaType）
    /// 以及 encodedFrameCount，并闭合 canonical logical ID。
    private static func validateFingerprintContract(
        _ fingerprint: AhaKeyRuntimeCompatibilityFingerprint,
        pageScope: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        resourceBindings: [AhaKeyRuntimeFieldResourceBinding]
    ) throws {
        let fields = fingerprint.actions.map(\.fieldID)
        guard fields.count == Set(fields).count else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        let canonical = fieldMask.sorted()
        guard fields == canonical else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard fields.allSatisfy({ AhaKeyStudioFieldOwnership.page(for: $0) == pageScope }) else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        let bindingByField = Dictionary(uniqueKeysWithValues: resourceBindings.map { ($0.fieldID, $0) })
        var pictureFields: Set<AhaKeyStudioFieldID> = []
        for action in fingerprint.actions {
            guard case .picture = action.command else { continue }
            pictureFields.insert(action.fieldID)
            guard let binding = bindingByField[action.fieldID],
                  case .screenTaskAsset(let modeSlot, let setIndex, let state) = binding.fieldID,
                  action.logicalSet == UInt8(setIndex),
                  action.displayState == state.rawValue,
                  action.physicalSlot == fingerprint.family.physicalSlot(forLogicalSet: UInt8(setIndex)),
                  action.resourceIdentity == binding.pictureIdentity,
                  action.encodedFrameCount == binding.encodedFrameCount else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            let expectedID = AhaKeyStudioPackageAssembler.taskAssetIdentifier(
                mode: modeSlot,
                set: Int(fingerprint.family.physicalSlot(forLogicalSet: UInt8(setIndex))),
                state: state
            )
            guard binding.logicalID.rawValue == expectedID,
                  action.resourceIdentity?.logicalID.rawValue == expectedID else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            guard let strategy = fingerprint.prepareStrategy,
                  strategy.opcode == fingerprint.family.pictureWire().prepareOpcode else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            _ = try strategy.prepareCount(encodedFrameCount: Int(binding.encodedFrameCount))
        }
        guard pictureFields == Set(resourceBindings.map(\.fieldID)) else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
    }

    private static func validateBindings(
        _ bindings: [AhaKeyRuntimeFieldResourceBinding],
        fieldMask: Set<AhaKeyStudioFieldID>,
        resources: [AhaKeyConfigurationResource]
    ) throws {
        let assetFields = Set(fieldMask.filter {
            if case .screenTaskAsset = $0 { return true }
            return false
        })
        let boundFields = bindings.map(\.fieldID)
        guard boundFields.count == Set(boundFields).count, Set(boundFields) == assetFields else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        let boundIdentities = bindings.map(\.resourceIdentity)
        guard boundIdentities.count == Set(boundIdentities).count else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        let resourceIdentities = Set(
            resources.map { AhaKeyRuntimeConfirmationLedger.Entry.ResourceIdentity(
                logicalID: $0.logicalIdentifier,
                sha256: $0.sha256
            ) }
        )
        guard Set(boundIdentities) == resourceIdentities else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        for binding in bindings {
            guard let resource = resources.first(where: { $0.logicalIdentifier == binding.logicalID }) else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            guard resource.sha256 == binding.sha256,
                  resource.byteCount == binding.byteCount,
                  resource.mediaType == binding.mediaType else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
        }
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
        let bindings = try AhaKeyRuntimePageSemantic.bindings(
            plan: plan,
            profile: profile,
            verifiedResources: verifiedResources
        )
        let ledger = try AhaKeyRuntimeConfirmationLedger.pending(
            fieldMask: plan.fieldMask,
            resources: verifiedResources
        )
        return try AhaKeyRuntimePageOperationContract(
            pageScope: plan.pageID,
            fieldMask: plan.fieldMask,
            targetDeviceID: targetDeviceID,
            baseObjectFingerprint: baseObjectFingerprint,
            compatibilityFingerprint: .make(plan: plan, profile: profile, bindings: bindings),
            confirmationLedger: ledger,
            resourceBindings: bindings,
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
            bindings: contract.resourceBindings,
            values: try plan.fieldMask.sorted().map { field in
                FieldValue(
                    id: WireFieldID(field),
                    value: try CanonicalValue(
                        plan.values[field],
                        field: field,
                        bindings: contract.resourceBindings
                    )
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
        var bindings: [AhaKeyRuntimeFieldResourceBinding]
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
            field: AhaKeyStudioFieldID,
            bindings: [AhaKeyRuntimeFieldResourceBinding]
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
                guard let match = bindings.first(where: { $0.fieldID == field }) else {
                    throw AhaKeyRuntimeContractError.pageOperationIncomplete
                }
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
    }
}

/// 冻结页面写的可执行值：只从 canonical payload 解码，禁止回读草稿路径。
public struct AhaKeyRuntimeFrozenPageValues: Equatable, Sendable {
    public let framesPerSecond: Int?
    public let statusLine: String?
    public let fieldValues: [AhaKeyStudioFieldID: Value]

    public enum Value: Equatable, Sendable {
        case text(String)
        case optionalText(String?)
        case integer(Int)
        case keyAction(AhaKeyDesiredConfiguration.KeyAction)
        case taskAsset(framesPerSecond: Int, declaredFrameCount: Int?)
    }
}

extension AhaKeyRuntimeCanonicalPageWrite {
    public static func frozenValues(from desiredConfiguration: Data) throws -> AhaKeyRuntimeFrozenPageValues {
        let payload = try JSONDecoder().decode(Payload.self, from: desiredConfiguration)
        var fieldValues: [AhaKeyStudioFieldID: AhaKeyRuntimeFrozenPageValues.Value] = [:]
        for item in payload.values {
            let field = try item.id.fieldID
            switch item.value {
            case .text(let text):
                fieldValues[field] = .text(text)
            case .optionalText(let text):
                fieldValues[field] = .optionalText(text)
            case .integer(let number):
                fieldValues[field] = .integer(number)
            case .keyAction(let action):
                fieldValues[field] = .keyAction(action)
            case .taskAsset(_, _, _, let fps, let frames, _, _):
                fieldValues[field] = .taskAsset(framesPerSecond: fps, declaredFrameCount: frames)
            }
        }
        return AhaKeyRuntimeFrozenPageValues(
            framesPerSecond: payload.framesPerSecond,
            statusLine: payload.statusLine,
            fieldValues: fieldValues
        )
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

/// 冻结的 0x84 9-state 行。恢复只重放这一份，禁止临场补零。
public struct AhaKeyRuntimeLightMappingRow: Codable, Equatable, Hashable, Sendable {
    public let mode: UInt8
    public let effects: [UInt8]

    /// 固件 0x84 已登记 effect index：0=off … 7=middleLight。
    public static let registeredFirmwareEffectIndices: ClosedRange<UInt8> = 0...7

    public init(mode: UInt8, effects: [UInt8]) throws {
        guard effects.count == 9,
              effects.allSatisfy({ Self.registeredFirmwareEffectIndices.contains($0) }) else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        self.mode = mode
        self.effects = effects
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode, effects
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .invalidCompatibilityFingerprint
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            mode: try container.decode(UInt8.self, forKey: .mode),
            effects: try container.decode([UInt8].self, forKey: .effects)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(effects, forKey: .effects)
    }
}

/// 兼容语义 fingerprint：canonical typed emitted-action 列表，保留 logical→physical 映射。
/// prepare 是 per-chunk strategy（与生产 resourceUploadProgram 同构）；defaultBind 至多一次。
public struct AhaKeyRuntimeCompatibilityFingerprint: Codable, Equatable, Hashable, Sendable {
    public static let forbiddenKeys: Set<String> = [
        "battery", "batteryLevel", "rssi", "channel", "transport",
        "progress", "capacity", "path", "fileURL", "localPath",
    ]

    public let family: Family
    public let prepareStrategy: AhaKeyRuntimePicturePrepareStrategy?
    public let defaultBindOpcode: UInt8?
    public let actions: [AhaKeyRuntimeEmittedAction]
    /// 冻结的 0x84 完整 9-state 行，纳入 fingerprint identity；恢复只重放这一份。
    public let lightMappingRows: [AhaKeyRuntimeLightMappingRow]

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
        actions: [AhaKeyRuntimeEmittedAction],
        prepareStrategy: AhaKeyRuntimePicturePrepareStrategy? = nil,
        defaultBindOpcode: UInt8? = nil,
        lightMappingRows: [AhaKeyRuntimeLightMappingRow] = []
    ) throws {
        try Self.validate(
            family: family,
            actions: actions,
            prepareStrategy: prepareStrategy,
            defaultBindOpcode: defaultBindOpcode,
            lightMappingRows: lightMappingRows
        )
        self.family = family
        self.prepareStrategy = prepareStrategy
        self.defaultBindOpcode = defaultBindOpcode
        self.actions = actions
        self.lightMappingRows = lightMappingRows
    }

    public static func make(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile,
        bindings: [AhaKeyRuntimeFieldResourceBinding] = [],
        verifiedResources: [AhaKeyConfigurationResource] = []
    ) throws -> AhaKeyRuntimeCompatibilityFingerprint {
        let resolvedBindings = bindings.isEmpty
            ? try AhaKeyRuntimePageSemantic.bindings(
                plan: plan,
                profile: profile,
                verifiedResources: verifiedResources
            )
            : bindings
        let actions = try AhaKeyRuntimePageSemantic.actions(
            plan: plan,
            profile: profile,
            bindings: resolvedBindings
        )
        let lightMappingRows = try AhaKeyRuntimePageSemantic.lightMappingRows(from: plan)
        return try AhaKeyRuntimeCompatibilityFingerprint(
            family: try Family.make(profile),
            actions: actions,
            prepareStrategy: try AhaKeyRuntimePageSemantic.prepareStrategy(for: actions, profile: profile),
            defaultBindOpcode: try AhaKeyRuntimePageSemantic.defaultBindOpcode(plan: plan, profile: profile),
            lightMappingRows: lightMappingRows
        )
    }

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    private static func validate(
        family: Family,
        actions: [AhaKeyRuntimeEmittedAction],
        prepareStrategy: AhaKeyRuntimePicturePrepareStrategy?,
        defaultBindOpcode: UInt8?,
        lightMappingRows: [AhaKeyRuntimeLightMappingRow]
    ) throws {
        guard !actions.isEmpty else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        let fields = actions.map(\.fieldID)
        guard fields.count == Set(fields).count, fields == fields.sorted() else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        let pictureActions = actions.filter { action in
            if case .picture = action.command { return true }
            return false
        }
        let wire = family.pictureWire()
        if pictureActions.isEmpty {
            guard prepareStrategy == nil, defaultBindOpcode == nil else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            guard actions.allSatisfy({ $0.session == .none }) else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        } else {
            guard let prepareStrategy, prepareStrategy.opcode == wire.prepareOpcode else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            for action in pictureActions {
                guard action.session == wire.session,
                      let frames = action.encodedFrameCount else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
                _ = try prepareStrategy.prepareCount(encodedFrameCount: Int(frames))
            }
            if let defaultBindOpcode {
                guard family == .legacyStandard,
                      AhaKeyRuntimeEmittedAction.pictureDefaultBindOpcodes.contains(defaultBindOpcode) else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
            }
        }
        for action in actions {
            try AhaKeyRuntimeEmittedAction.validate(action)
            try validate(action, in: family, prepareStrategy: prepareStrategy, defaultBindOpcode: defaultBindOpcode)
        }
        try validateLightMappingRows(lightMappingRows, actions: actions)
    }

    private static func validateLightMappingRows(
        _ rows: [AhaKeyRuntimeLightMappingRow],
        actions: [AhaKeyRuntimeEmittedAction]
    ) throws {
        let mappingModes = Set(actions.compactMap { action -> UInt8? in
            guard case .lightMapping = action.command,
                  case .lightMapping(let mode, _) = action.fieldID else { return nil }
            return mode
        })
        let rowModes = rows.map(\.mode)
        guard rowModes.count == Set(rowModes).count,
              rowModes == rowModes.sorted(),
              Set(rowModes) == mappingModes else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        for row in rows {
            guard row.effects.count == 9 else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        }
    }

    private static func validate(
        _ action: AhaKeyRuntimeEmittedAction,
        in family: Family,
        prepareStrategy: AhaKeyRuntimePicturePrepareStrategy?,
        defaultBindOpcode: UInt8?
    ) throws {
        switch action.command {
        case .picture(let picture):
            guard let logicalSet = action.logicalSet, let physicalSlot = action.physicalSlot else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            let wire = family.pictureWire()
            guard physicalSlot == family.physicalSlot(forLogicalSet: logicalSet),
                  physicalSlot <= 1,
                  picture.bindOpcode == wire.bindOpcode,
                  action.opcode == wire.bindOpcode,
                  action.binding == wire.binding,
                  action.session == wire.session,
                  action.activation == wire.activation,
                  prepareStrategy?.opcode == wire.prepareOpcode else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            switch family {
            case .legacyStandard:
                guard physicalSlot == 0 else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
                if let defaultBindOpcode, defaultBindOpcode != AhaKeyWireFrameBuilder.cmdUpdatePic {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
            case .rhinoDualSet, .currentSession:
                guard defaultBindOpcode == nil else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
            }
        case .setActiveSet:
            switch family {
            case .legacyStandard:
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            case .rhinoDualSet, .currentSession:
                guard let logicalSet = action.logicalSet, let physicalSlot = action.physicalSlot else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
                guard physicalSlot == family.physicalSlot(forLogicalSet: logicalSet) else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
                guard action.opcode == AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
            }
        default:
            break
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case family, sessionUpload, prepareStrategy, defaultBindOpcode, actions, lightMappingRows
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .invalidCompatibilityFingerprint
        )
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
            actions: container.decode([AhaKeyRuntimeEmittedAction].self, forKey: .actions),
            prepareStrategy: container.decodeIfPresent(
                AhaKeyRuntimePicturePrepareStrategy.self,
                forKey: .prepareStrategy
            ),
            defaultBindOpcode: container.decodeIfPresent(UInt8.self, forKey: .defaultBindOpcode),
            lightMappingRows: container.decodeIfPresent(
                [AhaKeyRuntimeLightMappingRow].self,
                forKey: .lightMappingRows
            ) ?? []
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
        try container.encodeIfPresent(prepareStrategy, forKey: .prepareStrategy)
        try container.encodeIfPresent(defaultBindOpcode, forKey: .defaultBindOpcode)
        try container.encode(actions, forKey: .actions)
        if !lightMappingRows.isEmpty {
            try container.encode(lightMappingRows, forKey: .lightMappingRows)
        }
    }
}

extension AhaKeyRuntimeCompatibilityFingerprint.Family {
    struct PictureWire: Equatable {
        let prepareOpcode: UInt8
        let bindOpcode: UInt8
        let binding: AhaKeyRuntimeEmittedAction.Binding
        let session: AhaKeyRuntimeEmittedAction.Session
        let activation: AhaKeyRuntimeCompatibilityFingerprint.Activation
    }

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

    func pictureWire() -> PictureWire {
        switch self {
        case .legacyStandard:
            return PictureWire(
                prepareOpcode: AhaKeyWireFrameBuilder.cmdPrepareWrite,
                bindOpcode: AhaKeyWireFrameBuilder.cmdUpdateTaskPic,
                binding: .legacyTask,
                session: .prepareWrite,
                activation: .implicit
            )
        case .rhinoDualSet(let sessionUpload):
            return PictureWire(
                prepareOpcode: sessionUpload
                    ? AhaKeyWireFrameBuilder.cmdPrepareSessionWrite
                    : AhaKeyWireFrameBuilder.cmdPrepareWrite,
                bindOpcode: AhaKeyWireFrameBuilder.cmdUpdateTaskPicSet,
                binding: .taskSet,
                session: sessionUpload ? .sessionPrepare : .prepareWrite,
                activation: .none
            )
        case .currentSession:
            return PictureWire(
                prepareOpcode: AhaKeyWireFrameBuilder.cmdPrepareSessionWrite,
                bindOpcode: AhaKeyWireFrameBuilder.cmdUpdateTaskPicSet,
                binding: .taskSet,
                session: .sessionPrepare,
                activation: .none
            )
        }
    }

    func physicalSlot(forLogicalSet logical: UInt8) -> UInt8 {
        switch self {
        case .legacyStandard:
            return 0
        case .rhinoDualSet, .currentSession:
            return logical
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
        guard resourceEntries.count == Set(resourceEntries).count else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        guard Set(fieldEntries) == fieldMask else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        let expectedResources = Set(
            resources.map {
                Entry.ResourceIdentity(logicalID: $0.logicalIdentifier, sha256: $0.sha256)
            }
        )
        guard Set(resourceEntries) == expectedResources else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        guard entries.count == fieldMask.count + resources.count else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
    }

    public enum Entry: Codable, Equatable, Hashable, Comparable, Sendable {
        case pendingField(AhaKeyStudioFieldID)
        case pendingResource(logicalID: AhaKeyResourceIdentifier, sha256: AhaKeySHA256Digest)

        public struct ResourceIdentity: Codable, Equatable, Hashable, Sendable {
            public let logicalID: AhaKeyResourceIdentifier
            public let sha256: AhaKeySHA256Digest

            public init(logicalID: AhaKeyResourceIdentifier, sha256: AhaKeySHA256Digest) {
                self.logicalID = logicalID
                self.sha256 = sha256
            }
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
            try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
                in: decoder,
                allowed: Set(CodingKeys.allCases.map(\.rawValue)),
                error: .pageOperationIncomplete
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.pendingField) != container.contains(.pendingResource) else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
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
    public var canonicalToken: String { WireFieldID(self).rawValue }

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

/// schema=1 仍走 planner 受理；schema=2 只校验冻结 page contract 与 CAS digest，禁止解码整机 DesiredConfiguration。
public struct AhaKeyRuntimeSchemaAwareAcceptanceValidator: AhaKeyRuntimePackageAcceptanceValidator {
    private let schema1: any AhaKeyRuntimePackageAcceptanceValidator

    public init(schema1: any AhaKeyRuntimePackageAcceptanceValidator = AhaKeyConfigurationPlanner.AcceptanceValidator()) {
        self.schema1 = schema1
    }

    public func validate(
        package: AhaKeyConfigurationPackage,
        resources: [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput]
    ) throws {
        if package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion {
            guard let page = package.pageOperation else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            try page.validate(matchingDevice: package.targetDeviceID, resources: package.resources)
            for resource in package.resources {
                guard let input = resources[resource.logicalIdentifier] else { continue }
                let digest = SHA256.hash(data: input.contents)
                    .map { String(format: "%02x", $0) }
                    .joined()
                guard digest == resource.sha256.rawValue else {
                    throw AhaKeyRuntimePersistenceError.resourceDigestMismatch(resource.logicalIdentifier)
                }
                guard input.contents.count == resource.byteCount else {
                    throw AhaKeyRuntimePersistenceError.resourceByteCountMismatch(resource.logicalIdentifier)
                }
            }
            return
        }
        try schema1.validate(package: package, resources: resources)
    }
}
