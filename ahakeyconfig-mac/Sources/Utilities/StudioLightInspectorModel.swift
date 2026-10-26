import Foundation
import Combine
import AhaKeyConfigShared

@MainActor
final class StudioLightInspectorModel: ObservableObject {
    struct Conflict: Identifiable {
        let id = UUID()
        let target: StudioLightDrafts.Target
        let actual: StudioLightDrafts.Fact
        let desired: UInt8
    }

    static let storageKey = "ahakey.studio.light.inspector.v1"
    private let defaults: UserDefaults
    @Published var values: StudioLightDrafts {
        didSet {
            if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: Self.storageKey) }
        }
    }
    @Published private(set) var catalog: WS3LightCatalogSnapshot?
    let writeCompleted = PassthroughSubject<(message: String, wrote: Bool), Never>()
    @Published var batchConflict: StudioInlineLightBatch.Conflict?
    @Published var selectedState: UInt8 = 0
    @Published private(set) var showsError = false
    @Published var message: String?
    @Published var conflict: Conflict?
    @Published private(set) var isBusy = false
    private var operation: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(StudioLightDrafts.self, from: $0) } ?? .init()
    }

    func target(for mode: AhaKeyModeSlot) -> StudioLightDrafts.Target {
        .effect(mode: UInt8(mode.rawValue), state: selectedState)
    }

    func previewEffect(_ effect: LightEffectStyle, mode: AhaKeyModeSlot,
                       ble: AhaKeyBLEManager, session: StudioInspectorSession) {
        let selected = target(for: mode)
        guard !isBusy, !session.isBusy, effect != .off, let brightness = values.drafts[.brightness],
              let fact = values.facts[selected], selected.accepts(fact.value) else { return }
        values.edit(selected, value: effect.firmwareIndex)
        run(target: selected, ble: ble, session: session, preview: .light(effect: effect.firmwareIndex, brightness: brightness))
    }

    func cancel() { operation?.cancel() }

    func clearFeedback() {
        conflict = nil
        batchConflict = nil
        message = nil
        showsError = false
    }

    func run(target: StudioLightDrafts.Target, ble: AhaKeyBLEManager, session: StudioInspectorSession,
             save: Bool = false, overwrite: Conflict? = nil, preview: WS3DisplayPreview? = nil) {
        guard !isBusy, !session.isBusy else { return }
        let baseline = values.facts[target]
        let action: StudioInlineLightOperation.Action
        if save {
            guard let planned = StudioInlineLightOperation.saving(target: target, values: values,
                baselineOverride: overwrite?.actual, desiredOverride: overwrite?.desired) else { return }
            action = planned
        } else if let preview { action = .preview(preview) }
        else { action = .read }
        let deviceID = StudioInlineLightOperation.expectedDeviceID(for: action,
            cached: baseline?.deviceID ?? values.facts[.brightness]?.deviceID)
        let scope = preview == .stop ? NSLocalizedString("临时预览", comment: "") : Self.scopeTitle(target)
        perform(scope: scope, session: session) { [self] in
            let result = try await StudioInlineLightOperation.run(target: target, action: action,
                session: session, expectedDeviceID: deviceID, read: { selected, context in
                    guard values.permitsReadback(deviceID: context.deviceID) else {
                        throw StudioInspectorSession.Failure.deviceChanged
                    }
                    // Re-establish the existing CP2 readback gate for every lease.
                    let display = try await ble.readWS3DisplayForEditing()
                    let actual: UInt8
                    switch selected {
                    case .brightness: actual = display.brightness
                    case .effect(let mode, let state):
                        actual = try await ble.readWS3SingleLightForEditing(mode: mode, state: state).effect
                    }
                    return .init(selected: .init(deviceID: context.deviceID, value: actual), brightness: display.brightness)
                }, save: { setting, actual, generation in
                    try await ble.saveWS3DisplaySetting(setting, baseline: actual, expectedGeneration: generation)
                }, preview: { request in
                    try await ble.previewWS3Display(request)
                }, writeStarted: { catalog = nil; values.markUnconfirmed(target) })
            // Publish only after the lease's final device/generation check.
            switch result {
            case .read(let reading):
                observe(reading, target: target)
                message = NSLocalizedString("已读取。", comment: "")
            case .readOnly(let reading):
                showsError = true
                if let preview {
                    values.observePreview(target: target, selected: reading.selected, brightness: reading.brightness, request: preview)
                } else { observe(reading, target: target, preservingSelection: true) }
                message = NSLocalizedString("键盘当前值无法安全编辑，保持只读。", comment: "")
            case .conflict(let reading, let desired):
                observe(reading, target: target)
                conflict = Conflict(target: target, actual: reading.selected, desired: desired)
            case .saved(let reading, let wrote):
                observe(reading, target: target)
                if wrote || !values.unconfirmed.contains(target) { values.confirm(target, fact: reading.selected) }
                message = NSLocalizedString(wrote ? "已保存。" : "已是当前设置。", comment: "")
            case .previewed(let reading):
                if let preview {
                    values.observePreview(target: target, selected: reading.selected, brightness: reading.brightness, request: preview)
                }
                message = NSLocalizedString(preview == .stop ? "预览已停止。" : "已发送预览，约 10 秒后结束。", comment: "")
            }
        }
    }

    func writePlan(for mode: AhaKeyModeSlot) -> StudioLightWritePlan? {
        try? StudioLightWritePlan.make(mode: UInt8(mode.rawValue), values: values)
    }

    func writeChanges(mode: AhaKeyModeSlot, ble: AhaKeyBLEManager, session: StudioInspectorSession,
                      confirmedPlan: StudioLightWritePlan? = nil) {
        guard !isBusy, !session.isBusy,
              let plan = confirmedPlan ?? writePlan(for: mode), !plan.items.isEmpty else { return }
        let scope = (AhaKeyModeSlot(rawValue: Int(plan.mode))?.title ?? "") + " · " + NSLocalizedString("灯条", comment: "")
        batchConflict = nil
        var attemptedWrite = false
        perform(scope: scope, session: session, failureContext: {
            attemptedWrite ? NSLocalizedString("部分修改可能已生效，草稿与待确认标记已保留；请重新核对后写入。", comment: "") : nil
        }) { [self] in
            let result = try await StudioInlineLightBatch.run(plan: plan, session: session, read: { plan, context in
                let display = try await ble.readWS3DisplayForEditing()
                let brightness = StudioLightDrafts.Fact(deviceID: context.deviceID, value: display.brightness)
                var selected: [StudioLightDrafts.Target: StudioLightDrafts.Fact] = [:]
                for item in plan.items {
                    let value: UInt8
                    if item.target == .brightness { value = display.brightness }
                    else { value = try await ble.readWS3SettingForEditing(item.target.setting(item.desired)) }
                    selected[item.target] = .init(deviceID: context.deviceID, value: value)
                }
                return .init(values: selected, brightness: brightness)
            }, save: { setting, baseline, generation in
                try await ble.saveWS3DisplaySetting(setting, baseline: baseline, expectedGeneration: generation)
            }, verify: { item, context in
                let value = try await ble.readWS3SettingForEditing(item.target.setting(item.desired))
                return .init(deviceID: context.deviceID, value: value)
            }, writeStarted: { target in attemptedWrite = true; catalog = nil; values.markUnconfirmed(target) })
            switch result {
            case .readOnly(let reading):
                observeBatch(reading)
                showsError = true
                message = NSLocalizedString("键盘当前值无法安全编辑，保持只读。", comment: "")
            case .conflict(let conflict):
                observeBatch(conflict.reading)
                batchConflict = conflict
            case .completed(let reading, let writes):
                var updated = values
                updated.observe(.brightness, fact: reading.brightness)
                for item in plan.items { updated.confirm(item.target, fact: reading.values[item.target]!) }
                values = updated
                message = NSLocalizedString(writes > 0 ? "已写入当前模式的灯条修改。" : "当前配置已核对一致，无需写入。", comment: "")
                let text = writes > 0
                    ? NSLocalizedString("本模式的灯效修改已写入；其他模式的灯效草稿保留。", comment: "") +
                        (plan.items.contains(where: { $0.target == .brightness }) ? "\n" + NSLocalizedString("全局亮度修改已对全部模式生效。", comment: "") : "")
                    : NSLocalizedString("当前配置已核对一致，无需写入。", comment: "")
                writeCompleted.send((Self.receipt(scope: scope, text: text), writes > 0))
            }
        }
    }

    func adoptBatchConflict(_ conflict: StudioInlineLightBatch.Conflict) {
        for target in conflict.changed { values.adopt(target) }
        batchConflict = nil
    }

    func pendingSummary(for mode: AhaKeyModeSlot) -> String {
        guard let plan = writePlan(for: mode) else { return "" }
        return plan.items.map { item in
            let value = item.target == .brightness ? "\(item.desired)%" : (LightEffectStyle(firmwareIndex: item.desired)?.title ?? "")
            return Self.scopeTitle(item.target) + " · " + value
        }.joined(separator: "\n")
    }

    private func observeBatch(_ reading: StudioInlineLightBatch.Reading) {
        var updated = values
        updated.observe(.brightness, fact: reading.brightness, preservingDraft: reading.values[.brightness] != nil)
        for (target, fact) in reading.values { updated.observe(target, fact: fact, preservingDraft: true) }
        values = updated
    }

    func readCatalog(ble: AhaKeyBLEManager, session: StudioInspectorSession) {
        perform(scope: NSLocalizedString("四模式灯效总览", comment: ""), session: session) { [self] in
            let result = try await session.withConnection { context in
                guard values.permitsReadback(deviceID: context.deviceID) else {
                    throw StudioInspectorSession.Failure.deviceChanged
                }
                let display = try await ble.readWS3DisplayForEditing()
                let catalog = try await ble.readWS3LightCatalogForEditing()
                return (deviceID: context.deviceID, brightness: display.brightness, catalog: catalog)
            }
            var updated = values
            updated.observe(.brightness, fact: .init(deviceID: result.deviceID, value: result.brightness))
            for light in result.catalog.lights {
                updated.observe(.effect(mode: light.mode, state: light.state), fact: .init(deviceID: result.deviceID, value: light.effect))
            }
            values = updated
            catalog = result.catalog
            message = NSLocalizedString("已读取全部灯效。", comment: "")
        }
    }

    func discardDrafts() {
        guard !isBusy else { return }
        values = .init()
        showsError = false
        catalog = nil
        conflict = nil
        message = NSLocalizedString("本地灯光草稿已清除，请重新读取；未重置键盘，也不会撤销已发送的修改。", comment: "")
    }

    private func perform(scope: String, session: StudioInspectorSession, failureContext: (() -> String?)? = nil, body: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !session.isBusy else { return }
        isBusy = true
        showsError = false
        message = nil
        conflict = nil
        operation = Task { @MainActor in
            defer { isBusy = false; operation = nil }
            do {
                try await body()
                if let currentMessage = message { message = Self.receipt(scope: scope, text: currentMessage) }
            } catch {
                showsError = true
                let detail = [failureContext?(), KeyboardSettingsFeedback.message(for: error)].compactMap { $0 }.joined(separator: "\n")
                message = Self.receipt(scope: scope, text: detail)
            }
        }
    }

    static func scopeTitle(_ target: StudioLightDrafts.Target) -> String {
        switch target {
        case .brightness: return NSLocalizedString("全局亮度", comment: "")
        case .effect(let mode, let state):
            guard let slot = AhaKeyModeSlot(rawValue: Int(mode)), let item = IDEState(rawValue: state) else {
                return NSLocalizedString("灯效", comment: "")
            }
            return slot.title + " · " + slot.name + " · " + item.shortLabel
        }
    }

    static func receipt(scope: String, text: String) -> String {
        String(format: NSLocalizedString("%@：%@", comment: ""), scope, text)
    }

    private func observe(_ reading: StudioInlineLightOperation.Reading, target: StudioLightDrafts.Target, preservingSelection: Bool = false) {
        values.observe(.brightness, fact: .init(deviceID: reading.selected.deviceID, value: reading.brightness))
        values.observe(target, fact: reading.selected, preservingDraft: preservingSelection)
    }
}

