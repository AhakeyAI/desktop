import XCTest
@testable import AhaKeyConfigShared

final class BLELogPolicyTests: XCTestCase {

    /// 周期 TX/RX（→ CMD、← DATA/NOTIFY、写入完成、每轮状态原文、空转轮询）：
    /// 不进默认永久级（内存 Store / os_log / ble-comm.log），仅详细会话开启时写抓包文件。
    func testVerboseCategoryIsVerboseSessionOnly() {
        let routing = BLELogCategory.verbose.routing
        XCTAssertFalse(routing.entersMemoryStore)
        XCTAssertFalse(routing.entersSystemLog)
        XCTAssertFalse(routing.entersPersistentLog)
        XCTAssertTrue(routing.requiresVerboseSession)
    }

    /// 连接生命周期 / 状态变化 / 协议错误：进默认永久级（内存 + os_log + ble-comm.log）。
    func testDefaultLevelCategoriesEnterPersistentLog() {
        for category in [BLELogCategory.lifecycle, .stateChange, .error] {
            let routing = category.routing
            XCTAssertTrue(routing.entersMemoryStore, "\(category) 应进内存 Store")
            XCTAssertTrue(routing.entersSystemLog, "\(category) 应进 os_log")
            XCTAssertTrue(routing.entersPersistentLog, "\(category) 应写 ble-comm.log")
            XCTAssertFalse(routing.requiresVerboseSession, "\(category) 不依赖详细会话")
        }
    }

    /// 一次性运行信息（扫描、特征就绪、用户写操作）：内存诊断级——进内存 Store，但不写 ble-comm.log。
    func testDiagnosticCategorySkipsPersistentLog() {
        let routing = BLELogCategory.diagnostic.routing
        XCTAssertTrue(routing.entersMemoryStore)
        XCTAssertTrue(routing.entersSystemLog)
        XCTAssertFalse(routing.entersPersistentLog)
        XCTAssertFalse(routing.requiresVerboseSession)
    }
}

final class CoreSnapshotChangeSummaryTests: XCTestCase {

    /// 无变化 → nil（轮询到相同状态帧时不记日志）。
    func testNoChangeReturnsNil() {
        var snapshot = CoreDeviceSnapshot()
        snapshot.workMode = 1
        snapshot.switchState = 0
        XCTAssertNil(CoreSnapshotChangeSummary.summarize(from: snapshot, to: snapshot))
    }

    /// 拨杆与模式同时变化：一条摘要，不逐字段多条。
    func testMultipleFieldChangesProduceSingleSummaryLine() {
        var old = CoreDeviceSnapshot()
        old.switchState = 0
        old.workMode = 1
        var new = old
        new.switchState = 1
        new.workMode = 2
        let summary = CoreSnapshotChangeSummary.summarize(from: old, to: new)
        XCTAssertEqual(summary, "模式 1→2, 拨杆 0→1")
    }

    /// 连接状态/设备身份变化不在摘要内（由生命周期日志覆盖）。
    func testConnectionIdentityChangesAreExcluded() {
        let old = CoreDeviceSnapshot()
        var new = old
        new.isConnected = true
        new.deviceName = "AhaKey-X1"
        new.deviceUUID = "ABC"
        XCTAssertNil(CoreSnapshotChangeSummary.summarize(from: old, to: new))
    }
}
