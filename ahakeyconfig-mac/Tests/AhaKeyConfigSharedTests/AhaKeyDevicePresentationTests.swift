import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyDevicePresentationTests: XCTestCase {

    // MARK: - 序列号 → 设备编号

    func testLegacySerialNumberPrefixIsIdentifier() {
        XCTAssertEqual(AhaKeyDevicePresentation.shortIdentifier(from: "505C-AABBCCDDEEFF"), "505C")
    }

    func testNewSerialNumberExtractsIdentifierFromUID() {
        XCTAssertEqual(AhaKeyDevicePresentation.shortIdentifier(from: "AHX1-C0F55C506C54889A"), "505C")
    }

    func testSerialNumberParsingIsCaseInsensitive() {
        XCTAssertEqual(AhaKeyDevicePresentation.shortIdentifier(from: "ahx1-c0f55c506c54889a"), "505C")
        XCTAssertEqual(AhaKeyDevicePresentation.shortIdentifier(from: "505c-aabbccddeeff"), "505C")
    }

    func testUnrecognizedSerialNumberReturnsNil() {
        XCTAssertNil(AhaKeyDevicePresentation.shortIdentifier(from: "505C"))
        XCTAssertNil(AhaKeyDevicePresentation.shortIdentifier(from: "AHX1-C0F5"))
        XCTAssertNil(AhaKeyDevicePresentation.shortIdentifier(from: ""))
    }

    // MARK: - 广播 manufacturer data → 设备编号

    func testAdvertisedIdentifierFromManufacturerData() {
        // 前 5 字节固定标识头 + 4 字节 ASCII 十六进制编号
        var data = Data([0x06, 0x00, 0x03, 0x00, 0x80])
        data.append(contentsOf: "505C".utf8)
        XCTAssertEqual(AhaKeyDevicePresentation.advertisedIdentifier(manufacturerData: data), "505C")
    }

    func testAdvertisedIdentifierRejectsBadPayloads() {
        XCTAssertNil(AhaKeyDevicePresentation.advertisedIdentifier(manufacturerData: nil))
        XCTAssertNil(AhaKeyDevicePresentation.advertisedIdentifier(manufacturerData: Data()))
        // 长度不足
        XCTAssertNil(AhaKeyDevicePresentation.advertisedIdentifier(
            manufacturerData: Data([0x06, 0x00, 0x03, 0x00, 0x80, 0x35, 0x30])
        ))
        // 标识头不匹配
        var wrongPrefix = Data([0x07, 0x00, 0x03, 0x00, 0x80])
        wrongPrefix.append(contentsOf: "505C".utf8)
        XCTAssertNil(AhaKeyDevicePresentation.advertisedIdentifier(manufacturerData: wrongPrefix))
        // 非十六进制字符
        var nonHex = Data([0x06, 0x00, 0x03, 0x00, 0x80])
        nonHex.append(contentsOf: "ZZZZ".utf8)
        XCTAssertNil(AhaKeyDevicePresentation.advertisedIdentifier(manufacturerData: nonHex))
    }

    // MARK: - BLE 名匹配（同时认 "AhaKey" 与 "AhaKey X1"）

    func testBLENameMatchingCoversOldAndNewNames() {
        XCTAssertTrue(AhaKeyDevicePresentation.matchesBLEName("AhaKey"))
        XCTAssertTrue(AhaKeyDevicePresentation.matchesBLEName("AhaKey X1"))
        XCTAssertTrue(AhaKeyDevicePresentation.matchesBLEName("ahakey x1"))
        XCTAssertFalse(AhaKeyDevicePresentation.matchesBLEName("Keyboard"))
        XCTAssertFalse(AhaKeyDevicePresentation.matchesBLEName(""))
    }

    // MARK: - 展示辅助

    func testSelectionSubtitleOnlyWhenNeeded() {
        XCTAssertNil(AhaKeyDevicePresentation.selectionSubtitle(identifier: "505C", deviceCount: 1))
        XCTAssertNil(AhaKeyDevicePresentation.selectionSubtitle(identifier: "—", deviceCount: 2))
        XCTAssertEqual(
            AhaKeyDevicePresentation.selectionSubtitle(identifier: "505C", deviceCount: 2),
            "设备编号 505C"
        )
        XCTAssertEqual(
            AhaKeyDevicePresentation.selectionSubtitle(identifier: "505C", deviceCount: 1, needsDisambiguation: true),
            "设备编号 505C"
        )
    }

    func testDiagnosticLabel() {
        XCTAssertEqual(AhaKeyDevicePresentation.diagnosticLabel(identifier: "505C"), "AhaKey X1 / 505C / —")
        XCTAssertEqual(
            AhaKeyDevicePresentation.diagnosticLabel(identifier: "505C", serialNumber: "AHX1-C0F55C506C54889A"),
            "AhaKey X1 / 505C / AHX1-C0F55C506C54889A"
        )
    }
}
