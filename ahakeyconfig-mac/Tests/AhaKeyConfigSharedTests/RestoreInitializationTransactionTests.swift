import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class RestoreInitializationTransactionTests: XCTestCase {
    typealias Restore = RestoreInitializationTransaction
    private let initial = Restore.Snapshot(handled: true, state: .never, attempt: 0)!
    private let complete = Restore.Snapshot(handled: true, state: .complete, attempt: 1)!

    private func reply(_ command: K1OutputRouteCommand, state: K1RestoreState,
                       attempt: UInt32, handled: Bool = true) -> Data {
        func le(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        return Data([0xAA, 0xBB, 0x9E, handled ? 0 : 1, 1, command.subcommand] +
            le(command.correlation) + [state.rawValue] + le(attempt) + [0xCC, 0xDD])
    }
    func testNoMutationOrQueryWithoutExplicitConsentAndPowerConfirmation() async {
        for (consent, power, expected) in [
            (false, true, Restore.Failure.confirmationRequired),
            (true, false, Restore.Failure.externalPowerRequired)
        ] {
            do {
                _ = try await Restore.start(baseline: initial, userConfirmed: consent, usbPowerConfirmed: power,
                    checkSession: {}, exchange: { _ in XCTFail("must not send"); return Data() },
                    writeStarted: { XCTFail("must not start") }, verifyDefaults: { XCTFail("must not verify"); return false })
                XCTFail("expected confirmation failure")
            } catch { XCTAssertEqual(error as? Restore.Failure, expected) }
        }
    }
    func testCompleteStatusNeedsIndependentDefaultsReadbackBeforeSuccess() async throws {
        var commands: [UInt8] = [], started = 0, verified = 0
        let result = try await Restore.start(baseline: initial, userConfirmed: true, usbPowerConfirmed: true,
            checkSession: {}, exchange: { command in
                commands.append(command.subcommand)
                if commands.count == 1 { return self.reply(command, state: .never, attempt: 0) }
                return self.reply(command, state: .complete, attempt: 1)
            }, writeStarted: { started += 1 }, verifyDefaults: { verified += 1; return true })
        XCTAssertEqual(result, .verified(complete))
        XCTAssertEqual(commands, [0x30, 0x31, 0x30, 0x30])
        XCTAssertEqual(started, 1); XCTAssertEqual(verified, 1)
    }
    func testHandledCompleteIsNotSuccessWhenDefaultsDoNotMatch() async throws {
        let result = try await Restore.verify(baseline: complete, checkSession: {},
            exchange: { command in
                XCTAssertEqual(command.subcommand, 0x30)
                return self.reply(command, state: .complete, attempt: 1)
            }, verifyDefaults: { false })
        XCTAssertEqual(result, .needsReadback(complete))
    }
    func testLostStartResponseIsNeverRetriedOrBlindlyReadOnChangedSession() async {
        var mutations = 0
        do {
            _ = try await Restore.start(baseline: initial, userConfirmed: true, usbPowerConfirmed: true,
                checkSession: {}, exchange: { command in
                    if command.subcommand == 0x31 {
                        mutations += 1
                        throw URLError(.networkConnectionLost)
                    }
                    XCTAssertEqual(mutations, 0, "do not query the failed connection")
                    return self.reply(command, state: .never, attempt: 0)
                }, writeStarted: {}, verifyDefaults: { XCTFail("no completion proof"); return false })
            XCTFail("expected unconfirmed outcome")
        } catch { XCTAssertEqual(error as? Restore.Failure, .writeUnconfirmed) }
        XCTAssertEqual(mutations, 1)
    }
    func testCompleteReadDoesNotAutomaticallyStartAnotherRestore() async throws {
        let result = try await Restore.read(checkSession: {}, exchange: { command in
            XCTAssertEqual(command.subcommand, 0x30)
            XCTAssertEqual(command.request?[3], 1, "status remains v1")
            return self.reply(command, state: .complete, attempt: 1)
        })
        XCTAssertEqual(result, complete)
        XCTAssertTrue(result.canStart, "a repeat still requires separate consent and power confirmation")
    }
    func testIncompleteRequiresExplicitRetryAndAdvanceOfAttempt() async throws {
        let incomplete = Restore.Snapshot(handled: true, state: .incomplete, attempt: 4)!
        var mutations = 0
        let result = try await Restore.start(baseline: incomplete, userConfirmed: true, usbPowerConfirmed: true,
            checkSession: {}, exchange: { command in
                if command.subcommand == 0x31 {
                    mutations += 1
                    return self.reply(command, state: .incomplete, attempt: 5, handled: false)
                }
                return self.reply(command, state: .incomplete, attempt: 4)
            }, writeStarted: {}, verifyDefaults: { XCTFail("refused restore"); return false })
        XCTAssertEqual(result, .unfinished(.init(handled: false, state: .incomplete, attempt: 5)!))
        XCTAssertEqual(mutations, 1)
    }
    func testLegacyACKMalformedStateAndStaleNonceNeverProveCapability() async {
        for fixture in 0..<3 {
            do {
                _ = try await Restore.read(checkSession: {}, exchange: { command in
                    if fixture == 0 { return Data([0xAA, 0xBB, 0x9E, 0, 0xCC, 0xDD]) }
                    var data = self.reply(command, state: .complete, attempt: 1)
                    if fixture == 1 { data[6] ^= 1 } else { data[10] = 0xFF }
                    return data
                })
                XCTFail("invalid capability accepted")
            } catch {
                XCTAssertEqual(error as? Restore.Failure, fixture == 0 ? .unsupported : .invalidReply)
            }
        }
    }
}
