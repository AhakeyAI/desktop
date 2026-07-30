import XCTest
@testable import AhaKeyConfig

final class AhaKeyProtocolTests: XCTestCase {
    func testParsesRhinoCapabilities() {
        let payload = Data([
            3, 4, 2, 4,
            0x3F, 0x00,
            0xC8, 0x00,
            0x20, 0x01,
            0x30, 0x01,
            0x02, 0x00, 0x00, 0x00,
            0xF6, 0x5D, 0x2C, 0x82,
            2, 0,
            0x28, 0x01,
            0x30, 0x01,
        ])

        let capabilities = AhaKeyResponseParser.parseCapabilities(payload)

        XCTAssertEqual(capabilities?.protocolVersion, 3)
        XCTAssertEqual(capabilities?.modeCount, 4)
        XCTAssertEqual(capabilities?.setCount, 2)
        XCTAssertEqual(capabilities?.stateCount, 4)
        XCTAssertEqual(capabilities?.maxPacketSize, 200)
        XCTAssertEqual(capabilities?.userSlotLimit, 288)
        XCTAssertEqual(capabilities?.factorySlotBase, 304)
        XCTAssertEqual(capabilities?.factoryBundleVersion, 2)
        XCTAssertEqual(capabilities?.factoryManifestCRC, 0x822C5DF6)
        XCTAssertEqual(capabilities?.factoryStatus, 2)
        XCTAssertEqual(capabilities?.reclaimSlotBase, 296)
        XCTAssertEqual(capabilities?.reclaimSlotLimit, 304)
        XCTAssertTrue(capabilities?.supportsIdleTaskPicture == true)
        XCTAssertTrue(capabilities?.supportsSessionUpload == true)
    }

    func testRejectsTruncatedCapabilities() {
        XCTAssertNil(AhaKeyResponseParser.parseCapabilities(Data(repeating: 0, count: 13)))
    }

    func testParsesCompactCapabilitiesThatFitDefaultBLEMTU() {
        let payload = Data([
            3, 4, 2, 4,
            0x3F, 0x00,
            0xC8, 0x00,
            0x14, 0x01,
            0x1C, 0x01,
            0x24, 0x01,
        ])

        let capabilities = AhaKeyResponseParser.parseCapabilities(payload)

        XCTAssertEqual(capabilities?.protocolVersion, 3)
        XCTAssertEqual(capabilities?.modeCount, 4)
        XCTAssertEqual(capabilities?.stateCount, 4)
        XCTAssertEqual(capabilities?.userSlotLimit, 276)
        XCTAssertEqual(capabilities?.reclaimSlotBase, 284)
        XCTAssertEqual(capabilities?.reclaimSlotLimit, 292)
        XCTAssertTrue(capabilities?.supportsIdleTaskPicture == true)
    }

    func testSessionCommandsUseLittleEndianFields() {
        XCTAssertEqual(
            Array(AhaKeyCommand.prepareSessionWrite(
                sessionID: 0x1234,
                chunkLength: 4096,
                address: 0x00123000
            )),
            [
                0xAA, 0xBB, 0x9B,
                0x34, 0x12,
                0x00, 0x10,
                0x00, 0x30, 0x12, 0x00,
                0xCC, 0xDD,
            ]
        )
        XCTAssertEqual(
            Array(AhaKeyCommand.abortPictureWrite(sessionID: 0x1234)),
            [0xAA, 0xBB, 0x9A, 0x34, 0x12, 0xCC, 0xDD]
        )
    }

    func testImageSourceLimitsMatchNegotiatedPolicy() {
        XCTAssertEqual(AhaKeyCommand.staticOLEDMaxSourceFileBytes, 50 * 1024 * 1024)
        XCTAssertEqual(AhaKeyCommand.animatedOLEDMaxSourceFileBytes, 50 * 1024 * 1024)
        XCTAssertEqual(AhaKeyCommand.taskOLEDMaxFrames, 30)
        XCTAssertEqual(AhaKeyCommand.oledEncodedFrameBytes, 25_600)
    }

    func testStaticGIFFramesCollapseBeforeUpload() {
        let frame = Data(repeating: 0x5A, count: AhaKeyCommand.oledEncodedFrameBytes)
        XCTAssertEqual(
            OLEDFrameEncoder.collapsingStaticFrames([frame, frame, frame]),
            [frame]
        )
        XCTAssertEqual(
            OLEDFrameEncoder.collapsingStaticFrames([
                frame,
                Data(repeating: 0, count: frame.count),
            ]).count,
            2
        )
    }

    func testRhinoCapabilitiesExposeAllFourTaskStates() {
        let capabilities = AhaKeyFirmwareCapabilities(
            protocolVersion: 3,
            modeCount: 4,
            setCount: 2,
            stateCount: 4,
            flags: 0x003F,
            maxPacketSize: 244,
            userSlotLimit: 276,
            factorySlotBase: 276,
            factoryBundleVersion: 1,
            factoryManifestCRC: 0,
            factoryStatus: 2,
            factoryError: 0,
            reclaimSlotBase: 284,
            reclaimSlotLimit: 292
        )

        XCTAssertEqual(
            capabilities.supportedTaskDisplayStates,
            [.idle, .working, .waiting, .done]
        )
    }
}
