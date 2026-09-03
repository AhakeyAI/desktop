import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyStudioPageModelTests: XCTestCase {
    func testEachFieldOwnsExactlyOnePage() {
        var seen = Set<AhaKeyStudioFieldID>()
        for field in AhaKeyStudioFieldOwnership.allOwnedFields() {
            XCTAssertTrue(seen.insert(field).inserted, "字段重复归属 \(field)")
            _ = AhaKeyStudioFieldOwnership.page(for: field)
        }
        let screen = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done)
        XCTAssertEqual(AhaKeyStudioFieldOwnership.page(for: screen), .screen(modeSlot: 0))
        let key = AhaKeyStudioFieldID.keyAction(modeSlot: 1, role: .voice)
        XCTAssertEqual(AhaKeyStudioFieldOwnership.page(for: key), .key(modeSlot: 1, role: .voice))
        XCTAssertNotEqual(
            AhaKeyStudioFieldOwnership.page(for: key),
            AhaKeyStudioFieldOwnership.page(for: screen)
        )
    }

    func testVerifiedEqualDirtyIsStrictNoOp() {
        let field = AhaKeyStudioFrozenField(
            id: .screenStatusLine(modeSlot: 0),
            value: .text("same"),
            isDirty: true,
            baseline: .init(trust: .verified, value: .text("same"))
        )
        XCTAssertTrue(AhaKeyStudioPageDiffer.isStrictNoOp(field))
    }

    func testWriteConfirmedExactMatchIsStrictNoOp() {
        let value = AhaKeyStudioFieldValue.asset(
            path: "/tmp/a.gif", framesPerSecond: 12, declaredFrameCount: 4,
            pixelWidth: 160, pixelHeight: 80
        )
        let field = AhaKeyStudioFrozenField(
            id: .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done),
            value: value,
            isDirty: true,
            baseline: .init(trust: .writeConfirmed, value: value)
        )
        XCTAssertTrue(AhaKeyStudioPageDiffer.isStrictNoOp(field))
    }

    func testUnknownNeverStrictNoOpWhenDirty() {
        let field = AhaKeyStudioFrozenField(
            id: .screenStatusLine(modeSlot: 0),
            value: .text("x"),
            isDirty: true,
            baseline: .unknown
        )
        XCTAssertFalse(AhaKeyStudioPageDiffer.isStrictNoOp(field))
    }

    func testUnknownNeverStrictNoOpEvenWhenMarkedClean() {
        let field = AhaKeyStudioFrozenField(
            id: .screenStatusLine(modeSlot: 0),
            value: .text("x"),
            isDirty: false,
            baseline: .unknown
        )
        XCTAssertFalse(AhaKeyStudioPageDiffer.isStrictNoOp(field))
    }

    func testLocalCacheProvenanceCannotBecomeVerified() {
        let authority = AhaKeyStudioFieldAuthority(
            value: .text("cached"),
            trust: .verified,
            provenance: .absent
        )
        XCTAssertEqual(authority.resolvedBaseline(), .unknown)
        let writeOnly = AhaKeyStudioFieldAuthority(
            value: .text("wrote"),
            trust: .verified,
            provenance: .writeConfirmation
        )
        XCTAssertEqual(writeOnly.resolvedBaseline().trust, .writeConfirmed)
        XCTAssertNotEqual(writeOnly.resolvedBaseline().trust, .verified)
    }

    func testLeverAndPowerAreNotWritable() {
        XCTAssertFalse(AhaKeyStudioFieldOwnership.isWritable(.lever))
        XCTAssertFalse(AhaKeyStudioFieldOwnership.isWritable(.power))
        XCTAssertTrue(AhaKeyStudioFieldOwnership.fieldIDs(on: .lever).isEmpty)
        XCTAssertTrue(AhaKeyStudioFieldOwnership.fieldIDs(on: .power).isEmpty)
    }

    func testStandardRequiredFieldsUseSelectedLogicalSet() {
        let required = AhaKeyStudioFieldOwnership.requiredFields(
            on: .screen(modeSlot: 0),
            profile: .legacyStandard,
            selectedTaskSet: 1
        )
        XCTAssertEqual(required.count, AhaKeyTaskDisplayState.legacyStates.count)
        XCTAssertFalse(required.contains { id in
            if case .screenTaskAsset(_, _, .idle) = id { return true }
            return false
        })
        XCTAssertTrue(required.allSatisfy {
            if case .screenTaskAsset(_, 1, _) = $0 { return true }
            return false
        })
        XCTAssertTrue(
            AhaKeyStudioFieldOwnership.requiredFields(
                on: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                selectedTaskSet: 1
            ).isEmpty
        )
    }
}
