import SwiftUI
import AhaKeyConfigShared

struct StudioLightStateSelector: View {
    let selectedState: UInt8
    let dirtyStates: Set<UInt8>
    let enabled: Bool
    let select: (UInt8) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(IDEState.workflowOrder) { item in
                Button { select(item.rawValue) } label: {
                    Text(item.shortLabel)
                        .font(.caption.weight(selectedState == item.rawValue ? .semibold : .regular))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(selectedState == item.rawValue ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .topTrailing) {
                            if dirtyStates.contains(item.rawValue) {
                                Circle().fill(Color.orange).frame(width: 5, height: 5).padding(5)
                            }
                        }
                }.buttonStyle(.plain).disabled(!enabled)
                    .accessibilityAddTraits(selectedState == item.rawValue ? .isSelected : [])
            }
        }
    }
}

/// Both firmware generations use the same cards. Selection edits only a local
/// draft; the separate play control is the only action that previews hardware.
struct StudioLightEffectPicker: View {
    let selection: LightEffectStyle?
    let enabled: Bool
    let previewEnabled: Bool
    let select: (LightEffectStyle) -> Void
    let preview: (LightEffectStyle) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(LightEffectStyle.allCases) { effect in
                card(effect)
            }
        }
    }

    private func card(_ effect: LightEffectStyle) -> some View {
        let selected = selection == effect
        return ZStack(alignment: .bottomTrailing) {
            Button { select(effect) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: effect.symbolName).frame(width: 13).foregroundStyle(.secondary)
                        Text(effect.title).fontWeight(.semibold)
                    }.font(.caption)
                    Text(effect.detail).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, effect == .off ? 0 : 20)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(!enabled)
            .accessibilityLabel(effect.title).accessibilityHint(effect.detail)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if effect != .off {
                Button { preview(effect) } label: {
                    Image(systemName: "play.circle").font(.system(size: 17))
                        .foregroundStyle(.white).frame(width: 24, height: 24)
                        .background(Circle().fill(Color.black.opacity(0.55)).padding(3))
                }
                .buttonStyle(.plain).padding(.trailing, 5).padding(.bottom, 4)
                .disabled(!previewEnabled)
                .help(NSLocalizedString("预览到键盘", comment: ""))
                .accessibilityLabel(String(format: NSLocalizedString("在键盘上预览 %@", comment: ""), effect.title))
            }
        }
    }
}
