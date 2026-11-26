import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate_dmg_background.swift <output-png>\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Installer", isDirectory: true)
guard let artwork = NSImage(contentsOf: assets.appendingPathComponent("InstallerArtwork.png")),
      let logo = NSImage(contentsOf: assets.appendingPathComponent("AhaKeyWordmark.png")) else {
    fputs("missing installer artwork or brand mark: \(assets.path)\n", stderr)
    exit(1)
}

// Keep the canvas and icon centers in sync with package_dmg.sh.
let width = 920
let height = 492
let bounds = NSRect(x: 0, y: 0, width: width, height: height)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create installer background canvas\n", stderr)
    exit(1)
}

func rect(x: CGFloat, top: CGFloat, width: CGFloat, height extent: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(height) - top - extent, width: width, height: extent)
}

func line(_ text: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    text.draw(in: rect(x: 30, top: top, width: CGFloat(width) - 60, height: 25), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style
    ])
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
artwork.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
let wordmarkWidth: CGFloat = 148
let wordmarkHeight = wordmarkWidth * logo.size.height / logo.size.width
logo.draw(in: rect(x: 25, top: 19, width: wordmarkWidth, height: wordmarkHeight),
          from: .zero, operation: .sourceOver, fraction: 1)

let ink = NSColor(srgbRed: 0.05, green: 0.10, blue: 0.17, alpha: 1)
let mutedInk = NSColor(srgbRed: 0.31, green: 0.37, blue: 0.46, alpha: 1)
line("拖到「应用程序」即可安装", top: 88, size: 18, weight: .semibold, color: ink)
line("Drag to Applications to install", top: 116, size: 14, weight: .medium, color: mutedInk)

// Finder supplies both draggable icons and their labels; the image contains only their guides.
for center in [CGFloat(230), CGFloat(690)] {
    let card = NSBezierPath(roundedRect: rect(x: center - 86, top: 157, width: 172, height: 176),
                            xRadius: 28, yRadius: 28)
    NSColor.white.withAlphaComponent(0.62).setFill()
    card.fill()
    NSColor(srgbRed: 0.75, green: 0.84, blue: 0.98, alpha: 1).setStroke()
    card.lineWidth = 1
    card.stroke()
}

let arrowBlue = NSColor(srgbRed: 0.07, green: 0.45, blue: 0.97, alpha: 1)
let arrowY = CGFloat(height) - 235
let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: 330, y: arrowY))
shaft.line(to: NSPoint(x: 573, y: arrowY))
shaft.lineWidth = 4
shaft.lineCapStyle = .round
shaft.setLineDash([1, 12], count: 2, phase: 0)
arrowBlue.setStroke()
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 590, y: arrowY))
head.line(to: NSPoint(x: 571, y: arrowY + 12))
head.line(to: NSPoint(x: 571, y: arrowY - 12))
head.close()
arrowBlue.setFill()
head.fill()

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render installer background\n", stderr)
    exit(1)
}
try png.write(to: output)
