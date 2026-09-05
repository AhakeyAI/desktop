import Foundation

public struct AhaKeyRuntimeInterfaceVersion: Codable, Equatable, Hashable, Sendable {
    public static let current = Self(major: 1, minor: 1)

    public let major: UInt16
    public let minor: UInt16

    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }
}

public struct AhaKeyRuntimeVersion: Codable, Equatable, Hashable, Sendable {
    public static let development = Self(
        major: 0,
        minor: 1,
        patch: 0,
        buildMetadata: "development"
    )

    public let major: UInt16
    public let minor: UInt16
    public let patch: UInt16
    public let buildMetadata: String?

    public init(major: UInt16, minor: UInt16, patch: UInt16, buildMetadata: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.buildMetadata = buildMetadata
    }
}

public struct AhaKeyRuntimeEventSequence: Codable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct AhaKeyRuntimeOperationID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct AhaKeyRuntimeDeviceID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty, normalized != "—" else {
            throw AhaKeyRuntimeContractError.invalidDeviceIdentifier
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

public struct AhaKeyConfigurationRevision: Codable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct AhaKeyRuntimeSessionGeneration: Codable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct AhaKeyRuntimeTransportGeneration: Codable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 权威对象的 typed 版本：连接 identity + 单调 canonical source + 进程 writer lease。
/// `writerLease == nil` 仅表示尚未被任何进程投影写入（schema=1 seed）。
public struct AhaKeyRuntimeAuthoritativeVersion: Codable, Equatable, Hashable, Sendable {
    public let deviceID: AhaKeyRuntimeDeviceID
    public let writerLease: AhaKeyRuntimeAuthoritativeWriterLease?
    public let sessionGeneration: AhaKeyRuntimeSessionGeneration
    public let transportGeneration: AhaKeyRuntimeTransportGeneration
    public let sourceRevision: AhaKeyRuntimeAuthoritativeSourceRevision
    public let sourceDigest: AhaKeyRuntimeObjectFingerprint

    public init(
        deviceID: AhaKeyRuntimeDeviceID,
        writerLease: AhaKeyRuntimeAuthoritativeWriterLease?,
        sessionGeneration: AhaKeyRuntimeSessionGeneration,
        transportGeneration: AhaKeyRuntimeTransportGeneration,
        sourceRevision: AhaKeyRuntimeAuthoritativeSourceRevision,
        sourceDigest: AhaKeyRuntimeObjectFingerprint
    ) {
        self.deviceID = deviceID
        self.writerLease = writerLease
        self.sessionGeneration = sessionGeneration
        self.transportGeneration = transportGeneration
        self.sourceRevision = sourceRevision
        self.sourceDigest = sourceDigest
    }

    public func matches(_ connection: AhaKeyRuntimeDeviceSnapshot) -> Bool {
        matches(
            deviceID: connection.id,
            sessionGeneration: connection.sessionGeneration,
            transportGeneration: connection.transportGeneration
        )
    }

    public func matches(
        deviceID: AhaKeyRuntimeDeviceID,
        sessionGeneration: AhaKeyRuntimeSessionGeneration,
        transportGeneration: AhaKeyRuntimeTransportGeneration
    ) -> Bool {
        self.deviceID == deviceID
            && self.sessionGeneration == sessionGeneration
            && self.transportGeneration == transportGeneration
    }
}

/// 进程实例级 durable writer lease。从 1 起，不允许 sentinel 0。
public struct AhaKeyRuntimeAuthoritativeWriterLease: Codable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) throws {
        guard rawValue > 0 else {
            throw AhaKeyRuntimeContractError.invalidAuthoritativeWriterLease
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(UInt64.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Canonical source 单调版本。从 1 起，不允许 sentinel 0。
public struct AhaKeyRuntimeAuthoritativeSourceRevision: Codable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public static let first = try! AhaKeyRuntimeAuthoritativeSourceRevision(1)

    public init(_ rawValue: UInt64) throws {
        guard rawValue > 0 else {
            throw AhaKeyRuntimeContractError.invalidAuthoritativeSourceRevision
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(UInt64.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public func advanced() throws -> AhaKeyRuntimeAuthoritativeSourceRevision {
        let next = rawValue + 1
        guard next > rawValue else {
            throw AhaKeyRuntimeContractError.invalidAuthoritativeSourceRevision
        }
        return try AhaKeyRuntimeAuthoritativeSourceRevision(next)
    }
}

public enum AhaKeyRuntimeLifecycleState: String, Codable, Equatable, Sendable {
    case starting
    case running
    case stopping
    case unavailable
}

public enum AhaKeyRuntimeDeviceProtocolState: String, Codable, Equatable, Sendable {
    case disconnected
    case probing
    case currentReady
    case legacyDenied
    case restricted
    case failed
}

public enum AhaKeyRuntimeTransport: String, Codable, Equatable, Sendable {
    case none
    case usb
    case bluetooth
}

public struct AhaKeyRuntimeDeviceCapability: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public static let configurationV4 = Self(rawValue: "configuration-v4")
    public static let usbConfiguration = Self(rawValue: "usb-configuration")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AhaKeyRuntimePercentage: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(_ rawValue: Int) throws {
        guard (0 ... 100).contains(rawValue) else {
            throw AhaKeyRuntimeContractError.invalidPercentage(rawValue)
        }
        self.rawValue = UInt8(rawValue)
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AhaKeyRuntimeModeIndex: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }
}

public struct AhaKeyRuntimeLightMode: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }
}

public struct AhaKeyRuntimeTaskPictureSetIndex: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }
}

