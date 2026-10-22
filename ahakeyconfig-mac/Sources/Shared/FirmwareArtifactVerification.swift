import Foundation
import CryptoKit

public enum FirmwareArtifactVerification {
    public enum Failure: Error, Equatable { case incompatibleCandidate, missingArtifact, wrongSize, wrongDigest }

    /// File naming and a valid Intel HEX checksum do not prove release identity.
    /// Verify the exact downloaded/bundled bytes before the programmer stages them.
    public static func verify(_ data: Data, candidate: FirmwareInstallCandidate) throws {
        guard candidate.canInstall else { throw Failure.incompatibleCandidate }
        guard let artifact = candidate.entry.artifact else { throw Failure.missingArtifact }
        guard data.count == artifact.byteCount else { throw Failure.wrongSize }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == artifact.sha256 else { throw Failure.wrongDigest }
    }
}

public enum FirmwarePostFlashVerification {
    public enum Result: Equatable, Sendable {
        case verified
        case missingExpectedIdentity
        case missingStatus
        case connectionChanged
        case keyUnavailable
        case identityMismatch
    }

    /// A successful ISP checksum is only the first stage. The new runtime must
    /// answer status and its expected catalog key on one fresh connection.
    public static func evaluate(expectedKey: String?, actualKey: String?, hasValidStatus: Bool,
        sameConnection: Bool) -> Result {
        guard let expectedKey, FirmwareReleaseCatalog.validKey(expectedKey) else { return .missingExpectedIdentity }
        guard sameConnection else { return .connectionChanged }
        guard hasValidStatus else { return .missingStatus }
        guard let actualKey, FirmwareReleaseCatalog.validKey(actualKey) else { return .keyUnavailable }
        guard expectedKey == actualKey else { return .identityMismatch }
        return .verified
    }
}
