import XCTest
@testable import AhaKeyConfig
@testable import AhaKeyConfigShared

@MainActor
final class StudioRestoreInspectorModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let initial = RestoreInitializationTransaction.Snapshot(handled: true, state: .never, attempt: 0)!
    private let complete = RestoreInitializationTransaction.Snapshot(handled: true, state: .complete, attempt: 1)!
    override func setUp() async throws {
        suite = "StudioRestoreInspectorModelTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testReadAndCancelledConfirmationNeverStartRestore() async {
        let model = StudioRestoreInspectorModel(defaults: defaults)
        var starts = 0
        let access = StudioRestoreInspectorModel.Access(
            read: { .init(deviceID: "device", value: self.initial) },
            start: { _, _, _ in starts += 1; throw URLError(.cancelled) },
            verify: { _ in XCTFail("not complete"); throw URLError(.cancelled) })
        await model.read(using: access)
        XCTAssertFalse(model.canSubmit)
        model.intendsRestore = true
        XCTAssertFalse(model.canSubmit)
        model.usbPowerConfirmed = true
        XCTAssertTrue(model.canSubmit)
        await model.start(using: access, userConfirmed: false)
        XCTAssertEqual(starts, 0)
        XCTAssertNil(defaults.array(forKey: StudioRestoreInspectorModel.pendingKey))
    }
    func testLostReplyPersistsRecoveryIntentAndReopeningDoesNotRetry() async {
        let model = StudioRestoreInspectorModel(defaults: defaults)
        var starts = 0
        let access = StudioRestoreInspectorModel.Access(
            read: { .init(deviceID: "device", value: self.initial) },
            start: { baseline, consent, power in
                XCTAssertEqual(baseline.deviceID, "device")
                XCTAssertTrue(consent); XCTAssertTrue(power)
                starts += 1; throw URLError(.networkConnectionLost)
            }, verify: { _ in XCTFail("no proof"); throw URLError(.cancelled) })
        await model.read(using: access)
        model.intendsRestore = true; model.usbPowerConfirmed = true
        await model.start(using: access, userConfirmed: true)
        XCTAssertNil(model.fact)
        XCTAssertEqual(defaults.stringArray(forKey: StudioRestoreInspectorModel.pendingKey), ["device"])
        let reopened = StudioRestoreInspectorModel(defaults: defaults)
        XCTAssertNotNil(reopened.message)
        XCTAssertFalse(reopened.canSubmit)
        XCTAssertEqual(starts, 1, "reconstruction must not execute a device command")
    }
    func testClaimedVerifiedResultWithoutActualReadbackCannotShowSuccess() async {
        let model = StudioRestoreInspectorModel(defaults: defaults)
        var successes: [Bool] = []
        let observer = model.writeCompleted.sink { successes.append($0.succeeded) }
        defer { observer.cancel() }
        let access = StudioRestoreInspectorModel.Access(
            read: { .init(deviceID: "device", value: self.initial) },
            start: { _, _, _ in .init(result: .verified(self.complete), readback: nil) },
            verify: { _ in .init(result: .needsReadback(self.complete), readback: nil) })
        await model.read(using: access)
        model.intendsRestore = true; model.usbPowerConfirmed = true
        await model.start(using: access, userConfirmed: true)
        XCTAssertEqual(successes, [false])
        XCTAssertTrue(model.canVerify)
        XCTAssertFalse(model.canSubmit)
        XCTAssertEqual(defaults.stringArray(forKey: StudioRestoreInspectorModel.pendingKey), ["device"])
    }
    func testFreshIncompleteReadRequiresNewIntentAndPowerBeforeRetry() async {
        defaults.set(["device"], forKey: StudioRestoreInspectorModel.pendingKey)
        let model = StudioRestoreInspectorModel(defaults: defaults)
        let incomplete = RestoreInitializationTransaction.Snapshot(handled: true, state: .incomplete, attempt: 1)!
        var starts = 0
        let access = StudioRestoreInspectorModel.Access(
            read: { .init(deviceID: "device", value: incomplete) },
            start: { _, _, _ in
                starts += 1
                return .init(result: .refused(incomplete), readback: nil)
            }, verify: { _ in throw URLError(.cancelled) })
        await model.read(using: access)
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(model.canSubmit)
        XCTAssertEqual(defaults.stringArray(forKey: StudioRestoreInspectorModel.pendingKey), [])
        model.intendsRestore = true; model.usbPowerConfirmed = true
        await model.start(using: access, userConfirmed: true)
        XCTAssertEqual(starts, 1)
        XCTAssertFalse(model.intendsRestore)
        XCTAssertFalse(model.usbPowerConfirmed)
    }
    func testCompleteReadOffersVerificationAndRepeatRequiresFreshIntent() async {
        let model = StudioRestoreInspectorModel(defaults: defaults)
        var starts = 0, verifies = 0
        let access = StudioRestoreInspectorModel.Access(
            read: { .init(deviceID: "device", value: self.complete) },
            start: { _, _, _ in
                starts += 1
                return .init(result: .refused(.init(handled: false, state: .complete, attempt: 1)!), readback: nil)
            },
            verify: { baseline in
                XCTAssertEqual(baseline.deviceID, "device")
                verifies += 1
                return .init(result: .needsReadback(self.complete), readback: nil)
            })
        await model.read(using: access)
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(model.canSubmit)
        await model.verify(using: access)
        model.intendsRestore = true; model.usbPowerConfirmed = true
        XCTAssertTrue(model.canSubmit)
        await model.start(using: access, userConfirmed: true)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(verifies, 1)
    }
    func testActiveVoicePreflightDoesNotLeaveAnUnconfirmedReset() async {
        let model = StudioRestoreInspectorModel(defaults: defaults)
        var wrote: [Bool] = []
        let observer = model.writeCompleted.sink { wrote.append($0.wrote) }
        defer { observer.cancel() }
        let access = StudioRestoreInspectorModel.Access(
            read: { .init(deviceID: "device", value: self.initial) },
            start: { _, _, _ in throw StudioRestoreInspectorModel.Failure.voiceActive },
            verify: { _ in throw URLError(.cancelled) })
        await model.read(using: access)
        model.intendsRestore = true; model.usbPowerConfirmed = true
        await model.start(using: access, userConfirmed: true)
        XCTAssertEqual(wrote, [false])
        XCTAssertEqual(model.fact?.value, initial)
        XCTAssertEqual(defaults.stringArray(forKey: StudioRestoreInspectorModel.pendingKey) ?? [], [])
    }

    func testKnownRefusalWithoutStartingAttemptDoesNotPermanentlyBlockRepeat() async {
        for attempt: UInt32 in [1, 2] {
            defaults.removeObject(forKey: StudioRestoreInspectorModel.pendingKey)
            let model = StudioRestoreInspectorModel(defaults: defaults)
            let access = StudioRestoreInspectorModel.Access(
                read: { .init(deviceID: "device", value: self.complete) },
                start: { _, _, _ in
                    .init(result: .refused(.init(handled: false, state: .complete, attempt: attempt)!), readback: nil)
                }, verify: { _ in throw URLError(.cancelled) })
            await model.read(using: access)
            model.intendsRestore = true; model.usbPowerConfirmed = true
            await model.start(using: access, userConfirmed: true)
            XCTAssertEqual(defaults.stringArray(forKey: StudioRestoreInspectorModel.pendingKey) ?? [],
                           attempt == 1 ? [] : ["device"])
        }
    }

    func testFreshCompleteReadAfterLostReplyAllowsOnlyNewExplicitRepeatWithoutClaimingVerified() async {
        defaults.set(["device"], forKey: StudioRestoreInspectorModel.pendingKey)
        let model = StudioRestoreInspectorModel(defaults: defaults)
        var starts = 0, successes = 0
        let observer = model.writeCompleted.sink { if $0.succeeded { successes += 1 } }
        defer { observer.cancel() }
        let access = StudioRestoreInspectorModel.Access(
            read: { .init(deviceID: "device", value: self.complete) },
            start: { _, _, _ in starts += 1; throw URLError(.cancelled) },
            verify: { _ in XCTFail("reading status is not full defaults verification"); throw URLError(.cancelled) })
        await model.read(using: access)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(successes, 0)
        XCTAssertFalse(model.canSubmit)
        XCTAssertTrue(model.canVerify)
        model.intendsRestore = true
        XCTAssertFalse(model.canSubmit)
        model.usbPowerConfirmed = true
        XCTAssertTrue(model.canSubmit, "fresh durable state plus fresh confirmation permits a new v2 attempt")
        XCTAssertEqual(defaults.stringArray(forKey: StudioRestoreInspectorModel.pendingKey) ?? [], [])
        XCTAssertEqual(starts, 0, "neither read nor consent toggles may send the mutation")
    }
}
