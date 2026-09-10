import XCTest
@testable import AhaKeyConfigShared

/// C5F：用户 picker intent 的因果消费。复用 C5ER1 attempt token。
final class AhaKeyStudioPageEditIntentLedgerTests: XCTestCase {
    func testPickerSelectionMatchesExactValueAndContext() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageEditIntentLedger()
        ledger.notePickerSelection(
            activeSet: 0,
            modeSlot: 0,
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(2),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        let values: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue] = [
            .screenActiveSet(modeSlot: 0): .integer(0),
        ]
        XCTAssertEqual(
            ledger.matchingFieldIDs(
                deviceID: device,
                sessionGeneration: .init(1),
                transportGeneration: .init(2),
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                currentValues: values
            ),
            [.screenActiveSet(modeSlot: 0)]
        )
        ledger.observeContext(
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(2),
            pageID: .screen(modeSlot: 0),
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            currentValues: [.screenActiveSet(modeSlot: 0): .integer(1)]
        )
        XCTAssertTrue(
            ledger.matchingFieldIDs(
                deviceID: device,
                sessionGeneration: .init(1),
                transportGeneration: .init(2),
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                currentValues: [.screenActiveSet(modeSlot: 0): .integer(0)]
            ).isEmpty,
            "A→B 后旧 A intent 必须作废"
        )
    }

    func testRuntimeContextChangeVoidsIntentWithoutRegisteringPicker() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageEditIntentLedger()
        ledger.notePickerSelection(
            activeSet: 0,
            modeSlot: 0,
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        ledger.observeContext(
            deviceID: device,
            sessionGeneration: .init(2),
            transportGeneration: .init(1),
            pageID: .screen(modeSlot: 0),
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            currentValues: [.screenActiveSet(modeSlot: 0): .integer(0)]
        )
        XCTAssertTrue(
            ledger.matchingFieldIDs(
                deviceID: device,
                sessionGeneration: .init(1),
                transportGeneration: .init(1),
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                currentValues: [.screenActiveSet(modeSlot: 0): .integer(0)]
            ).isEmpty
        )
    }

    func testAcceptedAttemptClearsIntentAndStaleResultCannotClearNewerIntent() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var confirmation = AhaKeyStudioPageOverwriteConfirmationLedger()
        var ledger = AhaKeyStudioPageEditIntentLedger()
        let snapshot = activeSetSnapshot(set: 0, overwriteConfirmed: true)
        let identity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            snapshot: snapshot
        )
        ledger.notePickerSelection(
            activeSet: 0,
            modeSlot: 0,
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        confirmation.observeCurrentIdentity(identity)
        let stale = confirmation.beginAttempt(for: identity)
        ledger.bindAttempt(stale, fields: [.screenActiveSet(modeSlot: 0)])

        ledger.notePickerSelection(
            activeSet: 1,
            modeSlot: 0,
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        ledger.applyCommitResult(.accepted(AhaKeyRuntimeOperationID()), attempt: stale, currentIdentity: identity)
        XCTAssertEqual(
            ledger.matchingFieldIDs(
                deviceID: device,
                sessionGeneration: .init(1),
                transportGeneration: .init(1),
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                currentValues: [.screenActiveSet(modeSlot: 0): .integer(1)]
            ),
            [.screenActiveSet(modeSlot: 0)],
            "迟到 accepted 不得清新的 B intent"
        )

        var snapshotB = snapshot
        snapshotB.selectedTaskSet = 1
        snapshotB.fields = snapshotB.fields.map { field in
            guard field.id == .screenActiveSet(modeSlot: 0) else { return field }
            var next = field
            next.value = .integer(1)
            return next
        }
        let identityB = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            snapshot: snapshotB
        )
        confirmation.observeCurrentIdentity(identityB)
        let fresh = confirmation.beginAttempt(for: identityB)
        ledger.bindAttempt(fresh, fields: [.screenActiveSet(modeSlot: 0)])
        ledger.applyCommitResult(.noOp, attempt: fresh, currentIdentity: identityB)
        XCTAssertTrue(
            ledger.matchingFieldIDs(
                deviceID: device,
                sessionGeneration: .init(1),
                transportGeneration: .init(1),
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                currentValues: [.screenActiveSet(modeSlot: 0): .integer(1)]
            ).isEmpty
        )
    }

    func testRequiresOverwriteKeepsIntent() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var confirmation = AhaKeyStudioPageOverwriteConfirmationLedger()
        var ledger = AhaKeyStudioPageEditIntentLedger()
        let snapshot = activeSetSnapshot(set: 0, overwriteConfirmed: false)
        let identity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            snapshot: snapshot
        )
        ledger.notePickerSelection(
            activeSet: 0,
            modeSlot: 0,
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        confirmation.observeCurrentIdentity(identity)
        let attempt = confirmation.beginAttempt(for: identity)
        ledger.bindAttempt(attempt, fields: [.screenActiveSet(modeSlot: 0)])
        ledger.applyCommitResult(.requiresOverwriteConfirmation, attempt: attempt, currentIdentity: identity)
        XCTAssertEqual(
            ledger.matchingFieldIDs(
                deviceID: device,
                sessionGeneration: .init(1),
                transportGeneration: .init(1),
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                currentValues: [.screenActiveSet(modeSlot: 0): .integer(0)]
            ),
            [.screenActiveSet(modeSlot: 0)]
        )
    }

    func testErrorAndIdentityMismatchDoNotClearIntent() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var confirmation = AhaKeyStudioPageOverwriteConfirmationLedger()
        var ledger = AhaKeyStudioPageEditIntentLedger()
        let snapshot = activeSetSnapshot(set: 0, overwriteConfirmed: true)
        let identity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            snapshot: snapshot
        )
        ledger.notePickerSelection(
            activeSet: 0,
            modeSlot: 0,
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        confirmation.observeCurrentIdentity(identity)
        let failed = confirmation.beginAttempt(for: identity)
        ledger.bindAttempt(failed, fields: [.screenActiveSet(modeSlot: 0)])
        ledger.noteAttemptFailed(attempt: failed, currentIdentity: identity)
        XCTAssertEqual(
            ledger.matchingFieldIDs(
                deviceID: device,
                sessionGeneration: .init(1),
                transportGeneration: .init(1),
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                currentValues: [.screenActiveSet(modeSlot: 0): .integer(0)]
            ),
            [.screenActiveSet(modeSlot: 0)],
            "error 必须保留 intent"
        )

        confirmation.observeCurrentIdentity(identity)
        let mismatch = confirmation.beginAttempt(for: identity)
        ledger.bindAttempt(mismatch, fields: [.screenActiveSet(modeSlot: 0)])
        let otherIdentity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: try AhaKeyRuntimeDeviceID("OTHER"),
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            snapshot: snapshot
        )
        ledger.applyCommitResult(
            .accepted(AhaKeyRuntimeOperationID()),
            attempt: mismatch,
            currentIdentity: otherIdentity
        )
        XCTAssertEqual(
            ledger.matchingFieldIDs(
                deviceID: device,
                sessionGeneration: .init(1),
                transportGeneration: .init(1),
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                currentValues: [.screenActiveSet(modeSlot: 0): .integer(0)]
            ),
            [.screenActiveSet(modeSlot: 0)],
            "identity 不匹配的 accepted 不得清 intent"
        )
    }

    private func activeSetSnapshot(set: Int, overwriteConfirmed: Bool) -> AhaKeyStudioPageSnapshot {
        AhaKeyStudioPageSnapshot(
            pageID: .screen(modeSlot: 0),
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            selectedTaskSet: set,
            overwriteConfirmed: overwriteConfirmed,
            fields: [
                AhaKeyStudioFrozenField(
                    id: .screenActiveSet(modeSlot: 0),
                    value: .integer(set),
                    isDirty: true,
                    baseline: .unknown
                ),
            ]
        )
    }
}