/// Stable device-state projection exposed to Studio. Diagnostic telemetry such as RSSI
/// intentionally lives outside this snapshot so routine sampling cannot refresh hidden UI.
public struct AhaKeyRuntimeDeviceState: Codable, Equatable, Sendable {
    public let batteryLevel: AhaKeyRuntimePercentage?
    public let workMode: AhaKeyRuntimeModeIndex?
    public let lightMode: AhaKeyRuntimeLightMode?
    public let leverPosition: AhaKeyRuntimeLeverPosition?
    public let brightness: AhaKeyRuntimePercentage?
    public let firmwareVersion: String?
    public let activeTaskPictureSets: [AhaKeyRuntimeModeIndex: AhaKeyRuntimeTaskPictureSetIndex]

    public init(
        batteryLevel: AhaKeyRuntimePercentage? = nil,
        workMode: AhaKeyRuntimeModeIndex? = nil,
        lightMode: AhaKeyRuntimeLightMode? = nil,
        leverPosition: AhaKeyRuntimeLeverPosition? = nil,
        brightness: AhaKeyRuntimePercentage? = nil,
        firmwareVersion: String? = nil,
        activeTaskPictureSets: [AhaKeyRuntimeModeIndex: AhaKeyRuntimeTaskPictureSetIndex] = [:]
    ) {
        self.batteryLevel = batteryLevel
        self.workMode = workMode
        self.lightMode = lightMode
        self.leverPosition = leverPosition
        self.brightness = brightness
        self.firmwareVersion = firmwareVersion
        self.activeTaskPictureSets = activeTaskPictureSets
    }
}

public struct AhaKeyRuntimeDeviceSnapshot: Codable, Equatable, Sendable {
    public let id: AhaKeyRuntimeDeviceID
    public let displayName: String
    public let protocolState: AhaKeyRuntimeDeviceProtocolState
    public let preferredTransport: AhaKeyRuntimeTransport
    public let usbAttached: Bool
    public let bluetoothConnected: Bool
    public let capabilities: Set<AhaKeyRuntimeDeviceCapability>
    public let sessionGeneration: AhaKeyRuntimeSessionGeneration
    public let transportGeneration: AhaKeyRuntimeTransportGeneration
    public let state: AhaKeyRuntimeDeviceState
    /// 设备读回 / 权威对象快照的 canonical content。缺省 nil；换代时带新字节。
    public let authoritativeObject: Data?

    public init(
        id: AhaKeyRuntimeDeviceID,
        displayName: String,
        protocolState: AhaKeyRuntimeDeviceProtocolState,
        preferredTransport: AhaKeyRuntimeTransport,
        usbAttached: Bool,
        bluetoothConnected: Bool,
        capabilities: Set<AhaKeyRuntimeDeviceCapability> = [],
        sessionGeneration: AhaKeyRuntimeSessionGeneration = .init(0),
        transportGeneration: AhaKeyRuntimeTransportGeneration = .init(0),
        state: AhaKeyRuntimeDeviceState = .init(),
        authoritativeObject: Data? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.protocolState = protocolState
        self.preferredTransport = preferredTransport
        self.usbAttached = usbAttached
        self.bluetoothConnected = bluetoothConnected
        self.capabilities = capabilities
        self.sessionGeneration = sessionGeneration
        self.transportGeneration = transportGeneration
        self.state = state
        self.authoritativeObject = authoritativeObject
    }
}

public enum AhaKeyRuntimePermission: String, Codable, Equatable, Hashable, Sendable {
    case microphone
    case speechRecognition
    case accessibility
    case inputMonitoring
}

public enum AhaKeyRuntimePermissionState: String, Codable, Equatable, Sendable {
    case notRequired
    case notDetermined
    case authorized
    case denied
    case restricted
}

public struct AhaKeyRuntimePermissionSnapshot: Codable, Equatable, Sendable {
    public let states: [AhaKeyRuntimePermission: AhaKeyRuntimePermissionState]

    public init(states: [AhaKeyRuntimePermission: AhaKeyRuntimePermissionState] = [:]) {
        self.states = states
    }

    public subscript(permission: AhaKeyRuntimePermission) -> AhaKeyRuntimePermissionState? {
        states[permission]
    }
}

public enum AhaKeyRuntimeKeepAliveReason: String, Codable, Equatable, Hashable, Sendable {
    case ahaType
    case aiHooks
    case dynamicDeviceState
    case sessionRouting
    case powerProtection
    case temporaryDiagnostics
    case activeOperation
    case studioConnection
}

public enum AhaKeyRuntimeShortcutModifier: String, Codable, Equatable, Hashable, Sendable {
    case control
    case option
    case shift
    case command
    case function
}

public struct AhaKeyRuntimeShortcut: Codable, Equatable, Sendable {
    public static let f18 = Self(hidUsage: 0x6D)

    public let hidUsage: UInt16
    public let modifiers: Set<AhaKeyRuntimeShortcutModifier>

    public init(hidUsage: UInt16, modifiers: Set<AhaKeyRuntimeShortcutModifier> = []) {
        self.hidUsage = hidUsage
        self.modifiers = modifiers
    }
}

