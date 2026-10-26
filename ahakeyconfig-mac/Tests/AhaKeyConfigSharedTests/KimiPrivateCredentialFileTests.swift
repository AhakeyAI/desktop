import XCTest
import Darwin
@testable import AhaKeyConfigShared

final class KimiPrivateCredentialFileTests: XCTestCase {
    private let token = String(repeating: "A", count: 43)
    private func fixture(_ contents: String? = nil) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kimi-credential-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                              attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("server.token")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data((contents ?? token).utf8),
                                                    attributes: [.posixPermissions: 0o600]))
        return file
    }
    private func failure(_ expected: KimiPrivateCredentialFile.Failure,
                         _ operation: () throws -> KimiLocalBearerCredential) {
        XCTAssertThrowsError(try operation()) { XCTAssertEqual($0 as? KimiPrivateCredentialFile.Failure, expected) }
    }
    func testConsentPrecedesOwnerOrFileAccess() {
        failure(.notAuthorized) {
            try KimiPrivateCredentialFile.read(URL(fileURLWithPath: "/nonexistent"), userAuthorized: false,
                                              verifyOwner: { XCTFail("Consent must precede probing"); return false })
        }
    }
    func testOwnerMustBeVerifiedBeforeAndAfterRead() throws {
        let file = try fixture()
        failure(.untrustedOwner) { try KimiPrivateCredentialFile.read(file, userAuthorized: true, verifyOwner: { false }) }
        var calls = 0
        failure(.changed) {
            try KimiPrivateCredentialFile.read(file, userAuthorized: true, verifyOwner: { calls += 1; return calls == 1 })
        }
        XCTAssertEqual(calls, 2)
    }
    func testCredentialOnlyExposesHeaderWithinExplicitOperationAndRedactsInspection() throws {
        let file = try fixture(" \n" + token + "\n")
        let value = try KimiPrivateCredentialFile.read(file, userAuthorized: true, verifyOwner: { true })
        XCTAssertEqual(String(describing: value), "<redacted>")
        XCTAssertEqual(String(reflecting: value), "<redacted>")
        XCTAssertTrue(Mirror(reflecting: value).children.isEmpty)
        XCTAssertTrue(value.withAuthorizationHeader { $0 == "Bearer " + token })
    }
    func testPublicPermissionsSymlinksAndHardlinksAreRejected() throws {
        let file = try fixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        failure(.invalidFile) { try KimiPrivateCredentialFile.read(file, userAuthorized: true, verifyOwner: { true }) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let link = file.deletingLastPathComponent().appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        failure(.invalidFile) { try KimiPrivateCredentialFile.read(link, userAuthorized: true, verifyOwner: { true }) }
        try FileManager.default.removeItem(at: link)
        try FileManager.default.linkItem(at: file, to: link)
        failure(.invalidFile) { try KimiPrivateCredentialFile.read(file, userAuthorized: true, verifyOwner: { true }) }
    }
    func testMalformedOrOversizedValuesCannotBecomeHTTPHeaders() throws {
        for contents in [String(repeating: "a", count: 31), token + "\r\nInjected: value", String(repeating: "a", count: 513)] {
            let file = try fixture(contents)
            failure(contents.utf8.count < 32 ? .invalidFile : .invalidToken) {
                try KimiPrivateCredentialFile.read(file, userAuthorized: true, verifyOwner: { true })
            }
        }
        let oversized = try fixture(String(repeating: "a", count: 1025))
        failure(.invalidFile) { try KimiPrivateCredentialFile.read(oversized, userAuthorized: true, verifyOwner: { true }) }
    }
}
