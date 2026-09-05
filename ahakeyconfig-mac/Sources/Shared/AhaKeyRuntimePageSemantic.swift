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
            let physical = Int(try physicalSlot(profile: profile, logicalSet: logicalSet))
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
                    mediaType: verified.mediaType,
                    encodedFrameCount: try encodedFrameCount(asset: asset, input: input)
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
        profile: AhaKeyOLEDCompatibilityProfile,
        bindings: [AhaKeyRuntimeFieldResourceBinding] = []
    ) throws -> [AhaKeyRuntimeEmittedAction] {
        let bindingByField = Dictionary(uniqueKeysWithValues: bindings.map { ($0.fieldID, $0) })
        return try plan.fieldMask.sorted().map { field in
            try action(for: field, plan: plan, profile: profile, bindings: bindingByField)
        }
    }

    private static func action(
        for field: AhaKeyStudioFieldID,
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile,
        bindings: [AhaKeyStudioFieldID: AhaKeyRuntimeFieldResourceBinding]
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
            let physical = try physicalSlot(profile: profile, logicalSet: logicalSet)
            return try AhaKeyRuntimeEmittedAction(
                fieldID: field,
                command: .setActiveSet,
                opcode: AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet,
                subtype: nil,
                logicalSet: UInt8(logicalSet),
                displayState: nil,
                physicalSlot: physical,
                geometry: .none,
                binding: .none,
                session: .none,
                activation: .setActiveSetOpcode
            )
        case .screenTaskAsset(_, let logicalSet, let state):
            guard let binding = bindings[field] else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            return try pictureAction(
                field: field,
                logicalSet: logicalSet,
                state: state,
                profile: profile,
                binding: binding
            )
        case .leverMacro, .powerAction:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
    }

    private static func pictureAction(
        field: AhaKeyStudioFieldID,
        logicalSet: Int,
        state: AhaKeyDesiredConfiguration.TaskDisplayState,
        profile: AhaKeyOLEDCompatibilityProfile,
        binding: AhaKeyRuntimeFieldResourceBinding
    ) throws -> AhaKeyRuntimeEmittedAction {
        let policy = profile.pictureOpcodes
        let family = try AhaKeyRuntimeCompatibilityFingerprint.Family.make(profile)
        let physical = family.physicalSlot(forLogicalSet: clampedLogicalSet(logicalSet))
        let wire = family.pictureWire()
        switch family {
        case .legacyStandard:
            guard policy.allowsPrepareWrite, policy.allowsBindLegacyTaskPicture else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        case .rhinoDualSet(let sessionUpload):
            guard policy.allowsBindTaskPicture else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            if sessionUpload {
                guard policy.allowsSessionPrepare else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
            } else {
                guard policy.allowsPrepareWrite else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
            }
        case .currentSession:
            guard policy.allowsSessionPrepare, policy.allowsBindTaskPicture else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        }
        return try AhaKeyRuntimeEmittedAction(
            fieldID: field,
            command: .picture(AhaKeyRuntimeEmittedAction.PictureSemantics(bindOpcode: wire.bindOpcode)),
            opcode: wire.bindOpcode,
            subtype: nil,
            logicalSet: UInt8(logicalSet),
            displayState: state.rawValue,
            physicalSlot: physical,
            geometry: .oled160x80,
            binding: wire.binding,
            session: wire.session,
            activation: wire.activation,
            resourceIdentity: binding.pictureIdentity,
            encodedFrameCount: binding.encodedFrameCount
        )
    }

    static func prepareStrategy(
        for actions: [AhaKeyRuntimeEmittedAction],
        profile: AhaKeyOLEDCompatibilityProfile
    ) throws -> AhaKeyRuntimePicturePrepareStrategy? {
        guard actions.contains(where: { if case .picture = $0.command { return true }; return false }) else {
            return nil
        }
        let family = try AhaKeyRuntimeCompatibilityFingerprint.Family.make(profile)
        return try AhaKeyRuntimePicturePrepareStrategy.production(opcode: family.pictureWire().prepareOpcode)
    }

    /// 与生产 `resourceUploadProgram` 相同：每帧每个 chunk 一次 prepare。
    public static func picturePrepareCount(
        encodedFrameCount: Int,
        layout: AhaKeyDeviceLayoutPolicy = .init()
    ) throws -> Int {
        try AhaKeyRuntimePicturePrepareStrategy.production(
            opcode: AhaKeyWireFrameBuilder.cmdPrepareWrite
        ).prepareCount(encodedFrameCount: encodedFrameCount, layout: layout)
    }

    /// 生成与校验共用 `Family.physicalSlot`，禁止再走 `AhaKeyOLEDSyncPlan.physicalTaskSetIndex`。
    public static func physicalSlot(
        profile: AhaKeyOLEDCompatibilityProfile,
        logicalSet: Int
    ) throws -> UInt8 {
        let family = try AhaKeyRuntimeCompatibilityFingerprint.Family.make(profile)
        return family.physicalSlot(forLogicalSet: clampedLogicalSet(logicalSet))
    }

    static func clampedLogicalSet(_ logicalSet: Int) -> UInt8 {
        UInt8(min(1, max(0, logicalSet)))
    }

    static func defaultBindOpcode(
        plan: AhaKeyStudioScopedWritePlan,
        profile: AhaKeyOLEDCompatibilityProfile
    ) throws -> UInt8? {
        let hasPicture = plan.fieldMask.contains { field in
            if case .screenTaskAsset = field { return true }
            return false
        }
        guard hasPicture, plan.bindsDefaultAnimation, profile.pictureOpcodes.allowsBindDefaultPicture else {
            return nil
        }
        return AhaKeyWireFrameBuilder.cmdUpdatePic
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

    private static func encodedFrameCount(
        asset: AhaKeyStudioTaskAssetDescriptor,
        input: AhaKeyStudioResourceInput
    ) throws -> UInt16 {
        let frames = asset.declaredFrameCount ?? input.declaredFrameCount
        guard frames > 0, frames <= AhaKeyDeviceLayoutPolicy().framesPerSlot, frames <= UInt16.max else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
        return UInt16(frames)
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

/// 与 picture action 共享的不可交换资源身份。比较 logicalID+digest+byteCount+mediaType，禁止只比集合。
public struct AhaKeyRuntimePictureResourceIdentity: Codable, Equatable, Hashable, Sendable {
    public let logicalID: AhaKeyResourceIdentifier
    public let sha256: AhaKeySHA256Digest
    public let byteCount: UInt64
    public let mediaType: AhaKeyMediaType

    public init(
        logicalID: AhaKeyResourceIdentifier,
        sha256: AhaKeySHA256Digest,
        byteCount: UInt64,
        mediaType: AhaKeyMediaType
    ) {
        self.logicalID = logicalID
        self.sha256 = sha256
        self.byteCount = byteCount
        self.mediaType = mediaType
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case logicalID, sha256, byteCount, mediaType
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .invalidCompatibilityFingerprint
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logicalID = try container.decode(AhaKeyResourceIdentifier.self, forKey: .logicalID)
        sha256 = try container.decode(AhaKeySHA256Digest.self, forKey: .sha256)
        byteCount = try container.decode(UInt64.self, forKey: .byteCount)
        mediaType = try container.decode(AhaKeyMediaType.self, forKey: .mediaType)
    }
}

/// 生产上传 prepare 策略：每帧每个 chunk 发送一次 0x80/0x9B，不是 operation-wide 0/1。
public struct AhaKeyRuntimePicturePrepareStrategy: Codable, Equatable, Hashable, Sendable {
    public let opcode: UInt8
    public let perChunk: Bool
    public let encodedFrameBytes: UInt32
    public let chunkBytes: UInt32

    public init(opcode: UInt8, perChunk: Bool, encodedFrameBytes: UInt32, chunkBytes: UInt32) throws {
        self.opcode = opcode
        self.perChunk = perChunk
        self.encodedFrameBytes = encodedFrameBytes
        self.chunkBytes = chunkBytes
        try Self.validate(self)
    }

    public static func production(opcode: UInt8) throws -> Self {
        let layout = AhaKeyDeviceLayoutPolicy()
        return try Self(
            opcode: opcode,
            perChunk: true,
            encodedFrameBytes: UInt32(layout.encodedFrameBytes),
            chunkBytes: UInt32(layout.chunkBytes)
        )
    }

    public func prepareCount(
        encodedFrameCount: Int,
        layout: AhaKeyDeviceLayoutPolicy = .init()
    ) throws -> Int {
        try Self.validate(self, layout: layout)
        guard encodedFrameCount > 0, encodedFrameCount <= layout.framesPerSlot else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        let chunksPerFrame = (Int(encodedFrameBytes) + Int(chunkBytes) - 1) / Int(chunkBytes)
        return encodedFrameCount * chunksPerFrame
    }

    private static func validate(
        _ strategy: Self,
        layout: AhaKeyDeviceLayoutPolicy = .init()
    ) throws {
        guard AhaKeyRuntimeEmittedAction.picturePrepareOpcodes.contains(strategy.opcode),
              strategy.perChunk,
              strategy.encodedFrameBytes == UInt32(layout.encodedFrameBytes),
              strategy.chunkBytes == UInt32(layout.chunkBytes),
              strategy.chunkBytes > 0 else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case opcode, perChunk, encodedFrameBytes, chunkBytes
    }

    public init(from decoder: Decoder) throws {
        try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)),
            error: .invalidCompatibilityFingerprint
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            opcode: container.decode(UInt8.self, forKey: .opcode),
            perChunk: container.decode(Bool.self, forKey: .perChunk),
            encodedFrameBytes: container.decode(UInt32.self, forKey: .encodedFrameBytes),
            chunkBytes: container.decode(UInt32.self, forKey: .chunkBytes)
        )
    }
}

