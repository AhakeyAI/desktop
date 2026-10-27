import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class RestoreRepeatV2Tests: XCTestCase {
    typealias Restore = RestoreInitializationTransaction
    private let baseline = Restore.Snapshot(handled: true, state: .complete, attempt: 7)!
    private let wire = Data([0xAA, 0xBB, 0x9E, 2, 0x31, 0xCC, 0xDD, 0x12, 0x34, 8, 0, 0, 0, 0xCC, 0xDD])

    private func reply(_ command: K1OutputRouteCommand, state: K1RestoreState, attempt: UInt32,
                       handled: Bool = true) -> Data {
        let nonce = (0..<4).map { UInt8(truncatingIfNeeded: command.correlation >> ($0 * 8)) }
        let number = (0..<4).map { UInt8(truncatingIfNeeded: attempt >> ($0 * 8)) }
        return Data([0xAA, 0xBB, 0x9E, handled ? 0 : 1, command.request![3], command.subcommand] +
            nonce + [state.rawValue] + number + [0xCC, 0xDD])
    }

    func testAcceptedFirmwareV2FrameRoundTripsAndReplyRequiresSameVersion() throws {
        let command = try XCTUnwrap(K1OutputRouteCommand(request: wire))
        XCTAssertEqual(command.request, wire)
        XCTAssertEqual(command.subcommand, 0x31)
        XCTAssertEqual(command.correlation, 0x3412DDCC)
        XCTAssertEqual(command.successReplyLength, 17)
        let response = reply(command, state: .complete, attempt: 8)
        XCTAssertEqual(K1OutputRouteReply.parse(response, for: command), .restore(handled: true, state: .complete, attempt: 8))
        var old = response; old[4] = 1
        XCTAssertNil(K1OutputRouteReply.parse(old, for: command))
        XCTAssertNil(K1OutputRouteReply.parse(response, for: .startRestore(nonce: command.correlation)))
    }

    func testV2CannotBeUsedAsStatusOrRouteCommandOrWithZeroAttempt() {
        var status = wire; status[4] = 0x30
        XCTAssertNil(K1OutputRouteCommand(request: status))
        var route = wire; route[4] = 0x00
        XCTAssertNil(K1OutputRouteCommand(request: route))
        var zero = wire; zero.replaceSubrange(9..<13, with: [0, 0, 0, 0])
        XCTAssertNil(K1OutputRouteCommand(request: zero))
        XCTAssertNil(K1OutputRouteCommand(request: wire.dropLast()))
    }

    func testV2UsesDedicatedRestoreGrantAndFreshProof() {
        let profile = FirmwareCapabilityProfile(identity: .knownWS2Catalog)
        XCTAssertFalse(ConfigurationCommandPolicy.permits(wire, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(wire, profile: profile, confirmedWrite: .k1Route,
            k1RouteReadbackVerified: true, restoreReadbackVerified: true))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(wire, profile: profile, confirmedWrite: .restoreInitialization))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(wire, profile: profile,
            confirmedWrite: .restoreInitialization, restoreReadbackVerified: true))
    }

    func testV2ReplyDelimiterBytesDoNotSplitAStream() throws {
        let command = try XCTUnwrap(K1OutputRouteCommand(request: wire))
        let response = reply(command, state: .complete, attempt: 0xDDCC)
        for split in 1..<response.count {
            var decoder = DeviceFrameDecoder()
            decoder.expectResponse(to: wire)
            XCTAssertTrue(decoder.append(response.prefix(split)).isEmpty)
            XCTAssertEqual(decoder.append(response.dropFirst(split)), [response])
            XCTAssertTrue(DeviceResponseMatcher.matches(request: wire, expectedCommand: 0x9E, response: response))
        }
    }

    func testRepeatUsesFreshNextAttemptExactlyOnceAndVerifiesDefaults() async throws {
        var requests: [K1OutputRouteCommand] = [], verified = 0
        let result = try await Restore.start(baseline: baseline, userConfirmed: true, usbPowerConfirmed: true,
            checkSession: {}, exchange: { command in
                requests.append(command)
                return self.reply(command, state: .complete, attempt: requests.count == 1 ? 7 : 8)
            }, writeStarted: {}, verifyDefaults: { verified += 1; return true })
        XCTAssertEqual(result, .verified(.init(handled: true, state: .complete, attempt: 8)!))
        XCTAssertEqual(requests.map(\.subcommand), [0x30, 0x31, 0x30, 0x30])
        let start = try XCTUnwrap(requests.first { $0.subcommand == 0x31 }?.request)
        XCTAssertEqual(start[3], 2)
        XCTAssertEqual(Array(start[9..<13]), [8, 0, 0, 0])
        XCTAssertEqual(verified, 1)
    }

    func testLostV2ReplyNeverResendsOrFallsBackToV1() async {
        var starts = 0
        do {
            _ = try await Restore.start(baseline: baseline, userConfirmed: true, usbPowerConfirmed: true,
                checkSession: {}, exchange: { command in
                    if command.subcommand == 0x31 {
                        starts += 1
                        XCTAssertEqual(command.request?[3], 2)
                        throw URLError(.networkConnectionLost)
                    }
                    XCTAssertEqual(starts, 0)
                    return self.reply(command, state: .complete, attempt: 7)
                }, writeStarted: {}, verifyDefaults: { XCTFail("unconfirmed restore"); return false })
            XCTFail("lost reply must remain unconfirmed")
        } catch { XCTAssertEqual(error as? Restore.Failure, .writeUnconfirmed) }
        XCTAssertEqual(starts, 1)
    }

    func testFailedAcceptedV2AttemptRemainsUnfinishedRatherThanUntouchedRefusal() async throws {
        let failed = Restore.Snapshot(handled: false, state: .incomplete, attempt: 8)!
        let result = try await Restore.start(baseline: baseline, userConfirmed: true, usbPowerConfirmed: true,
            checkSession: {}, exchange: { command in
                command.subcommand == 0x31
                    ? self.reply(command, state: .incomplete, attempt: 8, handled: false)
                    : self.reply(command, state: .complete, attempt: 7)
            }, writeStarted: {}, verifyDefaults: { XCTFail("failed attempt"); return false })
        XCTAssertEqual(result, .unfinished(failed))
    }

    func testVersion1ReplyToRepeatCannotTriggerFallbackOrVerification() async {
        var starts = 0
        do {
            _ = try await Restore.start(baseline: baseline, userConfirmed: true, usbPowerConfirmed: true,
                checkSession: {}, exchange: { command in
                    if command.subcommand == 0x31 {
                        starts += 1
                        var frame = self.reply(command, state: .complete, attempt: 7, handled: false)
                        frame[4] = 1
                        return frame
                    }
                    return self.reply(command, state: .complete, attempt: 7)
                }, writeStarted: {}, verifyDefaults: { XCTFail("old version is not proof"); return false })
            XCTFail("wrong-version result must stay unconfirmed")
        } catch { XCTAssertEqual(error as? Restore.Failure, .writeUnconfirmed) }
        XCTAssertEqual(starts, 1)
    }

    func testAttemptOverflowAndChangedBaselineNeverSendStart() async {
        for (state, attempt, expected) in [(K1RestoreState.complete, UInt32.max, Restore.Failure.unavailable),
                                          (.complete, 8, .changedSinceRead)] {
            let saved = attempt == UInt32.max ? Restore.Snapshot(handled: true, state: state, attempt: attempt)! : baseline
            do {
                _ = try await Restore.start(baseline: saved, userConfirmed: true, usbPowerConfirmed: true,
                    checkSession: {}, exchange: { command in
                        XCTAssertEqual(command.subcommand, 0x30)
                        return self.reply(command, state: state, attempt: attempt)
                    }, writeStarted: { XCTFail("no mutation") }, verifyDefaults: { false })
                XCTFail("expected admission failure")
            } catch { XCTAssertEqual(error as? Restore.Failure, expected) }
        }
    }
}