public struct AhaKeyRuntimeAhaTypePolicy: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var trigger: AhaKeyRuntimeShortcut

    public init(enabled: Bool = false, trigger: AhaKeyRuntimeShortcut = .f18) {
        self.enabled = enabled
        self.trigger = trigger
    }
}

public struct AhaKeyRuntimeAITool: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public static let claude = Self(rawValue: "claude")
    public static let codex = Self(rawValue: "codex")
    public static let cursor = Self(rawValue: "cursor")
    public static let kimi = Self(rawValue: "kimi")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum AhaKeyRuntimeLeverPosition: String, Codable, Equatable, Sendable {
    case up
    case middle
    case down
}

public enum AhaKeyRuntimeApprovalPolicy: Codable, Equatable, Sendable {
    case manual
    case followLever(automaticPosition: AhaKeyRuntimeLeverPosition)

    public var requiresDeviceConnection: Bool {
        if case .followLever = self { return true }
        return false
    }
}

public struct AhaKeyRuntimeAIHookPolicy: Codable, Equatable, Sendable {
    public var enabledTools: Set<AhaKeyRuntimeAITool>
    public var approvalPolicy: AhaKeyRuntimeApprovalPolicy

    public init(
        enabledTools: Set<AhaKeyRuntimeAITool> = [],
        approvalPolicy: AhaKeyRuntimeApprovalPolicy = .manual
    ) {
        self.enabledTools = enabledTools
        self.approvalPolicy = approvalPolicy
    }

    public var isEnabled: Bool { !enabledTools.isEmpty }
}

public enum AhaKeyRuntimeVoiceRoutingPolicy: String, Codable, Equatable, Sendable {
    case foreground
    case latestActionableSession
}

public struct AhaKeyRuntimeDevicePresentationPolicy: Codable, Equatable, Sendable {
    public var ledEnabled: Bool
    public var oledEnabled: Bool

    public init(ledEnabled: Bool = false, oledEnabled: Bool = false) {
        self.ledEnabled = ledEnabled
        self.oledEnabled = oledEnabled
    }

    public var isEnabled: Bool { ledEnabled || oledEnabled }
}

public struct AhaKeyRuntimeDiagnosticPolicy: Codable, Equatable, Sendable {
    public var verboseProtocolLoggingUntil: Date?

    public init(verboseProtocolLoggingUntil: Date? = nil) {
        self.verboseProtocolLoggingUntil = verboseProtocolLoggingUntil
    }
}

public struct AhaKeyRuntimePolicy: Codable, Equatable, Sendable {
    public var ahaType: AhaKeyRuntimeAhaTypePolicy
    public var aiHooks: AhaKeyRuntimeAIHookPolicy
    public var voiceRouting: AhaKeyRuntimeVoiceRoutingPolicy
    public var devicePresentation: AhaKeyRuntimeDevicePresentationPolicy
    public var powerProtectionEnabled: Bool
    public var diagnostics: AhaKeyRuntimeDiagnosticPolicy

    public init(
        ahaType: AhaKeyRuntimeAhaTypePolicy = .init(),
        aiHooks: AhaKeyRuntimeAIHookPolicy = .init(),
        voiceRouting: AhaKeyRuntimeVoiceRoutingPolicy = .foreground,
        devicePresentation: AhaKeyRuntimeDevicePresentationPolicy = .init(),
        powerProtectionEnabled: Bool = false,
        diagnostics: AhaKeyRuntimeDiagnosticPolicy = .init()
    ) {
        self.ahaType = ahaType
        self.aiHooks = aiHooks
        self.voiceRouting = voiceRouting
        self.devicePresentation = devicePresentation
        self.powerProtectionEnabled = powerProtectionEnabled
        self.diagnostics = diagnostics
    }

    public var requiresPersistentRuntime: Bool { !keepAliveReasons.isEmpty }

    public var requiresDeviceConnection: Bool {
        devicePresentation.isEnabled
            || (aiHooks.isEnabled && aiHooks.approvalPolicy.requiresDeviceConnection)
            || diagnostics.verboseProtocolLoggingUntil != nil
    }

    public var keepAliveReasons: Set<AhaKeyRuntimeKeepAliveReason> {
        var reasons: Set<AhaKeyRuntimeKeepAliveReason> = []
        if ahaType.enabled { reasons.insert(.ahaType) }
        if aiHooks.isEnabled { reasons.insert(.aiHooks) }
        if devicePresentation.isEnabled { reasons.insert(.dynamicDeviceState) }
        if voiceRouting == .latestActionableSession { reasons.insert(.sessionRouting) }
        if powerProtectionEnabled { reasons.insert(.powerProtection) }
        if diagnostics.verboseProtocolLoggingUntil != nil { reasons.insert(.temporaryDiagnostics) }
        return reasons
    }
}

