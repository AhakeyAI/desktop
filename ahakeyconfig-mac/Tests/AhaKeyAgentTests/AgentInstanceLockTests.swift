import XCTest
@testable import AhaKeyConfigAgent

final class AgentInstanceLockTests: XCTestCase {
    private var socketPath: String!

    override func setUp() {
        super.setUp()
        socketPath = "/tmp/ahk-lock-\(getpid())-\(UInt32.random(in: 0 ... .max)).sock"
    }

    override func tearDown() {
        unlink(AgentInstanceLock.lockPath(for: socketPath))
        super.tearDown()
    }

    func testSecondInstanceIsRejectedWhileFirstHoldsLock() {
        guard case .acquired(let first) = AgentInstanceLock.acquire(socketPath: socketPath) else {
            return XCTFail("first instance should acquire the lock")
        }
        XCTAssertEqual(AgentInstanceLock.acquire(socketPath: socketPath), .heldByOther)

        close(first)
        guard case .acquired(let again) = AgentInstanceLock.acquire(socketPath: socketPath) else {
            return XCTFail("lock should be reusable after the holder exits")
        }
        close(again)
    }

    func testSocketPathMustFitSunPath() {
        XCTAssertTrue(AgentInstanceLock.isValidSocketPath("/tmp/ahakey.sock"))
        XCTAssertFalse(AgentInstanceLock.isValidSocketPath(""))
        XCTAssertFalse(AgentInstanceLock.isValidSocketPath("/tmp/" + String(repeating: "a", count: 200)))
    }
}
