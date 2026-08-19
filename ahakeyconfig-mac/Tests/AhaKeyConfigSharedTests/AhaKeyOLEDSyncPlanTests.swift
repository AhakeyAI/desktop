import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyOLEDSyncPlanTests: XCTestCase {

    /// 设备默认动画绑定与 done 槽位不一致（用户自定义图已上传但默认绑定仍是出厂图）
    /// → 需要把默认动画重新绑定到 done 槽位。这是本次 bug 的核心场景。
    func testRepairWhenDefaultBindingDiffersFromDone() {
        let done = AhaKeyOLEDSyncPlan.Binding(startIndex: 10, frameCount: 2, frameIntervalMs: 83)
        let factoryDefault = AhaKeyOLEDSyncPlan.Binding(startIndex: 276, frameCount: 1, frameIntervalMs: 100)
        let repair = AhaKeyOLEDSyncPlan.defaultBindingRepair(
            doneAssetPath: "/tmp/custom.gif",
            deviceDone: done,
            deviceDefault: factoryDefault
        )
        XCTAssertEqual(repair, done)
    }

    /// 默认动画绑定已与 done 槽位一致 → 不重复绑定。
    func testNoRepairWhenDefaultBindingMatchesDone() {
        let done = AhaKeyOLEDSyncPlan.Binding(startIndex: 10, frameCount: 2, frameIntervalMs: 83)
        XCTAssertNil(AhaKeyOLEDSyncPlan.defaultBindingRepair(
            doneAssetPath: "/tmp/custom.gif",
            deviceDone: done,
            deviceDefault: done
        ))
    }

    /// 起始槽一致但帧数/帧间隔不同也算不一致 → 需要重新绑定。
    func testRepairWhenOnlyIntervalDiffers() {
        let done = AhaKeyOLEDSyncPlan.Binding(startIndex: 10, frameCount: 2, frameIntervalMs: 83)
        let stale = AhaKeyOLEDSyncPlan.Binding(startIndex: 10, frameCount: 2, frameIntervalMs: 100)
        XCTAssertEqual(AhaKeyOLEDSyncPlan.defaultBindingRepair(
            doneAssetPath: "/tmp/custom.gif",
            deviceDone: done,
            deviceDefault: stale
        ), done)
    }

    /// 用户没有设置 done 图（草稿路径为 nil）→ 不绑定。
    func testNoRepairWhenDoneAssetMissing() {
        let done = AhaKeyOLEDSyncPlan.Binding(startIndex: 10, frameCount: 2, frameIntervalMs: 83)
        XCTAssertNil(AhaKeyOLEDSyncPlan.defaultBindingRepair(
            doneAssetPath: nil,
            deviceDone: done,
            deviceDefault: nil
        ))
    }

    /// 设备 done 槽为空（没有帧数据）→ 不能绑定，避免指向空区间。
    func testNoRepairWhenDeviceDoneSlotEmpty() {
        let empty = AhaKeyOLEDSyncPlan.Binding(startIndex: 0, frameCount: 0, frameIntervalMs: 0)
        XCTAssertNil(AhaKeyOLEDSyncPlan.defaultBindingRepair(
            doneAssetPath: "/tmp/custom.gif",
            deviceDone: empty,
            deviceDefault: nil
        ))
        XCTAssertNil(AhaKeyOLEDSyncPlan.defaultBindingRepair(
            doneAssetPath: "/tmp/custom.gif",
            deviceDone: nil,
            deviceDefault: nil
        ))
    }

    /// 0x83 查询失败（deviceDefault 为 nil）但 done 槽有帧 → 保守地重新绑定一次。
    func testRepairWhenDefaultBindingUnreadable() {
        let done = AhaKeyOLEDSyncPlan.Binding(startIndex: 14, frameCount: 1, frameIntervalMs: 83)
        XCTAssertEqual(AhaKeyOLEDSyncPlan.defaultBindingRepair(
            doneAssetPath: "/tmp/custom.gif",
            deviceDone: done,
            deviceDefault: nil
        ), done)
    }

    func testProtocolAwareRepairOnlyRunsForLegacy() {
        let done = AhaKeyOLEDSyncPlan.Binding(startIndex: 14, frameCount: 1, frameIntervalMs: 83)

        XCTAssertEqual(AhaKeyOLEDSyncPlan.defaultBindingRepair(
            protocolMode: .legacy,
            doneAssetPath: "/tmp/custom.gif",
            deviceDone: done,
            deviceDefault: nil
        ), done)
        XCTAssertNil(AhaKeyOLEDSyncPlan.defaultBindingRepair(
            protocolMode: .current,
            doneAssetPath: "/tmp/custom.gif",
            deviceDone: done,
            deviceDefault: nil
        ))
        XCTAssertNil(AhaKeyOLEDSyncPlan.defaultBindingRepair(
            protocolMode: .restrictedUnknown,
            doneAssetPath: "/tmp/custom.gif",
            deviceDone: done,
            deviceDefault: nil
        ))
    }
}