public struct AhaKeyResourceIdentifier: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.contains("/"),
              !normalized.contains("\\"),
              normalized != ".",
              normalized != ".." else {
            throw AhaKeyRuntimeContractError.invalidResourceIdentifier
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

public struct AhaKeySHA256Digest: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.lowercased()
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard normalized.count == 64,
              normalized.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw AhaKeyRuntimeContractError.invalidResourceDigest
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

public struct AhaKeyMediaType: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AhaKeyRuntimeContractError.invalidMediaType
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

public struct AhaKeyConfigurationResource: Codable, Equatable, Hashable, Sendable {
    public let logicalIdentifier: AhaKeyResourceIdentifier
    public let sha256: AhaKeySHA256Digest
    public let byteCount: UInt64
    public let mediaType: AhaKeyMediaType

    public init(
        logicalIdentifier: String,
        sha256: String,
        byteCount: UInt64,
        mediaType: String
    ) throws {
        self.logicalIdentifier = try AhaKeyResourceIdentifier(logicalIdentifier)
        self.sha256 = try AhaKeySHA256Digest(sha256)
        self.byteCount = byteCount
        self.mediaType = try AhaKeyMediaType(mediaType)
    }

    public init(
        logicalIdentifier: AhaKeyResourceIdentifier,
        sha256: AhaKeySHA256Digest,
        byteCount: UInt64,
        mediaType: AhaKeyMediaType
    ) {
        self.logicalIdentifier = logicalIdentifier
        self.sha256 = sha256
        self.byteCount = byteCount
        self.mediaType = mediaType
    }

    private enum CodingKeys: String, CodingKey {
        case logicalIdentifier, sha256, byteCount, mediaType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            logicalIdentifier: try container.decode(AhaKeyResourceIdentifier.self, forKey: .logicalIdentifier),
            sha256: try container.decode(AhaKeySHA256Digest.self, forKey: .sha256),
            byteCount: try container.decode(UInt64.self, forKey: .byteCount),
            mediaType: try container.decode(AhaKeyMediaType.self, forKey: .mediaType)
        )
    }
}

public struct AhaKeyConfigurationPackage: Codable, Equatable, Sendable {
    public static let currentSchemaVersion: UInt16 = 1
    public static let pageScopedSchemaVersion: UInt16 = 2
    /// handshake 与 snapshot 共用的 schema 广告，禁止两处各写一份字面量。
    public static let advertisedSchemaVersions: Set<UInt16> = [
        currentSchemaVersion,
        pageScopedSchemaVersion,
    ]

    public let schemaVersion: UInt16
    public let operationID: AhaKeyRuntimeOperationID
    public let targetDeviceID: AhaKeyRuntimeDeviceID
    public let baseRevision: AhaKeyConfigurationRevision
    /// Canonical, versioned representation of the complete desired configuration.
    /// It is decoded and planned by Runtime; callers never send transport commands or physical slots.
    public let desiredConfiguration: Data
    public let resources: [AhaKeyConfigurationResource]
    /// C3A：页面写的稳定 contract。旧 schema=1 记录必须为 nil；schema=2 必须完整。
    public let pageOperation: AhaKeyRuntimePageOperationContract?

    public init(
        schemaVersion: UInt16 = Self.currentSchemaVersion,
        operationID: AhaKeyRuntimeOperationID = .init(),
        targetDeviceID: AhaKeyRuntimeDeviceID,
        baseRevision: AhaKeyConfigurationRevision,
        desiredConfiguration: Data,
        resources: [AhaKeyConfigurationResource],
        pageOperation: AhaKeyRuntimePageOperationContract? = nil
    ) throws {
        guard !desiredConfiguration.isEmpty else {
            throw AhaKeyRuntimeContractError.emptyDesiredConfiguration
        }
        guard Set(resources.map(\.logicalIdentifier)).count == resources.count else {
            throw AhaKeyRuntimeContractError.duplicateResourceIdentifier
        }
        switch schemaVersion {
        case Self.pageScopedSchemaVersion:
            guard let pageOperation else {
                throw AhaKeyRuntimeContractError.pageOperationIncomplete
            }
            try pageOperation.validate(matchingDevice: targetDeviceID, resources: resources)
        case Self.currentSchemaVersion:
            guard pageOperation == nil else {
                throw AhaKeyRuntimeContractError.invalidSchemaVersion
            }
        default:
            throw AhaKeyRuntimeContractError.unsupportedConfigurationSchema(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.targetDeviceID = targetDeviceID
        self.baseRevision = baseRevision
        self.desiredConfiguration = desiredConfiguration
        self.resources = resources
        self.pageOperation = pageOperation
    }

    public var isPageScoped: Bool { pageOperation != nil }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, operationID, targetDeviceID, baseRevision, desiredConfiguration, resources
        case pageOperation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(UInt16.self, forKey: .schemaVersion),
            operationID: container.decode(AhaKeyRuntimeOperationID.self, forKey: .operationID),
            targetDeviceID: container.decode(AhaKeyRuntimeDeviceID.self, forKey: .targetDeviceID),
            baseRevision: container.decode(AhaKeyConfigurationRevision.self, forKey: .baseRevision),
            desiredConfiguration: container.decode(Data.self, forKey: .desiredConfiguration),
            resources: container.decode([AhaKeyConfigurationResource].self, forKey: .resources),
            pageOperation: container.decodeIfPresent(AhaKeyRuntimePageOperationContract.self, forKey: .pageOperation)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(operationID, forKey: .operationID)
        try container.encode(targetDeviceID, forKey: .targetDeviceID)
        try container.encode(baseRevision, forKey: .baseRevision)
        try container.encode(desiredConfiguration, forKey: .desiredConfiguration)
        try container.encode(resources, forKey: .resources)
        try container.encodeIfPresent(pageOperation, forKey: .pageOperation)
    }
}

public struct AhaKeyRuntimeEventCode: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    /// 设备拒绝配置命令 / 0x81 ACK。
    public static let configurationDeviceRejected = must("configuration.device-rejected")
    /// 配置命令 ACK 超时。
    public static let configurationCommandTimeout = must("configuration.command-timeout")
    /// 传输断开。
    public static let configurationDisconnected = must("configuration.disconnected")
    /// 资源缺失或无法读取。
    public static let configurationResourceMissing = must("configuration.resource-missing")
    /// 编码失败（包体损坏或图片编码）。
    public static let configurationEncodingFailed = must("configuration.encoding-failed")
    /// planner / 步骤映射拒绝。
    public static let configurationPlanRejected = must("configuration.plan-rejected")
    /// schema=2 开始前 device / compatibility / base CAS 冲突，零写入 fail-closed。
    public static let configurationPreflightConflict = must("configuration.preflight-conflict")
    /// 线协议帧格式错误。
    public static let configurationMalformedFrame = must("configuration.malformed-frame")

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 128 else {
            throw AhaKeyRuntimeContractError.invalidEventCode
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

    private static func must(_ rawValue: String) -> AhaKeyRuntimeEventCode {
        do {
            return try AhaKeyRuntimeEventCode(rawValue)
        } catch {
            preconditionFailure("invalid built-in event code \(rawValue)")
        }
    }
}

/// C-3：可选结构化失败上下文。字段缺失解码为 nil；全 nil 视为无 context。
/// wire/WAL 只承载稳定标识，禁止本地化文本与自由格式日志。
public struct AhaKeyRuntimeOperationFailureContext: Codable, Equatable, Sendable {
    public let failedStepID: AhaKeyRuntimeStepIdentifier?
    public let opcode: UInt8?
    public let deviceStatus: UInt8?

