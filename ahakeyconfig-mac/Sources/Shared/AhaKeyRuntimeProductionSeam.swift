import Foundation

public struct AhaKeyRuntimeHookProtocolVersion: Codable, Equatable, Hashable, Sendable {
    public static let current = Self(major: 1, minor: 1)
    public static let previous = Self(major: 1, minor: 0)

    public let major: UInt16
    public let minor: UInt16

    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }
}

public enum AhaKeyRuntimeHookClient: String, Codable, Equatable, Sendable {
    case claude
    case codex
    case cursor
    case kimi
}

public struct AhaKeyRuntimeHookHandshake: Codable, Equatable, Sendable {
    public let protocolVersion: AhaKeyRuntimeHookProtocolVersion
    public let client: AhaKeyRuntimeHookClient
    public let hookBuildID: String

    public init(
        protocolVersion: AhaKeyRuntimeHookProtocolVersion,
        client: AhaKeyRuntimeHookClient,
        hookBuildID: String
    ) {
        self.protocolVersion = protocolVersion
        self.client = client
        self.hookBuildID = hookBuildID
    }
}

public enum AhaKeyRuntimeHookAIEvent: String, Codable, Equatable, Sendable {
    case idle
    case working
    case permissionRequested
    case awaitingFollowup
    case sessionEnded
}

public struct AhaKeyRuntimeHookAIState: Codable, Equatable, Sendable {
    public let event: AhaKeyRuntimeHookAIEvent
    public let requestID: UUID

    public init(event: AhaKeyRuntimeHookAIEvent, requestID: UUID) {
        self.event = event
        self.requestID = requestID
    }
}

public struct AhaKeyRuntimeHookApprovalQuery: Codable, Equatable, Sendable {
    public let requestID: UUID

    public init(requestID: UUID) {
        self.requestID = requestID
    }
}

public enum AhaKeyRuntimeHookApprovalDecision: String, Codable, Equatable, Sendable {
    case automatic
    case manual
    case unavailable
}

public enum AhaKeyRuntimeHookRequest: Codable, Equatable, Sendable {
    case handshake(AhaKeyRuntimeHookHandshake)
    case aiState(AhaKeyRuntimeHookAIState)
    case approvalQuery(AhaKeyRuntimeHookApprovalQuery)
    case leverQuery
}

public enum AhaKeyRuntimeHookResponse: Codable, Equatable, Sendable {
    case handshakeAccepted(AhaKeyRuntimeHookProtocolVersion)
    case acknowledged
    case approvalDecision(requestID: UUID, decision: AhaKeyRuntimeHookApprovalDecision)
    case leverPosition(AhaKeyRuntimeLeverPosition?)
}

public enum AhaKeyRuntimeHookSessionAcceptance: Equatable, Sendable {
    case handshakeAccepted(AhaKeyRuntimeHookProtocolVersion)
    case messageAccepted(AhaKeyRuntimeHookHandshake)
}

public enum AhaKeyRuntimeHookSessionError: Error, Equatable, Sendable {
    case handshakeRequired
    case handshakeAlreadyCompleted
    case unsupportedVersion
    case invalidBuildIdentifier
    case rateLimited
}

/// Per-connection protocol gate. It deliberately knows no BLE opcode or configuration API.
public struct AhaKeyRuntimeHookSession: Sendable {
    private let rateLimit: Int
    private let rateWindow: TimeInterval
    private var handshake: AhaKeyRuntimeHookHandshake?
    private var acceptedMessageTimes: [TimeInterval] = []

    public init(rateLimit: Int = 60, rateWindow: TimeInterval = 1) {
        precondition(rateLimit > 0)
        precondition(rateWindow > 0)
        self.rateLimit = rateLimit
        self.rateWindow = rateWindow
    }

    public mutating func accept(
        _ request: AhaKeyRuntimeHookRequest,
        at monotonicTime: TimeInterval
    ) throws -> AhaKeyRuntimeHookSessionAcceptance {
        switch request {
        case .handshake(let proposed):
            guard handshake == nil else { throw AhaKeyRuntimeHookSessionError.handshakeAlreadyCompleted }
            guard proposed.protocolVersion == .current || proposed.protocolVersion == .previous else {
                throw AhaKeyRuntimeHookSessionError.unsupportedVersion
            }
            let buildID = proposed.hookBuildID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !buildID.isEmpty, buildID.utf8.count <= 128 else {
                throw AhaKeyRuntimeHookSessionError.invalidBuildIdentifier
            }
            handshake = proposed
            return .handshakeAccepted(proposed.protocolVersion)

        case .aiState, .approvalQuery, .leverQuery:
            guard let handshake else { throw AhaKeyRuntimeHookSessionError.handshakeRequired }
            acceptedMessageTimes.removeAll { monotonicTime - $0 >= rateWindow }
            guard acceptedMessageTimes.count < rateLimit else {
                throw AhaKeyRuntimeHookSessionError.rateLimited
            }
            acceptedMessageTimes.append(monotonicTime)
            return .messageAccepted(handshake)
        }
    }
}

