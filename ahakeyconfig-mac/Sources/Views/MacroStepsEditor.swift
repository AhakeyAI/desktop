import SwiftUI

/// Shared presentation for key and lever macros. The caller owns storage,
/// operation locking and the protocol-specific payload budget.
struct MacroStepsEditor: View {
    @Binding var steps: [MacroStep]
    var maximumPayloadBytes = 98
    var minimumDelay: UInt8 = 1

    private var byteCount: Int { steps.count * 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("步骤（依次执行）", comment: ""))
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(String(format: NSLocalizedString("%d 步 · %d / %d 字节", comment: ""), steps.count, byteCount, maximumPayloadBytes))
                    .font(.caption)
                    .foregroundStyle(byteCount > maximumPayloadBytes ? .red : .secondary)
            }
            if steps.isEmpty {
                Text(NSLocalizedString("空宏。点下方「添加步骤」开始录制。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                // Lever records decode their steps from bytes on each read, so
                // row identity must not depend on newly generated UUIDs.
                ForEach(steps.indices, id: \.self) { index in
                    stepRow(index)
                }
            }
            HStack(spacing: 10) {
                Button {
                    guard byteCount + 2 <= maximumPayloadBytes else { return }
                    steps.append(MacroStep(action: .downKey, param: HIDUsage.enter))
                } label: {
                    Label(NSLocalizedString("添加步骤", comment: ""), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(byteCount + 2 > maximumPayloadBytes)
                Button(role: .destructive) { steps = [] } label: {
                    Label(NSLocalizedString("清空", comment: ""), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(steps.isEmpty)
            }
            if byteCount > maximumPayloadBytes && maximumPayloadBytes == 98 {
                Text(NSLocalizedString("超过固件单键宏 98 字节 / 49 步上限，同步时会被拒绝。", comment: ""))
                    .font(.caption).foregroundStyle(.red)
            }
            Text(NSLocalizedString("固件按顺序发送。延时可输入毫秒，按最接近的 3 ms 保存，单步最多 765 ms。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            if !steps.isEmpty {
                Text(String(format: NSLocalizedString("预览：%@", comment: ""), steps.displaySummary))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private func step(_ index: Int) -> MacroStep {
        steps.indices.contains(index) ? steps[index] : MacroStep(action: .noOp)
    }

    private func update(_ index: Int, _ transform: (inout MacroStep) -> Void) {
        var next = steps
        guard next.indices.contains(index) else { return }
        transform(&next[index])
        steps = next
    }

    private func move(_ index: Int, by offset: Int) {
        var next = steps
        guard next.indices.contains(index), next.indices.contains(index + offset) else { return }
        next.swapAt(index, index + offset)
        steps = next
    }

    private func stepRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Picker("", selection: Binding(get: { step(index).action }, set: { value in
                update(index) { item in
                    let previous = item.action
                    item.action = value
                    if previous.takesKeycodeParam != value.takesKeycodeParam
                        || previous.takesDelayParam != value.takesDelayParam {
                        switch value {
                        case .delay: item.param = 5
                        case .downKey, .upKey: item.param = HIDUsage.enter
                        case .noOp, .upAllKeys: item.param = 0
                        }
                    }
                }
            })) {
                ForEach(MacroAction.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().frame(width: 96)
            if step(index).action.takesKeycodeParam {
                Picker("", selection: Binding(get: { step(index).param }, set: { value in
                    update(index) { $0.param = value }
                })) {
                    Text(NSLocalizedString("未设置", comment: "")).tag(UInt8(0))
                    ForEach(HIDUsage.allOptions, id: \.code) { Text($0.name).tag($0.code) }
                }
                .pickerStyle(.menu).labelsHidden().frame(minWidth: 96)
            } else if step(index).action.takesDelayParam {
                MacroDelayField(units: Binding(get: { step(index).param }, set: { value in
                    update(index) { $0.param = value }
                }), minimum: minimumDelay)
            } else {
                Color.clear.frame(minWidth: 96, maxHeight: 1)
            }
            Spacer(minLength: 0)
            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless).disabled(index == 0)
            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless).disabled(index >= steps.count - 1)
            Button(role: .destructive) {
                var next = steps
                guard next.indices.contains(index) else { return }
                next.remove(at: index)
                steps = next
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }.buttonStyle(.borderless)
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
    }
}

private struct MacroDelayField: View {
    @Binding var units: UInt8
    let minimum: UInt8
    @State private var text = ""
    @FocusState private var focused: Bool

    private var milliseconds: Int { Int(max(minimum, units)) * 3 }

    var body: some View {
        HStack(spacing: 4) {
            TextField("延时毫秒", text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.caption.monospacedDigit())
                .frame(width: 56)
                .focused($focused)
                .accessibilityLabel(Text("延时毫秒"))
                .onSubmit { focused = false }
            Text("ms").font(.caption)
        }
        .frame(minWidth: 120)
        .onAppear { text = String(milliseconds) }
        .onChange(of: units) { _ in
            if !focused { text = String(milliseconds) }
        }
        .onChange(of: focused) { editing in
            if !editing { text = String(milliseconds) }
        }
        .onChange(of: text) { value in
            guard focused, let typed = Int(value.trimmingCharacters(in: .whitespaces)) else { return }
            let clamped = min(765, max(Int(minimum) * 3, typed))
            units = UInt8((clamped + 1) / 3)
        }
    }
}
