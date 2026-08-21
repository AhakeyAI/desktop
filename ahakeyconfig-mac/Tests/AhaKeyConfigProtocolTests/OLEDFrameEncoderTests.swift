import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AhaKeyConfig

final class OLEDFrameEncoderTests: XCTestCase {
    func testSourceSlightlyAboveTwoMiBStillUsesAutomaticDeviceEncoding() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ahakey-large-source-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0, count: 2 * 1024 * 1024 + 1))
        try handle.close()

        let frames = try OLEDFrameEncoder.frames(fromGIFAt: url, maxFrames: 1)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].count, AhaKeyCommand.oledWidth * AhaKeyCommand.oledHeight * 2)
    }

    func testSourceAboveTwentyMiBStillHitsSafetyLimit() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ahakey-oversized-source-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(AhaKeyCommand.oledMaxSourceFileBytes + 1))
        try handle.close()

        XCTAssertThrowsError(try OLEDFrameEncoder.validateSourceFileSize(at: url)) { error in
            guard case OLEDFrameEncodingError.sourceFileTooLarge(let fileSize, let maxBytes) = error else {
                return XCTFail("Expected sourceFileTooLarge, got \(error)")
            }
            XCTAssertEqual(fileSize, AhaKeyCommand.oledMaxSourceFileBytes + 1)
            XCTAssertEqual(maxBytes, AhaKeyCommand.oledMaxSourceFileBytes)
        }
    }
}