/// 显式 field → logical resource → verified digest。禁止按几何/帧数猜测。
public struct AhaKeyRuntimeFieldResourceBinding: Codable, Equatable, Hashable, Sendable {
    public let fieldID: AhaKeyStudioFieldID
    public let logicalID: AhaKeyResourceIdentifier
    public let sha256: AhaKeySHA256Digest
    public let byteCount: UInt64
    public let mediaType: AhaKeyMediaType
    public let encodedFrameCount: UInt16

    public var resourceIdentity: AhaKeyRuntimeConfirmationLedger.Entry.ResourceIdentity {
        .init(logicalID: logicalID, sha256: sha256)
    }

    public var pictureIdentity: AhaKeyRuntimePictureResourceIdentity {
        .init(logicalID: logicalID, sha256: sha256, byteCount: byteCount, mediaType: mediaType)
    }

    public init(
        fieldID: AhaKeyStudioFieldID,
        logicalID: AhaKeyResourceIdentifier,
        sha256: AhaKeySHA256Digest,
        byteCount: UInt64,
        mediaType: AhaKeyMediaType,
        encodedFrameCount: UInt16
    ) {
        self.fieldID = fieldID
        self.logicalID = logicalID
        self.sha256 = sha256
        self.byteCount = byteCount
        self.mediaType = mediaType
        self.encodedFrameCount = encodedFrameCount
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fieldID, logicalID, sha256, byteCount, mediaType, encodedFrameCount
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
        encodedFrameCount = try container.decode(UInt16.self, forKey: .encodedFrameCount)
        guard case .screenTaskAsset = fieldID, encodedFrameCount > 0 else {
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
    }
}

/// 一次页面写的实际 emitted action：per-field wire opcode/subtype + logical→physical 映射。
/// 图片 action 携带不可交换的 resource identity；prepare 次数由 per-chunk strategy 从冻结帧布局导出。
public struct AhaKeyRuntimeEmittedAction: Codable, Equatable, Hashable, Sendable {
    public static let registeredOpcodes: Set<UInt8> = [
        AhaKeyWireFrameBuilder.cmdUpdateCustomKey,
        AhaKeyWireFrameBuilder.cmdPrepareWrite,
        AhaKeyWireFrameBuilder.cmdUpdatePic,
        AhaKeyWireFrameBuilder.cmdSetLightMapping,
        AhaKeyWireFrameBuilder.cmdSetBrightness,
        AhaKeyWireFrameBuilder.cmdUpdateTaskPic,
        AhaKeyWireFrameBuilder.cmdUpdateTaskPicSet,
        AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet,
        AhaKeyWireFrameBuilder.cmdFinishTaskPicWrite,
        AhaKeyWireFrameBuilder.cmdPrepareSessionWrite,
    ]
    public static let registeredKeySubtypes: Set<UInt8> = [
        AhaKeyWireFrameBuilder.subShortcut,
        AhaKeyWireFrameBuilder.subMacro,
        AhaKeyWireFrameBuilder.subDescription,
    ]
    public static let pictureBindOpcodes: Set<UInt8> = [
        AhaKeyWireFrameBuilder.cmdUpdateTaskPic,
        AhaKeyWireFrameBuilder.cmdUpdateTaskPicSet,
    ]
    public static let picturePrepareOpcodes: Set<UInt8> = [
        AhaKeyWireFrameBuilder.cmdPrepareWrite,
        AhaKeyWireFrameBuilder.cmdPrepareSessionWrite,
    ]
    public static let pictureDefaultBindOpcodes: Set<UInt8> = [
        AhaKeyWireFrameBuilder.cmdUpdatePic,
    ]

