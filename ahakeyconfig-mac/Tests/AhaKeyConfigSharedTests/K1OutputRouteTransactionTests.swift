import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class K1OutputRouteTransactionTests: XCTestCase {
    private final class Keyboard {
        var routes = Array(repeating: K1OutputRoute(kind: .ordinary, action: Data([0x73, 1, 0x6D]))!, count: 4)
        var commands: [K1OutputRouteCommand] = []
        var staged = Data()
        var legacyACK = false, changeCRC = false, wrongChunkACK = false, loseCommit = false, disconnected = false
        var loseConnectionAfterCommit = false, changeOtherMode = false
        enum Lost: Error { case acknowledgement, connection }
        func check() throws { if disconnected { throw Lost.connection } }
        func exchange(_ command: K1OutputRouteCommand) throws -> Data {
            commands.append(command)
            let id = le(command.correlation)
            let fields: [UInt8]
            switch command {
            case .capability:
                if legacyACK { return Data([0xAA, 0xBB, 0x9E, 0, 0xCC, 0xDD]) }
                fields = id + [3, 4]
            case .read(_, let mode, let offset, let count):
                let bytes = routes[Int(mode)].serialized
                let checksum = WS3ResourcePayload.checksum(bytes) ^ (changeCRC && offset > 0 ? 1 : 0)
                fields = id + [mode, offset, 102, 0] + le(checksum) + Array(bytes[Int(offset)..<(Int(offset) + Int(count))])
            case .begin:
                staged = Data(); fields = id + id + [0, 0]
            case .chunk(_, let selector, let offset, let bytes):
                XCTAssertEqual(Int(offset), staged.count)
                staged.append(bytes)
                let end = UInt32(staged.count + (wrongChunkACK ? 1 : 0))
                fields = id + [selector] + Array(le(end).prefix(2)) + [UInt8(bytes.count)]
            case .commit(_, let selector):
                routes[Int(selector)] = K1OutputRoute(serialized: staged)!
                if changeOtherMode { routes[(Int(selector) + 1) % 4] = K1OutputRoute(kind: .ordinary, action: Data())! }
                if loseConnectionAfterCommit { disconnected = true }
                if loseCommit || loseConnectionAfterCommit { throw Lost.acknowledgement }
                fields = id + [selector] + le(WS3ResourcePayload.checksum(staged))
            default: XCTFail("No Restore mutation belongs to a route save"); throw Lost.connection
            }
            return Data([0xAA, 0xBB, 0x9E, 0, 1, command.subcommand] + fields + [0xCC, 0xDD])
        }
        private func le(_ n: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) } }
        var writes: [K1OutputRouteCommand] { commands.filter { [0x20, 0x21, 0x22].contains($0.subcommand) } }
        var commits: Int { commands.filter { $0.subcommand == 0x22 }.count }
    }
    private var consumer: K1OutputRoute { K1OutputRoute(kind: .consumer, action: Data([0xCF, 0]))! }

    func testConsumerSaveChangesOnlySelectedModeAndChecksEveryOtherRoute() async throws {
        let keyboard = Keyboard(), before = Keyboard().routes
        var prepared = false, started = false
        let result = try await K1OutputRouteTransaction.save(mode: 2, baseline: before[2], target: consumer,
            maximumRequestBytes: 62, checkSession: keyboard.check, prepareHost: { prepared = true },
            writeStarted: { XCTAssertTrue(prepared); started = true }, exchange: keyboard.exchange)
        XCTAssertTrue(started)
        XCTAssertEqual(result.routes[2], consumer)
        for i in [0, 1, 3] { XCTAssertEqual(result.routes[i], before[i]) }
        XCTAssertEqual(keyboard.commits, 1)
        XCTAssertEqual(keyboard.writes.first?.subcommand, 0x20)
        for command in keyboard.writes {
            switch command {
            case .begin(_, let selector, _, _), .chunk(_, let selector, _, _), .commit(_, let selector): XCTAssertEqual(selector, 2)
            default: XCTFail("Unrelated mutation")
            }
        }
    }
    func test20ByteTransportUsesContiguousSmallChunksWithoutNewFragmentation() async throws {
        let keyboard = Keyboard()
        _ = try await K1OutputRouteTransaction.save(mode: 0, baseline: keyboard.routes[0], target: consumer,
            maximumRequestBytes: 20, checkSession: keyboard.check, exchange: keyboard.exchange)
        XCTAssertTrue(keyboard.commands.allSatisfy { $0.request!.count <= 20 })
        XCTAssertEqual(keyboard.commands.filter { $0.subcommand == 0x21 }.count, 21)
    }
    func testTransportTooSmallDoesNotEvenBeginOrPrepareHost() async {
        let keyboard = Keyboard()
        do {
            _ = try await K1OutputRouteTransaction.save(mode: 0, baseline: keyboard.routes[0], target: consumer,
                maximumRequestBytes: 17, checkSession: keyboard.check, prepareHost: { XCTFail() }, exchange: keyboard.exchange)
            XCTFail()
        } catch { XCTAssertEqual(error as? K1OutputRouteTransaction.Failure, .transportLimit) }
        XCTAssertTrue(keyboard.commands.isEmpty)
    }
    func testLegacyACKCannotAuthorizeRouteSave() async {
        let keyboard = Keyboard(); keyboard.legacyACK = true
        do {
            _ = try await K1OutputRouteTransaction.save(mode: 0, baseline: keyboard.routes[0], target: consumer,
                maximumRequestBytes: 62, checkSession: keyboard.check, prepareHost: { XCTFail() }, exchange: keyboard.exchange)
            XCTFail()
        } catch { XCTAssertEqual(error as? K1OutputRouteTransaction.Failure, .unsupported) }
        XCTAssertTrue(keyboard.writes.isEmpty)
    }
    func testConflictRetainsKeyboardValueBeforeHostOrFirmwareMutation() async {
        let keyboard = Keyboard(), baseline = Keyboard().routes[0]
        keyboard.routes[0] = consumer
        do {
            _ = try await K1OutputRouteTransaction.save(mode: 0, baseline: baseline, target: consumer,
                maximumRequestBytes: 62, checkSession: keyboard.check, prepareHost: { XCTFail() }, exchange: keyboard.exchange)
            XCTFail()
        } catch { XCTAssertEqual(error as? K1OutputRouteTransaction.Failure, .changedSinceRead(consumer)) }
        XCTAssertTrue(keyboard.writes.isEmpty)
    }
    func testChangedCRCBetweenSlicesStopsBeforeMutation() async {
        let keyboard = Keyboard(); keyboard.changeCRC = true
        do { _ = try await K1OutputRouteTransaction.read(checkSession: keyboard.check, exchange: keyboard.exchange); XCTFail() }
        catch { XCTAssertEqual(error as? K1OutputRouteTransaction.Failure, .invalidReply) }
        XCTAssertEqual(keyboard.commands.count, 3)
    }
    func testWrongChunkAcknowledgementNeverCommits() async {
        let keyboard = Keyboard(); keyboard.wrongChunkACK = true
        do {
            _ = try await K1OutputRouteTransaction.save(mode: 0, baseline: keyboard.routes[0], target: consumer,
                maximumRequestBytes: 62, checkSession: keyboard.check, exchange: keyboard.exchange)
            XCTFail()
        } catch { XCTAssertEqual(error as? K1OutputRouteTransaction.Failure, .invalidReply) }
        XCTAssertEqual(keyboard.commits, 0)
        XCTAssertNotEqual(keyboard.routes[0], consumer)
    }
    func testLostCommitReplyResolvedByReadbackWithoutReplay() async throws {
        let keyboard = Keyboard(); keyboard.loseCommit = true
        let result = try await K1OutputRouteTransaction.save(mode: 0, baseline: keyboard.routes[0], target: consumer,
            maximumRequestBytes: 62, checkSession: keyboard.check, exchange: keyboard.exchange)
        XCTAssertEqual(result.routes[0], consumer)
        XCTAssertEqual(keyboard.commits, 1)
    }
    func testLostConnectionAfterCommitIsUnconfirmedAndNeverReplayed() async {
        let keyboard = Keyboard(); keyboard.loseConnectionAfterCommit = true
        do {
            _ = try await K1OutputRouteTransaction.save(mode: 0, baseline: keyboard.routes[0], target: consumer,
                maximumRequestBytes: 62, checkSession: keyboard.check, exchange: keyboard.exchange)
            XCTFail()
        } catch { XCTAssertEqual(error as? K1OutputRouteTransaction.Failure, .writeUnconfirmed) }
        XCTAssertEqual(keyboard.commits, 1)
    }
    func testUnexpectedOtherModeChangeCannotBeReportedAsSuccessful() async {
        let keyboard = Keyboard(); keyboard.changeOtherMode = true
        do {
            _ = try await K1OutputRouteTransaction.save(mode: 0, baseline: keyboard.routes[0], target: consumer,
                maximumRequestBytes: 62, checkSession: keyboard.check, exchange: keyboard.exchange)
            XCTFail()
        } catch { XCTAssertEqual(error as? K1OutputRouteTransaction.Failure, .verificationMismatch) }
    }
    func testNoChangePreparesHostButDoesNotOpenFirmwareTransaction() async throws {
        let keyboard = Keyboard(); var prepared = false
        _ = try await K1OutputRouteTransaction.save(mode: 0, baseline: keyboard.routes[0], target: keyboard.routes[0],
            maximumRequestBytes: 62, checkSession: keyboard.check, prepareHost: { prepared = true }, exchange: keyboard.exchange)
        XCTAssertTrue(prepared); XCTAssertTrue(keyboard.writes.isEmpty)
    }
}
