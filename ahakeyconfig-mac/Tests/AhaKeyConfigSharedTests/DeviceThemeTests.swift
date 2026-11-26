import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class DeviceThemeTests: XCTestCase {
    private func reading(_ theme: AhaKeyDeviceTheme) -> Data {
        Data([0xAA, 0xBB, 0x88, 0, 4, 1, 3, theme.rawValue, 0x55, 0x49, 0xCC, 0xDD])
    }
    private let ack = Data([0xAA, 0xBB, 0x8E, 0, 0xCC, 0xDD])

    func testExactFramesAndBothValues() {
        XCTAssertEqual(AhaKeyDeviceThemeProtocol.query, Data([0xAA, 0xBB, 0x88, 4, 0xCC, 0xDD]))
        for theme in AhaKeyDeviceTheme.allCases {
            XCTAssertEqual(AhaKeyDeviceThemeProtocol.set(theme),
                Data([0xAA, 0xBB, 0x8E, 2, theme.rawValue, 0xCC, 0xDD]))
            XCTAssertEqual(AhaKeyDeviceThemeProtocol.parseRead(reading(theme)), theme)
            XCTAssertTrue(AhaKeyDeviceThemeProtocol.isSetRequest(AhaKeyDeviceThemeProtocol.set(theme)))
        }
    }

    func testStrictReadAndAckValidation() {
        let valid = reading(.dark)
        for length in 0..<valid.count {
            XCTAssertNil(AhaKeyDeviceThemeProtocol.parseRead(valid.prefix(length)))
        }
        for index in valid.indices where index != 7 {
            var bad = valid; bad[index] ^= 1
            XCTAssertNil(AhaKeyDeviceThemeProtocol.parseRead(bad), "byte \(index)")
        }
        for value in UInt8(2)...UInt8.max {
            var bad = valid; bad[7] = value
            XCTAssertNil(AhaKeyDeviceThemeProtocol.parseRead(bad))
        }
        XCTAssertNil(AhaKeyDeviceThemeProtocol.parseRead(valid + Data([0])))
        XCTAssertEqual(AhaKeyDeviceThemeProtocol.parseRead((Data([0]) + valid).dropFirst()), .dark)
        XCTAssertTrue(AhaKeyDeviceThemeProtocol.isSuccessAck(ack))
        for index in ack.indices {
            var bad = ack; bad[index] ^= 1
            XCTAssertFalse(AhaKeyDeviceThemeProtocol.isSuccessAck(bad))
        }
        XCTAssertFalse(AhaKeyDeviceThemeProtocol.isSuccessAck(ack + Data([0])))
    }

    func testFramerHandlesEveryReadAndSetAckSplit() {
        for frame in [reading(.dark), reading(.light), ack] {
            for split in 1..<frame.count {
                var decoder = DeviceNotificationFramer()
                XCTAssertTrue(decoder.append(frame.prefix(split)).isEmpty)
                XCTAssertEqual(decoder.append(frame.dropFirst(split)), [frame])
            }
        }
        var decoder = DeviceNotificationFramer()
        XCTAssertEqual(decoder.append(reading(.light) + ack), [reading(.light), ack])
    }

    func testMatcherAcceptsNegativeProbeButNeverAnotherSelector() {
        let query = AhaKeyDeviceThemeProtocol.query
        XCTAssertTrue(DeviceResponseMatcher.matches(request: query, expectedCommand: 0x88, response: reading(.light)))
        XCTAssertTrue(DeviceResponseMatcher.matches(request: query, expectedCommand: 0x88,
            response: Data([0xAA, 0xBB, 0x88, 0, 0xCC, 0xDD])))
        XCTAssertFalse(DeviceResponseMatcher.matches(request: query, expectedCommand: 0x88,
            response: Data([0xAA, 0xBB, 0x88, 0, 0, 35, 0xCC, 0xDD])))
    }

    func testPolicyRequiresCurrentCapabilityAndNarrowGrantIncludingLegacy() {
        for profile: FirmwareCapabilityProfile? in [nil, .legacyAfterStatusReadback()] {
            XCTAssertTrue(ConfigurationCommandPolicy.permits(AhaKeyDeviceThemeProtocol.query, profile: profile))
            let request = AhaKeyDeviceThemeProtocol.set(.light)
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .deviceTheme))
            XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: profile,
                confirmedWrite: .deviceTheme, deviceThemeReadbackVerified: true))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request + Data([0]), profile: profile,
                confirmedWrite: .deviceTheme, deviceThemeReadbackVerified: true))
        }
        XCTAssertFalse(WS3CommandOwnership.permits(ack, uploading: false, updating: false,
            grant: .ws3Display, themeActive: true))
        XCTAssertTrue(WS3CommandOwnership.permits(AhaKeyDeviceThemeProtocol.set(.light), uploading: false,
            updating: false, grant: .deviceTheme, themeActive: true))
        XCTAssertFalse(WS3CommandOwnership.permits(AhaKeyDeviceThemeProtocol.set(.light), uploading: true,
            updating: false, grant: .deviceTheme))
    }

    func testReadDoesNotWriteAndSaveDiscoversBeforeSetThenReadsBack() async throws {
        var commands: [Data] = []
        let read = try await DeviceThemeTransaction.run(validate: {}, exchange: { request in
            commands.append(request); return self.reading(.dark)
        })
        XCTAssertEqual(read.theme, .dark)
        XCTAssertFalse(read.saved)
        XCTAssertEqual(commands, [AhaKeyDeviceThemeProtocol.query])
        commands = []
        let result = try await DeviceThemeTransaction.run(selection: .light, validate: {}, exchange: { request in
            commands.append(request)
            return request[2] == 0x8E ? self.ack : self.reading(commands.count == 1 ? .dark : .light)
        })
        XCTAssertTrue(result.saved)
        XCTAssertEqual(commands, [AhaKeyDeviceThemeProtocol.query, AhaKeyDeviceThemeProtocol.set(.light),
                                   AhaKeyDeviceThemeProtocol.query])
    }

    func testGenericAckOrBusyDoesNotAuthorizeSet() async {
        for reply in [Data([0xAA, 0xBB, 0x88, 0, 0xCC, 0xDD]),
                      Data([0xAA, 0xBB, 0x88, 1, 0xCC, 0xDD])] {
            var commands: [Data] = []
            do {
                _ = try await DeviceThemeTransaction.run(selection: .light, validate: {}, exchange: { request in
                    commands.append(request); return reply
                })
                XCTFail("unverified capability cannot write")
            } catch {}
            XCTAssertEqual(commands, [AhaKeyDeviceThemeProtocol.query])
        }
    }

    func testRejectedSetDoesNotReadBackOrClaimSaved() async {
        var commands: [Data] = []
        do {
            _ = try await DeviceThemeTransaction.run(selection: .light, validate: {}, exchange: { request in
                commands.append(request)
                return request[2] == 0x88 ? self.reading(.dark) : Data([0xAA, 0xBB, 0x8E, 1, 0xCC, 0xDD])
            })
            XCTFail("rejected SET cannot succeed")
        } catch {}
        XCTAssertEqual(commands.count, 2)
    }

    func testMismatchedReadbackReturnsDeviceValueWithoutSaved() async throws {
        let result = try await DeviceThemeTransaction.run(selection: .light, validate: {}, exchange: { request in
            request[2] == 0x88 ? self.reading(.dark) : self.ack
        })
        XCTAssertEqual(result.theme, .dark)
        XCTAssertFalse(result.saved)
    }

    func testChangedSessionStopsBeforeSet() async {
        var current = true
        var commands: [Data] = []
        do {
            _ = try await DeviceThemeTransaction.run(selection: .light, validate: {
                if !current { throw CancellationError() }
            }, exchange: { request in
                commands.append(request); current = false; return self.reading(.dark)
            })
            XCTFail("replaced connection cannot write")
        } catch {}
        XCTAssertEqual(commands, [AhaKeyDeviceThemeProtocol.query])
    }

    func testTimeoutDoesNotAutomaticallyRetrySet() async {
        var commands: [Data] = []
        do {
            _ = try await DeviceThemeTransaction.run(selection: .light, validate: {}, exchange: { request in
                commands.append(request)
                if request[2] == 0x8E { throw CancellationError() }
                return self.reading(.dark)
            })
            XCTFail("timed out SET cannot succeed")
        } catch {}
        XCTAssertEqual(commands.count, 2)
    }
}
