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
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let sourceImage = sourceImageURL.flatMap { NSImage(contentsOf: $0) }

for (size, filename) in sizes {
    let image = sourceImage.map { renderSourceIcon($0, size: CGFloat(size)) } ?? makeIcon(size: CGFloat(size))
    let destination = outputDirectory.appendingPathComponent(filename)
    try pngData(from: image).write(to: destination)
}

// MARK: - Icon rendering

func renderSourceIcon(_ source: NSImage, size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    source.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: source.size),
        operation: .sourceOver,
        fraction: 1.0
    )

    image.unlockFocus()
    return image
}

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let s = size

    // ── Background: white ──────────────────────────────────────────────────
    NSColor.white.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: s, height: s))

    // ── "A" letter: bold geometric dark charcoal ───────────────────────────
    // Use heaviest system font weight to match the bold geometric "A" in reference
    let aColor = NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
    let aFont  = NSFont.systemFont(ofSize: s * 0.86, weight: .black)
    let aAttribs: [NSAttributedString.Key: Any] = [
        .font: aFont,
        .foregroundColor: aColor,
    ]
    let aStr  = NSAttributedString(string: "A", attributes: aAttribs)
    let aSize = aStr.size()
    // Center horizontally; nudge slightly below vertical center for optical balance
    let aX = (s - aSize.width) / 2
    let aY = (s - aSize.height) / 2 - s * 0.02
    aStr.draw(at: NSPoint(x: aX, y: aY))

    // ── Lightning bolt: electric blue diagonal slash ────────────────────────
    // Bolt runs from upper-right → lower-left, cutting through the "A".
    // All coordinates in 0…1000 space; scaled to actual icon size via `pt()`.
    let boltBlue = NSColor(calibratedRed: 0.08, green: 0.38, blue: 0.96, alpha: 1.0)
    let sc = s / 1000.0
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * sc, y: y * sc) }

    // Classic zigzag lightning bolt outline (8 vertices, clockwise):
    //   Upper section  → step right (jog) → Lower section → tip → back up
    //
    //   P1 ── P2                (top edge)
    //   |       \
    //   P8       P3 ── P4       (step: lower section is offset right ~90 units)
    //   |               \
    //   P7 ── P6          P5    (tip)

    let bolt = NSBezierPath()
    bolt.move(to:  pt(502, 880))   // P1  top-left
    bolt.line(to:  pt(662, 880))   // P2  top-right
    bolt.line(to:  pt(492, 474))   // P3  mid-right (upper section right edge at step)
    bolt.line(to:  pt(580, 474))   // P4  step-right (lower section right edge start)
    bolt.line(to:  pt(406, 78))    // P5  bottom tip right
    bolt.line(to:  pt(328, 78))    // P6  bottom tip left
    bolt.line(to:  pt(393, 454))   // P7  mid-left  (lower section left edge at step)
    bolt.line(to:  pt(305, 454))   // P8  step-left (upper section left edge)
    bolt.close()                   // back to P1

    boltBlue.setFill()
    bolt.fill()

    image.unlockFocus()
    return image
}

// MARK: - PNG helper

func pngData(from image: NSImage) throws -> Data {
    guard let tiff   = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png    = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1)
    }
    return png
}