    public init(
        failedStepID: AhaKeyRuntimeStepIdentifier? = nil,
        opcode: UInt8? = nil,
        deviceStatus: UInt8? = nil
    ) {
        self.failedStepID = failedStepID
        self.opcode = opcode
        self.deviceStatus = deviceStatus
    }

    public var isEmpty: Bool {
        failedStepID == nil && opcode == nil && deviceStatus == nil
    }

    public func mergingMissingStep(_ step: AhaKeyRuntimeStepIdentifier) -> AhaKeyRuntimeOperationFailureContext {
        if failedStepID != nil { return self }
        return AhaKeyRuntimeOperationFailureContext(
            failedStepID: step,
            opcode: opcode,
            deviceStatus: deviceStatus
        )
    }
}

public enum AhaKeyRuntimeOperationState: String, Codable, Equatable, Sendable {
    case accepted
    case running
    case paused
    case cancellationRequested
    case completed
    case resumablePartial
    case failedWithoutWrites
    case failedWithPartialCommit

    public var isTerminal: Bool {
        self == .completed
            || self == .failedWithoutWrites
            || self == .failedWithPartialCommit
    }

    public var isRecoveryCandidate: Bool { !isTerminal }

    /// Interface v1.1 shipped the resumable partial state under this wire spelling.
    /// Keep encoding it so older v1.1 clients remain able to decode new events/snapshots.
    public var compatibleRawValue: String {
        self == .resumablePartial ? "partiallyCompleted" : rawValue
    }

