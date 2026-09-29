import XCTest
@testable import AhaKeyConfigShared

final class BLEConnectionLockTests: XCTestCase {

    private func makeTempLockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BLEConnectionLockTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("ble-owner.lock")
    }

    /// 同一锁文件：一个实例持有时，第二次独立 acquire 失败（flock 关联 open file description，进程内同样互斥）。
    func testSecondAcquireFailsWhileHeld() {
        let url = makeTempLockURL()
        let first = BLEConnectionLock(lockURL: url)
        let second = BLEConnectionLock(lockURL: url)
        XCTAssertTrue(first.acquire())
        XCTAssertTrue(first.holdsLock)
        XCTAssertFalse(second.acquire())
        XCTAssertFalse(second.holdsLock)
        // 已持有实例重复 acquire 返回 true
        XCTAssertTrue(first.acquire())
        first.release()
    }

    /// release 之后另一实例可再 acquire。
    func testAcquireSucceedsAfterRelease() {
        let url = makeTempLockURL()
        let first = BLEConnectionLock(lockURL: url)
        let second = BLEConnectionLock(lockURL: url)
        XCTAssertTrue(first.acquire())
        first.release()
        XCTAssertFalse(first.holdsLock)
        XCTAssertTrue(second.acquire())
        second.release()
    }

    /// fd 直接 close（模拟进程死亡，不走 LOCK_UN）后锁自动释放，可再 acquire。
    func testAcquireSucceedsAfterFdCloseSimulatingProcessDeath() {
        let url = makeTempLockURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fd = url.path.withCString { open($0, O_CREAT | O_RDWR, 0o644) }
        XCTAssertGreaterThanOrEqual(fd, 0)
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        close(fd) // 进程死亡等价路径：关闭引用该 open file description 的最后一个 fd

        let lock = BLEConnectionLock(lockURL: url)
        XCTAssertTrue(lock.acquire())
        lock.release()
    }

    /// 不同路径的锁互不影响。
    func testDifferentPathsAreIndependent() {
        let first = BLEConnectionLock(lockURL: makeTempLockURL())
        let second = BLEConnectionLock(lockURL: makeTempLockURL())
        XCTAssertTrue(first.acquire())
        XCTAssertTrue(second.acquire())
        first.release()
        second.release()
    }
}
