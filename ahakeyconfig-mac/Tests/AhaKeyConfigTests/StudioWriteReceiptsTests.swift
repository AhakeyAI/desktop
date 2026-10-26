import XCTest
@testable import AhaKeyConfig

final class StudioWriteReceiptsTests: XCTestCase {
    func testScopeIdentifiersRoundTripWithoutBecomingReadbackFacts() {
        let values: Set<String> = ["A:2:0", "legacy:B:1:oledDisplay"]
        XCTAssertEqual(StudioWriteReceipts.decode(StudioWriteReceipts.encode(values)), values)
        var resolved = values; resolved.remove("A:2:0")
        XCTAssertEqual(StudioWriteReceipts.decode(StudioWriteReceipts.encode(resolved)), ["legacy:B:1:oledDisplay"])
    }
    func testMalformedOrExcessiveIdentifiersAreNotLoaded() {
        XCTAssertTrue(StudioWriteReceipts.decode(Data()).isEmpty)
        XCTAssertTrue(StudioWriteReceipts.decode(Data("[42]".utf8)).isEmpty)
        XCTAssertTrue(StudioWriteReceipts.decode(StudioWriteReceipts.encode([String(repeating: "A", count: 257)])).isEmpty)
    }
}