public enum AhaKeyRuntimeProductionSeamError: Error, Equatable, Sendable {
    case emptyFrame
    case frameTooLarge(maximum: Int, received: Int)
    case malformedFrame
}

public struct AhaKeyRuntimeXPCPeerIdentity: Equatable, Sendable {
    public let userID: UInt32
    public let teamIdentifier: String
    public let signingIdentifier: String

    public init(userID: UInt32, teamIdentifier: String, signingIdentifier: String) {
        self.userID = userID
        self.teamIdentifier = teamIdentifier
        self.signingIdentifier = signingIdentifier
    }
}

public struct AhaKeyRuntimeXPCPeerPolicy: Sendable {
    public let expectedUserID: UInt32
    public let expectedTeamIdentifier: String
    public let allowedSigningIdentifiers: Set<String>

    public init(
        expectedUserID: UInt32,
        expectedTeamIdentifier: String,
        allowedSigningIdentifiers: Set<String>
    ) {
        precondition(!expectedTeamIdentifier.isEmpty)
        precondition(!allowedSigningIdentifiers.isEmpty)
        self.expectedUserID = expectedUserID
        self.expectedTeamIdentifier = expectedTeamIdentifier
        self.allowedSigningIdentifiers = allowedSigningIdentifiers
    }

    public func allows(_ identity: AhaKeyRuntimeXPCPeerIdentity) -> Bool {
        identity.userID == expectedUserID
            && identity.teamIdentifier == expectedTeamIdentifier
            && allowedSigningIdentifiers.contains(identity.signingIdentifier)
    }

    // MARK: - WBS 5.2 生产 libxpc peer requirement

    /// 批准的发布 Team ID（Developer ID 签名链）。
    public static let productionTeamIdentifier = "P2VFVRZK7P"
    /// 允许连接生产 Runtime XPC 的客户端签名身份（Studio；后续签名 Runtime helper 加入此集合）。
    public static let productionAllowedSigningIdentifiers: Set<String> = ["lab.jawa.ahakeyconfig"]

    /// 生产默认策略：当前 UID + 批准 Team ID + Studio 签名身份。测试不得通过此处弱化默认值；
    /// 测试 identity 只能经 init 显式注入。
    public static func production(expectedUserID: UInt32 = getuid()) -> Self {
        Self(
            expectedUserID: expectedUserID,
            expectedTeamIdentifier: productionTeamIdentifier,
            allowedSigningIdentifiers: productionAllowedSigningIdentifiers
        )
    }

    /// 生成绑定到 XPC peer 的 code signing requirement 字符串（macOS 12+
    /// `xpc_connection_set_peer_code_signing_requirement` 语义）：Apple 信任锚 +
    /// 批准 Team ID + 允许的签名身份之一。
    public var codeSigningRequirement: String {
        let identifiers = allowedSigningIdentifiers
            .sorted()
            .map { "identifier \"\($0)\"" }
            .joined(separator: " or ")
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\" and (\(identifiers))"
    }
}

public struct AhaKeyRuntimeXPCHandshake: Codable, Equatable, Sendable {
    public let interfaceVersion: AhaKeyRuntimeInterfaceVersion
    public let clientBuildID: String

    public init(interfaceVersion: AhaKeyRuntimeInterfaceVersion, clientBuildID: String) {
        self.interfaceVersion = interfaceVersion
        self.clientBuildID = clientBuildID
    }
}

