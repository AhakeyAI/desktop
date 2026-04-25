import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: swift generate_icons.swift <output-iconset-dir> [source-image]\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let sourceImageURL = arguments.count >= 3 ? URL(fileURLWithPath: arguments[2]) : nil
let fileManager = FileManager.default

try? fileManager.removeItem(at: outputDirectory)
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

let sourceImage = sourceImageURL.flatMap { NSImage(contentsOf: $0) }

for (size, filename) in sizes {
    let image: NSImage
    if let sourceImage {
        image = renderSourceIcon(sourceImage, size: CGFloat(size))
    } else {
        image = makeDockIcon(size: CGFloat(size))
    }
    let destination = outputDirectory.appendingPathComponent(filename)
    try pngData(from: image).write(to: destination)
}

func renderSourceIcon(_ source: NSImage, size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(origin: .zero, size: image.size)
    source.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)

    image.unlockFocus()
    return image
}

func makeDockIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high
    let rect = NSRect(origin: .zero, size: image.size)
    let r = size * 0.22

    // 渐变背景——和 EchoWrite 风格相近的冷色调
    let bg = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.88, green: 0.93, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 0.86, blue: 0.92, alpha: 1)
        ]
    )?.draw(in: bg, angle: 90)

    // 柔和光晕
    drawBlurBlob(
        color: NSColor(calibratedRed: 0.40, green: 0.65, blue: 0.95, alpha: 0.25),
        rect: NSRect(x: size * 0.30, y: size * 0.35, width: size * 0.40, height: size * 0.35),
        blur: size * 0.10
    )

    // 中央：简约键盘轮廓（圆角矩形 + 4 个小方块）
    let kbW = size * 0.56
    let kbH = size * 0.30
    let kbX = (size - kbW) / 2
    let kbY = size * 0.38

    let kbRect = NSRect(x: kbX, y: kbY, width: kbW, height: kbH)
    let kb = NSBezierPath(roundedRect: kbRect, xRadius: size * 0.04, yRadius: size * 0.04)
    NSColor.white.withAlphaComponent(0.75).setFill()
    kb.fill()
    NSColor.white.withAlphaComponent(0.50).setStroke()
    kb.lineWidth = max(1, size * 0.005)
    kb.stroke()

    // 4 个按键
    let keyInset = size * 0.03
    let keyGap = size * 0.02
    let innerW = kbW - keyInset * 2
    let keyW = (innerW - keyGap * 3) / 4
    let keyH = kbH - keyInset * 2
    for i in 0..<4 {
        let x = kbX + keyInset + CGFloat(i) * (keyW + keyGap)
        let y = kbY + keyInset
        let keyRect = NSRect(x: x, y: y, width: keyW, height: keyH)
        let key = NSBezierPath(roundedRect: keyRect, xRadius: size * 0.015, yRadius: size * 0.015)

        // 第一个键（麦克风）用强调色
        if i == 0 {
            NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.90, alpha: 0.85).setFill()
        } else {
            NSColor(calibratedWhite: 0.92, alpha: 0.90).setFill()
        }
        key.fill()
    }

    // 麦克风键上画一个小圆点
    let dotSize = size * 0.03
    let firstKeyX = kbX + keyInset
    let firstKeyY = kbY + keyInset
    let dotRect = NSRect(
        x: firstKeyX + (keyW - dotSize) / 2,
        y: firstKeyY + (keyH - dotSize) / 2,
        width: dotSize,
        height: dotSize
    )
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    image.unlockFocus()
    return image
}

func drawBlurBlob(color: NSColor, rect: NSRect, blur: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowColor = color
    shadow.shadowOffset = .zero
    shadow.set()
    let blob = NSBezierPath(ovalIn: rect)
    color.setFill()
    blob.fill()
}

func pngData(from image: NSImage) throws -> Data {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1)
    }
    return png
}
