import SwiftUI

/// Gen2 电子海洋灯效画布预览（多行 LED 矩阵，SwiftUI 模拟）。
struct OceanLightPreviewView: View {
    let config: OceanLightConfig
    var rowCount: Int = 3
    var ledsPerRow: Int = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSince1970
            GeometryReader { proxy in
                let preset = config.selectedPreset
                let totalCount = rowCount * ledsPerRow
                let colors = oceanColors(
                    preset: preset,
                    time: time,
                    count: totalCount,
                    brightness: config.powerSwitchEnabled ? config.brightness : 0.08,
                    imuTilt: config.imuEnabled ? sin(time * 0.7) * 0.35 : 0
                )

                ZStack {
                    RoundedRectangle(cornerRadius: min(proxy.size.height / 2, 14), style: .continuous)
                        .fill(Color.black.opacity(0.14))

                    if config.powerSwitchEnabled {
                        Canvas { context, size in
                            let horizontalPadding: CGFloat = 8
                            let verticalPadding: CGFloat = 5
                            let usableWidth = size.width - horizontalPadding * 2
                            let usableHeight = size.height - verticalPadding * 2
                            let colSpacing = usableWidth / CGFloat(max(ledsPerRow - 1, 1))
                            let rowSpacing = usableHeight / CGFloat(max(rowCount - 1, 1))
                            let dotSize = min(colSpacing * 0.55, rowSpacing * 0.62, 7)

                            for row in 0..<rowCount {
                                for col in 0..<ledsPerRow {
                                    let index = row * ledsPerRow + col
                                    let rowWave = config.imuEnabled
                                        ? sin(time * 1.2 + Double(row) * 0.85 + Double(col) * 0.18) * 2.2
                                        : 0
                                    let x = horizontalPadding + CGFloat(col) * colSpacing
                                    let y = verticalPadding + CGFloat(row) * rowSpacing + CGFloat(rowWave)
                                    let rect = CGRect(
                                        x: x - dotSize / 2,
                                        y: y - dotSize / 2,
                                        width: dotSize,
                                        height: dotSize
                                    )
                                    context.fill(Path(ellipseIn: rect), with: .color(colors[index]))
                                    context.fill(
                                        Path(ellipseIn: rect.insetBy(dx: -1.2, dy: -1.2)),
                                        with: .color(colors[index].opacity(0.22))
                                    )
                                }
                            }
                        }
                    } else {
                        Text("灯效已关闭")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func oceanColors(
        preset: OceanLightPreset,
        time: TimeInterval,
        count: Int,
        brightness: Double,
        imuTilt: Double
    ) -> [Color] {
        guard brightness > 0.05 else {
            return Array(repeating: Color.gray.opacity(0.15), count: count)
        }

        let palette = preset.previewColors
        return (0..<count).map { index in
            let row = index / ledsPerRow
            let col = index % ledsPerRow
            let rowPhase = Double(row) / Double(max(rowCount - 1, 1))
            let colPhase = Double(col) / Double(max(ledsPerRow - 1, 1))
            let phase = colPhase * 0.72 + rowPhase * 0.28
            let t = time * animationSpeed(for: preset.animationKind)
            let wave: Double
            switch preset.animationKind {
            case .flow:
                wave = (sin(t * 1.4 + phase * 6.28 + imuTilt * 2) + 1) / 2
            case .pulse:
                wave = (sin(t * 2.0 + rowPhase * 1.4) + 1) / 2 * (0.35 + colPhase * 0.65)
            case .wave:
                wave = (sin(t * 1.1 + phase * 4.5 + imuTilt + rowPhase * 2.2) + 1) / 2
            case .sparkle:
                wave = abs(sin(t * 3.5 + phase * 12 + imuTilt * 3 + Double(row) * 1.7))
            }
            let colorIndex = min(palette.count - 1, Int(phase * Double(palette.count - 1) + wave * 0.5))
            let base = palette[colorIndex]
            let rowBoost = 0.92 + rowPhase * 0.08
            return base.opacity((0.22 + wave * brightness * 0.78) * rowBoost)
        }
    }

    private func animationSpeed(for kind: OceanLightAnimationKind) -> Double {
        switch kind {
        case .flow: return 1.0
        case .pulse: return 0.85
        case .wave: return 0.75
        case .sparkle: return 1.25
        }
    }
}
