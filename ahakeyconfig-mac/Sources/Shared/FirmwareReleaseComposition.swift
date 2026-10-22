import Foundation
import CryptoKit

/// Offline release binding. This verifies evidence integrity and declarations,
/// not the truth of a human UAT report or authorization to publish a release.
public struct FirmwareReleaseComposition: Codable, Sendable {
    public struct FileReference: Codable, Sendable {
        public let path: String
        public let sha256: String
        public let byteCount: Int
    }
    public struct Client: Codable, Sendable {
        public let version: String
        public let variant: String
        public let sourceCommit: String
        public let installer: FileReference
    }
    public struct Firmware: Codable, Sendable {
        public let key: String
        public let sourceCommit: String
        public let image: FileReference
    }
    public struct Budget: Codable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable { case codeFlash, ram, w25q }
        public let kind: Kind
        public let usedBytes: Int
        public let approvedLimitBytes: Int
    }
    public struct Evidence: Codable, Sendable {
        public enum Result: String, Codable, Sendable { case passed, failed, pending }
        public let gate: String
        public let result: Result
        public let clientCommit: String
        public let installerSHA256: String
        public let firmwareSHA256: String
        public let recoverySHA256: String
        public let firmwareSourceCommit: String
        public let recoverySourceCommit: String
        public let catalogRevision: Int
        public let report: FileReference
    }
    public let schemaVersion: Int
    public let client: Client
    public let firmware: Firmware
    public let recovery: Firmware
    public let catalog: FileReference
    public let catalogRevision: Int
    public let budgets: [Budget]
    public let evidence: [Evidence]

    public static let requiredGates: Set<String> = ["protocol-governance", "mac-core-uat", "firmware-budget",
        "firmware-recovery", "installer-signing-notarization", "compatibility-known-limitations", "full-regression"]
    public enum Failure: Error, Equatable {
        case malformed, unsupportedSchema, invalidClient, invalidCommit, invalidBudget, unsafePath
        case invalidFileReference, fileMissing, fileChanged, digestMismatch, invalidCandidate, invalidRecovery
        case catalogRevisionMismatch, missingEvidence, unconfirmedEvidence, evidenceScopeMismatch
    }
    public struct Report: Codable, Sendable {
        public let clientCommit: String
        public let firmwareKey: String
        public let firmwareCommit: String
        public let recoveryKey: String
        public let recoveryCommit: String
        public let installerSHA256: String
        public let firmwareSHA256: String
        public let recoverySHA256: String
        public let catalogSHA256: String
        public let verifiedSigningKeySHA256: String
        public let catalogRevision: Int
        public let boundEvidenceGates: [String]
        public let conclusion: String
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576, let value = try? JSONDecoder().decode(Self.self, from: data) else { throw Failure.malformed }
        return value
    }
    public func verify(root: URL, publicKeys: [String: Data], minimumCatalogRevision: Int) throws -> Report {
        guard schemaVersion == 1 else { throw Failure.unsupportedSchema }
        guard let version = FirmwareDesktopVersion(client.version), client.variant == "legacy-macos",
              ["dmg", "pkg", "zip"].contains(URL(fileURLWithPath: client.installer.path).pathExtension.lowercased()) else { throw Failure.invalidClient }
        guard [client.sourceCommit, firmware.sourceCommit, recovery.sourceCommit].allSatisfy(Self.validCommit) else { throw Failure.invalidCommit }
        guard catalogRevision >= minimumCatalogRevision, minimumCatalogRevision > 0 else { throw Failure.catalogRevisionMismatch }
        guard budgets.count == Budget.Kind.allCases.count, Set(budgets.map(\.kind)) == Set(Budget.Kind.allCases),
              budgets.allSatisfy({ $0.approvedLimitBytes > 0 && $0.usedBytes >= 0 && $0.usedBytes <= $0.approvedLimitBytes }),
              budgets.first(where: { $0.kind == .codeFlash }).map({ $0.usedBytes > 0 && $0.approvedLimitBytes <= FirmwareImageValidator.ch582CodeFlashSize }) == true,
              budgets.first(where: { $0.kind == .ram }).map({ $0.usedBytes > 0 }) == true else { throw Failure.invalidBudget }
        let envelope = try boundBytes(catalog, root: root, maximum: 2_097_152)
        let verified = try FirmwareCatalogEnvelope.decodeAndVerify(envelope, publicKeys: publicKeys, minimumRevision: minimumCatalogRevision)
        let signedEnvelope = try JSONDecoder().decode(FirmwareCatalogEnvelope.self, from: envelope)
        guard let signingKey = publicKeys[signedEnvelope.keyID] else { throw FirmwareReleaseCatalog.Failure.unknownSigner }
        guard verified.value.revision == catalogRevision else { throw Failure.catalogRevisionMismatch }
        let context = FirmwareDesktopContext(version: version, variant: client.variant)
        let candidates = FirmwareCandidateSelection.candidates(catalog: verified, identity: .key(firmware.key), context: context)
        guard let target = candidates.first(where: { $0.entry.key == firmware.key && $0.canInstall && $0.entry.channel == .stable }) else {
            throw Failure.invalidCandidate
        }
        guard let recoveryTarget = candidates.first(where: { $0.entry.key == recovery.key && $0.canInstall && $0.entry.recoverySafe }) else {
            throw Failure.invalidRecovery
        }
        try checkImage(firmware.image, candidate: target, root: root)
        try checkImage(recovery.image, candidate: recoveryTarget, root: root)
        if firmware.key != recovery.key && firmware.image.sha256 == recovery.image.sha256 { throw Failure.invalidRecovery }
        _ = try boundFile(client.installer, root: root, maximum: 16 * 1024 * 1024 * 1024)
        guard evidence.count <= 128, Set(evidence.map(\.gate)).count == evidence.count,
              Self.requiredGates.isSubset(of: Set(evidence.map(\.gate))) else { throw Failure.missingEvidence }
        for item in evidence {
            guard !item.gate.isEmpty, item.gate.utf8.count <= 64, item.gate.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw Failure.missingEvidence }
            guard item.result == .passed else { throw Failure.unconfirmedEvidence }
            guard item.clientCommit == client.sourceCommit, item.installerSHA256 == client.installer.sha256,
                  item.firmwareSHA256 == firmware.image.sha256, item.recoverySHA256 == recovery.image.sha256,
                  item.firmwareSourceCommit == firmware.sourceCommit, item.recoverySourceCommit == recovery.sourceCommit,
                  item.catalogRevision == catalogRevision else { throw Failure.evidenceScopeMismatch }
            _ = try boundFile(item.report, root: root, maximum: 64 * 1024 * 1024)
        }
        return Report(clientCommit: client.sourceCommit, firmwareKey: firmware.key, firmwareCommit: firmware.sourceCommit,
            recoveryKey: recovery.key, recoveryCommit: recovery.sourceCommit, installerSHA256: client.installer.sha256,
            firmwareSHA256: firmware.image.sha256, recoverySHA256: recovery.image.sha256,
            catalogSHA256: catalog.sha256, verifiedSigningKeySHA256: Self.digest(signingKey),
            catalogRevision: catalogRevision, boundEvidenceGates: evidence.map(\.gate).sorted(),
            conclusion: "Composition bindings verified; evidence content and publication approval still require review.")
    }
    private func checkImage(_ file: FileReference, candidate: FirmwareInstallCandidate, root: URL) throws {
        let bytes = try boundBytes(file, root: root, maximum: FirmwareImageValidator.maximumFileSize)
        guard URL(fileURLWithPath: file.path).lastPathComponent == candidate.entry.artifact?.filename else { throw Failure.invalidFileReference }
        try FirmwareArtifactVerification.verify(bytes, candidate: candidate)
        _ = try FirmwareImageValidator.validate(data: bytes, sourceURL: URL(fileURLWithPath: file.path))
    }
    private static func validCommit(_ value: String) -> Bool {
        value.utf8.count == 40 && value != String(repeating: "0", count: 40) &&
            value == value.lowercased() && value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
    private func safeURL(_ path: String, root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.utf8.count <= 512, !path.contains("\\"), !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw Failure.unsafePath }
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let url = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw Failure.unsafePath }
        return url
    }
    private func boundBytes(_ reference: FileReference, root: URL, maximum: Int) throws -> Data {
        let url = try boundFile(reference, root: root, maximum: maximum)
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        guard bytes.count == reference.byteCount, Self.digest(bytes) == reference.sha256 else { throw Failure.fileChanged }
        return bytes
    }
    /// Installers can be large. Stream at most 1 MiB at a time instead of loading
    /// them into memory; recheck size/time after hashing to catch concurrent edits.
    private func boundFile(_ reference: FileReference, root: URL, maximum: Int) throws -> URL {
        guard FirmwareReleaseCatalog.validDigest(reference.sha256), (1...maximum).contains(reference.byteCount) else { throw Failure.invalidFileReference }
        let url = try safeURL(reference.path, root: root)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let before = try? url.resourceValues(forKeys: keys), before.isRegularFile == true,
              before.fileSize == reference.byteCount else { throw Failure.fileMissing }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256(), count = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            guard chunk.count <= reference.byteCount - count else { throw Failure.fileChanged }
            count += chunk.count; hasher.update(data: chunk)
        }
        let after = try url.resourceValues(forKeys: keys)
        guard count == reference.byteCount, before.fileSize == after.fileSize,
              before.contentModificationDate == after.contentModificationDate else { throw Failure.fileChanged }
        guard hasher.finalize().map({ String(format: "%02x", $0) }).joined() == reference.sha256 else { throw Failure.digestMismatch }
        return url
    }
    private static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}
