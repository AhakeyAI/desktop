import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AhaKeyConfig

final class OLEDFrameEncoderTests: XCTestCase {
    func testValidPNGEncodesOneFrame() throws {
        let url = try temporaryFile(contents: try solidRedPNG())
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNoThrow(try OLEDFrameEncoder.validateDecodableFrames(at: url))
        let frames = try OLEDFrameEncoder.frames(fromGIFAt: url)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].count, AhaKeyCommand.oledWidth * AhaKeyCommand.oledHeight * 2)
        XCTAssertTrue(frames[0].contains { $0 != 0 })
    }

    func testTruncatedPNGIsRejectedInsteadOfEncodedAsBlackFrame() throws {
        let png = try solidRedPNG()
        let url = try temporaryFile(contents: png.prefix(png.count / 2))
        defer { try? FileManager.default.removeItem(at: url) }

        assertUndecodable(try OLEDFrameEncoder.validateDecodableFrames(at: url))
        assertUndecodable(try OLEDFrameEncoder.frames(fromGIFAt: url))
    }

    func testPNGWithCorruptedImageDataIsRejected() throws {
        var png = try solidRedPNG()
        // 保留签名、IHDR 与末尾 IEND，只破坏中间的 IDAT 压缩数据。
        for index in stride(from: png.count / 2, to: png.count - 12, by: 2) {
            png[index] ^= 0x5A
        }
        let url = try temporaryFile(contents: png)
        defer { try? FileManager.default.removeItem(at: url) }

        assertUndecodable(try OLEDFrameEncoder.validateDecodableFrames(at: url))
        assertUndecodable(try OLEDFrameEncoder.frames(fromGIFAt: url))
    }

    func testBundledAnimatedGIFDecodesEveryFrame() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/DefaultOLED/claude_0.gif")

        XCTAssertGreaterThan(OLEDFrameEncoder.frameCount(at: url), 1)
        XCTAssertNoThrow(try OLEDFrameEncoder.validateDecodableFrames(at: url))
    }

    private func assertUndecodable<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case .undecodableFrame(index: 0) = error as? OLEDFrameEncodingError else {
                return XCTFail("unexpected error: \(error)", file: file, line: line)
            }
        }
    }

    private func solidRedPNG() throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 64,
            height: 32,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let image = try XCTUnwrap(context.makeImage())

        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func temporaryFile(contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oled-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try contents.write(to: url)
        return url
    }
}
