import AppKit
import CoreGraphics
import Foundation

/// GIF / 屏幕预览 / BLE 上传共用的像素风图像处理。
enum PixelArtProcessor {
    /// 画布预览：块更大，近看更有像素感。
    static let canvasBlockSize = 3
    /// 设备编码（160×80）：与固件低分辨率 LCD 匹配。
    static let encodeBlockSize = 4
    static let colorLevels = 6

    static func pixelateNSImage(
        _ image: NSImage,
        width: Int,
        height: Int,
        blockSize: Int = canvasBlockSize,
        levels: Int = colorLevels
    ) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let processed = pixelateCGImage(cg, width: width, height: height, blockSize: blockSize, levels: levels) else {
            return image
        }
        return NSImage(cgImage: processed, size: NSSize(width: width, height: height))
    }

    static func pixelateCGImage(
        _ source: CGImage,
        width: Int,
        height: Int,
        blockSize: Int = canvasBlockSize,
        levels: Int = colorLevels
    ) -> CGImage? {
        guard width > 0, height > 0, blockSize > 0 else { return nil }

        let lowW = max(1, width / blockSize)
        let lowH = max(1, height / blockSize)
        var lowRGBA = [UInt8](repeating: 0, count: lowW * lowH * 4)

        guard let lowCtx = rgbaContext(width: lowW, height: lowH, data: &lowRGBA) else { return nil }
        lowCtx.interpolationQuality = .none
        lowCtx.setFillColor(CGColor(gray: 0, alpha: 1))
        lowCtx.fill(CGRect(x: 0, y: 0, width: lowW, height: lowH))

        let scale = min(Double(lowW) / Double(source.width), Double(lowH) / Double(source.height))
        let drawW = Double(source.width) * scale
        let drawH = Double(source.height) * scale
        let drawRect = CGRect(
            x: (Double(lowW) - drawW) / 2,
            y: (Double(lowH) - drawH) / 2,
            width: drawW,
            height: drawH
        )
        lowCtx.draw(source, in: drawRect)
        quantizeRGBA(&lowRGBA, levels: levels)

        var outRGBA = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let sx = min(lowW - 1, x / blockSize)
                let sy = min(lowH - 1, y / blockSize)
                let src = (sy * lowW + sx) * 4
                let dst = (y * width + x) * 4
                outRGBA[dst] = lowRGBA[src]
                outRGBA[dst + 1] = lowRGBA[src + 1]
                outRGBA[dst + 2] = lowRGBA[src + 2]
                outRGBA[dst + 3] = 255
            }
        }

        guard let outCtx = rgbaContext(width: width, height: height, data: &outRGBA) else { return nil }
        return outCtx.makeImage()
    }

    private static func rgbaContext(width: Int, height: Int, data: inout [UInt8]) -> CGContext? {
        CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func quantizeRGBA(_ pixels: inout [UInt8], levels: Int) {
        let steps = max(2, levels)
        let stepSize = 255.0 / Double(steps - 1)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            for c in 0 ..< 3 {
                let v = Double(pixels[i + c])
                let q = (v / stepSize).rounded() * stepSize
                pixels[i + c] = UInt8(min(255, max(0, Int(q))))
            }
        }
    }
}
