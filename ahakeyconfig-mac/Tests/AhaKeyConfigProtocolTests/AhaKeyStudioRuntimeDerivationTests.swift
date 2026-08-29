import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

/// WBS-5.7 切片 3：`AhaKeyStudioRuntimeDerivation` 纯派生函数的 reducer 级单测。
/// 覆盖视图依赖的全部映射口径：offline 空投影、字段映射、协议模式、拨杆、任务图套图、
/// 无 activeDevice、resyncing 仍算在线。
final class AhaKeyStudioRuntimeDerivationTests: XCTestCase {

    // MARK: - 测试夹具

    private func makeDevice(
        id: String = "AA:BB:CC:DD:EE:FF",
        name: String = "AhaKey",
        protocolState: AhaKeyRuntimeDeviceProtocolState = .currentReady,
        preferredTransport: AhaKeyRuntimeTransport = .bluetooth,
        usbAttached: Bool = false,
        bluetoothConnected: Bool = true,
        state: AhaKeyRuntimeDeviceState = .init()
    ) -> AhaKeyRuntimeDeviceSnapshot {
        AhaKeyRuntimeDeviceSnapshot(
            id: try! AhaKeyRuntimeDeviceID(id),
            displayName: name,
            protocolState: protocolState,
            preferredTransport: preferredTransport,
            usbAttached: usbAttached,
            bluetoothConnected: bluetoothConnected,
            state: state
        )
    }

    private func makeSnapshot(
        devices: [AhaKeyRuntimeDeviceSnapshot],
        activeDeviceID: AhaKeyRuntimeDeviceID?,
        revision: UInt64 = 7
    ) -> AhaKeyRuntimeSnapshot {
        AhaKeyRuntimeSnapshot(
            lifecycleState: .running,
            devices: devices,
            activeDeviceID: activeDeviceID,
            configurationRevision: AhaKeyConfigurationRevision(revision),
            operations: [],
            policy: AhaKeyRuntimePolicy(),
            latestEventSequence: AhaKeyRuntimeEventSequence(42)
        )
    }

    // MARK: - offline / 无快照

    func testOfflineYieldsEmptyPresentation() {
        let device = makeDevice()
        let snapshot = makeSnapshot(devices: [device], activeDeviceID: device.id)
        for connection in [AhaKeyStudioRuntimeConnectionState.offline, .connecting] {
            let presentation = AhaKeyStudioRuntimeDerivation.presentation(
                for: AhaKeyStudioRuntimeViewState(connection: connection, snapshot: snapshot)
            )
            XCTAssertFalse(presentation.isConnected)
            XCTAssertFalse(presentation.isConfigurationReady)
            XCTAssertNil(presentation.deviceName)
            XCTAssertNil(presentation.deviceKey)
            XCTAssertNil(presentation.activeDeviceID)
        }
    }

    func testOnlineWithoutSnapshotYieldsEmptyPresentation() {
        let presentation = AhaKeyStudioRuntimeDerivation.presentation(
            for: AhaKeyStudioRuntimeViewState(connection: .online, snapshot: nil)
        )
        XCTAssertEqual(presentation, AhaKeyStudioDevicePresentation())
    }

    // MARK: - 在线字段映射

    func testOnlineDeviceMapsAllFields() throws {
        let state = AhaKeyRuntimeDeviceState(
            batteryLevel: try AhaKeyRuntimePercentage(88),
            workMode: AhaKeyRuntimeModeIndex(2),
            lightMode: AhaKeyRuntimeLightMode(1),
            leverPosition: .up,
            brightness: try AhaKeyRuntimePercentage(40),
            firmwareVersion: "1.2.3",
            activeTaskPictureSets: [
                AhaKeyRuntimeModeIndex(0): AhaKeyRuntimeTaskPictureSetIndex(1),
                AhaKeyRuntimeModeIndex(2): AhaKeyRuntimeTaskPictureSetIndex(3)
            ]
        )
        let device = makeDevice(
            protocolState: .currentReady,
            preferredTransport: .usb,
            usbAttached: true,
            bluetoothConnected: true,
            state: state
        )
        let snapshot = makeSnapshot(devices: [device], activeDeviceID: device.id, revision: 9)
        let presentation = AhaKeyStudioRuntimeDerivation.presentation(
            for: AhaKeyStudioRuntimeViewState(connection: .online, snapshot: snapshot)
        )

        XCTAssertTrue(presentation.isConnected)
        XCTAssertTrue(presentation.isConfigurationReady)
        XCTAssertEqual(presentation.protocolMode, .current)
        XCTAssertEqual(presentation.deviceName, "AhaKey")
        XCTAssertEqual(presentation.deviceKey, device.id.rawValue)
        XCTAssertEqual(presentation.batteryLevel, 88)
        XCTAssertEqual(presentation.workMode, 2)
        XCTAssertEqual(presentation.lightMode, 1)
        XCTAssertEqual(presentation.switchState, 0)
        XCTAssertTrue(presentation.hasReportedSwitchState)
        XCTAssertEqual(presentation.brightness, 40)
        XCTAssertEqual(presentation.firmwareVersion, "1.2.3")
        XCTAssertEqual(presentation.activeTaskPictureSets, [0: 1, 2: 3])
        XCTAssertEqual(presentation.preferredTransport, .usb)
        XCTAssertTrue(presentation.usbAttached)
        XCTAssertTrue(presentation.isUSBConfigurationActive)
        XCTAssertEqual(presentation.configurationRevision, AhaKeyConfigurationRevision(9))
        XCTAssertEqual(presentation.activeDeviceID, device.id)
    }