public struct AhaKeyRuntimeXPCCapability: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public static let snapshot = Self(rawValue: "snapshot")
    public static let eventReplay = Self(rawValue: "event-replay")
    public static let configuration = Self(rawValue: "configuration")
    public static let diagnostics = Self(rawValue: "diagnostics")
    public static let firmwareUpgrade = Self(rawValue: "firmware-upgrade")
    public static let policy = Self(rawValue: "policy")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AhaKeyRuntimeXPCServerHandshake: Codable, Equatable, Sendable {
    public let runtimeVersion: AhaKeyRuntimeVersion
    public let interfaceVersion: AhaKeyRuntimeInterfaceVersion
    public let supportedConfigurationSchemaVersions: Set<UInt16>
    public let capabilities: Set<AhaKeyRuntimeXPCCapability>

    public init(
        runtimeVersion: AhaKeyRuntimeVersion,
        interfaceVersion: AhaKeyRuntimeInterfaceVersion,
        supportedConfigurationSchemaVersions: Set<UInt16>,
        capabilities: Set<AhaKeyRuntimeXPCCapability>
    ) {
        precondition(!supportedConfigurationSchemaVersions.isEmpty)
        precondition(!capabilities.isEmpty)
        self.runtimeVersion = runtimeVersion
        self.interfaceVersion = interfaceVersion
        self.supportedConfigurationSchemaVersions = supportedConfigurationSchemaVersions
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey {
        case runtimeVersion
        case interfaceVersion
        case supportedConfigurationSchemaVersions
        case capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let runtimeVersion = try container.decode(AhaKeyRuntimeVersion.self, forKey: .runtimeVersion)
        let interfaceVersion = try container.decode(AhaKeyRuntimeInterfaceVersion.self, forKey: .interfaceVersion)
        let schemaVersions = try container.decode(Set<UInt16>.self, forKey: .supportedConfigurationSchemaVersions)
        let capabilities = try container.decode(Set<AhaKeyRuntimeXPCCapability>.self, forKey: .capabilities)
        guard !schemaVersions.isEmpty, !capabilities.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "XPC handshake must advertise schema versions and capabilities")
            )
        }
        self.runtimeVersion = runtimeVersion
        self.interfaceVersion = interfaceVersion
        self.supportedConfigurationSchemaVersions = schemaVersions
        self.capabilities = capabilities
    }
}

public struct AhaKeyRuntimeFirmwareUpgradeRequest: Codable, Equatable, Sendable {
    public let operationID: AhaKeyRuntimeOperationID
    public let targetDeviceID: AhaKeyRuntimeDeviceID
    public let firmwareResource: AhaKeyConfigurationResource

    public init(
        operationID: AhaKeyRuntimeOperationID,
        targetDeviceID: AhaKeyRuntimeDeviceID,
        firmwareResource: AhaKeyConfigurationResource
    ) {
        self.operationID = operationID
        self.targetDeviceID = targetDeviceID
        self.firmwareResource = firmwareResource
    }
}

public enum AhaKeyRuntimeXPCRequest: Codable, Equatable, Sendable {
    case handshake(AhaKeyRuntimeXPCHandshake)
    case snapshot
    case events(after: AhaKeyRuntimeEventSequence?)
    case apply(AhaKeyConfigurationPackage)
    case requestCancellation(AhaKeyRuntimeOperationID)
    case updatePolicy(AhaKeyRuntimePolicy)
    case diagnostics(after: AhaKeyRuntimeEventSequence?)
    case startFirmwareUpgrade(AhaKeyRuntimeFirmwareUpgradeRequest)
}

public enum AhaKeyRuntimeXPCResponse: Codable, Equatable, Sendable {
    case handshakeAccepted(AhaKeyRuntimeXPCServerHandshake)
    case snapshot(AhaKeyRuntimeSnapshot)
    case eventReplay(AhaKeyRuntimeEventReplayResult)
    case operationAccepted(AhaKeyRuntimeOperationID)
    case cancellation(AhaKeyRuntimeCancellationDisposition)
    case policyUpdated
    case diagnosticEvents([AhaKeyRuntimeEvent])
    case firmwareUpgradeAccepted(AhaKeyRuntimeOperationID)
    case failure(AhaKeyRuntimeEventCode)
}

public enum AhaKeyRuntimeXPCSessionAcceptance: Equatable, Sendable {
    case handshakeAccepted(AhaKeyRuntimeInterfaceVersion)
    case requestAccepted
}

public enum AhaKeyRuntimeXPCSessionError: Error, Equatable, Sendable {
    case handshakeRequired
    case handshakeAlreadyCompleted
    case unsupportedInterfaceVersion
    case invalidBuildIdentifier
}

public struct AhaKeyRuntimeXPCSession: Sendable {
    private var negotiatedVersion: AhaKeyRuntimeInterfaceVersion?

    public init() {}