    public init?(compatibleRawValue: String) {
        if compatibleRawValue == "partiallyCompleted" {
            self = .resumablePartial
        } else {
            self.init(rawValue: compatibleRawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        guard let value = Self(compatibleRawValue: rawValue) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown operation state")
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(compatibleRawValue)
    }
}

/// C3C：显式 abandon 资格窗口。仅 FIFO 队首 paused/resumable 且持续断连满此时长才可受理。
public enum AhaKeyRuntimeAbandonPolicy {
    public static let requiredDisconnectedDuration: TimeInterval = 60
}

/// Runtime 拥有的 baseline 信任；不得从 Studio cache 升格为 verified。
public enum AhaKeyRuntimeBaselineTrust: String, Codable, Equatable, Sendable {
    case verified
    case writeConfirmed
    case unknown
}

public enum AhaKeyRuntimeBaselineProvenance: String, Codable, Equatable, Sendable {
    case deviceReadback
    case writeConfirmation
    case absent
}

/// 持久化的 typed 字段值。不含本地路径；图片用 CAS digest。
public enum AhaKeyRuntimeBaselineValue: Codable, Equatable, Sendable {
    case text(String)
    case optionalText(String?)
    case integer(Int)
    case keyAction(AhaKeyDesiredConfiguration.KeyAction)
    case taskAsset(
        sha256: String,
        byteCount: UInt64,
        mediaType: String,
        framesPerSecond: Int,
        declaredFrameCount: Int?
    )
}

/// 按 device/page/field 稳定键持久化的页面 baseline。
public struct AhaKeyRuntimeFieldBaseline: Codable, Equatable, Sendable {
    public let deviceID: AhaKeyRuntimeDeviceID
    public let pageID: AhaKeyStudioPageID
    public let fieldID: AhaKeyStudioFieldID
    public let value: AhaKeyRuntimeBaselineValue
    public let trust: AhaKeyRuntimeBaselineTrust
    public let provenance: AhaKeyRuntimeBaselineProvenance
    public let operationID: AhaKeyRuntimeOperationID
    public let authorityGeneration: UInt64?

    public init(
        deviceID: AhaKeyRuntimeDeviceID,
        pageID: AhaKeyStudioPageID,
        fieldID: AhaKeyStudioFieldID,
        value: AhaKeyRuntimeBaselineValue,
        trust: AhaKeyRuntimeBaselineTrust,
        provenance: AhaKeyRuntimeBaselineProvenance,
        operationID: AhaKeyRuntimeOperationID,
        authorityGeneration: UInt64? = nil
    ) {
        self.deviceID = deviceID
        self.pageID = pageID
        self.fieldID = fieldID
        self.value = value
        self.trust = trust
        self.provenance = provenance
        self.operationID = operationID
        self.authorityGeneration = authorityGeneration
    }
}

/// 冻结 ledger 减去已密封完整 field/resource 后的精确剩余。
public struct AhaKeyRuntimePageResidual: Codable, Equatable, Sendable {
    public let fieldIDs: [AhaKeyStudioFieldID]
    public let resources: [AhaKeyRuntimeConfirmationLedger.Entry.ResourceIdentity]

    public init(
        fieldIDs: [AhaKeyStudioFieldID] = [],
        resources: [AhaKeyRuntimeConfirmationLedger.Entry.ResourceIdentity] = []
    ) {
        self.fieldIDs = fieldIDs
        self.resources = resources
    }

    public var isEmpty: Bool { fieldIDs.isEmpty && resources.isEmpty }
}

public struct AhaKeyRuntimePageConfirmationProjection: Equatable, Sendable {
    public let confirmedFieldIDs: Set<AhaKeyStudioFieldID>
    public let confirmedResources: Set<AhaKeyRuntimeConfirmationLedger.Entry.ResourceIdentity>
    public let residual: AhaKeyRuntimePageResidual
}

public enum AhaKeyRuntimeAbandonDisposition: Codable, Equatable, Sendable {
    case abandoned
    case refused
    case notFound
    case alreadyFinished
}

public struct AhaKeyRuntimeOperationSummary: Codable, Equatable, Sendable {
    public let id: AhaKeyRuntimeOperationID
    public let targetDeviceID: AhaKeyRuntimeDeviceID
    public let state: AhaKeyRuntimeOperationState
    public let completedSteps: UInt32
    public let totalSteps: UInt32
    public let messageCode: AhaKeyRuntimeEventCode?
    /// C-2：已确认资源字节。缺省/旧 payload 为 nil，不改变 WAL 步语义。
    public let completedBytes: UInt64?
    /// C-2：本包资源总字节。缺省/旧 payload 为 nil。
    public let totalBytes: UInt64?
    /// C-2：当前正在执行的资源步。缺省/旧 payload 为 nil。
    public let currentStepID: AhaKeyRuntimeStepIdentifier?
    /// C-3：结构化失败上下文。缺省/旧 payload 为 nil；成功 operation 必须为 nil。
    public let failureContext: AhaKeyRuntimeOperationFailureContext?
    /// C3C：精确剩余 field/resource。缺省/旧 payload 为 nil。
    public let residual: AhaKeyRuntimePageResidual?
    /// C3C：本页已确认 baseline。缺省/旧 payload 为 nil。
    public let confirmedBaselines: [AhaKeyRuntimeFieldBaseline]?

    public init(
        id: AhaKeyRuntimeOperationID,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        state: AhaKeyRuntimeOperationState,
        completedSteps: UInt32 = 0,
        totalSteps: UInt32 = 0,
        messageCode: AhaKeyRuntimeEventCode? = nil,
        completedBytes: UInt64? = nil,
        totalBytes: UInt64? = nil,
        currentStepID: AhaKeyRuntimeStepIdentifier? = nil,
        failureContext: AhaKeyRuntimeOperationFailureContext? = nil,
        residual: AhaKeyRuntimePageResidual? = nil,
        confirmedBaselines: [AhaKeyRuntimeFieldBaseline]? = nil
    ) {
        self.id = id
        self.targetDeviceID = targetDeviceID
        self.state = state
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
        self.messageCode = messageCode
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.currentStepID = currentStepID
        self.failureContext = failureContext.flatMap { $0.isEmpty ? nil : $0 }
        self.residual = residual
        self.confirmedBaselines = confirmedBaselines
    }

    public func withByteProgress(
        completedBytes: UInt64?,
        totalBytes: UInt64?,
        currentStepID: AhaKeyRuntimeStepIdentifier?
    ) -> AhaKeyRuntimeOperationSummary {
        AhaKeyRuntimeOperationSummary(
            id: id,
            targetDeviceID: targetDeviceID,
            state: state,
            completedSteps: completedSteps,
            totalSteps: totalSteps,
            messageCode: messageCode,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            currentStepID: currentStepID,
            failureContext: failureContext,
            residual: residual,
            confirmedBaselines: confirmedBaselines
        )
    }

    public func withPageFacts(
        residual: AhaKeyRuntimePageResidual?,
        confirmedBaselines: [AhaKeyRuntimeFieldBaseline]?
    ) -> AhaKeyRuntimeOperationSummary {
        AhaKeyRuntimeOperationSummary(
            id: id,
            targetDeviceID: targetDeviceID,
            state: state,
            completedSteps: completedSteps,
            totalSteps: totalSteps,
            messageCode: messageCode,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            currentStepID: currentStepID,
            failureContext: failureContext,
            residual: residual,
            confirmedBaselines: confirmedBaselines
        )
    }
}

/// 资源上传字节进度的内存投影。不写入 WAL；失败/取消不得越过最后确认块。
public struct AhaKeyByteProgressProjector: Equatable, Sendable {
    public static let minimumPublishInterval: TimeInterval = 0.25
    public static let minimumPublishIntervalNanoseconds: UInt64 = 250_000_000

    public private(set) var completedBytes: UInt64 = 0
    public private(set) var totalBytes: UInt64
    public private(set) var currentStepID: AhaKeyRuntimeStepIdentifier?
    private var lastPublishedCompleted: UInt64?
    private var lastPublishedStep: AhaKeyRuntimeStepIdentifier?
    private var lastPublishAtNanos: UInt64?

    public init(totalBytes: UInt64) {
        self.totalBytes = totalBytes
    }

    /// 生产 executor 进入资源步：只切 currentStepID，不推进 completedBytes。
    /// 切换 event 服从 ≤4Hz；snapshot overlay 立即反映新 step。
    public mutating func enterStep(
        stepID: AhaKeyRuntimeStepIdentifier,
        nowNanos: UInt64
    ) -> Bool {
        guard currentStepID != stepID else { return false }
        currentStepID = stepID
        return considerPublish(nowNanos: nowNanos, force: false)
    }

    /// 分块成功确认后推进。返回是否应对外发布（同值不发；运行中 ≤4Hz）。
    /// `nowNanos` 必须是单调 tick（生产用 `DispatchTime` uptime）；墙钟回拨不得长期压制。
    public mutating func confirmChunk(
        stepID: AhaKeyRuntimeStepIdentifier,
        bytes: UInt64,
        nowNanos: UInt64
    ) -> Bool {
        currentStepID = stepID
        let next = completedBytes &+ bytes
        completedBytes = totalBytes == 0 ? next : min(next, totalBytes)
        return considerPublish(nowNanos: nowNanos, force: false)
    }

    /// 完成/失败/取消：立即发布最终已确认值（仍不得越过最后确认块）。
    public mutating func publishTerminal(nowNanos: UInt64) -> Bool {
        considerPublish(nowNanos: nowNanos, force: true)
    }

    public func overlay(_ summary: AhaKeyRuntimeOperationSummary) -> AhaKeyRuntimeOperationSummary {
        guard totalBytes > 0 else { return summary }
        return summary.withByteProgress(
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            currentStepID: currentStepID
        )
    }

    private mutating func considerPublish(nowNanos: UInt64, force: Bool) -> Bool {
        if lastPublishedCompleted == completedBytes, lastPublishedStep == currentStepID {
            return false
        }
        if !force, let last = lastPublishAtNanos, nowNanos >= last,
           nowNanos - last < Self.minimumPublishIntervalNanoseconds {
            return false
        }
        lastPublishedCompleted = completedBytes
        lastPublishedStep = currentStepID
        lastPublishAtNanos = nowNanos
        return true
    }
}

public struct AhaKeyRuntimeSnapshot: Codable, Equatable, Sendable {
    public let runtimeVersion: AhaKeyRuntimeVersion
    public let interfaceVersion: AhaKeyRuntimeInterfaceVersion
    public let supportedConfigurationSchemaVersions: Set<UInt16>
    public let lifecycleState: AhaKeyRuntimeLifecycleState
    public let devices: [AhaKeyRuntimeDeviceSnapshot]
    public let activeDeviceID: AhaKeyRuntimeDeviceID?
    public let configurationRevision: AhaKeyConfigurationRevision
    public let operations: [AhaKeyRuntimeOperationSummary]
    public let policy: AhaKeyRuntimePolicy
    public let permissions: AhaKeyRuntimePermissionSnapshot
    public let keepAliveReasons: Set<AhaKeyRuntimeKeepAliveReason>
    public let latestEventSequence: AhaKeyRuntimeEventSequence
    /// C3C：当前设备已确认页面 baseline。缺省/旧 payload 为空。
    public let pageBaselines: [AhaKeyRuntimeFieldBaseline]

    public init(
        runtimeVersion: AhaKeyRuntimeVersion = .development,
        interfaceVersion: AhaKeyRuntimeInterfaceVersion = .current,
        supportedConfigurationSchemaVersions: Set<UInt16> = [AhaKeyConfigurationPackage.currentSchemaVersion],
        lifecycleState: AhaKeyRuntimeLifecycleState,
        devices: [AhaKeyRuntimeDeviceSnapshot],
        activeDeviceID: AhaKeyRuntimeDeviceID?,
        configurationRevision: AhaKeyConfigurationRevision,
        operations: [AhaKeyRuntimeOperationSummary],
        policy: AhaKeyRuntimePolicy,
        permissions: AhaKeyRuntimePermissionSnapshot = .init(),
        keepAliveReasons: Set<AhaKeyRuntimeKeepAliveReason>? = nil,
        latestEventSequence: AhaKeyRuntimeEventSequence,
        pageBaselines: [AhaKeyRuntimeFieldBaseline] = []
    ) {
        self.runtimeVersion = runtimeVersion
        self.interfaceVersion = interfaceVersion
        self.supportedConfigurationSchemaVersions = supportedConfigurationSchemaVersions
        self.lifecycleState = lifecycleState
        self.devices = devices
        self.activeDeviceID = activeDeviceID
        self.configurationRevision = configurationRevision
        self.operations = operations
        self.policy = policy
        self.permissions = permissions
        self.keepAliveReasons = keepAliveReasons ?? policy.keepAliveReasons
        self.latestEventSequence = latestEventSequence
        self.pageBaselines = pageBaselines
    }
}

public enum AhaKeyRuntimeEventPayload: Codable, Equatable, Sendable {
    case snapshotInvalidated
    case deviceChanged(AhaKeyRuntimeDeviceSnapshot)
    case operationChanged(AhaKeyRuntimeOperationSummary)
    case policyChanged(AhaKeyRuntimePolicy)
    case lifecycleChanged(AhaKeyRuntimeLifecycleState)
    case permissionsChanged(AhaKeyRuntimePermissionSnapshot)
    case keepAliveReasonsChanged(Set<AhaKeyRuntimeKeepAliveReason>)
    case diagnostic(AhaKeyRuntimeDiagnosticEvent)
    case security(AhaKeyRuntimeSecurityEvent)
}

public enum AhaKeyRuntimeEventSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
}

public struct AhaKeyRuntimeDiagnosticEvent: Codable, Equatable, Sendable {
    public let code: AhaKeyRuntimeEventCode
    public let severity: AhaKeyRuntimeEventSeverity

