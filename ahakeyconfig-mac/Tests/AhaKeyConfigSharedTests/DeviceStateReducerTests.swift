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

    func testPhysicalSwitchStateTracksSuccessiveStatusFrames() {
        let base = DeviceStateReducer.apply(sampleStatus, core: CoreDeviceSnapshot(), diagnostics: DeviceDiagnosticsSnapshot())
        let manual = DeviceStateEvent.fullStatus(
            battery: 87, firmwareMain: 1, firmwareSub: 2,
            workMode: 2, lightMode: 1, switchState: 1,
            brightness: 35, activePictureSet: 0
        )
        let changed = DeviceStateReducer.apply(manual, core: base.core, diagnostics: base.diagnostics)
        XCTAssertEqual(changed.core.switchState, 1)
        XCTAssertEqual(changed.effect, .none)
        let repeated = DeviceStateReducer.apply(manual, core: changed.core, diagnostics: changed.diagnostics)
        XCTAssertEqual(repeated.core, changed.core)
    }
}