    public let fieldID: AhaKeyStudioFieldID
    public let command: Command
    public let opcode: UInt8?
    public let subtype: UInt8?
    public let logicalSet: UInt8?
    public let displayState: UInt8?
    public let physicalSlot: UInt8?
    public let geometry: AhaKeyRuntimeCompatibilityFingerprint.Geometry
    public let binding: Binding
    public let session: Session
    public let activation: AhaKeyRuntimeCompatibilityFingerprint.Activation
    public let resourceIdentity: AhaKeyRuntimePictureResourceIdentity?
    public let encodedFrameCount: UInt16?

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
        public let bindOpcode: UInt8

        public init(bindOpcode: UInt8) {
            self.bindOpcode = bindOpcode
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case bindOpcode
        }

        public init(from decoder: Decoder) throws {
            try AhaKeyRuntimeStrictCodingKey.rejectUnknown(
                in: decoder,
                allowed: Set(CodingKeys.allCases.map(\.rawValue)),
                error: .invalidCompatibilityFingerprint
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bindOpcode = try container.decode(UInt8.self, forKey: .bindOpcode)
        }
    }

    /// 单一协议映射：semantic command → 实际会发送的 opcode/必要 subtype。
    /// 无设备命令的字段（status/FPS/voice）明确为 nil，禁止用 enum 名反推或填 capability set。
    public static func expectedWire(for command: Command) -> (opcode: UInt8?, subtype: UInt8?) {
        switch command {
        case .keyShortcut:
            return (AhaKeyWireFrameBuilder.cmdUpdateCustomKey, AhaKeyWireFrameBuilder.subShortcut)
        case .keyMacro:
            return (AhaKeyWireFrameBuilder.cmdUpdateCustomKey, AhaKeyWireFrameBuilder.subMacro)
        case .keyDescription:
            return (AhaKeyWireFrameBuilder.cmdUpdateCustomKey, AhaKeyWireFrameBuilder.subDescription)
        case .keyVoicePreset, .screenStatus, .screenFramesPerSecond:
            return (nil, nil)
        case .lightMapping:
            return (AhaKeyWireFrameBuilder.cmdSetLightMapping, nil)
        case .lightBrightness:
            return (AhaKeyWireFrameBuilder.cmdSetBrightness, nil)
        case .setActiveSet:
            return (AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet, nil)
        case .picture(let picture):
            return (picture.bindOpcode, nil)
        }
    }

