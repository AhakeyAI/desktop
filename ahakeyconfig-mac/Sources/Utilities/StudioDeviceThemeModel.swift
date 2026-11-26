import AhaKeyConfigShared
import Combine
import Foundation

@MainActor
final class StudioDeviceThemeModel: ObservableObject {
    struct Reading {
        let deviceID: String
        let result: DeviceThemeTransaction.Result
    }
    struct Access {
        let perform: @MainActor (String?, AhaKeyDeviceTheme?) async throws -> Reading

        static func production(ble: AhaKeyBLEManager, session: StudioInspectorSession) -> Self {
            .init { expectedDeviceID, selection in
                try await session.withConnection(expectedDeviceID: expectedDeviceID) { context in
                    let result = try await ble.configureDeviceTheme(selection: selection)
                    try session.validate(context)
                    return Reading(deviceID: context.deviceID, result: result)
                }
            }
        }
    }

    @Published private(set) var confirmed: AhaKeyDeviceTheme?
    @Published private(set) var deviceID: String?
    @Published private(set) var isBusy = false
    @Published private(set) var showsError = false
    @Published private(set) var message = NSLocalizedString("读取键盘后选择 Dark / Light。", comment: "")
    private var operationID = UUID()
    private var task: Task<Void, Never>?

    func read(deviceID: String?, using access: Access, completion: (() -> Void)? = nil) {
        run(selection: nil, expectedDeviceID: deviceID, using: access, completion: completion)
    }

    func choose(_ theme: AhaKeyDeviceTheme, using access: Access) {
        guard confirmed != nil, let deviceID else { return }
        run(selection: theme, expectedDeviceID: deviceID, using: access)
    }

    func invalidateIfChanged(deviceID: String?) {
        guard let deviceID, let previous = self.deviceID, previous != deviceID else { return }
        cancel()
        confirmed = nil
        self.deviceID = nil
        showsError = true
        message = NSLocalizedString("键盘已变化，请重新读取主题。", comment: "")
    }

    func cancel() {
        operationID = UUID()
        task?.cancel()
        task = nil
        isBusy = false
    }

    private func run(selection: AhaKeyDeviceTheme?, expectedDeviceID: String?, using access: Access,
                     completion: (() -> Void)? = nil) {
        guard !isBusy else { return }
        let id = UUID()
        operationID = id
        isBusy = true
        showsError = false
        message = NSLocalizedString(selection == nil ? "正在读取设备主题…" : "正在保存主题…", comment: "")
        task = Task { @MainActor in
            defer {
                if self.operationID == id {
                    self.isBusy = false
                    self.task = nil
                    completion?()
                }
            }
            do {
                let reading = try await access.perform(expectedDeviceID, selection)
                try Task.checkCancellation()
                guard self.operationID == id else { return }
                guard expectedDeviceID.map({ $0 == reading.deviceID }) ?? true else {
                    throw StudioInspectorSession.Failure.deviceChanged
                }
                self.deviceID = reading.deviceID
                self.confirmed = reading.result.theme
                self.showsError = selection != nil && !reading.result.saved
                self.message = NSLocalizedString(selection == nil ? "已读取设备主题，由键盘掉电保存。"
                    : (reading.result.saved ? "已保存" : "读回主题与选择不一致，请稍后重试。"), comment: "")
            } catch {
                guard self.operationID == id else { return }
                self.showsError = true
                self.message = error.localizedDescription
            }
        }
    }
}
