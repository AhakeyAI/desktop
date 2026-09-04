import CryptoKit
import Foundation

/// C3AR2：单一协议映射边界。由 plan + profile 生成冻结 field→resource 绑定与 emitted-action 列表。
public enum AhaKeyRuntimePageSemantic {
    public static func bindings(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile,
        verifiedResources: [AhaKeyConfigurationResource]
    ) throws -> [AhaKeyRuntimeFieldResourceBinding] {
        let verifiedIDs = verifiedResources.map(\.logicalIdentifier)
        let planIDs = plan.resources.map(\.logicalIdentifier)
        guard Set(verifiedIDs).count == verifiedIDs.count,
              Set(planIDs).count == planIDs.count else {
            throw AhaKeyRuntimeContractError.duplicateResourceIdentifier
        }
        let verifiedByID = Dictionary(
            uniqueKeysWithValues: verifiedResources.map { ($0.logicalIdentifier, $0) }
        )
        let planByID = Dictionary(
            uniqueKeysWithValues: plan.resources.map { ($0.logicalIdentifier, $0) }
        )
        var bindings: [AhaKeyRuntimeFieldResourceBinding] = []
        var consumed = Set<AhaKeyResourceIdentifier>()
        for field in plan.fieldMask.sorted() {
            guard case .screenTaskAsset(let slot, let logicalSet, let state) = field else { continue }
            guard case .taskAsset(let asset) = plan.values[field] else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            let physical = AhaKeyOLEDSyncPlan.physicalTaskSetIndex(profile: profile, logicalSet: logicalSet)
            let expectedID = try AhaKeyResourceIdentifier(
                AhaKeyStudioPackageAssembler.taskAssetIdentifier(mode: slot, set: physical, state: state)
            )
            guard let verified = verifiedByID[expectedID], let input = planByID[expectedID] else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            guard consumed.insert(expectedID).inserted else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            try validateGeometry(asset: asset, input: input)
            try verifySourceBytesIfPresent(input: input, expected: verified)
            bindings.append(
                AhaKeyRuntimeFieldResourceBinding(
                    fieldID: field,
                    logicalID: verified.logicalIdentifier,
                    sha256: verified.sha256,
                    byteCount: verified.byteCount,
                    mediaType: verified.mediaType
                )
            )
        }
        let expectedIDs = Set(verifiedResources.map(\.logicalIdentifier))
        guard consumed == expectedIDs, consumed == Set(plan.resources.map(\.logicalIdentifier)) else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        return bindings
    }

    public static func actions(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile
    ) throws -> [AhaKeyRuntimeEmittedAction] {
        try plan.fieldMask.sorted().map { field in
            try action(for: field, plan: plan, profile: profile)
        }
    }

