import AppKit

// Renders the DMG window background.
//
// usage: swift generate_dmg_background.swift <output.(tiff|png)> [art.png] [logo.png]
//
// A DMG background cannot follow the viewer's system language (Finder shows one
// picture for everyone), so the picture explains itself with the two icons and the
// arrow, and the short instruction is written in Chinese, Korean and English.
//
// `art.png` is an optional decorative backdrop (corners only, middle left empty).
// `.tiff` output carries a 1x and a 2x representation so the window stays sharp on
// Retina displays; `.png` writes the 1x image only.

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: swift generate_dmg_background.swift <output.(tiff|png)> [art.png] [logo.png]\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let artImage = arguments.count >= 3 ? NSImage(contentsOfFile: arguments[2]) : nil
let logoImage = arguments.count >= 4 ? NSImage(contentsOfFile: arguments[3]) : nil

// Must match package_dmg.sh: window bounds {200, 120, 1120, 672} (title bar included) => content 920 x 520,
// icon size 128, app icon centre (230, 235), Applications centre (690, 235), measured
// from the top-left corner. Finder may show its path bar over the bottom ~30 pt, so
// nothing important sits there.
let width: CGFloat = 920
let height: CGFloat = 520
let iconCenterY: CGFloat = 235
let appIconCenterX: CGFloat = 230
let applicationsCenterX: CGFloat = 690
let iconSize: CGFloat = 128

let brandBlue = NSColor(srgbRed: 0x16 / 255.0, green: 0x77 / 255.0, blue: 0xFF / 255.0, alpha: 1)
let brandBlueLight = NSColor(srgbRed: 0x2A / 255.0, green: 0xA3 / 255.0, blue: 0xFF / 255.0, alpha: 1)
let textColor = NSColor(srgbRed: 0x0B / 255.0, green: 0x12 / 255.0, blue: 0x20 / 255.0, alpha: 1)
let mutedColor = NSColor(srgbRed: 0x5B / 255.0, green: 0x67 / 255.0, blue: 0x7A / 255.0, alpha: 1)

/// Converts a top-left based y (Finder coordinates) into AppKit's bottom-left space.
func flipY(_ y: CGFloat) -> CGFloat { height - y }

func drawCentered(_ text: String, font: NSFont, color: NSColor, centerY: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: style,
    ]
    let size = (text as NSString).size(withAttributes: attributes)
    let rect = NSRect(x: 0, y: flipY(centerY) - size.height / 2, width: width, height: size.height)
    (text as NSString).draw(in: rect, withAttributes: attributes)
}

func drawScene() {
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    // Backdrop: the decorative art when given, otherwise the brand's soft white-to-blue.
    if let art = artImage {
        // Scale to cover the canvas, anchored at the centre.
        let scale = max(width / art.size.width, height / art.size.height)
        let drawSize = NSSize(width: art.size.width * scale, height: art.size.height * scale)
        art.draw(in: NSRect(x: (width - drawSize.width) / 2, y: (height - drawSize.height) / 2,
                            width: drawSize.width, height: drawSize.height),
                 from: .zero, operation: .copy, fraction: 1)
    } else {
        NSGradient(colors: [
            NSColor.white,
            NSColor(srgbRed: 0xEE / 255.0, green: 0xF5 / 255.0, blue: 0xFF / 255.0, alpha: 1),
        ])!.draw(in: bounds, angle: -90)
    }

    // Brand row: logo mark + "AhaKey Studio" in the website's blue gradient wordmark style.
    let wordmarkFont = NSFont(name: "AvenirNext-Heavy", size: 26) ?? NSFont.systemFont(ofSize: 26, weight: .heavy)
    let wordmark = "AhaKey Studio"
    let wordmarkSize = (wordmark as NSString).size(withAttributes: [.font: wordmarkFont])
    let logoSide: CGFloat = logoImage == nil ? 0 : 30
    let gap: CGFloat = logoImage == nil ? 0 : 10
    let rowWidth = logoSide + gap + wordmarkSize.width
    let rowX = (width - rowWidth) / 2
    let rowCenterY: CGFloat = 46
    if let logo = logoImage {
        logo.draw(in: NSRect(x: rowX, y: flipY(rowCenterY) - logoSide / 2, width: logoSide, height: logoSide),
                  from: .zero, operation: .sourceOver, fraction: 1)
    }
    let wordmarkRect = NSRect(x: rowX + logoSide + gap, y: flipY(rowCenterY) - wordmarkSize.height / 2,
                              width: wordmarkSize.width, height: wordmarkSize.height)
    let wordmarkImage = NSImage(size: wordmarkSize, flipped: false) { rect in
        (wordmark as NSString).draw(in: rect, withAttributes: [.font: wordmarkFont, .foregroundColor: NSColor.black])
        NSGraphicsContext.current?.compositingOperation = .sourceIn
        NSGradient(colors: [brandBlueLight, brandBlue])!.draw(in: rect, angle: -90)
        return true
    }
    wordmarkImage.draw(in: wordmarkRect)

    // The instruction in the three languages the app ships.
    drawCentered("拖到「应用程序」即可安装", font: .systemFont(ofSize: 17, weight: .semibold), color: textColor, centerY: 90)
    drawCentered("응용 프로그램 폴더로 끌어 놓으면 설치돼요", font: .systemFont(ofSize: 15, weight: .medium), color: textColor, centerY: 115)
    drawCentered("Drag to Applications to install", font: .systemFont(ofSize: 13, weight: .regular), color: mutedColor, centerY: 137)

    // Soft plates under the two icons so they read as drop zones on any backdrop.
    for centerX in [appIconCenterX, applicationsCenterX] {
        let plate = NSRect(x: centerX - 86, y: flipY(iconCenterY) - 98, width: 172, height: 176)
        let path = NSBezierPath(roundedRect: plate, xRadius: 28, yRadius: 28)
        NSColor.white.withAlphaComponent(0.72).setFill()
        path.fill()
        brandBlue.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // Finder on recent macOS sometimes leaves the /Applications symlink without an
    // icon; draw the real folder icon underneath so the target is always visible.
    let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
    folderIcon.size = NSSize(width: iconSize, height: iconSize)
    folderIcon.draw(in: NSRect(x: applicationsCenterX - iconSize / 2, y: flipY(iconCenterY) - iconSize / 2,
                               width: iconSize, height: iconSize),
                    from: .zero, operation: .sourceOver, fraction: 1)

    // Arrow: dotted shaft, solid head, in brand blue.
    let arrowY = flipY(iconCenterY)
    let x0 = appIconCenterX + 100
    let x1 = applicationsCenterX - 100
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: x0, y: arrowY))
    shaft.line(to: NSPoint(x: x1 - 16, y: arrowY))
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    let dash: [CGFloat] = [2, 11]
    shaft.setLineDash(dash, count: 2, phase: 0)
    brandBlue.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: x1, y: arrowY))
    head.line(to: NSPoint(x: x1 - 20, y: arrowY + 13))
    head.line(to: NSPoint(x: x1 - 20, y: arrowY - 13))
    head.close()
    brandBlue.setFill()
    head.fill()
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawScene()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output: Data?
if outputURL.pathExtension.lowercased() == "tiff" {
    output = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)
} else {
    output = render(scale: 1).representation(using: .png, properties: [:])
}
guard let output else {
    fputs("failed to render background\n", stderr)
    exit(1)
}
try output.write(to: outputURL)
