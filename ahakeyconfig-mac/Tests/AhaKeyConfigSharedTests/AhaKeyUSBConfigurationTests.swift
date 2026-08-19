import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyUSBConfigurationTests: XCTestCase {
    func testCommandReportUsesA1ChannelAndPadsTo64Bytes() throws {
        let frame = Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD])

        let report = try AhaKeyUSBHIDReportCodec.report(channel: .command, payload: frame)

        XCTAssertEqual(report.count, 64)
        XCTAssertEqual(Array(report.prefix(7)), [0xA1, 0x05, 0xAA, 0xBB, 0x04, 0xCC, 0xDD])
        XCTAssertTrue(report.dropFirst(7).allSatisfy { $0 == 0 })
    }

    func testDataReportsSplitPayloadInto62ByteChunks() throws {
        let payload = Data((0 ..< 130).map(UInt8.init))

        let reports = try AhaKeyUSBHIDReportCodec.dataReports(for: payload)

        XCTAssertEqual(reports.count, 3)
        XCTAssertEqual(reports.map { $0.count }, [64, 64, 64])
        XCTAssertEqual(reports.map { $0[0] }, [0xA2, 0xA2, 0xA2])
        XCTAssertEqual(reports.map { $0[1] }, [62, 62, 6])
        let reconstructed = reports.reduce(into: Data()) { result, report in
            result.append(contentsOf: report[2 ..< 2 + Int(report[1])])
        }
        XCTAssertEqual(reconstructed, payload)
    }

    func testInboundReportExtractsProtocolFrameAndRejectsMalformedReports() {
        let firmwareResponse = Data([0xAA, 0xBB, 0x99, 0x00, 0xCC, 0xDD] + [UInt8](repeating: 0, count: 58))
        XCTAssertEqual(
            AhaKeyUSBHIDReportCodec.protocolFrame(from: firmwareResponse),
            Data([0xAA, 0xBB, 0x99, 0x00, 0xCC, 0xDD])
        )
        XCTAssertEqual(
            AhaKeyUSBHIDReportCodec.protocolFrame(from: Data([0x00]) + firmwareResponse),
            Data([0xAA, 0xBB, 0x99, 0x00, 0xCC, 0xDD])
        )

        let valid = Data([0xA1, 0x07, 0x00, 0xAA, 0xBB, 0x99, 0x00, 0xCC, 0xDD] + [UInt8](repeating: 0, count: 55))
        XCTAssertEqual(
            AhaKeyUSBHIDReportCodec.protocolFrame(from: valid),
            Data([0xAA, 0xBB, 0x99, 0x00, 0xCC, 0xDD])
        )

        XCTAssertNil(AhaKeyUSBHIDReportCodec.protocolFrame(from: Data([0xA1, 0x3F] + [UInt8](repeating: 0, count: 62))))
        XCTAssertNil(AhaKeyUSBHIDReportCodec.protocolFrame(from: Data([0xA1, 0x05, 0xAA, 0xBB, 0x99, 0x00, 0x00])))
    }

    func testUSBRouteRequiresCurrentProtocolAttachedDeviceAndOwnedSession() {
        XCTAssertEqual(
            route(protocolMode: .current),
            .usb
        )

        for mode in [
            AhaKeyProtocolMode.negotiating,
            .legacy,
            .legacyBaseOnly,
            .restrictedUnknown,
        ] {
            XCTAssertEqual(
                route(protocolMode: mode),
                .ble
            )
        }

        XCTAssertEqual(
            route(protocolMode: .current, usbAttached: false),
            .ble
        )
        XCTAssertEqual(
            route(protocolMode: .current, configurationSessionOwned: false),
            .ble
        )
        XCTAssertEqual(
            route(protocolMode: .current, forceBLE: true),
            .ble
        )
    }

    func testUSBRouteRequiresUSBAndBLEDeviceIdentifiersToMatch() {
        XCTAssertEqual(route(protocolMode: .current, usbIdentifier: "505C", negotiatedIdentifier: "505C"), .usb)
        XCTAssertEqual(route(protocolMode: .current, usbIdentifier: "515C", negotiatedIdentifier: "505C"), .ble)
        XCTAssertEqual(route(protocolMode: .current, usbIdentifier: nil, negotiatedIdentifier: "505C"), .ble)
        XCTAssertEqual(route(protocolMode: .current, usbIdentifier: "505C", negotiatedIdentifier: nil), .ble)
        XCTAssertEqual(route(protocolMode: .current, usbIdentifier: "—", negotiatedIdentifier: "505C"), .ble)
    }

    private func route(
        protocolMode: AhaKeyProtocolMode,
        usbAttached: Bool = true,
        configurationSessionOwned: Bool = true,
        usbIdentifier: String? = "505C",
        negotiatedIdentifier: String? = "505C",
        forceBLE: Bool = false
    ) -> AhaKeyConfigurationTransportRoute {
        AhaKeyConfigurationTransportSelector.route(
            AhaKeyConfigurationTransportContext(
                protocolMode: protocolMode,
                usbAttached: usbAttached,
                configurationSessionOwned: configurationSessionOwned,
                usbDeviceIdentifier: usbIdentifier,
                negotiatedDeviceIdentifier: negotiatedIdentifier,
                forceBLE: forceBLE
            )
        )
    }
}
