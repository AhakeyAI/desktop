import SwiftUI
import AhaKeyConfigShared

/// Settings-only reset flow. Component drafts remain owned by the main inspector.
struct StudioFactoryResetSheet: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @StateObject private var model = StudioRestoreInspectorModel()
    @StateObject private var session: StudioInspectorSession
    @ObservedObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @ObservedObject private var voiceRelay = VoiceRelayService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var preparation = false
    @State private var confirmsReset = false
    @State private var outcome: KeyboardWriteOutcome?
    @State private var operation: Task<Void, Never>?
    let onResetAttempt: () -> Void

    init(bleManager: AhaKeyBLEManager, onResetAttempt: @escaping () -> Void) {
        self.bleManager = bleManager
        self.onResetAttempt = onResetAttempt
        _session = StateObject(wrappedValue: StudioInspectorSession(bleManager: bleManager))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("恢复出厂设置", comment: "")).font(.title2.bold())
                Text(NSLocalizedString(preparation ? "2 / 2 · 准备恢复" : "1 / 2 · 确认恢复范围", comment: ""))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            if !preparation {
                Label(NSLocalizedString("恢复整把键盘，应用于所有模式", comment: ""), systemImage: "keyboard")
                    .font(.headline)
                Text(NSLocalizedString("键位与语音、待机与拨杆、屏幕与灯光将恢复默认设置。", comment: ""))
                Label(NSLocalizedString("自定义画面将停用，原素材无法从键盘导出。", comment: ""), systemImage: "photo")
                Label(NSLocalizedString("本地草稿保留，不会自动写入键盘。", comment: ""), systemImage: "doc")
                Text(NSLocalizedString("仅清除蓝牙配对，请使用键盘的“忘记主机”。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Label(NSLocalizedString("键盘恢复状态", comment: ""), systemImage: "keyboard")
                    Spacer()
                    if model.isBusy { ProgressView().controlSize(.small) }
                    Button { readStatus() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help(NSLocalizedString("重新读取", comment: ""))
                        .accessibilityLabel(NSLocalizedString("重新读取", comment: ""))
                        .disabled(model.isBusy)
                }
                Text(status).font(.callout).foregroundStyle(.secondary)
                if let outcome {
                    Label(NSLocalizedString(outcome.succeeded ? "恢复设置已核对" : "请先核对恢复结果", comment: ""),
                          systemImage: outcome.succeeded ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.headline)
                }
                if model.fact?.value.canStart == true && outcome == nil {
                    Toggle(NSLocalizedString("已连接键盘 USB 供电，并会保持连接", comment: ""), isOn: $model.usbPowerConfirmed)
                    Text(NSLocalizedString("恢复期间请勿断电，也不要操作键盘。", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            Divider()
            HStack {
                Button(NSLocalizedString(preparation ? "返回" : "取消", comment: "")) {
                    if preparation { preparation = false; model.clearIntent(); outcome = nil }
                    else { dismiss() }
                }.disabled(model.isBusy)
                Spacer()
                if !preparation {
                    Button(NSLocalizedString("下一步", comment: "")) {
                        preparation = true; readStatus()
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else if outcome != nil {
                    if model.canVerify {
                        Button(NSLocalizedString("核对恢复后的设置", comment: "")) { verify() }
                            .disabled(model.isBusy)
                    }
                    Button(NSLocalizedString("完成", comment: "")) { dismiss() }
                        .buttonStyle(.borderedProminent).disabled(model.isBusy)
                } else {
                    Button(NSLocalizedString("恢复出厂设置", comment: ""), role: .destructive) { confirmsReset = true }
                        .buttonStyle(.borderedProminent).tint(.red).disabled(!model.canSubmit)
                }
            }
        }
        .padding(24).frame(width: 500, height: 440)
        .interactiveDismissDisabled(model.isBusy)
        .onAppear { _ = session.beginEditing(deviceID: bleManager.bleDeviceUUID, isConnected: bleManager.isConnected) }
        .onDisappear { operation?.cancel(); session.endEditing() }
        .onReceive(model.writeCompleted) { result in
            outcome = result
            if result.wrote { onResetAttempt() }
        }
        .confirmationDialog(NSLocalizedString("恢复整把键盘的设置？", comment: ""), isPresented: $confirmsReset, titleVisibility: .visible) {
            Button(NSLocalizedString("恢复出厂设置", comment: ""), role: .destructive) {
                operation = Task { await model.start(using: access, userConfirmed: true) }
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("将恢复所有模式的键盘设置并停用自定义画面。本地草稿保留，请保持 USB 供电。", comment: ""))
        }
    }

    private func readStatus() {
        operation = Task {
            await model.read(using: access)
            guard !Task.isCancelled else { return }
            outcome = nil
            model.intendsRestore = model.fact?.value.canStart == true
        }
    }
    private func verify() {
        operation = Task { await model.verify(using: access) }
    }
    private var status: String {
        guard let state = model.fact?.value.state else {
            return NSLocalizedString(model.isBusy ? "正在读取键盘…" : "尚未读取键盘", comment: "")
        }
        let key: String
        switch state {
        case .never: key = "尚未执行恢复"
        case .inProgress: key = "恢复尚在进行，请勿断电"
        case .incomplete: key = "上次恢复未完成"
        case .complete: key = "键盘报告恢复已完成"
        case .storageUnavailable: key = "暂时无法读取恢复记录"
        case .unsupported: key = "此固件不支持恢复初始化"
        }
        return NSLocalizedString(key, comment: "")
    }
    var access: StudioRestoreInspectorModel.Access {
        .init(read: {
            try await session.withConnection { context in
                .init(deviceID: context.deviceID, value: try await bleManager.readRestoreInitializationStatus())
            }
        }, start: { baseline, confirmed, power in
            guard !nativeSpeech.isRecording, !nativeSpeech.isStartingRecording,
                  !voiceRelay.hasActiveFunctionRelayHold else {
                throw StudioRestoreInspectorModel.Failure.voiceActive
            }
            return try await session.withConnection(expectedDeviceID: baseline.deviceID) { context in
                guard !nativeSpeech.isRecording, !nativeSpeech.isStartingRecording,
                      !voiceRelay.hasActiveFunctionRelayHold else {
                    throw StudioRestoreInspectorModel.Failure.voiceActive
                }
                let result = try await bleManager.restoreInitializationConfirmed(baseline: baseline.value,
                    expectedGeneration: context.generation, userConfirmed: confirmed, usbPowerConfirmed: power,
                    writeStarted: {})
                return .init(result: result, readback: bleManager.restoreInitializationReadback)
            }
        }, verify: { baseline in
            try await session.withConnection(expectedDeviceID: baseline.deviceID) { context in
                let result = try await bleManager.verifyRestoreInitializationReadback(baseline: baseline.value,
                    expectedGeneration: context.generation)
                return .init(result: result, readback: bleManager.restoreInitializationReadback)
            }
        })
    }
}