    public init(code: AhaKeyRuntimeEventCode, severity: AhaKeyRuntimeEventSeverity) {
        self.code = code
        self.severity = severity
    }
}

public struct AhaKeyRuntimeSecurityEvent: Codable, Equatable, Sendable {
    public let code: AhaKeyRuntimeEventCode
    public let severity: AhaKeyRuntimeEventSeverity

    public init(code: AhaKeyRuntimeEventCode, severity: AhaKeyRuntimeEventSeverity) {
        self.code = code
        self.severity = severity
    }
}

public struct AhaKeyRuntimeEventContext: Codable, Equatable, Sendable {
    public let operationID: AhaKeyRuntimeOperationID?
    public let deviceID: AhaKeyRuntimeDeviceID?
    public let sessionGeneration: AhaKeyRuntimeSessionGeneration?
    public let transportGeneration: AhaKeyRuntimeTransportGeneration?

    public init(
        operationID: AhaKeyRuntimeOperationID? = nil,
        deviceID: AhaKeyRuntimeDeviceID? = nil,
        sessionGeneration: AhaKeyRuntimeSessionGeneration? = nil,
        transportGeneration: AhaKeyRuntimeTransportGeneration? = nil
    ) {
        self.operationID = operationID
        self.deviceID = deviceID
        self.sessionGeneration = sessionGeneration
        self.transportGeneration = transportGeneration
    }
}

public struct AhaKeyRuntimeEvent: Codable, Equatable, Sendable {
    public let sequence: AhaKeyRuntimeEventSequence
    public let context: AhaKeyRuntimeEventContext
    public let payload: AhaKeyRuntimeEventPayload

