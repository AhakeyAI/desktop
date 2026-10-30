// Deterministic macOS HIL fixtures; these are not production artwork.
// Usage: swift scripts/generate_ws3_capacity_fixtures.swift <new-output-directory>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_ws3_capacity_fixtures.swift <new-output-directory>\n", stderr)
    exit(2)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let singleEntries = (0..<19).filter { $0 != 12 && $0 != 13 }
let names = [9, 13].map { String(format: "capacity-source-%02d.gif", $0) } +
    singleEntries.map { String(format: "resource-entry-%02d.png", $0) }
for name in names {
    let candidate = folder.appendingPathComponent(name)
    guard !FileManager.default.fileExists(atPath: candidate.path) else {
        fputs("Refusing to overwrite an existing fixture. Choose a new output directory.\n", stderr)
        exit(2)
    }
}
for count in [9, 13] {
    let url = folder.appendingPathComponent(String(format: "capacity-source-%02d.gif", count))
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil),
          let ctx = CGContext(data: nil, width: 160, height: 80, bitsPerComponent: 8, bytesPerRow: 640,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("fixture context") }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    ctx.setShouldAntialias(false)
    for index in 0..<count {
        ctx.setFillColor(red: 0.035, green: 0.05, blue: 0.07, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
        ctx.setFillColor(red: 0.12, green: 0.7, blue: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 8 + index * 136 / (count - 1), y: 25, width: 8, height: 30))
        ctx.setFillColor(red: 0.85, green: 0.9, blue: 0.95, alpha: 1)
        for position in 0...index { ctx.fill(CGRect(x: 8 + position * 10, y: 8, width: 6, height: 5)) }
        guard let image = ctx.makeImage() else { fatalError("fixture frame") }
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1, kCGImagePropertyGIFUnclampedDelayTime: 0.1]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest), let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) == count else { fatalError("fixture GIF") }
    let bytes = try Data(contentsOf: url).count
    print("fixture=\(url.lastPathComponent) frames=\(count) width=160 height=80 fileBytes=\(bytes)")
}

// Numbered single-frame images cover the other 17 entries. The two capacity
// GIFs remain assigned to entries 12/13 for the final visual check.
let digits: [[UInt8]] = [
    [14,17,19,21,25,17,14], [4,12,4,4,4,4,14], [14,17,1,2,4,8,31],
    [30,1,1,14,1,1,30], [2,6,10,18,31,2,2], [31,16,16,30,1,1,30],
    [14,16,16,30,17,17,14], [31,1,2,4,8,8,8], [14,17,17,14,17,17,14],
    [14,17,17,15,1,1,14]
]
for entry in singleEntries {
    let url = folder.appendingPathComponent(String(format: "resource-entry-%02d.png", entry))
    // Entry 0 also exercises automatic resizing of a multi-megabyte source.
    let width = entry == 0 ? 1600 : 160, height = entry == 0 ? 800 : 80
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("single-frame fixture") }
    ctx.setShouldAntialias(false)
    if entry == 0 {
        let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var seed: UInt32 = 0xA4A5E001
        for index in 0..<(width * height) {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            pixels[index * 4] = UInt8(8 + (seed & 127))
            pixels[index * 4 + 1] = UInt8(8 + ((seed >> 8) & 127))
            pixels[index * 4 + 2] = UInt8(8 + ((seed >> 16) & 127))
            pixels[index * 4 + 3] = 255
        }
        ctx.scaleBy(x: 10, y: 10)
    } else {
        ctx.setFillColor(red: 0.025 + Double(entry % 3) * 0.045,
                         green: 0.03 + Double(entry % 5) * 0.025,
                         blue: 0.05 + Double(entry % 7) * 0.03, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
    }
    ctx.setFillColor(red: 0.9, green: 0.95, blue: 1, alpha: 1)
    for (position, digit) in [entry / 10, entry % 10].enumerated() {
        for row in 0..<7 {
            for column in 0..<5 where digits[digit][row] & (1 << (4 - column)) != 0 {
                ctx.fill(CGRect(x: 45 + position * 36 + column * 6, y: 15 + (6 - row) * 7, width: 5, height: 6))
            }
        }
    }
    ctx.setFillColor(red: 0.15, green: 0.7, blue: 0.5, alpha: 1)
    ctx.fill(CGRect(x: 8, y: 4, width: 144 * (entry + 1) / 19, height: 3))
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(source) == 1, let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == width && image.height == height else { fatalError("single-frame fixture validation") }
    print("fixture=\(url.lastPathComponent) entry=\(entry) frames=1 width=\(width) height=\(height)")
}
