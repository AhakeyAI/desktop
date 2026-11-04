import AppKit
import SwiftUI
import Darwin

@MainActor final class ConflictFixture: ObservableObject {
    @Published var busy = false
    @Published var conflict = false
    let root = Bundle.main.bundleURL.deletingLastPathComponent()
    var fixed: Bool { (try? String(contentsOf: root.appendingPathComponent("resource-conflict-mode.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == "fixed" }
    func run() async {
        try? await Task.sleep(for: .milliseconds(300))
        busy = true
        try? await Task.sleep(for: .milliseconds(100))
        conflict = true
        try? await Task.sleep(for: .milliseconds(700))
        busy = false
        try? await Task.sleep(for: .milliseconds(600))
        var buttons: [[String: Any]] = []
        func inspect(_ view: NSView) {
            if let button = view as? NSButton {
                buttons.append(["title": button.title, "enabled": button.isEnabled])
            }
            for subview in view.subviews { inspect(subview) }
        }
        for window in NSApp.windows {
            if let content = window.contentView { inspect(content) }
            for child in window.childWindows ?? [] { if let content = child.contentView { inspect(content) } }
        }
        let result: [String: Any] = ["fixed": fixed, "busy": busy, "conflict": conflict, "buttons": buttons]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("resource-conflict-\(fixed ? "fixed" : "baseline").json"))
        }
        // Disposable diagnostic only: exit even if a native alert has a modal loop.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { exit(0) }
    }
}
struct AlertChild: View {
    @ObservedObject var fixture: ConflictFixture
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Text("Resource conflict fixture - no Bluetooth or writes")
            .padding(24)
            .alert("键盘当前素材已变化", isPresented: Binding(
                get: { fixture.fixed ? StudioResourceConflictReadiness.mayPresent(hasConflict: fixture.conflict, editorEnabled: enabled, operationBusy: fixture.busy) : fixture.conflict },
                set: { fixture.conflict = $0 })) {
                    if fixture.fixed {
                        Button("采用键盘当前值") { fixture.conflict = false }
                        Button("确认修改") { fixture.conflict = false }
                        Button("取消", role: .cancel) { fixture.conflict = false }
                    } else {
                        Button("采用键盘当前值", role: .cancel) { fixture.conflict = false }
                        Button("确认修改") { fixture.conflict = false }
                    }
                } message: { Text("键盘当前：默认显示\n待写入：capacity-source-13.gif") }
    }
}
@main struct ResourceConflictQA: App {
    @StateObject private var fixture = ConflictFixture()
    var body: some Scene {
        WindowGroup("Resource Conflict QA") {
            VStack { AlertChild(fixture: fixture) }
                .disabled(fixture.busy)
                .task { await fixture.run() }
        }
    }
}