    public init(
        sequence: AhaKeyRuntimeEventSequence,
        context: AhaKeyRuntimeEventContext = .init(),
        payload: AhaKeyRuntimeEventPayload
    ) {
        self.sequence = sequence
        self.context = context
        self.payload = payload
    }
}

public enum AhaKeyRuntimeCancellationDisposition: String, Codable, Equatable, Sendable {
    case requested
    case alreadyFinished
    case notFound
    /// schema=2 running/paused/resumable 拒绝普通取消；queued 仍可无写入移除。
    case refused
}

public protocol AhaKeyRuntimeClient: Sendable {
    func snapshot() async throws -> AhaKeyRuntimeSnapshot
    func events(after sequence: AhaKeyRuntimeEventSequence?) async -> AsyncThrowingStream<AhaKeyRuntimeEvent, Error>
    func apply(_ package: AhaKeyConfigurationPackage) async throws -> AhaKeyRuntimeOperationID
    func requestCancellation(of operation: AhaKeyRuntimeOperationID) async throws -> AhaKeyRuntimeCancellationDisposition
    func requestAbandon(of operation: AhaKeyRuntimeOperationID) async throws -> AhaKeyRuntimeAbandonDisposition
    func updatePolicy(_ policy: AhaKeyRuntimePolicy) async throws
}

public enum AhaKeyRuntimeContractError: Error, Equatable, Sendable {
    case invalidDeviceIdentifier
    case invalidResourceIdentifier
    case invalidResourceDigest
    case invalidMediaType
    case invalidSchemaVersion
    case emptyDesiredConfiguration
    case duplicateResourceIdentifier
    case runtimeUnavailable
    case unsupportedConfigurationSchema(UInt16)
    case targetDeviceMismatch
    case staleConfigurationRevision(expected: AhaKeyConfigurationRevision, received: AhaKeyConfigurationRevision)
    case operationIdentifierConflict
    case invalidPercentage(Int)
    case invalidEventCode
    case pageOperationIncomplete
    case pageOperationDeviceMismatch
    case invalidCompatibilityFingerprint
    case invalidObjectFingerprint
    case unsupportedPeerForPageOperation
    case invalidAuthoritativeWriterLease
    case invalidAuthoritativeSourceRevision
}
