import XCTest
@testable import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioDeviceThemeModelTests: XCTestCase {
    private final class Port {
        var requests: [(String?, AhaKeyDeviceTheme?)] = []
        var continuation: CheckedContinuation<StudioDeviceThemeModel.Reading, Error>?
        var access: StudioDeviceThemeModel.Access {
            .init { deviceID, selection in
                self.requests.append((deviceID, selection))
                return try await withCheckedThrowingContinuation { self.continuation = $0 }
            }
        }
        func reply(_ theme: AhaKeyDeviceTheme, saved: Bool = false, deviceID: String = "A") {
            let pending = continuation; continuation = nil
            pending?.resume(returning: .init(deviceID: deviceID, result: .init(theme: theme, saved: saved)))
        }
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw StudioInspectorSession.Failure.connectionTimeout
    }

    private func readDark(_ model: StudioDeviceThemeModel, _ port: Port) async throws {
        model.read(deviceID: "A", using: port.access)
        try await waitFor { port.continuation != nil }
        port.reply(.dark)
        try await waitFor { !model.isBusy }
    }

    func testThemeChoiceMustNotReachDeviceBeforeWriteButton() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        try await readDark(model, port)
        model.choose(.light)
        await Task.yield()
        XCTAssertEqual(port.requests.count, 1, "Selecting a theme must only stage a draft, not contact the keyboard")
        XCTAssertEqual(model.confirmed, .dark)
        XCTAssertEqual(model.selected, .light)
        XCTAssertTrue(model.hasDraft)
        XCTAssertFalse(model.isBusy)
    }

    func testExplicitWriteSerializesSubmissionAndClearsOnlyAfterReadback() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        model.choose(.light)
        XCTAssertFalse(model.hasDraft)
        try await readDark(model, port)
        model.choose(.light)
        let save = Task { try await model.writeDraft(expectedDeviceID: "A", using: port.access) }
        try await waitFor { port.continuation != nil }
        model.choose(.dark)
        do {
            try await model.writeDraft(expectedDeviceID: "A", using: port.access)
            XCTFail("Concurrent write must be rejected")
        } catch {}
        XCTAssertEqual(port.requests.count, 2)
        XCTAssertEqual(port.requests.last?.0, "A")
        XCTAssertEqual(port.requests.last?.1, .light)
        XCTAssertEqual(model.confirmed, .dark)
        XCTAssertTrue(model.hasDraft)
        port.reply(.light, saved: true)
        try await save.value
        XCTAssertEqual(model.confirmed, .light)
        XCTAssertFalse(model.hasDraft)
        XCTAssertFalse(model.isBusy)
    }

    func testNewKeyboardDiscardsLateSaveCompletion() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        try await readDark(model, port)
        model.choose(.light)
        let save = Task { try await model.writeDraft(expectedDeviceID: "A", using: port.access) }
        try await waitFor { port.continuation != nil }
        model.invalidateIfChanged(deviceID: "B")
        XCTAssertNil(model.confirmed)
        XCTAssertFalse(model.hasDraft)
        port.reply(.light, saved: true)
        do { try await save.value; XCTFail("Old device reply cannot confirm success") } catch {}
        XCTAssertNil(model.confirmed)
        XCTAssertNotEqual(model.message, "已保存")
    }

    func testReadbackMismatchKeepsDraftAndActualDeviceValue() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        try await readDark(model, port)
        model.choose(.light)
        let save = Task { try await model.writeDraft(expectedDeviceID: "A", using: port.access) }
        try await waitFor { port.continuation != nil }
        port.reply(.dark, saved: false)
        do { try await save.value; XCTFail("Mismatch cannot save") } catch {}
        XCTAssertEqual(model.confirmed, .dark)
        XCTAssertEqual(model.selected, .light)
        XCTAssertTrue(model.hasDraft)
        XCTAssertTrue(model.showsError)
    }

    func testRefreshPreservesPendingDraftAndChoosingActualValueClearsIt() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        try await readDark(model, port)
        model.choose(.light)
        try await readDark(model, port)
        XCTAssertEqual(model.selected, .light)
        XCTAssertTrue(model.hasDraft)
        model.choose(.dark)
        XCTAssertFalse(model.hasDraft)
        XCTAssertEqual(port.requests.count, 2, "Only the two explicit reads may reach the device")
    }

    func testSubmissionRequiresSameKeyboardAsDraft() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        try await readDark(model, port)
        model.choose(.light)
        do {
            try await model.writeDraft(expectedDeviceID: "B", using: port.access)
            XCTFail("Cannot submit A's draft to B")
        } catch {}
        XCTAssertEqual(port.requests.count, 1)
        XCTAssertTrue(model.hasDraft)
    }

    func testWrongDeviceCannotPublishConfirmedTheme() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        model.read(deviceID: "A", using: port.access)
        try await waitFor { port.continuation != nil }
        port.reply(.light, saved: true, deviceID: "B")
        try await waitFor { !model.isBusy }
        XCTAssertNil(model.confirmed)
        XCTAssertNotEqual(model.message, "已保存")
    }
}
