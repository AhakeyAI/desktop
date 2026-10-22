import SwiftUI

struct KeyboardWriteOutcome: Identifiable {
    let id = UUID()
    let succeeded: Bool
    let message: String
    let wrote: Bool

    init(succeeded: Bool, message: String, wrote: Bool = true) {
        self.succeeded = succeeded
        self.message = message
        self.wrote = wrote
    }
}

extension Notification.Name {
    static let ahaKeyHardwareEditingFinished = Notification.Name("ahaKey.hardwareEditingFinished")
}

extension View {
    func keyboardWriteResult(_ outcome: Binding<KeyboardWriteOutcome?>, onFinish: (() -> Void)? = nil) -> some View {
        modifier(KeyboardWriteResultModifier(outcome: outcome, onFinish: onFinish))
    }
}

private struct KeyboardWriteResultModifier: ViewModifier {
    @Binding var outcome: KeyboardWriteOutcome?
    let onFinish: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.alert(NSLocalizedString(outcome?.succeeded == true ? (outcome?.wrote == true ? "写入成功" : "已确认") : "写入结果", comment: ""),
            isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } }), presenting: outcome) { result in
                if result.succeeded {
                    Button(NSLocalizedString("继续编辑", comment: ""), role: .cancel) { }
                    Button(NSLocalizedString("完成编辑", comment: "")) {
                        if let onFinish { onFinish() }
                        else {
                            dismiss()
                            NotificationCenter.default.post(name: .ahaKeyHardwareEditingFinished, object: nil)
                        }
                    }.keyboardShortcut(.defaultAction)
                } else {
                    Button(NSLocalizedString("好", comment: ""), role: .cancel) { }
                }
            } message: { result in Text(result.message) }
    }
}
