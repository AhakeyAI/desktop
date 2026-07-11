import SwiftUI

struct VoiceInputFloatingHUD: View {
    @ObservedObject var nativeSpeech: NativeSpeechTranscriptionService
    var onCancel: () -> Void
    var onConfirm: () -> Void
    var onDragChanged: (CGSize) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    @State private var recentlyFinished = false
    @State private var dragStartTranslation: CGSize = .zero

    var body: some View {
        Group {
            if isVisible {
                hudBody
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let delta = CGSize(
                                    width: value.translation.width - dragStartTranslation.width,
                                    height: -value.translation.height + dragStartTranslation.height
                                )
                                dragStartTranslation = value.translation
                                onDragChanged(delta)
                            }
                            .onEnded { _ in
                                dragStartTranslation = .zero
                                onDragEnded()
                            }
                    )
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: isVisible)
        .onChange(of: nativeSpeech.lastCommittedText) { newValue in
            guard !newValue.isEmpty else { return }
            recentlyFinished = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                recentlyFinished = false
            }
        }
    }

    private var isVisible: Bool {
        nativeSpeech.isRecording || nativeSpeech.statusMessage.contains("整理") || recentlyFinished
    }

    @ViewBuilder
    private var hudBody: some View {
        if nativeSpeech.isRecording {
            HStack(spacing: 10) {
                hudIconButton(systemImage: "xmark", action: onCancel)
                MiniVoiceMeter()
                    .frame(width: 64, height: 24)
                hudIconButton(systemImage: "checkmark", action: onConfirm, filled: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.black.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        } else {
            Text(recentlyFinished ? "Done" : "Thinking")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(.black.opacity(0.74), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.24), radius: 14, y: 7)
        }
    }

    private func hudIconButton(systemImage: String, action: @escaping () -> Void, filled: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(filled ? Color.black : Color.white)
                .frame(width: 28, height: 28)
                .background(filled ? Color.white : Color.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct MiniVoiceMeter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<13, id: \.self) { index in
                    Capsule()
                        .fill(index == 6 ? Color.white : Color.white.opacity(0.86))
                        .frame(width: index == 6 ? 2 : 3, height: barHeight(index: index, phase: t))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barHeight(index: Int, phase: TimeInterval) -> CGFloat {
        if index == 6 { return 18 }
        if reduceMotion { return 8 }
        let wave = sin(phase * 8 + Double(index) * 0.7) * 0.5 + 0.5
        return 5 + CGFloat(wave) * 14
    }
}
