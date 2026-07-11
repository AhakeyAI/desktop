import SwiftUI

/// 语音 / Record 键帽图标：实心圆点（与 Gen2 硬件丝印一致）。
struct RecordKeyIcon: View {
    var color: Color = Color.black.opacity(0.88)
    var diameter: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
    }
}

/// 画布键帽图标：submit / voice 使用硬件丝印，其余走 SF Symbol。
struct CanvasKeyRoleIcon: View {
    let role: AhaKeyKeyRole
    var color: Color = Color.black.opacity(0.88)
    var size: CGFloat

    var body: some View {
        Group {
            switch role {
            case .submit:
                SubmitKeyIcon(color: color)
                    .frame(width: size * 1.35, height: size * 1.15)
            case .voice:
                RecordKeyIcon(color: color, diameter: size * 0.62)
            default:
                Image(systemName: role.systemImage)
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(color)
            }
        }
        .fixedSize()
    }
}

/// 回车键帽图标：左侧箭头 + 圆角外框 + 居中 X（与 Gen2 硬件丝印一致）。
struct SubmitKeyIcon: View {
    var color: Color = Color.black.opacity(0.88)

    var body: some View {
        GeometryReader { geo in
            let stroke = min(geo.size.width, geo.size.height) * 0.11
            ZStack {
                SubmitKeyCapShape()
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                SubmitKeyXShape()
                    .stroke(color, style: StrokeStyle(lineWidth: stroke * 0.9, lineCap: .round))
            }
        }
        .aspectRatio(1.18, contentMode: .fit)
        .fixedSize()
    }
}

private struct SubmitKeyCapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let insetX = w * 0.04
        let insetY = h * 0.06
        let tipX = insetX
        let bodyLeft = w * 0.34
        let right = w - insetX
        let top = insetY
        let bottom = h - insetY
        let midY = h * 0.5

        path.move(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: bodyLeft, y: top))
        path.addLine(to: CGPoint(x: tipX, y: midY))
        path.addLine(to: CGPoint(x: bodyLeft, y: bottom))
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.closeSubpath()
        return path
    }
}

private struct SubmitKeyXShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let left = w * 0.46
        let right = w * 0.78
        let top = h * 0.30
        let bottom = h * 0.70

        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.move(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom))
        return path
    }
}
