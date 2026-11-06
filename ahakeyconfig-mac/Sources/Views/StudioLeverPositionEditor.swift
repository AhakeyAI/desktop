import SwiftUI
import AhaKeyConfigShared

/// One detail surface: factory approvals, shortcut or macro, never stacked editors.
struct StudioLeverPositionEditor: View {
    @Binding var position: SideSwitchReadback.Position
    var positionIndex = 0
    var approvalContent: ((UInt8) -> AnyView)?

    private enum Choice: String, CaseIterable {
        case automatic = "自动批准", manual = "手动批准"
        case shortcut = "快捷键", macro = "宏", disabled = "不执行"
    }

    private var choice: Choice? {
        switch position.bindType {
        case 0: return .automatic
        case 1: return .manual
        case 2: return .disabled
        case 3: return position.action.first == 0x74 ? .macro : .shortcut
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                choiceRow(Choice.allCases)
                VStack(alignment: .leading, spacing: 8) {
                    choiceRow([.automatic, .manual])
                    choiceRow([.shortcut, .macro, .disabled])
                }
            }
            if position.bindType == 0 || position.bindType == 1 {
                if positionIndex == 1 && position.bindType == 0 {
                    Text(NSLocalizedString("自动批准仅在拨杆在上且保留出厂自动绑定时启用。", comment: ""))
                        .font(.caption).foregroundStyle(.orange)
                }
                if let approvalContent { approvalContent(position.bindType) }
            } else if position.bindType == 3 {
                KeyboardActionEditor(action: Binding(get: { position.action }, set: {
                    position = .init(bindType: 3, action: $0)
                }), showsActionTypePicker: false)
            } else if position.bindType == 2 {
                Text(NSLocalizedString("拨到此位置不发送按键动作。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func choiceRow(_ choices: [Choice]) -> some View {
        HStack(spacing: 10) {
            ForEach(choices, id: \.self) { value in
                Button { select(value) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: choice == value ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(choice == value ? Color.accentColor : Color.secondary)
                        Text(NSLocalizedString(value.rawValue, comment: ""))
                    }.fixedSize()
                }
                .font(.caption).buttonStyle(.plain)
                .accessibilityAddTraits(choice == value ? .isSelected : [])
            }
        }
    }

    private func select(_ value: Choice) {
        guard value != choice else { return }
        switch value {
        case .automatic: position = .init(bindType: 0, action: Data())
        case .manual: position = .init(bindType: 1, action: Data())
        case .disabled: position = .init(bindType: 2, action: Data())
        case .shortcut: position = .init(bindType: 3, action: Data([0x73, 0]))
        case .macro: position = .init(bindType: 3, action: Data([0x74, 2, 4, 0]))
        }
    }
}
