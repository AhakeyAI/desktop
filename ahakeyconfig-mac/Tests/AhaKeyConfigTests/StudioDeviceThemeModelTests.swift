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

    func testReadThenExplicitSelectionAndRapidClicksAreSerialized() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        model.choose(.light, using: port.access)
        XCTAssertTrue(port.requests.isEmpty)
        model.read(deviceID: "A", using: port.access)
        try await waitFor { port.continuation != nil }
        port.reply(.dark)
        try await waitFor { !model.isBusy }
        XCTAssertEqual(model.confirmed, .dark)
        model.choose(.light, using: port.access)
        model.choose(.dark, using: port.access)
        try await waitFor { port.continuation != nil }
        XCTAssertEqual(port.requests.count, 2)
        XCTAssertEqual(port.requests.last?.0, "A")
        XCTAssertEqual(port.requests.last?.1, .light)
        XCTAssertEqual(model.confirmed, .dark)
        port.reply(.light, saved: true)
        try await waitFor { !model.isBusy }
        XCTAssertEqual(model.confirmed, .light)
        XCTAssertEqual(model.message, "已保存")
    }

    func testNewKeyboardDiscardsLateSaveCompletion() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        model.read(deviceID: "A", using: port.access)
        try await waitFor { port.continuation != nil }
        port.reply(.dark)
        try await waitFor { !model.isBusy }
        model.choose(.light, using: port.access)
        try await waitFor { port.continuation != nil }
        model.invalidateIfChanged(deviceID: "B")
        XCTAssertNil(model.confirmed)
        port.reply(.light, saved: true)
        await Task.yield()
        XCTAssertNil(model.confirmed)
        XCTAssertNotEqual(model.message, "已保存")
    }

    func testReadbackMismatchShowsActualWithoutSuccess() async throws {
        let port = Port(), model = StudioDeviceThemeModel()
        model.read(deviceID: "A", using: port.access)
        try await waitFor { port.continuation != nil }
        port.reply(.dark)
        try await waitFor { !model.isBusy }
        model.choose(.light, using: port.access)
        try await waitFor { port.continuation != nil }
        port.reply(.dark, saved: false)
        try await waitFor { !model.isBusy }
        XCTAssertEqual(model.confirmed, .dark)
        XCTAssertNotEqual(model.message, "已保存")
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