    // MARK: - 协议模式映射

    func testProtocolStateMapping() {
        let cases: [(AhaKeyRuntimeDeviceProtocolState, AhaKeyProtocolMode)] = [
            (.currentReady, .current),
            (.legacyDenied, .legacyBaseOnly),
            (.restricted, .restrictedUnknown),
            (.failed, .restrictedUnknown),
            (.probing, .negotiating),
            (.disconnected, .negotiating)
        ]
        for (state, expected) in cases {
            XCTAssertEqual(
                AhaKeyStudioRuntimeDerivation.protocolMode(for: state),
                expected,
                "protocolState \(state) 应映射为 \(expected)"
            )
        }
    }

    func testLegacyDeniedDeviceIsNotConfigurationReady() {
        let device = makeDevice(protocolState: .legacyDenied)
        let snapshot = makeSnapshot(devices: [device], activeDeviceID: device.id)
        let presentation = AhaKeyStudioRuntimeDerivation.presentation(
            for: AhaKeyStudioRuntimeViewState(connection: .online, snapshot: snapshot)
        )
        XCTAssertTrue(presentation.isConnected)
        XCTAssertEqual(presentation.protocolMode, .legacyBaseOnly)
        XCTAssertFalse(presentation.isConfigurationReady)
    }

    // MARK: - 拨杆映射

    func testLeverPositionMapping() {
        XCTAssertEqual(AhaKeyStudioRuntimeDerivation.switchState(for: .up), 0)
        XCTAssertEqual(AhaKeyStudioRuntimeDerivation.switchState(for: .middle), 1)
        XCTAssertEqual(AhaKeyStudioRuntimeDerivation.switchState(for: .down), 1)
    }

    func testMissingLeverKeepsDefaultSwitchStateUnreported() {
        let device = makeDevice(state: AhaKeyRuntimeDeviceState(leverPosition: nil))
        let snapshot = makeSnapshot(devices: [device], activeDeviceID: device.id)
        let presentation = AhaKeyStudioRuntimeDerivation.presentation(
            for: AhaKeyStudioRuntimeViewState(connection: .online, snapshot: snapshot)
        )
        XCTAssertFalse(presentation.hasReportedSwitchState)
        XCTAssertNil(presentation.currentConnectionSwitchState)
    }

    // MARK: - activeDevice 缺失 / 连接判据

    func testNoActiveDeviceYieldsConnectionDefaults() {
        let device = makeDevice()
        let snapshot = makeSnapshot(devices: [device], activeDeviceID: nil)
        let presentation = AhaKeyStudioRuntimeDerivation.presentation(
            for: AhaKeyStudioRuntimeViewState(connection: .online, snapshot: snapshot)
        )
        XCTAssertFalse(presentation.isConnected)
        XCTAssertNil(presentation.deviceName)
        XCTAssertNil(presentation.deviceKey)
        // revision 仍从快照带出（与 activeDevice 无关）
        XCTAssertEqual(presentation.configurationRevision, AhaKeyConfigurationRevision(7))
    }

    func testUSBOnlyDeviceCountsAsConnected() {
        let device = makeDevice(usbAttached: true, bluetoothConnected: false)
        let snapshot = makeSnapshot(devices: [device], activeDeviceID: device.id)
        let presentation = AhaKeyStudioRuntimeDerivation.presentation(
            for: AhaKeyStudioRuntimeViewState(connection: .online, snapshot: snapshot)
        )
        XCTAssertTrue(presentation.isConnected)
    }

    // MARK: - resyncing 仍算在线

    func testResyncingStillDerivesFromSnapshot() {
        let device = makeDevice()
        let snapshot = makeSnapshot(devices: [device], activeDeviceID: device.id)
        let presentation = AhaKeyStudioRuntimeDerivation.presentation(
            for: AhaKeyStudioRuntimeViewState(connection: .resyncing, snapshot: snapshot)
        )
        XCTAssertTrue(presentation.isConnected)
        XCTAssertEqual(presentation.deviceName, "AhaKey")
    }

    func testMergingSubmittedModeLeavesOtherModesUntouched() {
        let baseline = AhaKeyStudioDraft.default
        var submitted = baseline.draft(for: .mode1)
        submitted.oled.statusLine = "submitted-mode-1"
        submitted.oled.taskGIFSets[0].assets[3].localAssetPath = "/tmp/cursor.gif"
        let merged = AhaKeyStudioRuntimeStore.mergingSubmittedMode(submitted, into: baseline)
        XCTAssertEqual(merged.draft(for: .mode1).oled.statusLine, "submitted-mode-1")
        XCTAssertEqual(merged.draft(for: .mode1).oled.taskGIFSets[0].assets[3].localAssetPath, "/tmp/cursor.gif")
        XCTAssertEqual(
            merged.draft(for: .mode0).oled.statusLine,
            baseline.draft(for: .mode0).oled.statusLine
        )
        XCTAssertEqual(
            merged.draft(for: .mode2).oled.taskGIFSets[0].assets[3].localAssetPath,
            baseline.draft(for: .mode2).oled.taskGIFSets[0].assets[3].localAssetPath
        )
    }
}