    public mutating func accept(
        _ request: AhaKeyRuntimeXPCRequest
    ) throws -> AhaKeyRuntimeXPCSessionAcceptance {
        switch request {
        case .handshake(let proposed):
            guard negotiatedVersion == nil else {
                throw AhaKeyRuntimeXPCSessionError.handshakeAlreadyCompleted
            }
            let current = AhaKeyRuntimeInterfaceVersion.current
            let isCurrent = proposed.interfaceVersion == current
            let isPrevious = proposed.interfaceVersion.major == current.major
                && current.minor > 0
                && proposed.interfaceVersion.minor == current.minor - 1
            guard isCurrent || isPrevious else {
                throw AhaKeyRuntimeXPCSessionError.unsupportedInterfaceVersion
            }
            let buildID = proposed.clientBuildID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !buildID.isEmpty, buildID.utf8.count <= 128 else {
                throw AhaKeyRuntimeXPCSessionError.invalidBuildIdentifier
            }
            negotiatedVersion = proposed.interfaceVersion
            return .handshakeAccepted(proposed.interfaceVersion)

        case .snapshot, .events, .apply, .requestCancellation, .updatePolicy,
             .diagnostics, .startFirmwareUpgrade:
            guard negotiatedVersion != nil else {
                throw AhaKeyRuntimeXPCSessionError.handshakeRequired
            }
            return .requestAccepted
        }
    }
}

public enum AhaKeyRuntimeEventReplayResult: Codable, Equatable, Sendable {
    case events([AhaKeyRuntimeEvent])
    case snapshotRequired(latest: AhaKeyRuntimeEventSequence)
}

public enum AhaKeyRuntimeEventReplayError: Error, Equatable, Sendable {
    case nonMonotonicSequence
    case cursorAheadOfRuntime
}

/// Bounded, in-process replay. A gap is explicit so clients refresh the authoritative snapshot.
public struct AhaKeyRuntimeEventReplayBuffer: Sendable {
    public let capacity: Int
    private var retained: [AhaKeyRuntimeEvent] = []
    private var latest: AhaKeyRuntimeEventSequence?

    public init(
        capacity: Int = 256,
        latestSequence: AhaKeyRuntimeEventSequence? = nil
    ) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.latest = latestSequence
    }

    public mutating func append(_ event: AhaKeyRuntimeEvent) throws {
        if let latest, event.sequence <= latest {
            throw AhaKeyRuntimeEventReplayError.nonMonotonicSequence
        }
        latest = event.sequence
        retained.append(event)
        if retained.count > capacity {
            retained.removeFirst(retained.count - capacity)
        }
    }

    public func events(
        after cursor: AhaKeyRuntimeEventSequence?
    ) throws -> AhaKeyRuntimeEventReplayResult {
        guard let latest else { return .events([]) }
        guard let cursor else { return .snapshotRequired(latest: latest) }
        guard cursor <= latest else { throw AhaKeyRuntimeEventReplayError.cursorAheadOfRuntime }
        if cursor < latest {
            guard let first = retained.first?.sequence else {
                return .snapshotRequired(latest: latest)
            }
            if cursor.rawValue < first.rawValue,
               first.rawValue - cursor.rawValue > 1 {
                return .snapshotRequired(latest: latest)
            }
        }
        return .events(retained.filter { $0.sequence > cursor })
    }
}

/// Four-byte, big-endian length prefix followed by one JSON value.
public struct AhaKeyRuntimeJSONFrameCodec: Sendable {
    public let maximumPayloadBytes: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(maximumPayloadBytes: Int) {
        precondition(maximumPayloadBytes > 0)
        self.maximumPayloadBytes = maximumPayloadBytes
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let payload = try encoder.encode(value)
        guard !payload.isEmpty else { throw AhaKeyRuntimeProductionSeamError.emptyFrame }
        guard payload.count <= maximumPayloadBytes else {
            throw AhaKeyRuntimeProductionSeamError.frameTooLarge(
                maximum: maximumPayloadBytes,
                received: payload.count
            )
        }
        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        return frame
    }

    public func decodeOne<Value: Decodable>(
        _ type: Value.Type,
        from buffer: inout Data
    ) throws -> Value? {
        guard buffer.count >= MemoryLayout<UInt32>.size else { return nil }
        let payloadLength = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard payloadLength > 0 else { throw AhaKeyRuntimeProductionSeamError.emptyFrame }
        guard payloadLength <= UInt32(maximumPayloadBytes) else {
            throw AhaKeyRuntimeProductionSeamError.frameTooLarge(
                maximum: maximumPayloadBytes,
                received: Int(payloadLength)
            )
        }
        let frameLength = 4 + Int(payloadLength)
        guard buffer.count >= frameLength else { return nil }
        let frameStart = buffer.startIndex
        let payloadStart = buffer.index(frameStart, offsetBy: 4)
        let frameEnd = buffer.index(frameStart, offsetBy: frameLength)
        let payload = buffer.subdata(in: payloadStart ..< frameEnd)
        let value: Value
        do {
            value = try decoder.decode(type, from: payload)
        } catch {
            throw AhaKeyRuntimeProductionSeamError.malformedFrame
        }
        buffer.removeSubrange(frameStart ..< frameEnd)
        return value
    }
}
