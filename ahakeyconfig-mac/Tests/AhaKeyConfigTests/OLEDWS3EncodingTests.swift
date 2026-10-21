import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class OLEDWS3EncodingTests: XCTestCase {
    private func gif(frameCount: Int) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("frames.gif")
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 80, bitsPerComponent: 8,
            bytesPerRow: 160 * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil))
        for _ in 0..<frameCount { CGImageDestinationAddImage(destination, image, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testImageEncodingPreservesRGB565BEAndAddsOnlySlotPadding() throws {
        let url = try gif(frameCount: 1)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let frames = try OLEDFrameEncoder.frames(fromGIFAt: url, maximumFrames: 8)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].count, 25_600)
        XCTAssertEqual(Array(frames[0].prefix(4)), [0xF8, 0x00, 0xF8, 0x00])
        let payload = try WS3ResourcePayload(entryID: 0, frames: frames)
        XCTAssertEqual(payload.bytes.prefix(25_600), frames[0])
        XCTAssertEqual(payload.bytes.suffix(3072), Data(repeating: 0xFF, count: 3072))
    }

    func testGIFOverTargetCapacityIsRejectedWithoutTruncationButLegacyLimitRemains() throws {
        let url = try gif(frameCount: 9)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(OLEDFrameEncoder.frameCount(at: url), 9)
        XCTAssertThrowsError(try OLEDFrameEncoder.frames(fromGIFAt: url, maximumFrames: 8))
        XCTAssertEqual(try OLEDFrameEncoder.frames(fromGIFAt: url, maximumFrames: 12).count, 9)
        XCTAssertEqual(try OLEDFrameEncoder.frames(fromGIFAt: url).count, 9)
    }
}
