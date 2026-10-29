import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class K1RouteReadFragmentBudgetTests: XCTestCase {
    private final class Link {
        let routes: [K1OutputRoute] = [
            K1OutputRoute(kind: .consumer, action: Data([0xCF, 0]))!,
            K1OutputRoute(kind: .ordinary, action: Data([0x74, 98] + Array(repeating: [UInt8(0xAA), 0xBB, 0xCC, 0xDD], count: 25).flatMap { $0 }.prefix(98)))!,
            K1OutputRoute(kind: .ordinary, action: Data([0x73, 1, 0x6D]))!,
            K1OutputRoute(kind: .ordinary, action: Data())!
        ]
        var requested: [K1OutputRouteCommand] = []
        var changeChecksum = false
        enum Failure: Error { case missingFinalNotification, unexpectedWrite }

        func frame(for command: K1OutputRouteCommand) throws -> Data {
            let fields: [UInt8]
            switch command {
            case .capability: fields = le(command.correlation) + [3, 4]
            case .read(_, let mode, let offset, let count):
                let data = routes[Int(mode)].serialized
                let crc = WS3ResourcePayload.checksum(data) ^ (changeChecksum && offset > 0 ? 1 : 0)
                fields = le(command.correlation) + [mode, offset, 102, 0] + le(crc) + Array(data[Int(offset)..<(Int(offset) + Int(count))])
            default: throw Failure.unexpectedWrite
            }
            return Data([0xAA, 0xBB, 0x9E, 0, 1, command.subcommand] + fields + [0xCC, 0xDD])
        }
        func exchange(_ command: K1OutputRouteCommand) throws -> Data {
            requested.append(command)
            let reply = try frame(for: command)
            var framer = DeviceNotificationFramer()
            framer.expectResponse(to: try XCTUnwrap(command.request))
            var delivered: [Data] = []
            // Real 2026-10-29 trace: a 62-byte reply delivered three 20-byte
            // notifications, then its fourth (two-byte) tail never arrived.
            // Model that one-shot notification failure, not a protocol limit.
            for offset in stride(from: 0, to: min(reply.count, 60), by: 20) {
                delivered += framer.append(reply.subdata(in: offset..<min(reply.count, offset + 20)), at: 1)
            }
            guard let complete = delivered.first else { throw Failure.missingFinalNotification }
            return complete
        }
        private func le(_ value: UInt32) -> [UInt8] {
            (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        }
    }

    func testFullFourRouteReadSurvivesObservedNotificationBurstFailure() async throws {
        let link = Link()
        let snapshot = try await K1OutputRouteTransaction.read(checkSession: {}, exchange: link.exchange)
        XCTAssertEqual(snapshot.routes, link.routes, "Read complete records, including a maximum-length action and embedded frame markers")
        for mode: UInt8 in 0..<4 {
            let reads = link.requested.compactMap { command -> (UInt8, UInt8)? in
                guard case .read(_, let actualMode, let offset, let count) = command, actualMode == mode else { return nil }
                return (offset, count)
            }
            var end = 0
            for (offset, count) in reads {
                XCTAssertEqual(Int(offset), end)
                end += Int(count)
            }
            XCTAssertEqual(end, 102)
        }
        XCTAssertTrue(link.requested.allSatisfy { [0x00, 0x10].contains($0.subcommand) })
    }

    func testMissingTailDoesNotBecomeAValidShorterRecord() throws {
        let link = Link()
        let command = K1OutputRouteCommand.read(nonce: 0x4161601E, mode: 0, offset: 0, count: 42)
        let full = try link.frame(for: command)
        XCTAssertEqual(full.count, 62)
        var framer = DeviceNotificationFramer()
        framer.expectResponse(to: command.request!)
        for offset in [0, 20, 40] {
            XCTAssertTrue(framer.append(full.subdata(in: offset..<(offset + 20)), at: 1).isEmpty)
        }
        XCTAssertEqual(framer.append(full.suffix(2), at: 1.1), [full], "The decoder already accepts the final two-byte fragment when it actually arrives")
    }

    func testSmallerReadsStillRejectMixedChecksumSnapshots() async {
        let link = Link(); link.changeChecksum = true
        do {
            _ = try await K1OutputRouteTransaction.read(checkSession: {}, exchange: link.exchange)
            XCTFail("A changed record must never be accepted")
        } catch {
            XCTAssertEqual(error as? K1OutputRouteTransaction.Failure, .invalidReply)
        }
    }
}
