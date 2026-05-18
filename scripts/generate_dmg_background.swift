import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: swift generate_dmg_background.swift <output-png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])

// Background size must match DMG window content area
// Window bounds in osascript: {100, 100, 960, 580} => content 860 x 480
let width:  CGFloat = 860
let height: CGFloat = 480

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let bounds = NSRect(x: 0, y: 0, width: width, height: height)

// ── Background: clean white-to-light-gray, like macOS system dialogs ─────
NSGradient(colors: [
    NSColor(calibratedRed: 0.980, green: 0.982, blue: 0.988, alpha: 1),
    NSColor(calibratedRed: 0.940, green: 0.944, blue: 0.955, alpha: 1),
])!.draw(in: bounds, angle: 90)

// ── Title ─────────────────────────────────────────────────────────────────
let centerStyle = NSMutableParagraphStyle()
centerStyle.alignment = .center

let titleAttr: [NSAttributedString.Key: Any] = [
    .font:            NSFont.systemFont(ofSize: 26, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.13, alpha: 1),
    .paragraphStyle:  centerStyle,
]
"拖动 AhaKey Studio 到 Applications".draw(
    in: NSRect(x: 60, y: height - 82, width: width - 120, height: 40),
    withAttributes: titleAttr
)

// ── Subtitle ──────────────────────────────────────────────────────────────
let subAttr: [NSAttributedString.Key: Any] = [
    .font:            NSFont.systemFont(ofSize: 14, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.48, alpha: 1),
    .paragraphStyle:  centerStyle,
]
"安装完成后，就能像普通 Mac 应用一样打开使用".draw(
    in: NSRect(x: 80, y: height - 114, width: width - 160, height: 22),
    withAttributes: subAttr
)

// ── Arrow: clean filled shape between the two icon positions ──────────────
// App icon centre ~x=170, Applications icon centre ~x=690 (at icon size 100)
// Arrow spans roughly x 260 → 590, y centred at 210
let arrowColor = NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.95, alpha: 1)
let arrowY: CGFloat  = 210
let arrowX0: CGFloat = 268
let arrowX1: CGFloat = 588
let arrowLW: CGFloat = 6
let headLen: CGFloat = 22
let headHalf: CGFloat = 14

// Shaft
let shaft = NSBezierPath()
shaft.move(to:  NSPoint(x: arrowX0, y: arrowY))
shaft.line(to:  NSPoint(x: arrowX1 - headLen * 0.6, y: arrowY))
shaft.lineWidth    = arrowLW
shaft.lineCapStyle = .round
arrowColor.setStroke()
shaft.stroke()

// Filled arrowhead
let head = NSBezierPath()
head.move(to:     NSPoint(x: arrowX1,             y: arrowY))
head.line(to:     NSPoint(x: arrowX1 - headLen,   y: arrowY + headHalf))
head.line(to:     NSPoint(x: arrowX1 - headLen,   y: arrowY - headHalf))
head.close()
arrowColor.setFill()
head.fill()

// Arrow caption
let captionAttr: [NSAttributedString.Key: Any] = [
    .font:            NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: arrowColor,
    .paragraphStyle:  centerStyle,
]
"拖过去安装".draw(
    in: NSRect(x: arrowX0, y: arrowY - 36, width: arrowX1 - arrowX0, height: 20),
    withAttributes: captionAttr
)

image.unlockFocus()

guard let tiff   = image.tiffRepresentation,
      let rep    = NSBitmapImageRep(data: tiff),
      let png    = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render png background\n", stderr)
    exit(1)
}
try png.write(to: outputURL)
