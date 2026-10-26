import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class K1RouteInitializationTests: XCTestCase {
    private final class Keyboard {
        var routes: [K1OutputRoute]?
        var staged = Data()
        var commands: [K1OutputRouteCommand] = []
        var loseCommitReply = false
        var refuseCommit = false
        var restoreState: K1RestoreState?
        var afterChunk: (() -> Void)?
        enum Failure: Error { case lostReply }
        private func le(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        func exchange(_ command: K1OutputRouteCommand) throws -> Data {
            commands.append(command)
            let id = le(command.correlation)
            var status: UInt8 = 0
            let fields: [UInt8]
            switch command {
            case .restoreStatus:
                let state = restoreState ?? (routes == nil ? .storageUnavailable : .never)
                status = state == .storageUnavailable ? 1 : 0
                let attempt: UInt32 = [.incomplete, .inProgress, .complete].contains(state) ? 1 : 0
                fields = id + [state.rawValue] + le(attempt)
            case .capability: fields = id + [3, 4]
            case .begin(_, let selector, let length, _):
                XCTAssertEqual(selector, 0xFF); XCTAssertEqual(length, 408)
                staged = Data(); fields = id + id + [0, 0]
            case .chunk(_, let selector, let offset, let bytes):
                XCTAssertEqual(selector, 0xFF)
                XCTAssertEqual(Int(offset), staged.count)
                staged.append(bytes)
                fields = id + [selector] + Array(le(UInt32(staged.count)).prefix(2)) + [UInt8(bytes.count)]
                afterChunk?()
            case .commit(_, let selector):
                XCTAssertEqual(selector, 0xFF); XCTAssertEqual(staged.count, 408)
                if refuseCommit { status = 1; fields = id }
                else {
                    routes = (0..<4).map { K1OutputRoute(serialized: staged.subdata(in: ($0 * 102)..<(($0 + 1) * 102)))! }
                    if loseCommitReply { throw Failure.lostReply }
                    fields = id + [selector] + le(WS3ResourcePayload.checksum(staged))
                }
            case .read(_, let mode, let offset, let count):
                if let routes {
                    let bytes = routes[Int(mode)].serialized
                    fields = id + [mode, offset, 102, 0] + le(WS3ResourcePayload.checksum(bytes)) +
                        Array(bytes[Int(offset)..<(Int(offset) + Int(count))])
                } else { status = 1; fields = id }
            default: XCTFail("No reset or unrelated write belongs to initialization"); throw Failure.lostReply
            }
            return Data([0xAA, 0xBB, 0x9E, status, 1, command.subcommand] + fields + [0xCC, 0xDD])
        }
        var mutations: [K1OutputRouteCommand] { commands.filter { [0x20, 0x21, 0x22].contains($0.subcommand) } }
        var commits: Int { commands.filter { $0.subcommand == 0x22 }.count }
    }
    private func ordinary() -> K1RouteInitialization.Inputs {
        let keys = (UInt8(0)..<4).map { mode in
            OrdinaryKeyReadback(mode: mode, keyIndex: 0, actionType: mode == 3 ? 0 : 0x73,
                action: mode == 3 ? Data() : Data([0x6D]), description: Data("keep".utf8))
        }
        return .init(voiceState: 3, keys: keys)!
    }
    func testMacPresetBecomesConsumerInAllFourModesRatherThanInactiveF18() throws {
        let input = try XCTUnwrap(K1RouteInitialization.Inputs(voiceState: 2, keys: []))
        for route in input.routes.routes {
            XCTAssertEqual(route.kind, .consumer)
            XCTAssertEqual(route.action, Data([0xCF, 0]))
        }
    }
    func testUnknownIncompleteAndOversizedOrdinarySourcesAreNeverFilledWithDefaults() {
        XCTAssertNil(K1RouteInitialization.Inputs(voiceState: 3, keys: []))
        XCTAssertNil(K1RouteInitialization.Inputs(voiceState: 255, keys: []))
        var keys = ordinary().keys
        keys[1] = keys[0]
        XCTAssertNil(K1RouteInitialization.Inputs(voiceState: 3, keys: keys))
        keys = ordinary().keys
        keys[0] = .init(mode: 0, keyIndex: 0, actionType: 0x74, action: Data(repeating: 1, count: 99), description: Data())
        XCTAssertNil(K1RouteInitialization.Inputs(voiceState: 3, keys: keys))
    }
    func testInitializeUsesSingle408ByteCommitAndVerifiesEveryMode() async throws {
        let keyboard = Keyboard(), input = ordinary()
        let baseline = try await K1RouteInitialization.prepare(checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
        let actual = try await K1RouteInitialization.initialize(baseline: baseline, userConfirmed: true,
            maximumRequestBytes: 20, checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
        XCTAssertEqual(actual, input.routes)
        XCTAssertEqual(keyboard.commits, 1)
        XCTAssertEqual(keyboard.staged.count, 408)
        XCTAssertTrue(keyboard.commands.allSatisfy { $0.request!.count <= 20 })
    }
    func testNoConfirmationOrSmallTransportNeverBegins() async throws {
        for (consent, limit) in [(false, 62), (true, 17)] {
            let keyboard = Keyboard(), input = ordinary()
            let baseline = try await K1RouteInitialization.prepare(checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
            let before = keyboard.commands.count
            do {
                _ = try await K1RouteInitialization.initialize(baseline: baseline, userConfirmed: consent,
                    maximumRequestBytes: limit, checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
                XCTFail("expected preflight failure")
            } catch {}
            XCTAssertEqual(keyboard.commands.count, before)
            XCTAssertTrue(keyboard.mutations.isEmpty)
        }
    }
    func testExistingRecordAndIncompleteResetCannotBeOverwritten() async {
        for state in [K1RestoreState.never, .incomplete, .complete] {
            let keyboard = Keyboard(); keyboard.restoreState = state
            do {
                _ = try await K1RouteInitialization.prepare(checkSession: {}, exchange: keyboard.exchange, readInputs: { self.ordinary() })
                XCTFail("record is not available for bootstrap")
            } catch {
                XCTAssertEqual(error as? K1RouteInitialization.Failure, state == .incomplete ? .restoreUnfinished : .alreadyAvailable)
            }
            XCTAssertTrue(keyboard.mutations.isEmpty)
        }
    }
    func testSourceChangesDuringTransferStopBeforeCommit() async throws {
        let keyboard = Keyboard(), input = ordinary()
        let consumer = K1RouteInitialization.Inputs(voiceState: 2, keys: [])!
        var changed = false
        let baseline = try await K1RouteInitialization.prepare(checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
        keyboard.afterChunk = { changed = true }
        do {
            _ = try await K1RouteInitialization.initialize(baseline: baseline, userConfirmed: true,
                maximumRequestBytes: 62, checkSession: {}, exchange: keyboard.exchange,
                readInputs: { changed ? consumer : input })
            XCTFail("source changed")
        } catch { XCTAssertEqual(error as? K1RouteInitialization.Failure, .changedSinceRead) }
        XCTAssertEqual(keyboard.commits, 0)
        XCTAssertNil(keyboard.routes)
    }
    func testLostCommitReplyRecoversOnlyByReadingAndNeverRepeatsMutation() async throws {
        let keyboard = Keyboard(), input = ordinary()
        let baseline = try await K1RouteInitialization.prepare(checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
        keyboard.loseCommitReply = true
        let actual = try await K1RouteInitialization.initialize(baseline: baseline, userConfirmed: true,
            maximumRequestBytes: 62, checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
        XCTAssertEqual(actual, input.routes)
        XCTAssertEqual(keyboard.commits, 1)
    }
    func testActiveVoiceHostStopsBeforeAnyMutationOrWriteReceipt() async throws {
        let keyboard = Keyboard(), input = ordinary()
        let baseline = try await K1RouteInitialization.prepare(checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
        var markedStarted = false
        do {
            _ = try await K1RouteInitialization.initialize(baseline: baseline, userConfirmed: true,
                maximumRequestBytes: 62, checkSession: {}, exchange: keyboard.exchange,
                readInputs: { input }, prepareHost: { throw K1RouteInitialization.Failure.hostBusy },
                writeStarted: { markedStarted = true })
            XCTFail("active recording must prevent publication")
        } catch { XCTAssertEqual(error as? K1RouteInitialization.Failure, .hostBusy) }
        XCTAssertFalse(markedStarted)
        XCTAssertTrue(keyboard.mutations.isEmpty)
    }
    func testFirmwareRefusalCannotBeReportedAsInitialized() async throws {
        let keyboard = Keyboard(), input = ordinary()
        let baseline = try await K1RouteInitialization.prepare(checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
        keyboard.refuseCommit = true
        do {
            _ = try await K1RouteInitialization.initialize(baseline: baseline, userConfirmed: true,
                maximumRequestBytes: 62, checkSession: {}, exchange: keyboard.exchange, readInputs: { input })
            XCTFail("firmware refused publication")
        } catch { XCTAssertEqual(error as? K1RouteInitialization.Failure, .writeUnconfirmed) }
        XCTAssertNil(keyboard.routes)
        XCTAssertEqual(keyboard.commits, 1)
    }
}
