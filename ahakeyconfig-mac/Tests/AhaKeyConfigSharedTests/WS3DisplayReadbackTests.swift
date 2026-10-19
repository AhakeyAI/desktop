import XCTest
@testable import AhaKeyConfigShared

final class WS3DisplayReadbackTests: XCTestCase {
    private let integrity = Data([0xAA, 0xBB, 0x88, 0, 3, 0, 1, 0, 0, 0x70, 0, 0, 0xCC, 0xDD, 0x11, 0x22, 0xCC, 0xDD])
    private let basic = Data([0xAA, 0xBB, 0x88, 0, 2, 0, 1, 2, 0xCC, 0xDD])
    func testReadRequestsAndBoundsMatchFirmwareSelectors() throws {
        XCTAssertEqual(WS3DisplayItem.brightness.request, Data([0xAA, 0xBB, 0x88, 0, 0xCC, 0xDD]))
        XCTAssertEqual(WS3DisplayItem.singleLight(mode: 3, state: 8).request, Data([0xAA, 0xBB, 0x88, 1, 3, 8, 0xCC, 0xDD]))
        for id: UInt8 in 0..<19 {
            for item in [WS3DisplayItem.resourceBasic(id), .resourceIntegrity(id)] {
                XCTAssertEqual(WS3DisplayItem.from(request: try XCTUnwrap(item.request)), item)
            }
        }
        XCTAssertNil(WS3DisplayItem.resourceBasic(19).request)
        XCTAssertNil(WS3DisplayItem.singleLight(mode: 4, state: 0).request)
        XCTAssertNil(WS3DisplayItem.singleLight(mode: 0, state: 9).request)
    }
    func testValuesRequireMatchingSelectorsAndEchoedArguments() {
        let brightness = Data([0xAA, 0xBB, 0x88, 0, 0, 35, 0xCC, 0xDD])
        XCTAssertEqual(WS3DisplayValue.parse(brightness, for: .brightness), .brightness(35))
        XCTAssertNil(WS3DisplayValue.parse(brightness, for: .resourceBasic(0)))
        let light = Data([0xAA, 0xBB, 0x88, 0, 1, 2, 3, 255, 0xCC, 0xDD])
        XCTAssertEqual(WS3DisplayValue.parse(light, for: .singleLight(mode: 2, state: 3)), .singleLight(255))
        XCTAssertNil(WS3DisplayValue.parse(light, for: .singleLight(mode: 1, state: 3)))
    }
    func testIntegrityUsesLittleEndianAndDoesNotSplitOnBinaryTrailerBytes() throws {
        let value = try XCTUnwrap(WS3DisplayValue.parse(integrity, for: .resourceIntegrity(0)))
        XCTAssertEqual(value, .resourceIntegrity(frames: 1, bytes: 28672, crc32: 0x2211DDCC))
        let resource = try XCTUnwrap(WS3ResourceReadback(id: 0, basic: try XCTUnwrap(WS3DisplayValue.parse(basic, for: .resourceBasic(0))), integrity: value))
        XCTAssertTrue(resource.reportsValidUserResource)
        XCTAssertEqual(resource.crc32, 0x2211DDCC)
    }
    func testTornOrMaskedMetadataCannotBecomeAReportedValidResource() {
        let masked = WS3DisplayValue.resourceIntegrity(frames: 0, bytes: 0, crc32: 0)
        let writing = WS3DisplayValue.resourceBasic(userValid: false, writeState: .writing)
        XCTAssertFalse(WS3ResourceReadback(id: 0, basic: writing, integrity: masked)!.reportsValidUserResource)
        XCTAssertNil(WS3ResourceReadback(id: 0, basic: writing, integrity: .resourceIntegrity(frames: 1, bytes: 28672, crc32: 7)))
        XCTAssertNil(WS3ResourceReadback(id: 0, basic: .resourceBasic(userValid: true, writeState: .valid), integrity: masked))
    }
    func testOldGenericAckIsUnsupportedNotAReadbackOrWriteGrant() throws {
        let ack = Data([0xAA, 0xBB, 0x88, 0, 0xCC, 0xDD])
        XCTAssertEqual(WS3DisplayValue.parse(ack, for: .brightness), .unsupported)
        let request = try XCTUnwrap(WS3DisplayItem.brightness.request)
        XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x88, response: ack))
        let known = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: known))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: nil))
        XCTAssertFalse(known.canWriteWS3Resources)
        XCTAssertFalse(known.canUseWS3Presentation)
        for write in [Data([0xAA, 0xBB, 0x89, 0, 35, 0xCC, 0xDD]),
                      Data([0xAA, 0xBB, 0x8E, 0, 35, 0xCC, 0xDD]),
                      Data([0xAA, 0xBB, 0x8D, 0, 0xCC, 0xDD])] {
            XCTAssertFalse(ConfigurationCommandPolicy.permits(write, profile: known))
        }
        for command: UInt8 in 0x89...0x8E {
            XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, command, 0, 0xCC, 0xDD]), profile: known))
        }
    }
    func testRejectedAndMalformedRepliesDoNotBecomeValues() {
        XCTAssertEqual(WS3DisplayValue.parse(Data([0xAA, 0xBB, 0x88, 1, 0xCC, 0xDD]), for: .brightness), .rejected(1))
        XCTAssertNil(WS3DisplayValue.parse(Data(integrity.dropLast()), for: .resourceIntegrity(0)))
        var invalid = basic; invalid[6] = 2
        XCTAssertNil(WS3DisplayValue.parse(invalid, for: .resourceBasic(0)))
        invalid = basic; invalid[7] = 4
        XCTAssertNil(WS3DisplayValue.parse(invalid, for: .resourceBasic(0)))
        invalid = integrity; invalid[8] = 1
        XCTAssertNil(WS3DisplayValue.parse(invalid, for: .resourceIntegrity(0)))
    }
    func testResourceCapacityAndRequestEchoRejectStaleResponses() throws {
        var tooMany = integrity; tooMany[6] = 9; tooMany[8] = 0; tooMany[9] = 0xF0; tooMany[10] = 3
        XCTAssertNil(WS3DisplayValue.parse(tooMany, for: .resourceIntegrity(0)))
        tooMany[5] = 1
        XCTAssertNotNil(WS3DisplayValue.parse(tooMany, for: .resourceIntegrity(1)))
        let request = try XCTUnwrap(WS3DisplayItem.resourceBasic(1).request)
        XCTAssertFalse(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x88, response: basic))
        var current = basic; current[5] = 1
        XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x88, response: current))
    }
    func testDecoderHandlesEveryFragmentationAndCoalescingBoundary() {
        for split in 0...integrity.count {
            var decoder = DeviceFrameDecoder()
            let frames = decoder.append(Data(integrity.prefix(split))) + decoder.append(Data(integrity.dropFirst(split)))
            XCTAssertEqual(frames, [integrity], "split=\(split)")
        }
        var decoder = DeviceFrameDecoder()
        XCTAssertEqual(decoder.append(integrity + basic), [integrity, basic])
    }
}
