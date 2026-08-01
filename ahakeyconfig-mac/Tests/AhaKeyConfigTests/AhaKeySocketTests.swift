import XCTest

@testable import AhaKeyConfigAgent

final class AhaKeySocketTests: XCTestCase {
    /// sun_path 只有 104 字节，socket 路径含用户主目录，超长必须失败而不是溢出。
    func testRejectsPathLongerThanSunPath() {
        let tooLong = "/" + String(repeating: "a", count: 200)
        XCTAssertNil(AhaKeySocket.makeAddress(path: tooLong))
    }

    func testAcceptsPathAtCapacityBoundary() {
        var probe = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: probe.sun_path)
        _ = probe

        XCTAssertNotNil(AhaKeySocket.makeAddress(path: String(repeating: "a", count: capacity - 1)))
        XCTAssertNil(AhaKeySocket.makeAddress(path: String(repeating: "a", count: capacity)))
    }

    func testWritesTerminatedPath() throws {
        let path = "/tmp/ahakey-test.sock"
        var addr = try XCTUnwrap(AhaKeySocket.makeAddress(path: path))
        XCTAssertEqual(addr.sun_family, sa_family_t(AF_UNIX))
        let written = withUnsafePointer(to: &addr.sun_path) {
            String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
        }
        XCTAssertEqual(written, path)
    }

    func testDefaultPathFitsForATypicalUserName() {
        XCTAssertNotNil(AhaKeySocket.makeAddress(path: AhaKeySocket.defaultPath))
    }
}
