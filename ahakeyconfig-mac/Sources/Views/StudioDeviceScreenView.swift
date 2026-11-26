import AhaKeyConfigShared
import SwiftUI

/// Built-in chrome in the panel's 160×80 coordinate space. Artwork is rendered by
/// the existing player underneath this view; theme changes never transform it.
struct StudioDeviceScreenView: View {
    let state: StudioKeyboardPreviewState
    let battery: Int?
    let labels: [String]

    private var ink: Color { state.theme == .light ? Color(red: 0.06, green: 0.09, blue: 0.13) : Color(red: 0.96, green: 0.98, blue: 1) }
    private var paper: Color { state.theme == .light ? .white : .black }
    private var blue: Color { state.theme == .light ? Color(red: 0.03, green: 0.48, blue: 1) : Color(red: 0.27, green: 0.61, blue: 1) }

    var body: some View {
        GeometryReader { proxy in
            screen.frame(width: 160, height: 80)
                .scaleEffect(min(proxy.size.width / 160, proxy.size.height / 80), anchor: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        switch state.scene {
        case .daily: return "Mode \(state.mode + 1) · " + NSLocalizedString("日常设备信息", comment: "")
        case .system(let computer): return "Computer is " + (computer == .mac ? "Mac?" : "Windows?")
        case .boot: return NSLocalizedString("开机动画", comment: "")
        case .off: return NSLocalizedString("已关机", comment: "")
        case .shuttingDown: return NSLocalizedString("关机动画", comment: "")
        case .reconnecting: return "Reconnecting"
        case .artwork: return NSLocalizedString("当前模式画面", comment: "")
        }
    }

    @ViewBuilder private var screen: some View {
        ZStack {
            paper
            switch state.scene {
            case .off: Color.black
            case .daily: daily
            case .system(let computer): systemChoice(computer)
            case .reconnecting:
                notice("Reconnecting", detail: "Waiting for host")
                    .overlay(alignment: .bottom) {
                        TimelineView(.animation(minimumInterval: 0.25)) { context in
                            HStack(spacing: 5) {
                                ForEach(0..<3) { index in
                                    Circle().fill(Int(context.date.timeIntervalSince1970 * 4) % 3 == index ? blue : ink.opacity(0.2))
                                        .frame(width: 3, height: 3)
                                }
                            }
                        }.padding(.bottom, 6)
                    }
            case .boot: notice("AhaKey", detail: "Welcome").transition(.opacity.combined(with: .scale(scale: 0.9)))
            case .shuttingDown: notice("AhaKey", detail: "Goodbye").transition(.opacity)
            case .artwork: EmptyView()
            }
        }
        .foregroundStyle(ink)
        .animation(.easeInOut(duration: 0.18), value: state.scene)
    }

    private var brand: some View {
        Text("Aha").font(.system(size: 8, weight: .heavy)).foregroundStyle(blue)
    }

    private var daily: some View {
        VStack(spacing: 3) {
            HStack(alignment: .center, spacing: 5) {
                brand
                HStack(spacing: 3) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 7))
                    Text(state.connected ? "BT OK" : "BT --").font(.system(size: 7, weight: .medium))
                }
                Text("M\(state.mode + 1)").font(.system(size: 7)).foregroundStyle(ink.opacity(0.65))
                Spacer(minLength: 0)
                // Keep the percentage and icon in one group; no Spacer between them.
                HStack(spacing: 3) {
                    Text(battery.map { "\($0)%" } ?? "--%")
                        .font(.system(size: 8, weight: .medium)).monospacedDigit()
                    Image(systemName: "battery.75").font(.system(size: 12)).foregroundStyle(blue)
                }.fixedSize()
            }
            Rectangle().fill(ink.opacity(0.15)).frame(height: 0.5)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                ForEach(0..<4) { index in
                    HStack(spacing: 4) {
                        Image(systemName: ["mic.fill", "return", "xmark", "delete.left"][index])
                            .font(.system(size: 11)).foregroundStyle(blue).frame(width: 15)
                        Text(index < labels.count && !labels[index].isEmpty ? labels[index] : ["Voice", "Enter", "Escape", "Backspace"][index])
                            .font(.system(size: 9, weight: .medium)).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 18)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("AhaKey X1")
                Spacer()
                Text("MODE \(state.mode + 1)")
            }.font(.system(size: 6)).foregroundStyle(ink.opacity(0.65))
        }.padding(4)
    }

    private func notice(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            HStack { brand; Spacer() }
            Spacer(minLength: 0)
            Text(title).font(.system(size: title == "AhaKey" ? 21 : 16, weight: .semibold))
            Text(detail).font(.system(size: 9)).foregroundStyle(ink.opacity(0.65))
            Spacer(minLength: 0)
        }.padding(5)
    }

    private func systemChoice(_ computer: StudioKeyboardPreviewState.Computer) -> some View {
        VStack(spacing: 0) {
            HStack { brand; Spacer() }
            Text("Computer is").font(.system(size: 12, weight: .medium))
            Text(computer == .mac ? "Mac?" : "Windows?").font(.system(size: 18, weight: .semibold))
            Spacer(minLength: 2)
            HStack {
                Label("Yes", systemImage: "checkmark").foregroundStyle(blue)
                Spacer()
                Label("No", systemImage: "xmark")
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12)
        }.padding(5)
    }
}
