import SwiftUI

/// Gen2 磁吸底座：空槽显示触点底座；吸附模块后由虚拟硬件完全覆盖。
struct MagneticBaseView: View {
    let moduleState: MagneticModuleState

    private let baseFill = Color(red: 0.18, green: 0.19, blue: 0.21)
    private let magnetFill = Color(red: 0.82, green: 0.84, blue: 0.88)
    private let pinFill = Color(red: 0.82, green: 0.68, blue: 0.28)

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let corner = size * 0.2

            Group {
                if moduleState.isConnected {
                    MagneticModuleHardwareView(type: moduleState.attachedType)
                        .frame(width: size, height: size)
                } else {
                    emptyBase(size: size, corner: corner)
                }
            }
            .overlay {
                if !moduleState.isConnected {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .foregroundStyle(Color.white.opacity(0.22))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func emptyBase(size: CGFloat, corner: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [baseFill, baseFill.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)

            ForEach(Array(cornerOffsets.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.98), magnetFill, Color.gray.opacity(0.55)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: size * 0.09
                        )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .offset(x: point.x * size * 0.36, y: point.y * size * 0.36)
            }

            pinGrid(size: size)
        }
    }

    private var cornerOffsets: [CGPoint] {
        [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)]
    }

    @ViewBuilder
    private func pinGrid(size: CGFloat) -> some View {
        let spacing = size * 0.1
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(pinFill)
                            .frame(width: size * 0.075, height: size * 0.075)
                            .shadow(color: pinFill.opacity(0.6), radius: 1)
                    }
                }
            }
        }
    }
}
