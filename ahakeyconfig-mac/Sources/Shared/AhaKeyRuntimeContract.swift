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

/// Stable device-state projection exposed to Studio. Diagnostic telemetry such as RSSI
/// intentionally lives outside this snapshot so routine sampling cannot refresh hidden UI.
public struct AhaKeyRuntimeDeviceState: Codable, Equatable, Sendable {
    public let batteryLevel: Int?
    public let workMode: Int?
    public let lightMode: Int?
    public let leverPosition: Int?
    public let brightness: Int?
    public let firmwareVersion: String?
    public let activeTaskPictureSets: [Int: Int]

    public init(
        batteryLevel: Int? = nil,
        workMode: Int? = nil,
        lightMode: Int? = nil,
        leverPosition: Int? = nil,
        brightness: Int? = nil,
        firmwareVersion: String? = nil,
        activeTaskPictureSets: [Int: Int] = [:]
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
        state: AhaKeyRuntimeDeviceState = .init()
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
    case activeOperation
    case studioConnection
}

public struct AhaKeyRuntimePolicy: Codable, Equatable, Sendable {
    public var ahaTypeEnabled: Bool
    public var aiHooksEnabled: Bool
    public var dynamicDeviceStateEnabled: Bool
    public var sessionRoutingEnabled: Bool
    public var powerProtectionEnabled: Bool

    public init(
        ahaTypeEnabled: Bool = false,
        aiHooksEnabled: Bool = false,
        dynamicDeviceStateEnabled: Bool = false,
        sessionRoutingEnabled: Bool = false,
        powerProtectionEnabled: Bool = false
    ) {
        self.ahaTypeEnabled = ahaTypeEnabled
        self.aiHooksEnabled = aiHooksEnabled
        self.dynamicDeviceStateEnabled = dynamicDeviceStateEnabled
        self.sessionRoutingEnabled = sessionRoutingEnabled
        self.powerProtectionEnabled = powerProtectionEnabled
    }

    public var requiresPersistentRuntime: Bool {
        ahaTypeEnabled || aiHooksEnabled || dynamicDeviceStateEnabled || sessionRoutingEnabled || powerProtectionEnabled
    }

    public var requiresDeviceConnection: Bool {
        aiHooksEnabled || dynamicDeviceStateEnabled
    }

    public var keepAliveReasons: Set<AhaKeyRuntimeKeepAliveReason> {
        var reasons: Set<AhaKeyRuntimeKeepAliveReason> = []
        if ahaTypeEnabled { reasons.insert(.ahaType) }
        if aiHooksEnabled { reasons.insert(.aiHooks) }
        if dynamicDeviceStateEnabled { reasons.insert(.dynamicDeviceState) }
        if sessionRoutingEnabled { reasons.insert(.sessionRouting) }
        if powerProtectionEnabled { reasons.insert(.powerProtection) }
        return reasons
    }
}

public struct AhaKeyConfigurationResource: Codable, Equatable, Hashable, Sendable {
    public let logicalIdentifier: String
    public let sha256: String
    public let byteCount: UInt64
    public let mediaType: String

    public init(
        logicalIdentifier: String,
        sha256: String,
        byteCount: UInt64,
        mediaType: String
    ) throws {
        let identifier = logicalIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              !identifier.contains("/"),
              !identifier.contains("\\"),
              identifier != ".",
              identifier != ".." else {
            throw AhaKeyRuntimeContractError.invalidResourceIdentifier
        }
        let normalizedDigest = sha256.lowercased()
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard normalizedDigest.count == 64,
              normalizedDigest.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw AhaKeyRuntimeContractError.invalidResourceDigest
        }
        let normalizedMediaType = mediaType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMediaType.isEmpty else {
            throw AhaKeyRuntimeContractError.invalidMediaType
        }
        self.logicalIdentifier = identifier
        self.sha256 = normalizedDigest
        self.byteCount = byteCount
        self.mediaType = normalizedMediaType
    }
}

public struct AhaKeyConfigurationPackage: Codable, Equatable, Sendable {
    public static let currentSchemaVersion: UInt16 = 1

    public let schemaVersion: UInt16
    public let operationID: AhaKeyRuntimeOperationID
    public let targetDeviceID: AhaKeyRuntimeDeviceID
    public let baseRevision: AhaKeyConfigurationRevision
    /// Canonical, versioned representation of the complete desired configuration.
    /// It is decoded and planned by Runtime; callers never send transport commands or physical slots.
    public let desiredConfiguration: Data
    public let resources: [AhaKeyConfigurationResource]

    public init(
        schemaVersion: UInt16 = Self.currentSchemaVersion,
        operationID: AhaKeyRuntimeOperationID = .init(),
        targetDeviceID: AhaKeyRuntimeDeviceID,
        baseRevision: AhaKeyConfigurationRevision,
        desiredConfiguration: Data,
        resources: [AhaKeyConfigurationResource]
    ) throws {
        guard schemaVersion > 0 else {
            throw AhaKeyRuntimeContractError.invalidSchemaVersion
        }
        guard !desiredConfiguration.isEmpty else {
            throw AhaKeyRuntimeContractError.emptyDesiredConfiguration
        }
        guard Set(resources.map(\.logicalIdentifier)).count == resources.count else {
            throw AhaKeyRuntimeContractError.duplicateResourceIdentifier
        }
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.targetDeviceID = targetDeviceID
        self.baseRevision = baseRevision
        self.desiredConfiguration = desiredConfiguration
        self.resources = resources
    }
}

public enum AhaKeyRuntimeOperationState: String, Codable, Equatable, Sendable {
    case accepted
    case running
    case paused
    case cancellationRequested
    case completed
    case partiallyCompleted
    case failed

    public var isTerminal: Bool {
        self == .completed || self == .partiallyCompleted || self == .failed
    }
}

public struct AhaKeyRuntimeOperationSummary: Codable, Equatable, Sendable {
    public let id: AhaKeyRuntimeOperationID
    public let targetDeviceID: AhaKeyRuntimeDeviceID
    public let state: AhaKeyRuntimeOperationState
    public let completedSteps: UInt32
    public let totalSteps: UInt32
    public let messageCode: String?

    public init(
        id: AhaKeyRuntimeOperationID,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        state: AhaKeyRuntimeOperationState,
        completedSteps: UInt32 = 0,
        totalSteps: UInt32 = 0,
        messageCode: String? = nil
    ) {
        self.id = id
        self.targetDeviceID = targetDeviceID
        self.state = state
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
        self.messageCode = messageCode
    }
}

public struct AhaKeyRuntimeSnapshot: Codable, Equatable, Sendable {
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

    public init(
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
        latestEventSequence: AhaKeyRuntimeEventSequence
    ) {
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
}

public protocol AhaKeyRuntimeClient: Sendable {
    func snapshot() async throws -> AhaKeyRuntimeSnapshot
    func events(after sequence: AhaKeyRuntimeEventSequence?) async -> AsyncThrowingStream<AhaKeyRuntimeEvent, Error>
    func apply(_ package: AhaKeyConfigurationPackage) async throws -> AhaKeyRuntimeOperationID
    func requestCancellation(of operation: AhaKeyRuntimeOperationID) async throws -> AhaKeyRuntimeCancellationDisposition
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
}
