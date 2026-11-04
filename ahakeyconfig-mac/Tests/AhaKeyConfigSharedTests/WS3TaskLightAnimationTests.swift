import XCTest
@testable import AhaKeyConfigShared

final class WS3TaskLightAnimationTests: XCTestCase {
    func testMockHasThreeSessionsAndOneEmptySlotAcrossStateChanges() {
        let first = WS3TaskLightAnimation.mock(at: 0)
        let later = WS3TaskLightAnimation.mock(at: 3)
        XCTAssertEqual(first.snapshot.slots.compactMap { $0?.state }, [.running, .waiting, .done])
        XCTAssertEqual(later.snapshot.slots.compactMap { $0?.state }, [.waiting, .running, .done])
        XCTAssertNil(later.snapshot.slots[3])
        XCTAssertLessThan(later.intensity(slot: 0, at: 3.3), 0.2)
        XCTAssertEqual(later.intensity(slot: 2, at: 3.3), 1)
    }

    func testOnlyChangedSlotFlashesAndDuplicateSnapshotsDoNotRestartFlash() {
        var lights = WS3TaskLightAnimation()
        let original = WS3TaskLightAnimation.mock(at: 0).snapshot
        lights.observe(original, at: 0)
        XCTAssertEqual(lights.intensity(slot: 0, at: 5), 1)
        let changed = WS3TaskSnapshot(slots: [.init(state: .waiting), original.slots[1], original.slots[2], nil])!
        lights.observe(changed, at: 5)
        lights.observe(changed, at: 5.2)
        XCTAssertLessThan(lights.intensity(slot: 0, at: 5.3), 0.2)
        XCTAssertEqual(lights.intensity(slot: 1, at: 5.3), 1)
        XCTAssertEqual(lights.intensity(slot: 3, at: 5.3), 0)
        XCTAssertEqual(lights.intensity(slot: 0, at: 7), 1)
        lights.observe(original, at: 8)
        XCTAssertLessThan(lights.intensity(slot: 0, at: 8.3), 0.2)
    }
}
