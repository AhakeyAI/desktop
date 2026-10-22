import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class OLEDArtworkAdaptationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func gif(_ count: Int) throws -> URL {
        let url = try directory().appendingPathComponent("source.gif")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 160, height: 80, bitsPerComponent: 8, bytesPerRow: 640,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for index in 0..<count {
            let red = CGFloat(index) / CGFloat(max(1, count - 1))
            ctx.setFillColor(CGColor(red: red, green: 0, blue: 1 - red, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
            CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest)); return url
    }
    func testLargePNGIsAutomaticallyReducedWithoutChangingSource() throws {
        let url = try directory().appendingPathComponent("large.png"), width = 1024, height = 1024
        var bytes = [UInt8](repeating: 255, count: width * height * 4), random: UInt32 = 42
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 {
                random = random &* 1664525 &+ 1013904223
                bytes[pixel + channel] = UInt8(truncatingIfNeeded: random >> 24)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
        let original = try Data(contentsOf: url)
        XCTAssertGreaterThan(original.count, AhaKeyCommand.oledMaxSourceFileBytes)
        let result = try OLEDFrameEncoder.adaptedFrames(at: url, maximumFrames: 8)
        XCTAssertEqual(result.frames.count, 1); XCTAssertEqual(result.frames[0].count, 25_600)
        let previewSource = try XCTUnwrap(CGImageSourceCreateWithData(result.previewPNG as CFData, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(previewSource, 0, nil))
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), 160)
        XCTAssertTrue(result.wasResized)
        XCTAssertEqual(try WS3ResourcePayload(entryID: 8, frames: result.frames).bytes.count, 28_672)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testOversizedAnimationSamplesAcrossTheWholeClipForBothCapacities() throws {
        let url = try gif(13)
        let all = try OLEDFrameEncoder.frames(fromGIFAt: url)
        for (entry, maximum) in [(UInt8(0), 8), (UInt8(18), 12)] {
            let result = try OLEDFrameEncoder.adaptedFrames(at: url, maximumFrames: maximum)
            XCTAssertEqual(result.sourceFrameCount, 13); XCTAssertEqual(result.frames.count, maximum)
            XCTAssertEqual(result.frames.first, all.first); XCTAssertEqual(result.frames.last, all.last)
            XCTAssertEqual(Set(result.frames).count, maximum)
            XCTAssertEqual(try WS3ResourcePayload(entryID: entry, frames: result.frames).bytes.count, maximum * 28_672)
        }
    }
    func testSmallGIFKeepsEveryFrameAndLegacyCapacity() throws {
        let url = try gif(3)
        let result = try OLEDFrameEncoder.adaptedFrames(at: url)
        XCTAssertEqual(result.sourceFrameCount, 3)
        XCTAssertEqual(result.frames, try OLEDFrameEncoder.frames(fromGIFAt: url))
    }
    func testInvalidImageStillFails() throws {
        let url = try directory().appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: url)
        XCTAssertThrowsError(try OLEDFrameEncoder.adaptedFrames(at: url, maximumFrames: 8))
    }
    func testCancellationStopsBeforeDecoding() async throws {
        let url = try gif(3), gate = DispatchSemaphore(value: 0)
        let task = Task.detached {
            gate.wait()
            return try OLEDFrameEncoder.adaptedFrames(at: url, maximumFrames: 8)
        }
        task.cancel(); gate.signal()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testSamplingBoundsAndExtremeMetadataDoNotOverflow() throws {
        XCTAssertThrowsError(try OLEDFrameEncoder.frameSelection(sourceCount: 0, maximumFrames: 8))
        XCTAssertThrowsError(try OLEDFrameEncoder.frameSelection(sourceCount: 8, maximumFrames: 0))
        XCTAssertThrowsError(try OLEDFrameEncoder.frameSelection(sourceCount: 100, maximumFrames: 71))
        XCTAssertEqual(try OLEDFrameEncoder.frameSelection(sourceCount: 100, maximumFrames: 1), [0])
        XCTAssertEqual(try OLEDFrameEncoder.frameSelection(sourceCount: 3, maximumFrames: 8), [0, 1, 2])
        let indices = try OLEDFrameEncoder.frameSelection(sourceCount: Int.max, maximumFrames: 70)
        XCTAssertEqual(indices.first, 0); XCTAssertEqual(indices.last, Int.max - 1)
        XCTAssertEqual(Set(indices).count, 70); XCTAssertEqual(indices, indices.sorted())
    }
    func testPhotoOrientationIsAppliedBeforeFittingTheScreen() throws {
        let url = try directory().appendingPathComponent("portrait.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 80, bitsPerComponent: 8, bytesPerRow: 640,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try OLEDFrameEncoder.adaptedFrames(at: url, maximumFrames: 8)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.previewPNG as CFData, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThan(preview.width, preview.height)
        XCTAssertEqual(result.frames[0].prefix(2), Data([0, 0])) // portrait image has black side bars
        XCTAssertTrue(result.wasResized)
    }
}
