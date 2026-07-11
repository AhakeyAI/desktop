import AppKit
import ImageIO
import SwiftUI

/// 像素风 GIF 动画视图（画布 / Inspector / 预览弹窗共用）。
struct PixelArtAnimatedGIFView: View {
    let path: String
    let fps: Int
    var targetWidth: Int = 160
    var targetHeight: Int = 80
    var blockSize: Int = PixelArtProcessor.canvasBlockSize

    @State private var frames: [NSImage] = []
    @State private var currentFrame = 0
    @State private var gifTimer: Timer?

    var body: some View {
        Group {
            if !frames.isEmpty, currentFrame >= 0, currentFrame < frames.count {
                Image(nsImage: frames[currentFrame])
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { loadFrames() }
        .onDisappear {
            gifTimer?.invalidate()
            gifTimer = nil
        }
    }

    private func loadFrames() {
        gifTimer?.invalidate()
        gifTimer = nil

        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return }

        var images: [NSImage] = []
        images.reserveCapacity(count)
        for i in 0 ..< count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let pixel = PixelArtProcessor.pixelateNSImage(
                NSImage(cgImage: cgImage, size: .zero),
                width: targetWidth,
                height: targetHeight,
                blockSize: blockSize
            )
            images.append(pixel)
        }

        frames = images
        currentFrame = 0
        guard images.count > 1 else { return }
        let interval = 1.0 / Double(max(fps, 1))
        gifTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            currentFrame = (currentFrame + 1) % max(1, frames.count)
        }
    }
}

/// 无自定义 GIF 时的像素风默认屏（Gen2 参考渲染图：状态栏 + 波形）。
struct PixelArtStatusScreenView: View {
    var mode: AhaKeyModeSlot
    var screenWidth: CGFloat
    var screenHeight: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let t = timeline.date.timeIntervalSince1970
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

                let px = max(1, size.width / 40)
                let py = max(1, size.height / 20)

                drawPixelText(context: &context, text: "AhaKey", x: px * 2, y: py * 1.5, px: px, py: py, color: .white)
                drawPixelDot(context: &context, x: px * 14, y: py * 2, px: px, color: .green)

                drawPixelText(context: &context, text: "Listening", x: px * 2, y: py * 7, px: px, py: py, color: .white.opacity(0.9))
                drawWaveform(context: &context, t: t, x: px * 2, y: py * 10, width: size.width - px * 4, height: py * 5, px: px, py: py)

                drawPixelText(context: &context, text: mode.shortTitle, x: px * 2, y: size.height - py * 3, px: px, py: py, color: .cyan)
                drawPixelText(context: &context, text: "AI", x: px * 10, y: size.height - py * 3, px: px, py: py, color: .white.opacity(0.55))
            }
        }
    }

    private func drawPixelDot(context: inout GraphicsContext, x: CGFloat, y: CGFloat, px: CGFloat, color: Color) {
        let rect = CGRect(x: x, y: y, width: px * 1.2, height: px * 1.2)
        context.fill(Path(rect), with: .color(color))
    }

    private func drawPixelText(context: inout GraphicsContext, text: String, x: CGFloat, y: CGFloat, px: CGFloat, py: CGFloat, color: Color) {
        var cursor = x
        for char in text {
            drawChar(context: &context, char: char, x: cursor, y: y, px: px, py: py, color: color)
            cursor += px * 4.5
        }
    }

    private func drawChar(context: inout GraphicsContext, char: Character, x: CGFloat, y: CGFloat, px: CGFloat, py: CGFloat, color: Color) {
        let pattern = PixelFont.pattern(for: char)
        for (row, bits) in pattern.enumerated() {
            for col in 0 ..< 3 {
                if (bits >> (2 - col)) & 1 == 1 {
                    let rect = CGRect(x: x + CGFloat(col) * px, y: y + CGFloat(row) * py, width: px * 0.9, height: py * 0.9)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }

    private func drawWaveform(context: inout GraphicsContext, t: TimeInterval, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, px: CGFloat, py: CGFloat) {
        let bars = Int(width / (px * 1.4))
        guard bars > 0 else { return }
        for i in 0 ..< bars {
            let phase = sin(t * 3.5 + Double(i) * 0.55)
            let level = (phase + 1) / 2
            let barH = max(py, height * CGFloat(level))
            let rect = CGRect(
                x: x + CGFloat(i) * px * 1.4,
                y: y + height - barH,
                width: px,
                height: barH
            )
            context.fill(Path(rect), with: .color(.blue.opacity(0.85)))
        }
    }
}

/// 3×5 极简像素字体（大写字母 + 数字 + 常用符号）。
private enum PixelFont {
    static func pattern(for char: Character) -> [UInt8] {
        switch String(char).uppercased().first {
        case "A": return [0b010, 0b101, 0b111, 0b101, 0b101]
        case "B": return [0b110, 0b101, 0b110, 0b101, 0b110]
        case "C": return [0b011, 0b100, 0b100, 0b100, 0b011]
        case "D": return [0b110, 0b101, 0b101, 0b101, 0b110]
        case "E": return [0b111, 0b100, 0b110, 0b100, 0b111]
        case "G": return [0b011, 0b100, 0b101, 0b101, 0b011]
        case "H": return [0b101, 0b101, 0b111, 0b101, 0b101]
        case "I": return [0b111, 0b010, 0b010, 0b010, 0b111]
        case "K": return [0b101, 0b110, 0b100, 0b110, 0b101]
        case "L": return [0b100, 0b100, 0b100, 0b100, 0b111]
        case "M": return [0b101, 0b111, 0b111, 0b101, 0b101]
        case "N": return [0b101, 0b111, 0b111, 0b111, 0b101]
        case "O": return [0b010, 0b101, 0b101, 0b101, 0b010]
        case "R": return [0b110, 0b101, 0b110, 0b101, 0b101]
        case "S": return [0b011, 0b100, 0b010, 0b001, 0b110]
        case "T": return [0b111, 0b010, 0b010, 0b010, 0b010]
        case "U": return [0b101, 0b101, 0b101, 0b101, 0b111]
        case "V": return [0b101, 0b101, 0b101, 0b101, 0b010]
        case "W": return [0b101, 0b101, 0b111, 0b111, 0b101]
        case "Y": return [0b101, 0b101, 0b010, 0b010, 0b010]
        case "0": return [0b010, 0b101, 0b101, 0b101, 0b010]
        case "1": return [0b010, 0b110, 0b010, 0b010, 0b111]
        case "2": return [0b110, 0b001, 0b110, 0b100, 0b111]
        case "3": return [0b110, 0b001, 0b010, 0b001, 0b110]
        case ".": return [0b000, 0b000, 0b000, 0b000, 0b010]
        case "-": return [0b000, 0b000, 0b111, 0b000, 0b000]
        default:  return [0b000, 0b000, 0b000, 0b000, 0b000]
        }
    }
}
