import XCTest
@testable import AhaKeyConfig

final class AhaKeyTaskPictureCommandTests: XCTestCase {
    func testDraftMigrationRelocatesHistoricalBundlePathsInsideTaskSets() {
        let historicalPath = "/Applications/AhaKey Studio.app/Contents/Resources/DefaultOLED/cursor.gif"
        let currentPath = "/private/tmp/AhaKey Studio.app/Contents/Resources/DefaultOLED/cursor.gif"
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode1)
        var asset = mode.oled.taskAsset(set: 0, state: .done)
        asset.localAssetPath = historicalPath
        mode.oled.updateTaskAsset(set: 0, asset: asset)
        draft.updateMode(mode)

        let migrated = AhaKeyStudioStore.migratedDraft(from: draft) { slot in
            slot == .mode1 ? currentPath : nil
        }

        XCTAssertEqual(
            migrated.draft(for: .mode1).oled.taskAsset(set: 0, state: .done).localAssetPath,
            currentPath
        )
    }

    func testSessionCommandsUseLittleEndianFields() {
        XCTAssertEqual(Array(AhaKeyCommand.prepareSessionWrite(
            sessionID: 0x1234,
            chunkLength: 4096,
            address: 0x0012_3000
        )), [
            0xAA, 0xBB, 0x9B,
            0x34, 0x12,
            0x00, 0x10,
            0x00, 0x30, 0x12, 0x00,
            0xCC, 0xDD,
        ])
        XCTAssertEqual(
            Array(AhaKeyCommand.abortPictureWrite(sessionID: 0x1234)),
            [0xAA, 0xBB, 0x9A, 0x34, 0x12, 0xCC, 0xDD]
        )
    }

    func testLegacyAndCurrentMetadataCommandsRemainDistinct() {
        XCTAssertEqual(Array(AhaKeyCommand.updateTaskPicture(
            mode: 2, state: 3, startIndex: 0x1234, frameCount: 5, timeDelayMs: 83
        )).prefix(5), [0xAA, 0xBB, 0x93, 2, 3])
        XCTAssertEqual(Array(AhaKeyCommand.updateTaskPictureSet(
            mode: 2, set: 1, state: 3, startIndex: 0x1234, frameCount: 5, timeDelayMs: 83
        )).prefix(6), [0xAA, 0xBB, 0x95, 2, 1, 3])
        XCTAssertEqual(
            Array(AhaKeyCommand.readTaskPictureState(mode: 2, state: 3)),
            [0xAA, 0xBB, 0x94, 2, 3, 0xCC, 0xDD]
        )
        XCTAssertEqual(
            Array(AhaKeyCommand.readTaskPictureSet(mode: 2, set: 1, state: 3)),
            [0xAA, 0xBB, 0x96, 2, 1, 3, 0xCC, 0xDD]
        )
    }

    func testLegacyAndCurrentMetadataResponsesUseTheirOwnShape() {
        let legacy = AhaKeyResponseParser.parseTaskPictureStateResponse(Data([
            2, 3, 0x34, 0x12, 5, 0, 83, 0, 0x24, 0x01,
        ]))
        XCTAssertEqual(legacy?.set, 0)
        XCTAssertEqual(legacy?.state, 3)
        XCTAssertEqual(legacy?.startIndex, 0x1234)

        let current = AhaKeyResponseParser.parseTaskPictureSetResponse(Data([
            2, 1, 3, 0x34, 0x12, 5, 0, 83, 0, 0x20, 0x01, 1,
        ]))
        XCTAssertEqual(current?.set, 1)
        XCTAssertEqual(current?.state, 3)
        XCTAssertEqual(current?.activeSet, 1)
    }

    func testGenericSuccessForUnknownLegacyCommandIsNotTaskPictureSupport() {
        // 2026-06-23 之前的 1.x 固件会对未知 0x94 返回这个通用成功空包。
        let response = AhaKeyResponseParser.parseCommandResponse(Data([
            0xAA, 0xBB, 0x94, 0x00, 0xCC, 0xDD,
        ]))

        XCTAssertEqual(response?.cmd, AhaKeyCommand.cmdReadTaskPicState)
        XCTAssertEqual(response?.status, 0)
        XCTAssertEqual(response?.payload, Data())
        XCTAssertNil(AhaKeyResponseParser.parseTaskPictureStateResponse(response?.payload ?? Data()))
    }
}
