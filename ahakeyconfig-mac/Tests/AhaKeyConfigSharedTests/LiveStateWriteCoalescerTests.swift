import XCTest
@testable import AhaKeyConfigShared

final class LiveStateWriteCoalescerTests: XCTestCase {
    typealias Snapshot = LiveStateWriteCoalescer.Snapshot
    typealias Decision = LiveStateWriteCoalescer.Decision

    /// 相同状态连续输入 100 次：第一次 .write，之后全部 .skip（未触及 30s touch 边界）。
    func testIdenticalSnapshotsWriteOnceThenSkip() {
        var coalescer = LiveStateWriteCoalescer()
        let snapshot = Snapshot(lightMode: 1, switchState: 0, workMode: 0)
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1000), .write)
        for i in 1 ..< 100 {
            // 每 0.1s 一次，100 次共 10s，不到 touchInterval
            XCTAssertEqual(coalescer.decision(for: snapshot, at: 1000 + Double(i) * 0.1), .skip)
        }
    }

    /// 字段真实变化：恰好一次 .write；之后相同快照又恢复 .skip。
    func testFieldChangeWritesExactlyOnce() {
        var coalescer = LiveStateWriteCoalescer()
        let before = Snapshot(lightMode: 1, switchState: 0, workMode: 0)
        let after = Snapshot(lightMode: 1, switchState: 2, workMode: 0)
        XCTAssertEqual(coalescer.decision(for: before, at: 1000), .write)
        XCTAssertEqual(coalescer.decision(for: before, at: 1001), .skip)
        XCTAssertEqual(coalescer.decision(for: after, at: 1002), .write)
        XCTAssertEqual(coalescer.decision(for: after, at: 1003), .skip)
        // 变回去同样是真实变化
        XCTAssertEqual(coalescer.decision(for: before, at: 1004), .write)
    }

    /// 无变化到达 30 秒边界：输出 .touchOnly；touch 之后计时重置，再次 .skip。
    func testTouchOnlyAtBoundaryThenTimerResets() {
        var coalescer = LiveStateWriteCoalescer()
        let snapshot = Snapshot(lightMode: 1, switchState: 0, workMode: 0)
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1000), .write)
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1029.9), .skip)
        // 到达 30s 边界 → touchOnly
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1030), .touchOnly)
        // touch 重置计时：接下来 30s 内都是 skip
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1031), .skip)
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1059.9), .skip)
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1060), .touchOnly)
    }

    /// 事件性写入（hook stateValue，不改 agent* 字段）后基准的 mtime 计时刷新：
    /// 随后相同轮询状态不因到达 touch 边界而误判。
    func testHookEventWriteResetsTouchClock() {
        var coalescer = LiveStateWriteCoalescer()
        let snapshot = Snapshot(lightMode: 1, switchState: 0, workMode: 0)
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1000), .write)
        // t=1025：hook sendState 事件性写入（不改这三个字段，只刷新文件 mtime）
        coalescer.noteEventWrite(Snapshot(), at: 1025)
        // 若无基准刷新，t=1031 会误判 touchOnly；现在距离事件写入才 6s → skip
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1031), .skip)
        // 新的 30s 边界以事件写入为起点
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 1055), .touchOnly)
    }

    /// 事件性写入（虚拟拨杆覆盖，改 switchState）后基准同步：
    /// 随后携带同一 switchState 的轮询快照不误判为变化；
    /// 而真实硬件回包（拨杆值不同）仍会被正确判为变化。
    func testOverrideEventWriteUpdatesBaseline() {
        var coalescer = LiveStateWriteCoalescer()
        let hardware = Snapshot(lightMode: 1, switchState: 0, workMode: 0)
        XCTAssertEqual(coalescer.decision(for: hardware, at: 1000), .write)
        // 用户点击画布虚拟拨杆：事件性写入 switchState=2
        coalescer.noteEventWrite(Snapshot(switchState: 2), at: 1001)
        // 下一次轮询（override 仍生效，Agent 发布的是 effective=2 的快照）→ 不误判
        let overridden = Snapshot(lightMode: 1, switchState: 2, workMode: 0)
        XCTAssertEqual(coalescer.decision(for: overridden, at: 1002), .skip)
        // 真实硬件回包到达（switchState=0），override 清除 → 真实变化，必须写
        XCTAssertEqual(coalescer.decision(for: hardware, at: 1003), .write)
    }

    /// 首次发布（基准为空）必写，即使快照与文件既有内容碰巧一致也无妨——同时建立基准。
    func testFirstDecisionAlwaysWrites() {
        var coalescer = LiveStateWriteCoalescer()
        XCTAssertEqual(coalescer.decision(for: Snapshot(), at: 0), .write)
    }

    /// touchInterval 可注入。
    func testCustomTouchInterval() {
        var coalescer = LiveStateWriteCoalescer(touchInterval: 5)
        let snapshot = Snapshot(lightMode: 1, switchState: 0, workMode: 0)
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 100), .write)
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 104.9), .skip)
        XCTAssertEqual(coalescer.decision(for: snapshot, at: 105), .touchOnly)
    }
}
