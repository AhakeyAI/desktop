import Foundation
import CryptoKit

public struct FirmwareDesktopVersion: Codable, Hashable, Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 6 && $0.allSatisfy(\.isASCIIWholeNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
    public var text: String { "\(major).\(minor).\(patch)" }
}

private extension Character {
    var isASCIIWholeNumber: Bool { isASCII && isNumber }
}

/// Desktop-owned catalog format. Firmware continues to expose only its 0x9F key.
/// Signed catalog records never replace a successful same-connection readback.
public struct FirmwareReleaseCatalog: Codable, Equatable, Sendable {
    public enum Capability: String, Codable, Hashable, Sendable {
        case ordinaryKeys, voiceOnboarding, sideSwitchBindings, standby
        case ws3Display, ws3Resources, ws3Presentation
    }
    public enum Visibility: String, Codable, Sendable { case user, engineering, factory }
    public enum Channel: String, Codable, Sendable { case stable, preview, engineering }
    public struct Artifact: Codable, Equatable, Sendable {
        public let filename: String
        public let sha256: String
        public let byteCount: Int
        public let downloadURL: URL?
        public let bundledPath: String?
        public init(filename: String, sha256: String, byteCount: Int, downloadURL: URL? = nil, bundledPath: String? = nil) {
            self.filename = filename; self.sha256 = sha256; self.byteCount = byteCount
            self.downloadURL = downloadURL; self.bundledPath = bundledPath
        }
    }
    public struct Entry: Codable, Equatable, Sendable {
        public let key: String
        public let displayName: String
        public let hardware: String
        public let protocolProfile: String
        public let capabilities: Set<Capability>
        public let minimumDesktop: String
        public let desktopVariants: Set<String>
        public let visibility: Visibility
        public let channel: Channel
        public let releaseOrder: Int
        public let recommended: Bool
        public let recoverySafe: Bool
        public let limitations: [String]
        public let artifact: Artifact?
        public init(key: String, displayName: String, hardware: String, protocolProfile: String,
            capabilities: Set<Capability>, minimumDesktop: String, desktopVariants: Set<String>,
            visibility: Visibility, channel: Channel, releaseOrder: Int, recommended: Bool = false,
            recoverySafe: Bool = false, limitations: [String] = [], artifact: Artifact? = nil) {
            self.key = key; self.displayName = displayName; self.hardware = hardware; self.protocolProfile = protocolProfile
            self.capabilities = capabilities; self.minimumDesktop = minimumDesktop; self.desktopVariants = desktopVariants
            self.visibility = visibility; self.channel = channel; self.releaseOrder = releaseOrder
            self.recommended = recommended; self.recoverySafe = recoverySafe; self.limitations = limitations; self.artifact = artifact
        }
    }
    public let schemaVersion: Int
    public let revision: Int
    public let entries: [Entry]
    public init(revision: Int, entries: [Entry]) {
        self.schemaVersion = 1; self.revision = revision; self.entries = entries
    }
    public enum Failure: Error, Equatable {
        case tooLarge, unsupportedSchema, malformed, duplicateKey, invalidEntry, invalidArtifact
        case unknownSigner, invalidSignature, checksumMismatch, downgrade
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576 else { throw Failure.tooLarge }
        let value: Self
        do { value = try JSONDecoder().decode(Self.self, from: data) } catch { throw Failure.malformed }
        try value.validate()
        return value
    }
    public func validate() throws {
        guard schemaVersion == 1 else { throw Failure.unsupportedSchema }
        guard revision > 0, entries.count <= 1024 else { throw Failure.malformed }
        guard Set(entries.map(\.key)).count == entries.count else { throw Failure.duplicateKey }
        for entry in entries {
            guard Self.validKey(entry.key), entry.key.split(separator: "-").prefix(3).joined(separator: "-") == entry.hardware,
                  entry.key.split(separator: "-").dropFirst(3).first.map(String.init) == entry.protocolProfile,
                  Self.safeText(entry.displayName, maximum: 160), Self.safeText(entry.hardware, maximum: 48),
                  FirmwareDesktopVersion(entry.minimumDesktop) != nil, !entry.desktopVariants.isEmpty,
                  entry.desktopVariants.count <= 16, entry.desktopVariants.allSatisfy({ Self.safeText($0, maximum: 48) }),
                  entry.releaseOrder >= 0, entry.limitations.count <= 24,
                  entry.limitations.allSatisfy({ Self.safeText($0, maximum: 1024) }),
                  !entry.recommended || (entry.visibility == .user && entry.channel == .stable),
                  !entry.recoverySafe || (entry.visibility == .user && entry.channel == .stable) else { throw Failure.invalidEntry }
            if entry.visibility == .user && entry.artifact == nil { throw Failure.invalidArtifact }
            if let artifact = entry.artifact {
                guard Self.safeFilename(artifact.filename), Self.validDigest(artifact.sha256),
                      (1...16_777_216).contains(artifact.byteCount),
                      artifact.downloadURL != nil || artifact.bundledPath != nil else { throw Failure.invalidArtifact }
                if let url = artifact.downloadURL {
                    guard url.scheme == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil,
                          url.fragment == nil, url.port == nil || url.port == 443 else { throw Failure.invalidArtifact }
                }
                if let path = artifact.bundledPath {
                    guard !path.hasPrefix("/"), path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                        !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\")
                    }), path.utf8.count <= 256 else { throw Failure.invalidArtifact }
                }
            }
        }
    }
    public static func validKey(_ key: String) -> Bool {
        guard key.utf8.count <= 64, key == key.lowercased(),
              key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }) else { return false }
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 6, parts[0] == "x1", parts[1] == "c582",
              parts[2].hasPrefix("hw"), Self.numericSuffix(parts[2], prefix: 2),
              parts[3].hasPrefix("p"), Self.numericSuffix(parts[3], prefix: 1),
              FirmwareDesktopVersion(String(parts[4])) != nil,
              parts[5].hasPrefix("r"), Self.numericSuffix(parts[5], prefix: 1) else { return false }
        return true
    }
    public static func validDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.allSatisfy { $0.isASCII && $0.isHexDigit } && text == text.lowercased()
    }
    private static func numericSuffix(_ part: Substring, prefix: Int) -> Bool {
        let suffix = part.dropFirst(prefix)
        return !suffix.isEmpty && suffix.count <= 8 && suffix.allSatisfy(\.isASCIIWholeNumber)
    }
    private static func safeFilename(_ name: String) -> Bool {
        safeText(name, maximum: 160) && name.lowercased().hasSuffix(".hex") &&
            !name.contains("/") && !name.contains("\\") && name != "." && name != ".."
    }
    private static func safeText(_ text: String, maximum: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= maximum &&
            !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

public struct VerifiedFirmwareCatalog: Sendable {
    public let value: FirmwareReleaseCatalog
    fileprivate init(_ value: FirmwareReleaseCatalog) { self.value = value }
    /// This engineering profile preserves an accepted protocol; it is deliberately
    /// not a public release, recommended HEX, or recovery-safe artifact.
    public static let builtin: Self? = {
        let value = FirmwareReleaseCatalog(revision: 1, entries: [.init(
            key: FirmwareCapabilityProfile.ws2CatalogKey, displayName: "X1 accepted WS2 protocol",
            hardware: "x1-c582-hw1", protocolProfile: "p1",
            capabilities: [.ordinaryKeys, .voiceOnboarding, .sideSwitchBindings, .standby,
                .ws3Display, .ws3Presentation, .ws3Resources], minimumDesktop: "0.0.0",
            desktopVariants: ["legacy-macos", "legacy-windows"], visibility: .engineering,
            channel: .engineering, releaseOrder: 0)])
        guard (try? value.validate()) != nil else { return nil }
        return Self(value)
    }()
}

public struct FirmwareCatalogEnvelope: Codable, Sendable {
    public let keyID: String
    public let payload: Data
    public let sha256: String
    public let signature: Data
    public init(keyID: String, payload: Data, sha256: String, signature: Data) {
        self.keyID = keyID; self.payload = payload; self.sha256 = sha256; self.signature = signature
    }
    public func verified(publicKeys: [String: Data], minimumRevision: Int = 0) throws -> VerifiedFirmwareCatalog {
        guard payload.count <= 1_048_576 else { throw FirmwareReleaseCatalog.Failure.tooLarge }
        guard let rawKey = publicKeys[keyID], let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey) else {
            throw FirmwareReleaseCatalog.Failure.unknownSigner
        }
        guard key.isValidSignature(signature, for: payload) else { throw FirmwareReleaseCatalog.Failure.invalidSignature }
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        guard FirmwareReleaseCatalog.validDigest(sha256), digest == sha256 else { throw FirmwareReleaseCatalog.Failure.checksumMismatch }
        let catalog = try FirmwareReleaseCatalog.decode(payload)
        guard catalog.revision >= minimumRevision else { throw FirmwareReleaseCatalog.Failure.downgrade }
        return VerifiedFirmwareCatalog(catalog)
    }
    public static func decodeAndVerify(_ data: Data, publicKeys: [String: Data], minimumRevision: Int = 0) throws -> VerifiedFirmwareCatalog {
        guard data.count <= 2_097_152 else { throw FirmwareReleaseCatalog.Failure.tooLarge }
        guard let envelope = try? JSONDecoder().decode(Self.self, from: data) else { throw FirmwareReleaseCatalog.Failure.malformed }
        return try envelope.verified(publicKeys: publicKeys, minimumRevision: minimumRevision)
    }
}
