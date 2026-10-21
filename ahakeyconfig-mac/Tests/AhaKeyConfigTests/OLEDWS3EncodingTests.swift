import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class OLEDWS3EncodingTests: XCTestCase {
    private func gif(frameCount: Int, distinctFrames: Bool = false) throws -> URL {
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
        for index in 0..<frameCount {
            if distinctFrames {
                let colors: [CGColor] = [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                    CGColor(red: 0, green: 1, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)]
                context.setFillColor(colors[index % colors.count])
                context.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
                CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
            } else { CGImageDestinationAddImage(destination, image, nil) }
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testImageEncodingPreservesRGB565BEAndAddsOnlySlotPadding() throws {
        let url = try gif(frameCount: 1)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let frames = try OLEDFrameEncoder.frames(fromGIFAt: url, maximumFrames: 8)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].count, 25_600)
        // GIF/CoreGraphics color management can add green to device red.
        // The red component must still occupy the high RGB565 byte (BE),
        // and a uniform source must encode to identical consecutive pixels.
        XCTAssertGreaterThanOrEqual(frames[0][0] & 0xF8, 0xE0)
        XCTAssertEqual(frames[0].prefix(2), frames[0].subdata(in: 2..<4))
        let payload = try WS3ResourcePayload(entryID: 0, frames: frames)
        XCTAssertEqual(payload.bytes.prefix(25_600), frames[0])
        XCTAssertEqual(payload.bytes.suffix(3072), Data(repeating: 0xFF, count: 3072))
    }

    func testDistinctGIFFramesRemainDistinctAndInOrderThroughCP2Padding() throws {
        let url = try gif(frameCount: 3, distinctFrames: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let frames = try OLEDFrameEncoder.frames(fromGIFAt: url, maximumFrames: 12)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(Set(frames).count, 3)
        let pixels = frames.map { UInt16($0[0]) << 8 | UInt16($0[1]) }
        XCTAssertGreaterThanOrEqual((pixels[0] >> 11) & 31, 28)
        XCTAssertGreaterThanOrEqual((pixels[1] >> 5) & 63, 56)
        XCTAssertGreaterThanOrEqual(pixels[2] & 31, 28)
        let payload = try WS3ResourcePayload(entryID: 18, frames: frames)
        for index in frames.indices {
            let start = index * 28_672
            XCTAssertEqual(payload.bytes.subdata(in: start..<(start + 25_600)), frames[index])
        }
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
