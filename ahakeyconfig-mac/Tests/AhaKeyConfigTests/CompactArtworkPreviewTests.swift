import AppKit
import XCTest
@testable import AhaKeyConfig

final class CompactArtworkPreviewTests: XCTestCase {
    func testPNGPreviewUsesExpandedRGB565ScreenPixels() throws {
        var pixels = Data()
        for _ in 0..<12800 { pixels.append(contentsOf: [0xF8, 0]) }
        let data = try OLEDFrameEncoder.previewPNG(rgb565: pixels)
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(image.pixelsWide, 160); XCTAssertEqual(image.pixelsHigh, 80)
        // NSColor's calibrated/HDR conversion depends on the current display.
        // Verify the actual PNG pixels in an explicitly normalized sRGB buffer.
        let decoded = try XCTUnwrap(image.cgImage)
        var buffer = [UInt8](repeating: 0, count: 160 * 80 * 4)
        try buffer.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 160, height: 80,
                bitsPerComponent: 8, bytesPerRow: 160 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: 160, height: 80))
        }
        XCTAssertEqual(Array(buffer.prefix(4)), [255, 0, 0, 255])
        XCTAssertThrowsError(try OLEDFrameEncoder.previewPNG(rgb565: Data(count: 25599)))
    }
}
