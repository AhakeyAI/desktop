import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class WS3LightCatalogTests: XCTestCase {
    private func baseline(_ generation: UInt64 = 7) -> WS3DisplaySnapshot {
        .init(generation: generation, brightness: 35, resources: (UInt8(0)..<19).map {
            WS3ResourceReadback(id: $0, basic: .resourceBasic(userValid: false, writeState: .empty),
                integrity: .resourceIntegrity(frames: 0, bytes: 0, crc32: 0))!
        })
    }
    private func reply(_ request: Data, effect: UInt8? = nil) -> Data {
        let b = [UInt8](request)
        return Data([0xAA, 0xBB, 0x88, 0, 1, b[4], b[5], effect ?? UInt8((Int(b[4]) * 9 + Int(b[5])) % 17), 0xCC, 0xDD])
    }

    func testReadsExactlyFourByNineInOrderIncludingOffAndUnknown() async throws {
        var sent: [Data] = []
        let actual = try await ConfirmedWS3LightCatalog.read(baseline: baseline(), generation: 7,
            checkSession: {}, exchange: { request in
                sent.append(request)
                return self.reply(request, effect: sent.count == 36 ? 255 : nil)
            })
        XCTAssertEqual(actual.lights.count, 36)
        for index in 0..<36 {
            XCTAssertEqual(sent[index], WS3DisplayItem.singleLight(mode: UInt8(index / 9), state: UInt8(index % 9)).request)
        }
        XCTAssertEqual(actual.light(mode: 0, state: 0)?.effect, 0)
        XCTAssertEqual(actual.light(mode: 3, state: 8)?.effect, 255)
        XCTAssertTrue(sent.allSatisfy { $0[2] == 0x88 })
    }

    func testOldOrIncompleteProofDoesNotSendAnything() async {
        let full = baseline()
        let partial = WS3DisplaySnapshot(generation: 7, brightness: 35, resources: Array(full.resources.dropLast()))
        for proof in [baseline(6), partial] {
            var count = 0
            do {
                _ = try await ConfirmedWS3LightCatalog.read(baseline: proof, generation: 7, checkSession: {}, exchange: {
                    count += 1; return self.reply($0)
                })
                XCTFail()
            } catch { XCTAssertEqual(error as? WS3LightCatalogError, .unverifiedConnection) }
            XCTAssertEqual(count, 0)
        }
    }

    func testRejectedUnsupportedWrongSelectorAndMalformedStopWithoutPartialResult() async {
        let failures: [(Data, WS3LightCatalogError)] = [
            (Data([0xAA, 0xBB, 0x88, 1, 0xCC, 0xDD]), .rejected(1)),
            (Data([0xAA, 0xBB, 0x88, 0, 0xCC, 0xDD]), .unsupported),
            (Data([0xAA, 0xBB, 0x88, 0, 1, 3, 8, 5, 0xCC, 0xDD]), .invalidReply),
            (Data([0xAA, 0xBB, 0x88, 0, 1, 0, 3, 5, 9, 0xCC, 0xDD]), .invalidReply)
        ]
        for (bad, expected) in failures {
            var count = 0
            do {
                _ = try await ConfirmedWS3LightCatalog.read(baseline: baseline(), generation: 7, checkSession: {}, exchange: {
                    count += 1; return count == 4 ? bad : self.reply($0)
                })
                XCTFail()
            } catch { XCTAssertEqual(error as? WS3LightCatalogError, expected) }
            XCTAssertEqual(count, 4)
        }
    }

    func testConnectionChangeAfterReplyStopsBeforeNextQuery() async {
        var current: UInt64 = 7, count = 0
        do {
            _ = try await ConfirmedWS3LightCatalog.read(baseline: baseline(), generation: 7, checkSession: {
                guard current == 7 else { throw WS3LightCatalogError.unverifiedConnection }
            }, exchange: {
                count += 1
                if count == 2 { current = 8 }
                return self.reply($0)
            })
            XCTFail()
        } catch { XCTAssertEqual(error as? WS3LightCatalogError, .unverifiedConnection) }
        XCTAssertEqual(count, 2)
    }

    func testTaskCancellationDuringReplyStopsAndReturnsNoCatalog() async throws {
        let entered = expectation(description: "fifth read pending")
        var pending: CheckedContinuation<Data, Never>?, count = 0, held: Data?
        let work = Task { @MainActor in
            try await ConfirmedWS3LightCatalog.read(baseline: baseline(), generation: 7, checkSession: {}, exchange: {
                count += 1
                if count == 5 {
                    held = self.reply($0)
                    entered.fulfill()
                    return await withCheckedContinuation { pending = $0 }
                }
                return self.reply($0)
            })
        }
        await fulfillment(of: [entered], timeout: 2)
        work.cancel(); pending?.resume(returning: try XCTUnwrap(held))
        do { _ = try await work.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(count, 5)
    }

    func testCompleteSnapshotRejectsDuplicatesMissingInvalidAndMixedGeneration() {
        let rows = (0..<36).map { WS3SingleLightSnapshot(generation: 7, mode: UInt8($0 / 9), state: UInt8($0 % 9), effect: 0) }
        XCTAssertNotNil(WS3LightCatalogSnapshot(generation: 7, lights: Array(rows.reversed())))
        XCTAssertNil(WS3LightCatalogSnapshot(generation: 7, lights: Array(rows.dropLast())))
        for bad in [rows[0], .init(generation: 7, mode: 4, state: 0, effect: 1), .init(generation: 8, mode: 3, state: 8, effect: 1)] {
            XCTAssertNil(WS3LightCatalogSnapshot(generation: 7, lights: Array(rows.dropLast()) + [bad]))
        }
    }

    func testSingleItemUpdatePreservesOtherReadingsAndRejectsStaleGeneration() throws {
        let rows = (0..<36).map { WS3SingleLightSnapshot(generation: 7, mode: UInt8($0 / 9), state: UInt8($0 % 9), effect: 0) }
        let catalog = try XCTUnwrap(WS3LightCatalogSnapshot(generation: 7, lights: rows))
        let updated = try XCTUnwrap(catalog.replacing(.init(generation: 7, mode: 2, state: 5, effect: 16)))
        XCTAssertEqual(updated.light(mode: 2, state: 5)?.effect, 16)
        XCTAssertEqual(updated.lights.filter { $0.effect == 0 }.count, 35)
        XCTAssertNil(catalog.replacing(.init(generation: 8, mode: 2, state: 5, effect: 1)))
        XCTAssertNil(catalog.light(mode: 4, state: 0))
    }
}
