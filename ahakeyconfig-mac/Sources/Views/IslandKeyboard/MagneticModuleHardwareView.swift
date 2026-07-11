import SwiftUI

private enum HardwareChevronDirection { case up, down, left, right }

/// 磁吸模块虚拟硬件外观，用于键盘映射画布；设置页 Inspector 仍使用 SF Symbol。
struct MagneticModuleHardwareView: View {
    let type: MagneticModuleType

    private let bodyFill = Color(red: 0.95, green: 0.95, blue: 0.94)
    private let recessFill = Color(red: 0.90, green: 0.90, blue: 0.89)
    private let metalLight = Color(red: 0.94, green: 0.95, blue: 0.98)
    private let metalMid = Color(red: 0.74, green: 0.76, blue: 0.80)
    private let metalDark = Color(red: 0.50, green: 0.52, blue: 0.56)
    private let controlBlack = Color(red: 0.10, green: 0.10, blue: 0.11)

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let corner = size * 0.2
            let recessCorner = corner * 0.55

            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [bodyFill, bodyFill.opacity(0.94)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: max(size * 0.012, 0.6))
                    )
                    .shadow(color: .black.opacity(0.14), radius: size * 0.035, y: size * 0.02)

                RoundedRectangle(cornerRadius: recessCorner, style: .continuous)
                    .fill(recessFill)
                    .frame(width: size * 0.78, height: size * 0.78)
                    .overlay(
                        RoundedRectangle(cornerRadius: recessCorner, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: size * 0.006)
                    )

                moduleControl(size: size)

                Circle()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: size * 0.045, height: size * 0.045)
                    .offset(y: size * 0.36)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func moduleControl(size: CGFloat) -> some View {
        switch type {
        case .none:
            EmptyView()
        case .toggle:
            toggleControl(size: size)
        case .joystick:
            joystickControl(size: size)
        case .knob:
            knobControl(size: size)
        case .scrollWheel:
            scrollWheelControl(size: size)
        case .dpad:
            dpadControl(size: size)
        }
    }

    private func toggleControl(size: CGFloat) -> some View {
        ZStack {
            hardwareChevron(size: size * 0.08, direction: .up, onRecess: true)
                .offset(y: -size * 0.19)
            hardwareChevron(size: size * 0.08, direction: .down, onRecess: true)
                .offset(y: size * 0.19)

            RoundedRectangle(cornerRadius: size * 0.028, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [metalLight, metalMid, metalDark],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size * 0.13, height: size * 0.42)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.028, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: size * 0.006)
                )
                .shadow(color: .black.opacity(0.28), radius: size * 0.025, y: size * 0.012)
        }
    }

    private func joystickControl(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(controlBlack.opacity(0.94))
                .frame(width: size * 0.44, height: size * 0.44)
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: size * 0.012)
                .frame(width: size * 0.44, height: size * 0.44)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.30, green: 0.30, blue: 0.32), controlBlack],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.12
                    )
                )
                .frame(width: size * 0.26, height: size * 0.26)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: size * 0.004)
                )
                .shadow(color: .black.opacity(0.35), radius: size * 0.03, y: size * 0.018)
        }
    }

    private func knobControl(size: CGFloat) -> some View {
        let knobDiameter = size * 0.50
        return ZStack {
            Text("−")
                .font(.system(size: size * 0.10, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.24))
                .offset(x: -size * 0.22, y: size * 0.14)
            Text("+")
                .font(.system(size: size * 0.10, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.24))
                .offset(x: size * 0.22, y: size * 0.14)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [metalLight, metalMid, metalDark],
                            center: .topLeading,
                            startRadius: knobDiameter * 0.05,
                            endRadius: knobDiameter * 0.55
                        )
                    )

                KnurledRing()
                    .stroke(metalDark.opacity(0.55), lineWidth: knobDiameter * 0.07)
                    .padding(knobDiameter * 0.02)

                Circle()
                    .stroke(Color.white.opacity(0.38), lineWidth: size * 0.006)
            }
            .frame(width: knobDiameter, height: knobDiameter)
            .shadow(color: .black.opacity(0.24), radius: size * 0.03, y: size * 0.016)

            Capsule()
                .fill(Color.white.opacity(0.82))
                .frame(width: size * 0.016, height: size * 0.075)
                .offset(y: -knobDiameter * 0.34)
        }
    }

    private func scrollWheelControl(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
                .fill(Color.black.opacity(0.07))
                .frame(width: size * 0.58, height: size * 0.18)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [metalLight, metalMid, metalDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.50, height: size * 0.13)
                .overlay(
                    HStack(spacing: size * 0.028) {
                        ForEach(0..<6, id: \.self) { _ in
                            Capsule()
                                .fill(Color.black.opacity(0.13))
                                .frame(width: size * 0.007, height: size * 0.085)
                        }
                    }
                )
                .shadow(color: .black.opacity(0.22), radius: size * 0.022, y: size * 0.01)
        }
    }

    private func dpadControl(size: CGFloat) -> some View {
        let arm = size * 0.16
        let span = size * 0.50
        return ZStack {
            RoundedRectangle(cornerRadius: arm * 0.32, style: .continuous)
                .fill(controlBlack)
                .frame(width: arm, height: span)
            RoundedRectangle(cornerRadius: arm * 0.32, style: .continuous)
                .fill(controlBlack)
                .frame(width: span, height: arm)

            hardwareChevron(size: size * 0.07, direction: .up).offset(y: -span * 0.34)
            hardwareChevron(size: size * 0.07, direction: .down).offset(y: span * 0.34)
            hardwareChevron(size: size * 0.07, direction: .left).offset(x: -span * 0.34)
            hardwareChevron(size: size * 0.07, direction: .right).offset(x: span * 0.34)
        }
        .shadow(color: .black.opacity(0.22), radius: size * 0.022, y: size * 0.01)
    }

    private func hardwareChevron(size: CGFloat, direction: HardwareChevronDirection, onRecess: Bool = false) -> some View {
        HardwareChevronShape(direction: direction)
            .fill(onRecess ? Color.black.opacity(0.22) : Color.white.opacity(0.42))
            .frame(width: size, height: size)
    }
}

private struct KnurledRing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let teeth = 48
        for index in 0..<teeth {
            let angle = Double(index) / Double(teeth) * .pi * 2
            let inner = radius * 0.88
            let outer = radius
            let innerPoint = CGPoint(
                x: center.x + CGFloat(cos(angle)) * inner,
                y: center.y + CGFloat(sin(angle)) * inner
            )
            let outerPoint = CGPoint(
                x: center.x + CGFloat(cos(angle)) * outer,
                y: center.y + CGFloat(sin(angle)) * outer
            )
            path.move(to: innerPoint)
            path.addLine(to: outerPoint)
        }
        return path
    }
}

private struct HardwareChevronShape: Shape {
    var direction: HardwareChevronDirection = .up

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        switch direction {
        case .up:
            path.move(to: CGPoint(x: w * 0.5, y: 0))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
        case .down:
            path.move(to: CGPoint(x: w * 0.5, y: h))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 0))
        case .left:
            path.move(to: CGPoint(x: 0, y: h * 0.5))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w, y: 0))
        case .right:
            path.move(to: CGPoint(x: w, y: h * 0.5))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: 0))
        }
        path.closeSubpath()
        return path
    }
}
