import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: swift generate_dmg_background.swift <output-png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let width: CGFloat = 1200
let height: CGFloat = 760

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let bounds = NSRect(x: 0, y: 0, width: width, height: height)

let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.985, green: 0.99, blue: 1.0, alpha: 1.0),
    NSColor(calibratedRed: 0.945, green: 0.965, blue: 0.995, alpha: 1.0),
])!
background.draw(in: bounds, angle: -18)

let panelRect = NSRect(x: 54, y: 68, width: 1092, height: 610)
let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 36, yRadius: 36)
NSColor.white.withAlphaComponent(0.86).setFill()
panelPath.fill()
NSColor(calibratedWhite: 0.88, alpha: 1).setStroke()
panelPath.lineWidth = 1
panelPath.stroke()

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1),
    .paragraphStyle: titleStyle,
]
"拖动 AhaKey Studio 到 Applications".draw(
    in: NSRect(x: 180, y: 616, width: 840, height: 42),
    withAttributes: titleAttributes
)

let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1),
    .paragraphStyle: titleStyle,
]
"安装完成后，就能像普通 Mac 应用一样打开使用".draw(
    in: NSRect(x: 210, y: 584, width: 780, height: 24),
    withAttributes: subtitleAttributes
)

let accentBlue = NSColor(calibratedRed: 0.22, green: 0.52, blue: 0.95, alpha: 1)

func drawDropZone(_ rect: NSRect, label: String, accent: NSColor) {
    let zone = NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28)
    accent.withAlphaComponent(0.08).setFill()
    zone.fill()

    let dashPattern: [CGFloat] = [10, 10]
    zone.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
    accent.withAlphaComponent(0.35).setStroke()
    zone.lineWidth = 3
    zone.stroke()

    let labelStyle = NSMutableParagraphStyle()
    labelStyle.alignment = .center
    let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.26, alpha: 1),
        .paragraphStyle: labelStyle,
    ]
    label.draw(in: NSRect(x: rect.minX, y: rect.maxY + 14, width: rect.width, height: 28), withAttributes: labelAttributes)
}

let appZone = NSRect(x: 110, y: 224, width: 230, height: 230)
let appTargetZone = NSRect(x: 852, y: 224, width: 230, height: 230)
drawDropZone(appZone, label: "把 App 从这里拖出", accent: accentBlue)
drawDropZone(appTargetZone, label: "拖到这里完成安装", accent: accentBlue)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 376, y: 336))
arrow.line(to: NSPoint(x: 822, y: 336))
arrow.lineWidth = 10
arrow.lineCapStyle = .round
accentBlue.setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 820, y: 336))
arrowHead.line(to: NSPoint(x: 776, y: 366))
arrowHead.move(to: NSPoint(x: 820, y: 336))
arrowHead.line(to: NSPoint(x: 776, y: 306))
arrowHead.lineWidth = 10
arrowHead.lineCapStyle = .round
accentBlue.setStroke()
arrowHead.stroke()

let arrowStyle = NSMutableParagraphStyle()
arrowStyle.alignment = .center
let arrowAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
    .foregroundColor: accentBlue,
    .paragraphStyle: arrowStyle,
]
"拖过去安装".draw(in: NSRect(x: 436, y: 368, width: 320, height: 26), withAttributes: arrowAttributes)

let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.46, alpha: 1),
    .paragraphStyle: titleStyle,
]
"打开镜像后，直接把左边的 App 图标拖到右边的 Applications 图标".draw(
    in: NSRect(x: 180, y: 118, width: 840, height: 24),
    withAttributes: footerAttributes
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render png background\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
