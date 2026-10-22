import Foundation
import CryptoKit
import XCTest
@testable import AhaKeyConfigShared

final class FirmwareReleaseCatalogTests: XCTestCase {
    private let signer = Curve25519.Signing.PrivateKey()
    private var keys: [String: Data] { ["test": signer.publicKey.rawRepresentation] }
    private let context = FirmwareDesktopContext(version: FirmwareDesktopVersion("0.2.3")!)
    private func entry(_ revision: Int = 1, minimum: String = "0.2.0", channel: FirmwareReleaseCatalog.Channel = .stable,
        visibility: FirmwareReleaseCatalog.Visibility = .user, recommended: Bool = false, recovery: Bool = false,
        path: String = "Firmware/test.hex", hash: String = String(repeating: "a", count: 64)) -> FirmwareReleaseCatalog.Entry {
        .init(key: "x1-c582-hw1-p1-1.0.0-r00\(revision)", displayName: "Test \(revision)", hardware: "x1-c582-hw1",
            protocolProfile: "p1", capabilities: [.ordinaryKeys], minimumDesktop: minimum, desktopVariants: ["legacy-macos"],
            visibility: visibility, channel: channel, releaseOrder: revision, recommended: recommended, recoverySafe: recovery,
            artifact: .init(filename: "test.hex", sha256: hash, byteCount: 20, bundledPath: path))
    }
    private func envelope(_ entries: [FirmwareReleaseCatalog.Entry], revision: Int = 2) throws -> Data {
        let payload = try JSONEncoder().encode(FirmwareReleaseCatalog(revision: revision, entries: entries))
        return try signed(payload)
    }
    private func signed(_ payload: Data) throws -> Data {
        try JSONEncoder().encode(FirmwareCatalogEnvelope(keyID: "test", payload: payload,
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(), signature: signer.signature(for: payload)))
    }
    private func verified(_ entries: [FirmwareReleaseCatalog.Entry]) throws -> VerifiedFirmwareCatalog {
        try FirmwareCatalogEnvelope.decodeAndVerify(envelope(entries), publicKeys: keys)
    }
    func testAuthenticityAndRollbackAreRequired() throws {
        let bytes = try envelope([entry()])
        XCTAssertEqual(try FirmwareCatalogEnvelope.decodeAndVerify(bytes, publicKeys: keys).value.revision, 2)
        XCTAssertThrowsError(try FirmwareCatalogEnvelope.decodeAndVerify(bytes, publicKeys: [:]))
        XCTAssertThrowsError(try FirmwareCatalogEnvelope.decodeAndVerify(bytes, publicKeys: keys, minimumRevision: 3))
        let original = try JSONDecoder().decode(FirmwareCatalogEnvelope.self, from: bytes)
        let tampered = FirmwareCatalogEnvelope(keyID: original.keyID, payload: original.payload + Data([32]),
            sha256: original.sha256, signature: original.signature)
        XCTAssertThrowsError(try tampered.verified(publicKeys: keys))
        let wrongDigest = FirmwareCatalogEnvelope(keyID: original.keyID, payload: original.payload,
            sha256: String(repeating: "0", count: 64), signature: original.signature)
        XCTAssertThrowsError(try wrongDigest.verified(publicKeys: keys))
    }
    func testMalformedCatalogNeverBecomesAuthority() throws {
        XCTAssertThrowsError(try verified([entry(), entry()]))
        XCTAssertThrowsError(try verified([entry(path: "../escape.hex")]))
        XCTAssertThrowsError(try verified([entry(path: "/absolute.hex")]))
        XCTAssertThrowsError(try verified([entry(hash: "invalid")]))
        XCTAssertThrowsError(try verified([entry(minimum: "current")]))
        XCTAssertThrowsError(try verified([entry(channel: .engineering, recommended: true)]))
        XCTAssertThrowsError(try FirmwareCatalogEnvelope.decodeAndVerify(Data(repeating: 0, count: 2_097_153), publicKeys: keys))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(FirmwareReleaseCatalog(revision: 2, entries: [entry()]))) as? [String: Any])
        object["schemaVersion"] = 99
        XCTAssertThrowsError(try FirmwareCatalogEnvelope.decodeAndVerify(signed(JSONSerialization.data(withJSONObject: object)), publicKeys: keys))
    }
    func testFailureStatesAreDistinctAndCapabilitiesFailClosed() throws {
        let catalog = try verified([entry(minimum: "0.3.0")])
        let key = catalog.value.entries[0].key
        let pairs: [(FirmwareCatalogIdentity, VerifiedFirmwareCatalog?, FirmwareCatalogState)] = [
            (.readFailed, catalog, .keyReadFailed), (.legacy, catalog, .legacy),
            (.key(key), nil, .catalogUnavailable), (.key("other"), catalog, .unknownKey("other")),
            (.key(key), catalog, .desktopTooOld(required: "0.3.0"))]
        for (identity, value, state) in pairs {
            let decision = FirmwareCatalogDecision.evaluate(identity: identity, catalog: value, context: context)
            XCTAssertEqual(decision.state, state); XCTAssertFalse(decision.permitsAdvancedOperations)
            XCTAssertTrue(decision.capabilities.isEmpty)
        }
        let builtin = try XCTUnwrap(VerifiedFirmwareCatalog.builtin)
        XCTAssertTrue(FirmwareCatalogDecision.evaluate(identity: .key(FirmwareCapabilityProfile.ws2CatalogKey), catalog: builtin, context: context).permitsAdvancedOperations)
        XCTAssertTrue(FirmwareCandidateSelection.candidates(catalog: builtin, identity: .readFailed, context: context).isEmpty)
    }
    func testCandidatesDeduplicateBadgesAndDisableTooNewVersion() throws {
        let catalog = try verified([entry(1, recommended: true, recovery: true), entry(2, minimum: "0.3.0"),
            entry(3, channel: .engineering, visibility: .engineering)])
        let candidates = FirmwareCandidateSelection.candidates(catalog: catalog, identity: .key(entry().key), context: context)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].badges, [.latest]); XCTAssertFalse(candidates[0].canInstall)
        XCTAssertEqual(candidates[1].badges, [.recommended, .stableRecovery, .current]); XCTAssertTrue(candidates[1].canInstall)
        XCTAssertTrue(FirmwareCandidateSelection.candidates(catalog: catalog, identity: .readFailed, context: context).allSatisfy { !$0.canInstall })
        let windows = FirmwareDesktopContext(version: context.version, variant: "different")
        XCTAssertTrue(FirmwareCandidateSelection.candidates(catalog: catalog, identity: .legacy, context: windows).isEmpty)
    }
    func testLocalImageNeedsUniqueCompatibleTrustedMatch() throws {
        let hash = String(repeating: "a", count: 64)
        XCTAssertNotNil(FirmwareCandidateSelection.trustedLocalMatch(sha256: hash, catalog: try verified([entry()]), context: context))
        XCTAssertNil(FirmwareCandidateSelection.trustedLocalMatch(sha256: hash, catalog: try verified([entry(), entry(2)]), context: context))
        XCTAssertNil(FirmwareCandidateSelection.trustedLocalMatch(sha256: hash, catalog: try verified([entry(minimum: "1.0.0")]), context: context))
    }
    func testPreparedCandidateIsInvalidatedByCatalogArtifactChange() throws {
        let before = try verified([entry()])
        let old = try XCTUnwrap(FirmwareCandidateSelection.candidates(catalog: before, identity: .legacy, context: context).first)
        XCTAssertTrue(FirmwareCandidateSelection.isCurrent(old, in: [old]))
        let after = try verified([entry(hash: String(repeating: "b", count: 64))])
        let current = FirmwareCandidateSelection.candidates(catalog: after, identity: .legacy, context: context)
        XCTAssertEqual(old.entry.key, current.first?.entry.key)
        XCTAssertFalse(FirmwareCandidateSelection.isCurrent(old, in: current))
        XCTAssertFalse(FirmwareCandidateSelection.isCurrent(old, in: []))
        let unread = FirmwareCandidateSelection.candidates(catalog: before, identity: .readFailed, context: context)
        XCTAssertFalse(FirmwareCandidateSelection.isCurrent(old, in: unread))
    }
    func testPostFlashRequiresActualRuntimeIdentityAndStatus() {
        let key = entry().key
        XCTAssertEqual(FirmwarePostFlashVerification.evaluate(expectedKey: key, actualKey: key, hasValidStatus: true, sameConnection: true), .verified)
        XCTAssertEqual(FirmwarePostFlashVerification.evaluate(expectedKey: nil, actualKey: key, hasValidStatus: true, sameConnection: true), .missingExpectedIdentity)
        XCTAssertEqual(FirmwarePostFlashVerification.evaluate(expectedKey: key, actualKey: key, hasValidStatus: false, sameConnection: true), .missingStatus)
        XCTAssertEqual(FirmwarePostFlashVerification.evaluate(expectedKey: key, actualKey: key, hasValidStatus: true, sameConnection: false), .connectionChanged)
        XCTAssertEqual(FirmwarePostFlashVerification.evaluate(expectedKey: key, actualKey: nil, hasValidStatus: true, sameConnection: true), .keyUnavailable)
        XCTAssertEqual(FirmwarePostFlashVerification.evaluate(expectedKey: key, actualKey: entry(2).key, hasValidStatus: true, sameConnection: true), .identityMismatch)
    }
    func testArtifactMustMatchExactSignedBytesAndCompatibility() throws {
        let data = Data(repeating: 42, count: 20)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let catalog = try verified([entry(hash: hash)])
        let candidate = try XCTUnwrap(FirmwareCandidateSelection.candidates(catalog: catalog, identity: .legacy, context: context).first)
        XCTAssertNoThrow(try FirmwareArtifactVerification.verify(data, candidate: candidate))
        XCTAssertThrowsError(try FirmwareArtifactVerification.verify(data + Data([0]), candidate: candidate))
        XCTAssertThrowsError(try FirmwareArtifactVerification.verify(Data(repeating: 0, count: 20), candidate: candidate))
        let disabled = try XCTUnwrap(FirmwareCandidateSelection.candidates(catalog: catalog, identity: .readFailed, context: context).first)
        XCTAssertThrowsError(try FirmwareArtifactVerification.verify(data, candidate: disabled))
    }
    func testCacheFallbackRejectsCorruptionRollbackAndRevisionConflict() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("catalog.json")
        let baseline = try envelope([entry()], revision: 3)
        let store = FirmwareCatalogStore(publicKeys: keys, embeddedEnvelope: baseline, cacheURL: cache)
        let newer = try envelope([entry(2)], revision: 4)
        _ = try await store.acceptRefresh(newer)
        do { _ = try await store.acceptRefresh(baseline); XCTFail("rollback") } catch {}
        do { _ = try await store.acceptRefresh(envelope([entry(3)], revision: 4)); XCTFail("same revision changed") } catch {}
        do { _ = try await store.acceptRefresh(Data("broken".utf8)); XCTFail("invalid") } catch {}
        XCTAssertEqual(try Data(contentsOf: cache), newer)
        let restored = FirmwareCatalogStore(publicKeys: keys, embeddedEnvelope: baseline, cacheURL: cache)
        let snapshot = await restored.snapshot()
        XCTAssertEqual(snapshot.source, .cache); XCTAssertEqual(snapshot.catalog?.value.revision, 4)
        try Data("corrupt".utf8).write(to: cache)
        let fallback = await FirmwareCatalogStore(publicKeys: keys, embeddedEnvelope: baseline, cacheURL: cache).snapshot()
        XCTAssertEqual(fallback.source, .embedded); XCTAssertEqual(fallback.catalog?.value.revision, 3)
    }
}