    private static func action(
        for field: AhaKeyStudioFieldID,
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile
    ) throws -> AhaKeyRuntimeEmittedAction {
        guard let value = plan.values[field] else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        switch field {
        case .keyAction:
            let command: AhaKeyRuntimeEmittedAction.Command
            switch value {
            case .keyAction(.shortcut):
                command = .keyShortcut
            case .keyAction(.macro):
                command = .keyMacro
            default:
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            return try AhaKeyRuntimeEmittedAction.nonPicture(fieldID: field, command: command)
        case .keyDescription:
            return try AhaKeyRuntimeEmittedAction.nonPicture(fieldID: field, command: .keyDescription)
        case .keyVoicePreset:
            return try AhaKeyRuntimeEmittedAction.nonPicture(fieldID: field, command: .keyVoicePreset)
        case .lightMapping:
            return try AhaKeyRuntimeEmittedAction.nonPicture(fieldID: field, command: .lightMapping)
        case .lightBrightness:
            return try AhaKeyRuntimeEmittedAction.nonPicture(fieldID: field, command: .lightBrightness)
        case .screenStatusLine:
            return try AhaKeyRuntimeEmittedAction.nonPicture(fieldID: field, command: .screenStatus)
        case .screenFramesPerSecond:
            return try AhaKeyRuntimeEmittedAction.nonPicture(fieldID: field, command: .screenFramesPerSecond)
        case .screenActiveSet:
            guard profile.pictureOpcodes.allowsSetActiveSet, plan.emitsSetActiveSetOpcode else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            guard case .integer(let logicalSet) = value, (0...1).contains(logicalSet) else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            let physical = UInt8(
                AhaKeyOLEDSyncPlan.physicalTaskSetIndex(profile: profile, logicalSet: logicalSet)
            )
            return try AhaKeyRuntimeEmittedAction(
                fieldID: field,
                command: .setActiveSet,
                logicalSet: UInt8(logicalSet),
                displayState: nil,
                physicalSlot: physical,
                geometry: .none,
                binding: .none,
                session: .none,
                activation: .setActiveSetOpcode
            )
        case .screenTaskAsset(_, let logicalSet, let state):
            return try pictureAction(
                field: field,
                logicalSet: logicalSet,
                state: state,
                plan: plan,
                profile: profile
            )
        case .leverMacro, .powerAction:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
    }

    private static func pictureAction(
        field: AhaKeyStudioFieldID,
        logicalSet: Int,
        state: AhaKeyDesiredConfiguration.TaskDisplayState,
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile
    ) throws -> AhaKeyRuntimeEmittedAction {
        let policy = profile.pictureOpcodes
        let physical = UInt8(AhaKeyOLEDSyncPlan.physicalTaskSetIndex(profile: profile, logicalSet: logicalSet))
        let prepare: UInt8
        let bind: UInt8
        let binding: AhaKeyRuntimeEmittedAction.Binding
        let session: AhaKeyRuntimeEmittedAction.Session
        let activation: AhaKeyRuntimeCompatibilityFingerprint.Activation
        let defaultBind: UInt8?
        switch profile {
        case .legacyStandard:
            guard policy.allowsPrepareWrite, policy.allowsBindLegacyTaskPicture else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            prepare = 0x80
            bind = 0x93
            binding = .legacyTask
            session = .prepareWrite
            activation = .implicit
            defaultBind = plan.bindsDefaultAnimation && policy.allowsBindDefaultPicture ? 0x82 : nil
        case .rhinoDualSet(let sessionUpload):
            guard policy.allowsBindTaskPicture else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            if sessionUpload, policy.allowsSessionPrepare {
                prepare = 0x9B
                session = .sessionPrepare
            } else if policy.allowsPrepareWrite {
                prepare = 0x80
                session = .prepareWrite
            } else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            bind = 0x95
            binding = .taskSet
            activation = .none
            defaultBind = nil
        case .currentSessionCapable:
            guard policy.allowsSessionPrepare, policy.allowsBindTaskPicture else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            prepare = 0x9B
            bind = 0x95
            binding = .taskSet
            session = .sessionPrepare
            activation = .none
            defaultBind = nil
        case .unsupported:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        return try AhaKeyRuntimeEmittedAction(
            fieldID: field,
            command: .picture(
                AhaKeyRuntimeEmittedAction.PictureSemantics(
                    prepareOpcode: prepare,
                    bindOpcode: bind,
                    defaultBindOpcode: defaultBind
                )
            ),
            logicalSet: UInt8(logicalSet),
            displayState: state.rawValue,
            physicalSlot: physical,
            geometry: .oled160x80,
            binding: binding,
            session: session,
            activation: activation
        )
    }

    private static func validateGeometry(
        asset: AhaKeyStudioTaskAssetDescriptor,
        input: AhaKeyStudioResourceInput
    ) throws {
        guard input.pixelWidth == 160, input.pixelHeight == 80 else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        if let width = asset.pixelWidth, width != 160 {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        if let height = asset.pixelHeight, height != 80 {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        if let frames = asset.declaredFrameCount, frames != input.declaredFrameCount {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
    }

    private static func verifySourceBytesIfPresent(
        input: AhaKeyStudioResourceInput,
        expected: AhaKeyConfigurationResource
    ) throws {
        let path = input.fileURL.path
        guard FileManager.default.isReadableFile(atPath: path) else { return }
        let bytes = try Data(contentsOf: input.fileURL)
        let digest = SHA256.hash(data: bytes)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex == expected.sha256.rawValue, UInt64(bytes.count) == expected.byteCount else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
    }
}

/// 显式 field → logical resource → verified digest。禁止按几何/帧数猜测。
public struct AhaKeyRuntimeFieldResourceBinding: Codable, Equatable, Hashable, Sendable {
    public let fieldID: AhaKeyStudioFieldID
    public let logicalID: AhaKeyResourceIdentifier
    public let sha256: AhaKeySHA256Digest
    public let byteCount: UInt64
    public let mediaType: AhaKeyMediaType

    public var resourceIdentity: AhaKeyRuntimeConfirmationLedger.Entry.ResourceIdentity {
        .init(logicalID: logicalID, sha256: sha256)
    }

    public init(
        fieldID: AhaKeyStudioFieldID,
        logicalID: AhaKeyResourceIdentifier,
        sha256: AhaKeySHA256Digest,
        byteCount: UInt64,
        mediaType: AhaKeyMediaType
    ) {
        self.fieldID = fieldID
        self.logicalID = logicalID
        self.sha256 = sha256
        self.byteCount = byteCount
        self.mediaType = mediaType
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fieldID, logicalID, sha256, byteCount, mediaType
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .pageOperationIncomplete
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fieldID = try container.decode(AhaKeyStudioFieldID.self, forKey: .fieldID)
        logicalID = try container.decode(AhaKeyResourceIdentifier.self, forKey: .logicalID)
        sha256 = try container.decode(AhaKeySHA256Digest.self, forKey: .sha256)
        byteCount = try container.decode(UInt64.self, forKey: .byteCount)
        mediaType = try container.decode(AhaKeyMediaType.self, forKey: .mediaType)
        guard case .screenTaskAsset = fieldID else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
    }
}

/// 一次页面写的实际 emitted action：保留 logical→physical / state / binding / opcode。
public struct AhaKeyRuntimeEmittedAction: Codable, Equatable, Hashable, Sendable {
    public static let registeredOpcodes: Set<UInt8> = [
        0x73, 0x80, 0x82, 0x84, 0x85, 0x93, 0x95, 0x97, 0x98, 0x9B,
    ]
    public static let registeredKeySubtypes: Set<UInt8> = [0x73, 0x74, 0x75]
    public static let pictureBindOpcodes: Set<UInt8> = [0x93, 0x95]
    public static let picturePrepareOpcodes: Set<UInt8> = [0x80, 0x9B]
    public static let pictureDefaultBindOpcodes: Set<UInt8> = [0x82]

    public let fieldID: AhaKeyStudioFieldID
    public let command: Command
    public let logicalSet: UInt8?
    public let displayState: UInt8?
    public let physicalSlot: UInt8?
    public let geometry: AhaKeyRuntimeCompatibilityFingerprint.Geometry
    public let binding: Binding
    public let session: Session
    public let activation: AhaKeyRuntimeCompatibilityFingerprint.Activation

    public enum Binding: String, Codable, Equatable, Hashable, Sendable {
        case none
        case implicit
        case legacyTask = "legacy-0x93"
        case defaultPicture = "legacy-0x82"
        case taskSet = "task-0x95"
    }

    public enum Session: String, Codable, Equatable, Hashable, Sendable {
        case none
        case prepareWrite = "prepare-0x80"
        case sessionPrepare = "session-0x9B"
    }

    public enum Command: Equatable, Hashable, Sendable {
        case keyShortcut
        case keyMacro
        case keyDescription
        case keyVoicePreset
        case lightMapping
        case lightBrightness
        case screenStatus
        case screenFramesPerSecond
        case picture(PictureSemantics)
        case setActiveSet
    }

    public struct PictureSemantics: Codable, Equatable, Hashable, Sendable {
        public let prepareOpcode: UInt8
        public let bindOpcode: UInt8
        public let defaultBindOpcode: UInt8?

        public init(prepareOpcode: UInt8, bindOpcode: UInt8, defaultBindOpcode: UInt8?) {
            self.prepareOpcode = prepareOpcode
            self.bindOpcode = bindOpcode
            self.defaultBindOpcode = defaultBindOpcode
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case prepareOpcode, bindOpcode, defaultBindOpcode
        }

        public init(from decoder: Decoder) throws {
            try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
                in: decoder,
                allowed: Set(CodingKeys.allCases.map(\.rawValue)),
                error: .invalidCompatibilityFingerprint
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            prepareOpcode = try container.decode(UInt8.self, forKey: .prepareOpcode)
            bindOpcode = try container.decode(UInt8.self, forKey: .bindOpcode)
            defaultBindOpcode = try container.decodeIfPresent(UInt8.self, forKey: .defaultBindOpcode)
        }
    }

    public static func nonPicture(
        fieldID: AhaKeyStudioFieldID,
        command: Command
    ) throws -> AhaKeyRuntimeEmittedAction {
        try AhaKeyRuntimeEmittedAction(
            fieldID: fieldID,
            command: command,
            logicalSet: nil,
            displayState: nil,
            physicalSlot: nil,
            geometry: .none,
            binding: .none,
            session: .none,
            activation: .none
        )
    }

    public init(
        fieldID: AhaKeyStudioFieldID,
        command: Command,
        logicalSet: UInt8?,
        displayState: UInt8?,
        physicalSlot: UInt8?,
        geometry: AhaKeyRuntimeCompatibilityFingerprint.Geometry,
        binding: Binding,
        session: Session,
        activation: AhaKeyRuntimeCompatibilityFingerprint.Activation
    ) throws {
        self.fieldID = fieldID
        self.command = command
        self.logicalSet = logicalSet
        self.displayState = displayState
        self.physicalSlot = physicalSlot
        self.geometry = geometry
        self.binding = binding
        self.session = session
        self.activation = activation
        try Self.validate(self)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fieldID, command, logicalSet, displayState, physicalSlot, geometry, binding, session, activation
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .invalidCompatibilityFingerprint
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fieldID: container.decode(AhaKeyStudioFieldID.self, forKey: .fieldID),
            command: container.decode(Command.self, forKey: .command),
            logicalSet: container.decodeIfPresent(UInt8.self, forKey: .logicalSet),
            displayState: container.decodeIfPresent(UInt8.self, forKey: .displayState),
            physicalSlot: container.decodeIfPresent(UInt8.self, forKey: .physicalSlot),
            geometry: container.decode(
                AhaKeyRuntimeCompatibilityFingerprint.Geometry.self,
                forKey: .geometry
            ),
            binding: container.decode(Binding.self, forKey: .binding),
            session: container.decode(Session.self, forKey: .session),
            activation: container.decode(
                AhaKeyRuntimeCompatibilityFingerprint.Activation.self,
                forKey: .activation
            )
        )
    }

    static func validate(_ action: AhaKeyRuntimeEmittedAction) throws {
        switch action.command {
        case .picture(let picture):
            try validatePicture(action, picture: picture)
        case .setActiveSet:
            try validateSetActive(action)
        default:
            try validateNonPicture(action)
        }
        try validateFieldMatchesCommand(action)
    }

    private static func validatePicture(
        _ action: AhaKeyRuntimeEmittedAction,
        picture: PictureSemantics
    ) throws {
        guard Self.picturePrepareOpcodes.contains(picture.prepareOpcode),
              Self.pictureBindOpcodes.contains(picture.bindOpcode) else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        if let defaultBind = picture.defaultBindOpcode {
            guard Self.pictureDefaultBindOpcodes.contains(defaultBind) else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        }
        guard let physicalSlot = action.physicalSlot else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard let logicalSet = action.logicalSet, logicalSet <= 1 else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard let displayState = action.displayState,
              AhaKeyDesiredConfiguration.TaskDisplayState(rawValue: displayState) != nil else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard action.geometry == .oled160x80 else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        switch action.session {
        case .prepareWrite:
            guard picture.prepareOpcode == 0x80 else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        case .sessionPrepare:
            guard picture.prepareOpcode == 0x9B else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        case .none:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard case .screenTaskAsset(_, let fieldSet, let fieldState) = action.fieldID,
              UInt8(fieldSet) == logicalSet,
              fieldState.rawValue == displayState else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        _ = physicalSlot
    }

    private static func validateSetActive(_ action: AhaKeyRuntimeEmittedAction) throws {
        guard action.activation == .setActiveSetOpcode else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard let physicalSlot = action.physicalSlot, physicalSlot <= 1 else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard let logicalSet = action.logicalSet, logicalSet <= 1 else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard action.geometry == .none,
              action.binding == .none,
              action.session == .none,
              action.displayState == nil else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard case .screenActiveSet = action.fieldID else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        _ = physicalSlot
    }

    private static func validateNonPicture(_ action: AhaKeyRuntimeEmittedAction) throws {
        guard action.physicalSlot == nil,
              action.logicalSet == nil,
              action.displayState == nil,
              action.geometry == .none,
              action.binding == .none,
              action.session == .none,
              action.activation == .none else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        if case .picture = action.command {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
    }

    private static func validateFieldMatchesCommand(_ action: AhaKeyRuntimeEmittedAction) throws {
        switch (action.fieldID, action.command) {
        case (.keyAction, .keyShortcut), (.keyAction, .keyMacro),
             (.keyDescription, .keyDescription),
             (.keyVoicePreset, .keyVoicePreset),
             (.lightMapping, .lightMapping),
             (.lightBrightness, .lightBrightness),
             (.screenStatusLine, .screenStatus),
             (.screenFramesPerSecond, .screenFramesPerSecond),
             (.screenActiveSet, .setActiveSet),
             (.screenTaskAsset, .picture):
            return
        default:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
    }
}

extension AhaKeyRuntimeEmittedAction.Command: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, picture
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .invalidCompatibilityFingerprint
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "keyShortcut":
            self = .keyShortcut
        case "keyMacro":
            self = .keyMacro
        case "keyDescription":
            self = .keyDescription
        case "keyVoicePreset":
            self = .keyVoicePreset
        case "lightMapping":
            self = .lightMapping
        case "lightBrightness":
            self = .lightBrightness
        case "screenStatus":
            self = .screenStatus
        case "screenFramesPerSecond":
            self = .screenFramesPerSecond
        case "setActiveSet":
            self = .setActiveSet
        case "picture":
            self = .picture(try container.decode(AhaKeyRuntimeEmittedAction.PictureSemantics.self, forKey: .picture))
        default:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        if kind != "picture", container.contains(.picture) {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keyShortcut:
            try container.encode("keyShortcut", forKey: .kind)
        case .keyMacro:
            try container.encode("keyMacro", forKey: .kind)
        case .keyDescription:
            try container.encode("keyDescription", forKey: .kind)
        case .keyVoicePreset:
            try container.encode("keyVoicePreset", forKey: .kind)
        case .lightMapping:
            try container.encode("lightMapping", forKey: .kind)
        case .lightBrightness:
            try container.encode("lightBrightness", forKey: .kind)
        case .screenStatus:
            try container.encode("screenStatus", forKey: .kind)
        case .screenFramesPerSecond:
            try container.encode("screenFramesPerSecond", forKey: .kind)
        case .setActiveSet:
            try container.encode("setActiveSet", forKey: .kind)
        case .picture(let picture):
            try container.encode("picture", forKey: .kind)
            try container.encode(picture, forKey: .picture)
        }
    }
}

struct AhaKeyRuntimeStrictCodingKey: CodingKey {
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

    static func rejectUnknown(
        in decoder: Decoder,
        allowed: Set<String>,
        forbidden: Set<String> = AhaKeyRuntimeCompatibilityFingerprint.forbiddenKeys,
        error: AhaKeyRuntimeContractError
    ) throws {
        let dynamic = try decoder.container(keyedBy: Self.self)
        let names = Set(dynamic.allKeys.map(\.stringValue))
        if !names.isDisjoint(with: forbidden) {
            throw error
        }
        if !names.subtracting(allowed).isEmpty {
            throw error
        }
    }
}
