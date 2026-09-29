import XCTest
@testable import AhaKeyConfigShared

final class DeviceStateReducerTests: XCTestCase {

    private let sampleStatus = DeviceStateEvent.fullStatus(
        battery: 87, firmwareMain: 1, firmwareSub: 2,
        workMode: 2, lightMode: 1, switchState: 0,
        brightness: 35, activePictureSet: 0
    )

    /// 同一完整状态帧重复 apply 100 次：只有第一次产生快照变化，之后 99 次零变化。
    func testSameFullStatusApplied100TimesOnlyChangesOnce() {
        var core = CoreDeviceSnapshot()
        var diagnostics = DeviceDiagnosticsSnapshot()

        let first = DeviceStateReducer.apply(sampleStatus, core: core, diagnostics: diagnostics)
        XCTAssertNotEqual(first.core, core)
        core = first.core
        diagnostics = first.diagnostics

        for _ in 0 ..< 99 {
            let result = DeviceStateReducer.apply(sampleStatus, core: core, diagnostics: diagnostics)
            XCTAssertEqual(result.core, core)
            XCTAssertEqual(result.diagnostics, diagnostics)
            XCTAssertEqual(result.effect, .none)
        }
    }

    /// 某个字段真实变化：恰好产生一次快照更新，且只有该字段不同。
    func testSingleFieldChangeProducesExactlyOneSnapshotUpdate() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())

        let changed = DeviceStateEvent.fullStatus(
            battery: 87, firmwareMain: 1, firmwareSub: 2,
            workMode: 2, lightMode: 1, switchState: 0,
            brightness: 60, activePictureSet: 0
        )
        let result = DeviceStateReducer.apply(changed, core: base.core, diagnostics: base.diagnostics)
        XCTAssertNotEqual(result.core, base.core)
        XCTAssertEqual(result.core.brightness, 60)

        // 再 apply 同一帧：零变化
        let again = DeviceStateReducer.apply(changed, core: result.core, diagnostics: result.diagnostics)
        XCTAssertEqual(again.core, result.core)
        XCTAssertEqual(again.effect, .none)
    }

    /// workMode 不变时其他字段变化：不触发 workModeChanged；workMode 变化时恰好触发一次。
    func testWorkModeChangedEffectFiresOnlyOnRealChange() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())
        // 首次从初始值 0 → 2，触发一次
        XCTAssertEqual(base.effect, .workModeChanged(2))

        // workMode 不变、其他字段变化：无副作用
        let otherFieldChanged = DeviceStateEvent.fullStatus(
            battery: 50, firmwareMain: 1, firmwareSub: 2,
            workMode: 2, lightMode: 0, switchState: 1,
            brightness: 80, activePictureSet: 0
        )
        let r1 = DeviceStateReducer.apply(otherFieldChanged, core: base.core, diagnostics: base.diagnostics)
        XCTAssertEqual(r1.effect, .none)

        // workMode 真实变化：恰好触发一次
        let workModeChanged = DeviceStateEvent.fullStatus(
            battery: 50, firmwareMain: 1, firmwareSub: 2,
            workMode: 3, lightMode: 0, switchState: 1,
            brightness: 80, activePictureSet: 0
        )
        let r2 = DeviceStateReducer.apply(workModeChanged, core: r1.core, diagnostics: r1.diagnostics)
        XCTAssertEqual(r2.effect, .workModeChanged(3))

        // 同值再 apply：不再触发
        let r3 = DeviceStateReducer.apply(workModeChanged, core: r2.core, diagnostics: r2.diagnostics)
        XCTAssertEqual(r3.effect, .none)
    }

    /// battery 事件只更新电量字段，其他字段不变。
    func testBatteryEventOnlyUpdatesBatteryLevel() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())

        let result = DeviceStateReducer.apply(.battery(42), core: base.core, diagnostics: base.diagnostics)
        XCTAssertEqual(result.core.batteryLevel, 42)
        var expected = base.core
        expected.batteryLevel = 42
        XCTAssertEqual(result.core, expected)
        XCTAssertEqual(result.diagnostics, base.diagnostics)
        XCTAssertEqual(result.effect, .none)
    }

    /// 电量后到覆盖（last-write-wins）：状态帧与 Battery Service notify 谁后到谁生效。
    func testBatteryLastWriteWins() {
        var core = CoreDeviceSnapshot()
        let diagnostics = DeviceDiagnosticsSnapshot()

        core = DeviceStateReducer.apply(.battery(90), core: core, diagnostics: diagnostics).core
        XCTAssertEqual(core.batteryLevel, 90)

        // 完整状态帧后到，覆盖
        core = DeviceStateReducer.apply(sampleStatus, core: core, diagnostics: diagnostics).core
        XCTAssertEqual(core.batteryLevel, 87)

        // notify 后到，再覆盖
        core = DeviceStateReducer.apply(.battery(88), core: core, diagnostics: diagnostics).core
        XCTAssertEqual(core.batteryLevel, 88)
    }

    /// disconnected：连接状态断开、RSSI 复位、任务图套图清空；电量/模式/亮度/设备身份保留（与现有行为一致）。
    func testDisconnectedResetSemantics() {
        var core = CoreDeviceSnapshot()
        var diagnostics = DeviceDiagnosticsSnapshot()

        var result = DeviceStateReducer.apply(.connected(name: "AhaKey-X1", uuid: "ABC-123"), core: core, diagnostics: diagnostics)
        core = result.core
        result = DeviceStateReducer.apply(sampleStatus, core: core, diagnostics: result.diagnostics)
        core = result.core
        result = DeviceStateReducer.apply(.rssi(-55), core: core, diagnostics: result.diagnostics)
        diagnostics = result.diagnostics

        let after = DeviceStateReducer.apply(.disconnected, core: core, diagnostics: diagnostics)
        XCTAssertFalse(after.core.isConnected)
        XCTAssertEqual(after.core.activeTaskPictureSets, [:])
        XCTAssertEqual(after.diagnostics.signalStrength, 0)
        // 保留项
        XCTAssertEqual(after.core.batteryLevel, 87)
        XCTAssertEqual(after.core.workMode, 2)
        XCTAssertEqual(after.core.brightness, 35)
        XCTAssertEqual(after.core.deviceName, "AhaKey-X1")
        XCTAssertEqual(after.core.deviceUUID, "ABC-123")
    }

    /// rssi 事件只影响 diagnostics 投影，不影响 core 投影。
    func testRSSIOnlyTouchesDiagnostics() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())

        let result = DeviceStateReducer.apply(.rssi(-61), core: base.core, diagnostics: base.diagnostics)
        XCTAssertEqual(result.core, base.core)
        XCTAssertEqual(result.diagnostics.signalStrength, -61)
        XCTAssertEqual(result.effect, .none)
    }

    // MARK: - pending 乐观拨杆（阶段 5）

    /// userSetSwitch：快照携带 pending，发布一次，无副作用。
    func testUserSetSwitchSetsPending() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())

        let result = DeviceStateReducer.apply(.userSetSwitch(1), core: base.core, diagnostics: base.diagnostics)
        XCTAssertNotEqual(result.core, base.core)
        XCTAssertEqual(result.core.pendingSwitchOverride, 1)
        XCTAssertEqual(result.core.switchState, 0) // 确认值不动
        XCTAssertEqual(result.effect, .none)
    }

    /// 匹配回包：pending 清除、确认值入库，且恰好一次快照变化（重复同帧零变化）。
    func testMatchingReplyConfirmsAndClearsPending() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())
        let pending = DeviceStateReducer.apply(.userSetSwitch(1), core: base.core, diagnostics: base.diagnostics)

        let matching = DeviceStateEvent.fullStatus(
            battery: 87, firmwareMain: 1, firmwareSub: 2,
            workMode: 2, lightMode: 1, switchState: 1,
            brightness: 35, activePictureSet: 0
        )
        let confirmed = DeviceStateReducer.apply(matching, core: pending.core, diagnostics: pending.diagnostics)
        XCTAssertNotEqual(confirmed.core, pending.core)
        XCTAssertNil(confirmed.core.pendingSwitchOverride)
        XCTAssertEqual(confirmed.core.switchState, 1)
        XCTAssertEqual(confirmed.effect, .none)

        // 确认后同一帧再来：零变化零发布
        let again = DeviceStateReducer.apply(matching, core: confirmed.core, diagnostics: confirmed.diagnostics)
        XCTAssertEqual(again.core, confirmed.core)
        XCTAssertEqual(again.effect, .none)
    }

    /// 不匹配回包：视为在途旧帧——pending 与拨杆字段不动，其他字段正常更新。
    func testMismatchingReplyKeepsPendingAndSwitchUntouched() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())
        let pending = DeviceStateReducer.apply(.userSetSwitch(1), core: base.core, diagnostics: base.diagnostics)

        let stale = DeviceStateEvent.fullStatus(
            battery: 60, firmwareMain: 1, firmwareSub: 2,
            workMode: 2, lightMode: 1, switchState: 0,
            brightness: 50, activePictureSet: 0
        )
        let result = DeviceStateReducer.apply(stale, core: pending.core, diagnostics: pending.diagnostics)
        XCTAssertEqual(result.core.pendingSwitchOverride, 1)
        XCTAssertEqual(result.core.switchState, 0)
        // 其他字段照常更新
        XCTAssertEqual(result.core.batteryLevel, 60)
        XCTAssertEqual(result.core.brightness, 50)
        XCTAssertEqual(result.effect, .none)
    }

    /// 超时：清除 pending、回退到最后确认值，并产出"命令失败"副作用。
    func testTimeoutRevertsToLastConfirmedValueWithEffect() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())
        let pending = DeviceStateReducer.apply(.userSetSwitch(1), core: base.core, diagnostics: base.diagnostics)

        let timedOut = DeviceStateReducer.apply(.switchOverrideTimeout, core: pending.core, diagnostics: pending.diagnostics)
        XCTAssertNil(timedOut.core.pendingSwitchOverride)
        XCTAssertEqual(timedOut.core.switchState, 0) // 最后确认值
        XCTAssertEqual(timedOut.effect, .switchOverrideTimedOut)
    }

    /// pending 已确认后超时事件晚到（正常竞争）：零变化零副作用。
    func testLateTimeoutAfterConfirmationIsNoOp() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())

        let result = DeviceStateReducer.apply(.switchOverrideTimeout, core: base.core, diagnostics: base.diagnostics)
        XCTAssertEqual(result.core, base.core)
        XCTAssertEqual(result.effect, .none)
    }

    /// 外部确认（Agent 共享文件轮询）：值一致清除 pending 并入库；不一致忽略。
    func testSwitchOverrideConfirmedSemantics() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())
        let pending = DeviceStateReducer.apply(.userSetSwitch(1), core: base.core, diagnostics: base.diagnostics)

        // 不一致：忽略（在途旧帧）
        let mismatched = DeviceStateReducer.apply(.switchOverrideConfirmed(0), core: pending.core, diagnostics: pending.diagnostics)
        XCTAssertEqual(mismatched.core, pending.core)
        XCTAssertEqual(mismatched.effect, .none)

        // 一致：清除 pending、确认值入库
        let confirmed = DeviceStateReducer.apply(.switchOverrideConfirmed(1), core: pending.core, diagnostics: pending.diagnostics)
        XCTAssertNil(confirmed.core.pendingSwitchOverride)
        XCTAssertEqual(confirmed.core.switchState, 1)
        XCTAssertEqual(confirmed.effect, .none)
    }
}
