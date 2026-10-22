import Foundation
import CryptoKit
import XCTest
@testable import AhaKeyConfigShared

final class FirmwareReleaseCompositionTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let manifest: FirmwareReleaseComposition
        let keys: [String: Data]
    }
    private func fixture(imageBytes: Data = Data(":0100000001FE\n:00000001FF\n".utf8),
        installerBytes: Data = Data("synthetic installer fixture".utf8)) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        func file(_ path: String, _ bytes: Data) throws -> FirmwareReleaseComposition.FileReference {
            try bytes.write(to: root.appendingPathComponent(path))
            return .init(path: path, sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), byteCount: bytes.count)
        }
        let image = try file("test.hex", imageBytes)
        // Synthetic test bytes; never claim this is an installable DMG or UAT proof.
        let installer = try file("test.dmg", installerBytes)
        let proof = try file("evidence.txt", Data("synthetic evidence fixture; actual contents require maintainer review".utf8))
        let key = FirmwareCapabilityProfile.ws2CatalogKey
        let catalog = FirmwareReleaseCatalog(revision: 3, entries: [.init(key: key, displayName: "Synthetic release", hardware: "x1-c582-hw1", protocolProfile: "p1",
            capabilities: [.ordinaryKeys], minimumDesktop: "0.2.3", desktopVariants: ["legacy-macos"], visibility: .user,
            channel: .stable, releaseOrder: 1, recommended: true, recoverySafe: true,
            artifact: .init(filename: "test.hex", sha256: image.sha256, byteCount: image.byteCount, bundledPath: "test.hex"))])
        let signer = Curve25519.Signing.PrivateKey()
        let payload = try JSONEncoder().encode(catalog)
        let envelope = FirmwareCatalogEnvelope(keyID: "ephemeral-test-only", payload: payload,
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(), signature: try signer.signature(for: payload))
        let catalogFile = try file("catalog.json", JSONEncoder().encode(envelope))
        let commit = String(repeating: "a", count: 40)
        let manifest = FirmwareReleaseComposition(schemaVersion: 1,
            client: .init(version: "0.2.3", variant: "legacy-macos", sourceCommit: commit, installer: installer),
            firmware: .init(key: key, sourceCommit: String(repeating: "b", count: 40), image: image),
            recovery: .init(key: key, sourceCommit: String(repeating: "b", count: 40), image: image),
            catalog: catalogFile, catalogRevision: 3,
            budgets: [.init(kind: .codeFlash, usedBytes: 1000, approvedLimitBytes: 448 * 1024),
                      .init(kind: .ram, usedBytes: 1000, approvedLimitBytes: 32 * 1024),
                      .init(kind: .w25q, usedBytes: 0, approvedLimitBytes: 1024 * 1024)],
            evidence: FirmwareReleaseComposition.requiredGates.sorted().map { gate in
                .init(gate: gate, result: .passed, clientCommit: commit, installerSHA256: installer.sha256,
                    firmwareSHA256: image.sha256, recoverySHA256: image.sha256,
                    firmwareSourceCommit: String(repeating: "b", count: 40), recoverySourceCommit: String(repeating: "b", count: 40),
                    catalogRevision: 3, report: proof)
            })
        return Fixture(root: root, manifest: manifest, keys: ["ephemeral-test-only": signer.publicKey.rawRepresentation])
    }
    private func changed(_ value: FirmwareReleaseComposition, _ mutation: (inout [String: Any]) -> Void) throws -> FirmwareReleaseComposition {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        mutation(&object)
        return try FirmwareReleaseComposition.decode(JSONSerialization.data(withJSONObject: object))
    }
    func testCompleteBindingsDoNotClaimPublicationOrAuthenticUAT() throws {
        let f = try fixture()
        let result = try f.manifest.verify(root: f.root, publicKeys: f.keys, minimumCatalogRevision: 3)
        XCTAssertEqual(result.boundEvidenceGates.count, 7)
        XCTAssertEqual(result.catalogRevision, 3)
        XCTAssertTrue(result.conclusion.contains("still require review"))
    }
    func testMissingOrUnconfirmedOrWrongVersionEvidenceCannotPass() throws {
        let f = try fixture()
        for kind in 0..<7 {
            let bad = try changed(f.manifest) { object in
                var evidence = object["evidence"] as! [[String: Any]]
                if kind == 0 { evidence.removeLast() }
                if kind == 1 { evidence[0]["result"] = "pending" }
                if kind == 2 { evidence[0]["firmwareSHA256"] = String(repeating: "0", count: 64) }
                if kind == 3 { evidence[0]["installerSHA256"] = String(repeating: "0", count: 64) }
                if kind == 4 { evidence[0]["recoverySHA256"] = String(repeating: "0", count: 64) }
                if kind == 5 { evidence[0]["firmwareSourceCommit"] = String(repeating: "c", count: 40) }
                if kind == 6 { evidence[0]["recoverySourceCommit"] = String(repeating: "c", count: 40) }
                object["evidence"] = evidence
            }
            XCTAssertThrowsError(try bad.verify(root: f.root, publicKeys: f.keys, minimumCatalogRevision: 3))
        }
    }
    func testSignedButMalformedHEXStillFailsAndLargeInstallerStreams() throws {
        let invalid = try fixture(imageBytes: Data(":010000000100\n:00000001FF\n".utf8))
        XCTAssertThrowsError(try invalid.manifest.verify(root: invalid.root, publicKeys: invalid.keys, minimumCatalogRevision: 3)) { error in
            XCTAssertEqual(error as? FirmwareImageValidationError, .invalidChecksum(line: 1))
        }
        let large = try fixture(installerBytes: Data(repeating: 42, count: 2_500_000))
        XCTAssertNoThrow(try large.manifest.verify(root: large.root, publicKeys: large.keys, minimumCatalogRevision: 3))
    }
    func testUntrustedCatalogAndRevisionMismatchCannotPass() throws {
        let f = try fixture()
        XCTAssertThrowsError(try f.manifest.verify(root: f.root, publicKeys: [:], minimumCatalogRevision: 3))
        XCTAssertThrowsError(try f.manifest.verify(root: f.root, publicKeys: f.keys, minimumCatalogRevision: 4))
        let mismatch = try changed(f.manifest) { $0["catalogRevision"] = 4 }
        XCTAssertThrowsError(try mismatch.verify(root: f.root, publicKeys: f.keys, minimumCatalogRevision: 3))
    }
    func testChangedFileAndPathTraversalOrSymlinkEscapeCannotPass() throws {
        let f = try fixture()
        let bad = try changed(f.manifest) { object in
            var client = object["client"] as! [String: Any]
            var file = client["installer"] as! [String: Any]
            file["path"] = "../test.dmg"; client["installer"] = file; object["client"] = client
        }
        XCTAssertThrowsError(try bad.verify(root: f.root, publicKeys: f.keys, minimumCatalogRevision: 3))
        let external = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dmg")
        defer { try? FileManager.default.removeItem(at: external) }
        try Data("synthetic installer fixture".utf8).write(to: external)
        let installer = f.root.appendingPathComponent("test.dmg")
        try FileManager.default.removeItem(at: installer)
        try FileManager.default.createSymbolicLink(at: installer, withDestinationURL: external)
        XCTAssertThrowsError(try f.manifest.verify(root: f.root, publicKeys: f.keys, minimumCatalogRevision: 3))
        try FileManager.default.removeItem(at: installer)
        try Data("mutated installer".utf8).write(to: installer)
        XCTAssertThrowsError(try f.manifest.verify(root: f.root, publicKeys: f.keys, minimumCatalogRevision: 3))
    }
    func testOverspentBudgetAndWrongRecoveryIdentityCannotPass() throws {
        let f = try fixture()
        let over = try changed(f.manifest) { object in
            var budgets = object["budgets"] as! [[String: Any]]
            budgets[0]["usedBytes"] = Int(FirmwareImageValidator.ch582CodeFlashSize) + 1; object["budgets"] = budgets
        }
        XCTAssertThrowsError(try over.verify(root: f.root, publicKeys: f.keys, minimumCatalogRevision: 3))
        let recovery = try changed(f.manifest) { object in
            var recovery = object["recovery"] as! [String: Any]
            recovery["key"] = "x1-c582-hw1-p1-1.0.0-r999"; object["recovery"] = recovery
        }
        XCTAssertThrowsError(try recovery.verify(root: f.root, publicKeys: f.keys, minimumCatalogRevision: 3))
    }
    func testMaintainerCLIExecutesTheSameBindingChecks() throws {
        let f = try fixture()
        let manifest = f.root.appendingPathComponent("manifest.json"), keys = f.root.appendingPathComponent("trust.json")
        try JSONEncoder().encode(f.manifest).write(to: manifest)
        try JSONEncoder().encode(f.keys).write(to: keys)
        let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("ahakey-release-check")
        func run() throws -> (Int32, Data) {
            let process = Process(), output = Pipe()
            process.executableURL = executable; process.arguments = [manifest.path, f.root.path, keys.path, "3"]
            process.standardOutput = output; process.standardError = output
            try process.run()
            let bytes = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (process.terminationStatus, bytes)
        }
        let valid = try run(); XCTAssertEqual(valid.0, 0)
        XCTAssertEqual(try JSONDecoder().decode(FirmwareReleaseComposition.Report.self, from: valid.1).firmwareKey, f.manifest.firmware.key)
        try Data("changed".utf8).write(to: f.root.appendingPathComponent("test.hex"))
        let bad = try run(); XCTAssertEqual(bad.0, 1)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: bad.1) as? [String: String])
    }
}