    public static func nonPicture(
        fieldID: AhaKeyStudioFieldID,
        command: Command
    ) throws -> AhaKeyRuntimeEmittedAction {
        let wire = expectedWire(for: command)
        return try AhaKeyRuntimeEmittedAction(
            fieldID: fieldID,
            command: command,
            opcode: wire.opcode,
            subtype: wire.subtype,
            logicalSet: nil,
            displayState: nil,
            physicalSlot: nil,
            geometry: .none,
            binding: .none,
            session: .none,
            activation: .none,
            resourceIdentity: nil,
            encodedFrameCount: nil
        )
    }

    public init(
        fieldID: AhaKeyStudioFieldID,
        command: Command,
        opcode: UInt8?,
        subtype: UInt8?,
        logicalSet: UInt8?,
        displayState: UInt8?,
        physicalSlot: UInt8?,
        geometry: AhaKeyRuntimeCompatibilityFingerprint.Geometry,
        binding: Binding,
        session: Session,
        activation: AhaKeyRuntimeCompatibilityFingerprint.Activation,
        resourceIdentity: AhaKeyRuntimePictureResourceIdentity? = nil,
        encodedFrameCount: UInt16? = nil
    ) throws {
        self.fieldID = fieldID
        self.command = command
        self.opcode = opcode
        self.subtype = subtype
        self.logicalSet = logicalSet
        self.displayState = displayState
        self.physicalSlot = physicalSlot
        self.geometry = geometry
        self.binding = binding
        self.session = session
        self.activation = activation
        self.resourceIdentity = resourceIdentity
        self.encodedFrameCount = encodedFrameCount
        try Self.validate(self)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fieldID, command, opcode, subtype
        case logicalSet, displayState, physicalSlot, geometry, binding, session, activation
        case resourceIdentity, encodedFrameCount
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
            opcode: container.decodeIfPresent(UInt8.self, forKey: .opcode),
            subtype: container.decodeIfPresent(UInt8.self, forKey: .subtype),
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
            ),
            resourceIdentity: container.decodeIfPresent(
                AhaKeyRuntimePictureResourceIdentity.self,
                forKey: .resourceIdentity
            ),
            encodedFrameCount: container.decodeIfPresent(UInt16.self, forKey: .encodedFrameCount)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fieldID, forKey: .fieldID)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(opcode, forKey: .opcode)
        try container.encodeIfPresent(subtype, forKey: .subtype)
        try container.encodeIfPresent(logicalSet, forKey: .logicalSet)
        try container.encodeIfPresent(displayState, forKey: .displayState)
        try container.encodeIfPresent(physicalSlot, forKey: .physicalSlot)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(binding, forKey: .binding)
        try container.encode(session, forKey: .session)
        try container.encode(activation, forKey: .activation)
        try container.encodeIfPresent(resourceIdentity, forKey: .resourceIdentity)
        try container.encodeIfPresent(encodedFrameCount, forKey: .encodedFrameCount)
    }

    static func validate(_ action: AhaKeyRuntimeEmittedAction) throws {
        try validateWire(action)
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

    private static func validateWire(_ action: AhaKeyRuntimeEmittedAction) throws {
        let expected = expectedWire(for: action.command)
        guard action.opcode == expected.opcode, action.subtype == expected.subtype else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        if let opcode = action.opcode {
            guard registeredOpcodes.contains(opcode) else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        }
        if let subtype = action.subtype {
            guard action.opcode == AhaKeyWireFrameBuilder.cmdUpdateCustomKey,
                  registeredKeySubtypes.contains(subtype) else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
        } else if action.opcode == AhaKeyWireFrameBuilder.cmdUpdateCustomKey {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
    }

    private static func validatePicture(
        _ action: AhaKeyRuntimeEmittedAction,
        picture: PictureSemantics
    ) throws {
        guard Self.pictureBindOpcodes.contains(picture.bindOpcode),
              action.opcode == picture.bindOpcode,
              action.subtype == nil else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
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
        case .prepareWrite, .sessionPrepare:
            break
        case .none:
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard case .screenTaskAsset(_, let fieldSet, let fieldState) = action.fieldID,
              UInt8(fieldSet) == logicalSet,
              fieldState.rawValue == displayState else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard action.resourceIdentity != nil,
              let encodedFrameCount = action.encodedFrameCount,
              encodedFrameCount > 0,
              encodedFrameCount <= UInt16(AhaKeyDeviceLayoutPolicy().framesPerSlot) else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        _ = physicalSlot
    }

    private static func validateSetActive(_ action: AhaKeyRuntimeEmittedAction) throws {
        guard action.activation == .setActiveSetOpcode else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        guard action.opcode == AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet, action.subtype == nil else {
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
              action.displayState == nil,
              action.resourceIdentity == nil,
              action.encodedFrameCount == nil else {
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
              action.activation == .none,
              action.resourceIdentity == nil,
              action.encodedFrameCount == nil else {
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

/// schema=2 页面执行的最小步骤：一个 identity 对应一组可持久化、可关联 ledger 的命令。
public struct AhaKeyRuntimePageExecutionStep: Equatable, Sendable {
    public let identity: AhaKeyRuntimeStepIdentifier
    public let program: [AhaKeyDeviceProgramStep]
    public let fieldID: AhaKeyStudioFieldID?
    public let resourceID: AhaKeyResourceIdentifier?

    /// 冻结 program 非空即设备写；local 步 program 为空，不以 identity 字符串判定。
    public var writesDevice: Bool { !program.isEmpty }
}

/// 只从冻结 fieldMask/actions/bindings/prepareStrategy 生成的本页程序。禁止 `base:mode:*`。
public struct AhaKeyRuntimePageExecutionPlan: Equatable, Sendable {
    public let steps: [AhaKeyRuntimePageExecutionStep]

    public var identities: [AhaKeyRuntimeStepIdentifier] {
        steps.map(\.identity)
    }

    public func step(for identity: AhaKeyRuntimeStepIdentifier) -> AhaKeyRuntimePageExecutionStep? {
        steps.first { $0.identity == identity }
    }
}

public struct AhaKeyRuntimePageExecutionPreconditions: Equatable, Sendable {
    public let deviceID: AhaKeyRuntimeDeviceID
    public let profile: AhaKeyOLEDCompatibilityProfile
    public let baseObjectFingerprint: AhaKeyRuntimeObjectFingerprint?

    public init(
        deviceID: AhaKeyRuntimeDeviceID,
        profile: AhaKeyOLEDCompatibilityProfile,
        baseObjectFingerprint: AhaKeyRuntimeObjectFingerprint?
    ) {
        self.deviceID = deviceID
        self.profile = profile
        self.baseObjectFingerprint = baseObjectFingerprint
    }
}

public enum AhaKeyRuntimePageExecutionPreflightError: Error, Equatable, Sendable {
    case missingPreconditions
    case deviceMismatch
    case compatibilityMismatch
    case baseObjectConflict
    case mappingRejected
}

public enum AhaKeyConfigurationCancelError: Error, Equatable, Sendable {
    case refusedWhileActive
}

extension AhaKeyRuntimePageSemantic {
    /// C3B：本页步骤的唯一事实源。chunk / bind / default-bind / activation / 本地字段均有稳定 identity。
    public static func executionPlan(
        package: AhaKeyConfigurationPackage,
        layout: AhaKeyDeviceLayoutPolicy = .init(),
        userSlotLimit: Int
    ) throws -> AhaKeyRuntimePageExecutionPlan {
        guard package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion,
              let contract = package.pageOperation else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        try contract.validate(matchingDevice: package.targetDeviceID, resources: package.resources)
        guard userSlotLimit > 0 else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        let frozen = try AhaKeyRuntimeCanonicalPageWrite.frozenValues(
            from: package.desiredConfiguration
        )
        let fingerprint = contract.compatibilityFingerprint
        let bindingsByField = Dictionary(
            uniqueKeysWithValues: contract.resourceBindings.map { ($0.fieldID, $0) }
        )
        var pictureBindings: [AhaKeyRuntimeFieldResourceBinding] = []
        var seenPictureFields = Set<AhaKeyStudioFieldID>()
        for action in fingerprint.actions {
            if case .picture = action.command {
                guard seenPictureFields.insert(action.fieldID).inserted,
                      let binding = bindingsByField[action.fieldID] else {
                    throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
                }
                pictureBindings.append(binding)
            }
        }
        var flashSlotByLogicalID: [AhaKeyResourceIdentifier: Int] = [:]
        for (index, binding) in pictureBindings.enumerated() {
            guard flashSlotByLogicalID[binding.logicalID] == nil else {
                throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
            }
            flashSlotByLogicalID[binding.logicalID] = index
        }

        var steps: [AhaKeyRuntimePageExecutionStep] = []
        for action in fingerprint.actions {
            guard case .picture = action.command,
                  let binding = bindingsByField[action.fieldID],
                  let flashSlot = flashSlotByLogicalID[binding.logicalID] else {
                continue
            }
            steps.append(contentsOf: try pictureSteps(
                action: action,
                binding: binding,
                fingerprint: fingerprint,
                frozen: frozen,
                layout: layout,
                userSlotLimit: userSlotLimit,
                flashSlot: flashSlot
            ))
        }

        if let defaultOpcode = fingerprint.defaultBindOpcode {
            guard defaultOpcode == AhaKeyWireFrameBuilder.cmdUpdatePic,
                  let first = pictureBindings.first,
                  let flashSlot = flashSlotByLogicalID[first.logicalID] else {
                throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
            }
            let frames = Int(first.encodedFrameCount)
            steps.append(
                AhaKeyRuntimePageExecutionStep(
                    identity: try AhaKeyRuntimeStepIdentifier("page:defaultBind"),
                    program: [
                        .bindDefaultPicture(
                            mode: modeSlot(of: first.fieldID),
                            startIndex: layout.startFrameIndex(slot: flashSlot, userRegionBase: 0),
                            frameCount: UInt16(frames),
                            intervalMs: intervalMs(field: first.fieldID, frozen: frozen, layout: layout)
                        ),
                    ],
                    fieldID: first.fieldID,
                    resourceID: first.logicalID
                )
            )
        }

        for action in fingerprint.actions {
            switch action.command {
            case .picture:
                continue
            case .setActiveSet:
                steps.append(try activationStep(action: action))
            case .keyShortcut, .keyMacro, .keyDescription, .lightBrightness:
                steps.append(try wireFieldStep(action: action, frozen: frozen))
            case .lightMapping:
                guard case .lightMapping(let mode, _) = action.fieldID else {
                    throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
                }
                if steps.contains(where: {
                    $0.identity.rawValue == "page:field:lightMapping:\(mode)"
                }) {
                    continue
                }
                steps.append(try lightMappingStep(mode: mode, fingerprint: fingerprint, fieldID: action.fieldID))
            case .keyVoicePreset, .screenStatus, .screenFramesPerSecond:
                steps.append(try localFieldStep(action: action))
            }
        }

        let identities = steps.map(\.identity)
        guard Set(identities).count == identities.count,
              identities.allSatisfy({ !$0.rawValue.hasPrefix("base:mode:") }),
              identities.allSatisfy({ !$0.rawValue.hasPrefix("resource:") }) else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        return AhaKeyRuntimePageExecutionPlan(steps: steps)
    }

    public static func evaluatePreflight(
        package: AhaKeyConfigurationPackage,
        preconditions: AhaKeyRuntimePageExecutionPreconditions?,
        hasDeviceWrites: Bool
    ) throws {
        guard let contract = package.pageOperation,
              package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        guard let preconditions else {
            throw AhaKeyRuntimePageExecutionPreflightError.missingPreconditions
        }
        guard preconditions.deviceID == package.targetDeviceID,
              preconditions.deviceID == contract.targetDeviceID else {
            throw AhaKeyRuntimePageExecutionPreflightError.deviceMismatch
        }
        let liveFamily = try AhaKeyRuntimeCompatibilityFingerprint.Family.make(preconditions.profile)
        guard liveFamily == contract.compatibilityFingerprint.family else {
            throw AhaKeyRuntimePageExecutionPreflightError.compatibilityMismatch
        }
        if !hasDeviceWrites {
            guard let live = preconditions.baseObjectFingerprint else {
                throw AhaKeyRuntimePageExecutionPreflightError.missingPreconditions
            }
            guard live == contract.baseObjectFingerprint else {
                throw AhaKeyRuntimePageExecutionPreflightError.baseObjectConflict
            }
        }
    }

    /// WAL 已确认步骤里是否包含冻结 plan 中的设备写。local 空 program 不算。
    public static func hasDeviceWrites(
        confirmed: [AhaKeyRuntimeStepIdentifier],
        plan: AhaKeyRuntimePageExecutionPlan?
    ) -> Bool {
        guard let plan else { return false }
        return confirmed.contains { plan.step(for: $0)?.writesDevice == true }
    }

    /// 完整 field 设备动作才密封；chunk 中间进度不得提前密封 picture field。
    public static func sealsCompleteField(_ step: AhaKeyRuntimePageExecutionStep) -> Bool {
        guard step.writesDevice, step.fieldID != nil else { return false }
        return !step.identity.rawValue.hasPrefix("page:chunk:")
    }

    /// bind 才密封 resource；chunk 只是资源中间进度。
    public static func sealsCompleteResource(_ step: AhaKeyRuntimePageExecutionStep) -> Bool {
        guard step.writesDevice, step.resourceID != nil else { return false }
        return step.identity.rawValue.hasPrefix("page:bind:")
    }

    /// 冻结 ledger/plan 是投影唯一事实源；confirmed steps 只选择已完成的完整动作。
    public static func confirmationProjection(
        package: AhaKeyConfigurationPackage,
        confirmed: [AhaKeyRuntimeStepIdentifier],
        plan: AhaKeyRuntimePageExecutionPlan
    ) -> AhaKeyRuntimePageConfirmationProjection {
        let confirmedSet = Set(confirmed)
        var fields = Set<AhaKeyStudioFieldID>()
        var resources = Set<AhaKeyRuntimeConfirmationLedger.Entry.ResourceIdentity>()
        let bindings = package.pageOperation?.resourceBindings ?? []
        for step in plan.steps where confirmedSet.contains(step.identity) {
            if sealsCompleteField(step), let field = step.fieldID {
                fields.insert(field)
            }
            if sealsCompleteResource(step), let logical = step.resourceID,
               let binding = bindings.first(where: { $0.logicalID == logical }) {
                resources.insert(
                    AhaKeyRuntimeConfirmationLedger.Entry.ResourceIdentity(
                        logicalID: logical,
                        sha256: binding.sha256
                    )
                )
            }
        }
        let ledger = package.pageOperation?.confirmationLedger
        let residualFields = (ledger?.fieldIDs ?? []).subtracting(fields).sorted()
        let residualResources = (ledger?.entries.compactMap(\.resourceIdentity) ?? [])
            .filter { !resources.contains($0) }
            .sorted { lhs, rhs in
                if lhs.logicalID.rawValue != rhs.logicalID.rawValue {
                    return lhs.logicalID.rawValue < rhs.logicalID.rawValue
                }
                return lhs.sha256.rawValue < rhs.sha256.rawValue
            }
        return AhaKeyRuntimePageConfirmationProjection(
            confirmedFieldIDs: fields,
            confirmedResources: resources,
            residual: AhaKeyRuntimePageResidual(
                fieldIDs: residualFields,
                resources: residualResources
            )
        )
    }

    static func baselineValue(
        for field: AhaKeyStudioFieldID,
        package: AhaKeyConfigurationPackage
    ) throws -> AhaKeyRuntimeBaselineValue {
        let frozen = try AhaKeyRuntimeCanonicalPageWrite.frozenValues(
            from: package.desiredConfiguration
        )
        let bindings = package.pageOperation?.resourceBindings ?? []
        switch frozen.fieldValues[field] {
        case .text(let text):
            return .text(text)
        case .optionalText(let text):
            return .optionalText(text)
        case .integer(let number):
            return .integer(number)
        case .keyAction(let action):
            return .keyAction(action)
        case .taskAsset(let fps, let frames):
            guard let match = bindings.first(where: { $0.fieldID == field }) else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            return .taskAsset(
                sha256: match.sha256.rawValue,
                byteCount: match.byteCount,
                mediaType: match.mediaType.rawValue,
                framesPerSecond: fps,
                declaredFrameCount: frames
            )
        case nil:
            if case .screenStatusLine = field, let line = frozen.statusLine {
                return .text(line)
            }
            if case .screenFramesPerSecond = field, let fps = frozen.framesPerSecond {
                return .integer(fps)
            }
            throw AhaKeyRuntimeContractError.pageOperationIncomplete
        }
    }

    static func lightMappingRows(
        from plan: AhaKeyStudioScopedWritePlan
    ) throws -> [AhaKeyRuntimeLightMappingRow] {
        let modes = Set(plan.fieldMask.compactMap { id -> UInt8? in
            if case .lightMapping(let mode, _) = id { return mode }
            return nil
        })
        guard modes == Set(plan.lightMappingRows.keys) else {
            throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
        }
        return try modes.sorted().map { mode in
            guard let effects = plan.lightMappingRows[mode], effects.count == 9 else {
                throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
            }
            for fieldID in plan.fieldMask {
                guard case .lightMapping(let fieldMode, let state) = fieldID, fieldMode == mode else {
                    continue
                }
                guard Int(state) < 9,
                      case .text(let effect) = plan.values[fieldID],
                      effects[Int(state)] == AhaKeyConfigurationStepMapper.firmwareEffectIndex(effect) else {
                    throw AhaKeyRuntimeContractError.invalidCompatibilityFingerprint
                }
            }
            return try AhaKeyRuntimeLightMappingRow(mode: mode, effects: effects)
        }
    }

    private static func pictureSteps(
        action: AhaKeyRuntimeEmittedAction,
        binding: AhaKeyRuntimeFieldResourceBinding,
        fingerprint: AhaKeyRuntimeCompatibilityFingerprint,
        frozen: AhaKeyRuntimeFrozenPageValues,
        layout: AhaKeyDeviceLayoutPolicy,
        userSlotLimit: Int,
        flashSlot: Int
    ) throws -> [AhaKeyRuntimePageExecutionStep] {
        guard let strategy = fingerprint.prepareStrategy,
              let frames = action.encodedFrameCount.map(Int.init),
              frames == Int(binding.encodedFrameCount) else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        let expectedPrepares = try strategy.prepareCount(encodedFrameCount: frames, layout: layout)
        let usesSession = strategy.opcode == AhaKeyWireFrameBuilder.cmdPrepareSessionWrite
        guard strategy.opcode == AhaKeyWireFrameBuilder.cmdPrepareWrite
                || strategy.opcode == AhaKeyWireFrameBuilder.cmdPrepareSessionWrite,
              let upload = AhaKeyConfigurationStepMapper.resourceUploadProgram(
                digest: binding.sha256,
                slotIndex: flashSlot,
                encodedFrameCount: frames,
                usesSessionUpload: usesSession,
                userSlotLimit: userSlotLimit,
                layout: layout
              ),
              upload.count == expectedPrepares * 2 else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        var chunkSteps: [AhaKeyRuntimePageExecutionStep] = []
        for index in 0..<expectedPrepares {
            let pair = Array(upload[(index * 2)..<(index * 2 + 2)])
            guard case .prepareWrite(let sessionID, _, _) = pair[0],
                  case .writeResourceChunk = pair[1],
                  (sessionID != nil) == usesSession else {
                throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
            }
            chunkSteps.append(
                AhaKeyRuntimePageExecutionStep(
                    identity: try AhaKeyRuntimeStepIdentifier(
                        "page:chunk:\(binding.logicalID.rawValue):\(index)"
                    ),
                    program: pair,
                    fieldID: action.fieldID,
                    resourceID: binding.logicalID
                )
            )
        }
        chunkSteps.append(try bindStep(
            action: action,
            binding: binding,
            frozen: frozen,
            layout: layout,
            flashSlot: flashSlot
        ))
        return chunkSteps
    }

    private static func bindStep(
        action: AhaKeyRuntimeEmittedAction,
        binding: AhaKeyRuntimeFieldResourceBinding,
        frozen: AhaKeyRuntimeFrozenPageValues,
        layout: AhaKeyDeviceLayoutPolicy,
        flashSlot: Int
    ) throws -> AhaKeyRuntimePageExecutionStep {
        guard let frames = action.encodedFrameCount,
              let physical = action.physicalSlot,
              case .screenTaskAsset(let mode, _, let state) = action.fieldID else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        let start = layout.startFrameIndex(slot: flashSlot, userRegionBase: 0)
        let interval = intervalMs(field: action.fieldID, frozen: frozen, layout: layout)
        let program: [AhaKeyDeviceProgramStep]
        switch action.binding {
        case .legacyTask:
            program = [
                .bindLegacyTaskPicture(
                    mode: mode,
                    state: state.rawValue,
                    startIndex: start,
                    frameCount: frames,
                    intervalMs: interval
                ),
            ]
        case .taskSet:
            program = [
                .bindTaskPicture(
                    mode: mode,
                    set: physical,
                    state: state.rawValue,
                    startIndex: start,
                    frameCount: frames,
                    intervalMs: interval
                ),
            ]
        default:
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        return AhaKeyRuntimePageExecutionStep(
            identity: try AhaKeyRuntimeStepIdentifier("page:bind:\(action.fieldID.canonicalToken)"),
            program: program,
            fieldID: action.fieldID,
            resourceID: binding.logicalID
        )
    }

    private static func activationStep(
        action: AhaKeyRuntimeEmittedAction
    ) throws -> AhaKeyRuntimePageExecutionStep {
        guard action.opcode == AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet,
              let physical = action.physicalSlot,
              case .screenActiveSet(let mode) = action.fieldID else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        return AhaKeyRuntimePageExecutionStep(
            identity: try AhaKeyRuntimeStepIdentifier("page:activate:\(action.fieldID.canonicalToken)"),
            program: [.setActiveTaskPictureSet(mode: mode, set: physical)],
            fieldID: action.fieldID,
            resourceID: nil
        )
    }

    private static func wireFieldStep(
        action: AhaKeyRuntimeEmittedAction,
        frozen: AhaKeyRuntimeFrozenPageValues
    ) throws -> AhaKeyRuntimePageExecutionStep {
        let program: [AhaKeyDeviceProgramStep]
        switch (action.command, action.fieldID) {
        case (.keyShortcut, .keyAction(let mode, let role)):
            guard case .keyAction(.shortcut(let shortcut)) = frozen.fieldValues[action.fieldID] else {
                throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
            }
            program = [
                .setKeyShortcut(
                    mode: mode,
                    keyIndex: role.rawValue,
                    hidCodes: AhaKeyConfigurationStepMapper.shortcutHidCodes(shortcut)
                ),
            ]
        case (.keyMacro, .keyAction(let mode, let role)):
            guard case .keyAction(.macro(let macroSteps)) = frozen.fieldValues[action.fieldID] else {
                throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
            }
            program = [
                .setKeyMacro(
                    mode: mode,
                    keyIndex: role.rawValue,
                    pairs: macroSteps.flatMap { [$0.action, $0.param] }
                ),
            ]
        case (.keyDescription, .keyDescription(let mode, let role)):
            guard case .text(let text) = frozen.fieldValues[action.fieldID] else {
                throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
            }
            program = [.setKeyDescription(mode: mode, keyIndex: role.rawValue, text: text)]
        case (.lightBrightness, .lightBrightness(let mode)):
            guard case .integer(let brightness) = frozen.fieldValues[action.fieldID],
                  (1...100).contains(brightness) else {
                throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
            }
            _ = mode
            program = [.setBrightness(UInt8(brightness))]
        default:
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        return AhaKeyRuntimePageExecutionStep(
            identity: try AhaKeyRuntimeStepIdentifier("page:field:\(action.fieldID.canonicalToken)"),
            program: program,
            fieldID: action.fieldID,
            resourceID: nil
        )
    }

    private static func lightMappingStep(
        mode: UInt8,
        fingerprint: AhaKeyRuntimeCompatibilityFingerprint,
        fieldID: AhaKeyStudioFieldID
    ) throws -> AhaKeyRuntimePageExecutionStep {
        guard let row = fingerprint.lightMappingRows.first(where: { $0.mode == mode }),
              row.effects.count == 9 else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        return AhaKeyRuntimePageExecutionStep(
            identity: try AhaKeyRuntimeStepIdentifier("page:field:lightMapping:\(mode)"),
            program: [.setLightMapping(mode: mode, effects: row.effects)],
            fieldID: fieldID,
            resourceID: nil
        )
    }

    private static func localFieldStep(
        action: AhaKeyRuntimeEmittedAction
    ) throws -> AhaKeyRuntimePageExecutionStep {
        guard action.opcode == nil, action.subtype == nil else {
            throw AhaKeyRuntimePageExecutionPreflightError.mappingRejected
        }
        return AhaKeyRuntimePageExecutionStep(
            identity: try AhaKeyRuntimeStepIdentifier("page:local:\(action.fieldID.canonicalToken)"),
            program: [],
            fieldID: action.fieldID,
            resourceID: nil
        )
    }

    private static func intervalMs(
        field: AhaKeyStudioFieldID,
        frozen: AhaKeyRuntimeFrozenPageValues,
        layout: AhaKeyDeviceLayoutPolicy
    ) -> UInt16 {
        let fps: Int?
        if case .taskAsset(let assetFPS, _) = frozen.fieldValues[field] {
            fps = assetFPS
        } else {
            fps = frozen.framesPerSecond
        }
        guard let fps, fps > 0 else { return layout.defaultFrameIntervalFloor }
        return max(layout.defaultFrameIntervalFloor, UInt16(1000 / fps))
    }

    private static func modeSlot(of field: AhaKeyStudioFieldID) -> UInt8 {
        switch field {
        case .screenTaskAsset(let slot, _, _),
             .screenActiveSet(let slot),
             .screenStatusLine(let slot),
             .screenFramesPerSecond(let slot),
             .keyAction(let slot, _),
             .keyDescription(let slot, _),
             .keyVoicePreset(let slot, _),
             .lightBrightness(let slot),
             .lightMapping(let slot, _):
            return slot
        case .leverMacro, .powerAction:
            return 0
        }
    }
}