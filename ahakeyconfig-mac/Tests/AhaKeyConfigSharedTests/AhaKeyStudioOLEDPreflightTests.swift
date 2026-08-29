import CoreGraphics
import CryptoKit
import ImageIO
import XCTest
@testable import AhaKeyConfigShared

/// E-1：受理前 160×80 / 每素材固定 framesPerSlot 抽帧预检 + 当前模式 scoped apply。
final class AhaKeyStudioOLEDPreflightTests: XCTestCase {

    private final class FakeTransport: AhaKeyStudioRuntimeTransport, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requestLog: [String] = []
        private(set) var ingestedItems: [AhaKeyXPCResourceIngestionItem] = []
        private(set) var appliedPackage: AhaKeyConfigurationPackage?
        var ingestResponse: AhaKeyRuntimeXPCResponse?
        var applyResponse: AhaKeyRuntimeXPCResponse?

        func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
            lock.lock()
            defer { lock.unlock() }
            switch request {
            case .ingestResources(let items):
                requestLog.append("ingest(\(items.count))")
                ingestedItems = items
                return ingestResponse ?? .resourcesIngested
            case .apply(let package):
                requestLog.append("apply")
                appliedPackage = package
                return applyResponse ?? .operationAccepted(package.operationID)
            default:
                return .failure(try! AhaKeyRuntimeEventCode("unsupported"))
            }
        }
    }

    private final class RecordingLoader: AhaKeyStudioResourceLoader, @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        let inner = AhaKeyStudioGIFResourceLoader()

        var accessedPaths: [String] {
            lock.lock(); defer { lock.unlock() }
            return urls.map(\.path)
        }

        func load(from url: URL) throws -> AhaKeyStudioLoadedResource {
            lock.lock(); urls.append(url); lock.unlock()
            return try inner.load(from: url)
        }
    }

    private final class RecordingNormalizer: AhaKeyStudioImageNormalizer, @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        let inner = AhaKeyStudioOLEDImageNormalizer()

        var accessedPaths: [String] {
            lock.lock(); defer { lock.unlock() }
            return urls.map(\.path)
        }

        func normalize(
            from url: URL,
            maxFrames: Int,
            maxSourceFileBytes: Int
        ) throws -> AhaKeyStudioNormalizedImage {
            lock.lock(); urls.append(url); lock.unlock()
            return try inner.normalize(
                from: url,
                maxFrames: maxFrames,
                maxSourceFileBytes: maxSourceFileBytes
            )
        }
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ahakey-e1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeGIF(width: Int, height: Int, frames: Int, to url: URL, fill: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.compuserve.gif" as CFString,
            frames,
            nil
        ))
        for index in 0..<frames {
            let context = try XCTUnwrap(CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let mixed = CGFloat((index % 8) + 1) / 9.0
            context.setFillColor(CGColor(
                red: fill.components?[0] ?? mixed,
                green: mixed,
                blue: fill.components?[2] ?? 0,
                alpha: 1
            ))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let image = try XCTUnwrap(context.makeImage())
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func writeJPEG(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.jpeg" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func modeInput(slot: UInt8, url: URL?, frames: Int? = 120, width: Int? = 1024, height: Int? = 576) -> AhaKeyStudioModeInput {
        let empty = AhaKeyStudioTaskSetInput(assets: [
            AhaKeyStudioTaskAssetInput(state: .idle, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .working, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .waiting, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .done, framesPerSecond: 12),
        ])
        var setA = empty
        if let url {
            setA.assets[3] = AhaKeyStudioTaskAssetInput(
                state: .done,
                localFileURL: url,
                framesPerSecond: 12,
                declaredFrameCount: frames,
                pixelWidth: width,
                pixelHeight: height
            )
        }
        return AhaKeyStudioModeInput(
            slot: slot,
            keys: [
                AhaKeyStudioKeyInput(
                    role: .approve,
                    action: .shortcut(try! .init(modifiers: [], keyCode: 0x28)),
                    description: "Accept"
                ),
            ],
            oled: AhaKeyStudioOLEDInput(
                statusLine: "s", framesPerSecond: 12, taskSets: [setA, empty], activeSet: 0
            ),
            lightBar: AhaKeyStudioLightBarInput(
                stateMappings: [AhaKeyStudioLightMappingInput(state: 3, effect: "singleMove")],
                brightness: 35
            )
        )
    }

    func testLargeGIFPreflightIs160x80WithinCapacityAndMatchesAgentReencode() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("claude_0.gif")
        try writeGIF(width: 1024, height: 576, frames: 120, to: source)
        XCTAssertGreaterThan(AhaKeyOLEDFrameEncoderCore.frameCount(at: source), 30)

        let maxFrames = AhaKeyDeviceLayoutPolicy().framesPerSlot
        let transport = FakeTransport()
        let loader = RecordingLoader()
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0,
            resourceLoader: loader
        )
        _ = try await facade.apply(
            modes: [modeInput(slot: 0, url: source)],
            scope: .init(modeSlot: 0),
            targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
            baseRevision: .init(0),
            maxFrames: maxFrames
        )

        let package = try XCTUnwrap(transport.appliedPackage)
        let desired = try AhaKeyDesiredConfiguration.decode(from: package.desiredConfiguration)
        let done = try XCTUnwrap(desired.modes[0].oled.taskSets[0].assets.first { $0.state == .done })
        XCTAssertEqual(done.pixelWidth, 160)
        XCTAssertEqual(done.pixelHeight, 80)
        XCTAssertEqual(done.declaredFrameCount, maxFrames)
        XCTAssertEqual(desired.modes[0].oled.defaultAnimationFrames, maxFrames)

        let ingested = try XCTUnwrap(transport.ingestedItems.first)
        XCTAssertLessThanOrEqual(ingested.byteCount, AhaKeyConfigurationPlanner.Policy.currentDefault.maxAssetBytes)
        let ingestedURL = root.appendingPathComponent("ingested.gif")
        try ingested.data.write(to: ingestedURL)
        XCTAssertEqual(AhaKeyOLEDFrameEncoderCore.frameCount(at: ingestedURL), maxFrames)
        let first = try XCTUnwrap(CGImageSourceCreateWithData(ingested.data as CFData, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(first, 0, nil))
        XCTAssertEqual(preview.width, 160)
        XCTAssertEqual(preview.height, 80)

        let replay = try AhaKeyOLEDFrameEncoderCore.frames(
            fromImageAt: ingestedURL,
            maxFrames: maxFrames,
            maxSourceFileBytes: AhaKeyOLEDFrameEncoderCore.studioMaxSourceFileBytes
        )
        XCTAssertEqual(replay.count, maxFrames)
        XCTAssertEqual(
            replay.count * AhaKeyOLEDFrameEncoderCore.encodedFrameBytes,
            maxFrames * AhaKeyOLEDFrameEncoderCore.encodedFrameBytes
        )
        XCTAssertEqual(AhaKeyOLEDFrameEncoderCore.encodedStream(frames: replay).count, replay.count * 25600)
    }

    func testStaticPNGAndJPEGNormalizeToSingle160x80Frame() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let png = root.appendingPathComponent("still.png")
        let jpeg = root.appendingPathComponent("still.jpg")
        try writePNG(width: 800, height: 400, to: png)
        try writeJPEG(width: 640, height: 480, to: jpeg)

        for (url, slot) in [(png, UInt8(0)), (jpeg, UInt8(1))] {
            let transport = FakeTransport()
            let facade = AhaKeyStudioRuntimeFacade(
                transport: transport,
                clientBuildID: "test",
                reconnectBackoffBase: 0,
                idlePollInterval: 0
            )
            _ = try await facade.apply(
                modes: [modeInput(slot: slot, url: url, frames: 1, width: 800, height: 400)],
                scope: .init(modeSlot: slot),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            let desired = try AhaKeyDesiredConfiguration.decode(
                from: try XCTUnwrap(transport.appliedPackage).desiredConfiguration
            )
            let done = try XCTUnwrap(desired.modes[0].oled.taskSets[0].assets.first { $0.state == .done })
            XCTAssertEqual(done.pixelWidth, 160)
            XCTAssertEqual(done.pixelHeight, 80)
            XCTAssertEqual(done.declaredFrameCount, 1)
            XCTAssertFalse(transport.ingestedItems.isEmpty)
            XCTAssertGreaterThan(transport.ingestedItems[0].byteCount, 0)
            XCTAssertEqual(transport.ingestedItems[0].logicalIdentifier.rawValue, "mode\(slot)-default")
        }
    }

    func testOtherModeUnreadablePathIsNotOpened() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("cursor.gif")
        try writeGIF(width: 160, height: 80, frames: 2, to: current)
        let missing = URL(fileURLWithPath: "/tmp/ahakey-e1-missing-\(UUID().uuidString)/kimi-downloads.gif")

        let transport = FakeTransport()
        let loader = RecordingLoader()
        let normalizer = RecordingNormalizer()
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0,
            resourceLoader: loader,
            imageNormalizer: normalizer
        )
        _ = try await facade.apply(
            modes: [
                modeInput(slot: 1, url: current, frames: 2, width: 160, height: 80),
                modeInput(slot: 0, url: missing, frames: nil, width: nil, height: nil),
            ],
            scope: .init(modeSlot: 1),
            targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
            baseRevision: .init(0)
        )
        XCTAssertFalse(normalizer.accessedPaths.contains(missing.path))
        XCTAssertFalse(loader.accessedPaths.contains(missing.path))
        XCTAssertTrue(normalizer.accessedPaths.contains(current.path))
        let desired = try AhaKeyDesiredConfiguration.decode(
            from: try XCTUnwrap(transport.appliedPackage).desiredConfiguration
        )
        XCTAssertEqual(desired.modes.map(\.slot), [1])
        XCTAssertEqual(Set(desired.referencedResources.map(\.rawValue)), ["mode1-default"])
    }

    func testCurrentModeUnreadableStillFailsClosedWithoutIngest() async throws {
        let missing = URL(fileURLWithPath: "/tmp/ahakey-e1-current-missing-\(UUID().uuidString).gif")
        let transport = FakeTransport()
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        do {
            _ = try await facade.apply(
                modes: [modeInput(slot: 2, url: missing)],
                scope: .init(modeSlot: 2),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("当前模式无效资源必须失败")
        } catch let error as AhaKeyStudioApplyError {
            guard case .encodingFailed = error else {
                return XCTFail("应为 encodingFailed，实际 \(error)")
            }
        }
        XCTAssertTrue(transport.requestLog.isEmpty)
    }

    func testEmptyScopeFailsClosedWithoutIngest() async throws {
        let transport = FakeTransport()
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        do {
            _ = try await facade.apply(
                modes: [modeInput(slot: 0, url: nil)],
                scope: .empty,
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("空范围必须失败")
        } catch let error as AhaKeyStudioApplyError {
            XCTAssertEqual(error, .emptyApplyScope)
        }
        XCTAssertTrue(transport.requestLog.isEmpty)
    }

    func testOversizedSourceFailsBeforeIngest() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("huge.gif")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(AhaKeyOLEDFrameEncoderCore.studioMaxSourceFileBytes + 1))
        try handle.close()

        let transport = FakeTransport()
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        do {
            _ = try await facade.apply(
                modes: [modeInput(slot: 0, url: url)],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("超 20 MiB 必须失败")
        } catch let error as AhaKeyStudioApplyError {
            guard case .sourceFileTooLarge(_, let size, let max) = error else {
                return XCTFail("应为 sourceFileTooLarge，实际 \(error)")
            }
            XCTAssertEqual(size, AhaKeyOLEDFrameEncoderCore.studioMaxSourceFileBytes + 1)
            XCTAssertEqual(max, AhaKeyOLEDFrameEncoderCore.studioMaxSourceFileBytes)
        }
        XCTAssertTrue(transport.requestLog.isEmpty)
    }

    func testSampledIndexesMatchUniformFramesPerSlotFormula() {
        XCTAssertEqual(
            AhaKeyOLEDFrameEncoderCore.sampledFrameIndexes(sourceCount: 120, maxFrames: 30).count,
            30
        )
        XCTAssertEqual(AhaKeyOLEDFrameEncoderCore.sampledFrameIndexes(sourceCount: 120, maxFrames: 30).first, 0)
        XCTAssertEqual(AhaKeyOLEDFrameEncoderCore.sampledFrameIndexes(sourceCount: 120, maxFrames: 30).last, 119)
    }

    func testUnknownSourceSizeUsesBoundedReadAndStillEnforcesLimit() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let small = root.appendingPathComponent("small.png")
        try writePNG(width: 160, height: 80, to: small)
        AhaKeyOLEDFrameEncoderCore.testingSourceByteCountOverride = { _ in nil }
        defer { AhaKeyOLEDFrameEncoderCore.testingSourceByteCountOverride = nil }

        let transport = FakeTransport()
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        _ = try await facade.apply(
            modes: [modeInput(slot: 0, url: small, frames: 1, width: 160, height: 80)],
            scope: .init(modeSlot: 0),
            targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
            baseRevision: .init(0)
        )
        XCTAssertEqual(transport.requestLog, ["ingest(1)", "apply"])

        let huge = root.appendingPathComponent("huge.gif")
        XCTAssertTrue(FileManager.default.createFile(atPath: huge.path, contents: nil))
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(AhaKeyOLEDFrameEncoderCore.studioMaxSourceFileBytes + 1))
        try handle.close()
        let failTransport = FakeTransport()
        let failFacade = AhaKeyStudioRuntimeFacade(
            transport: failTransport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        do {
            _ = try await failFacade.apply(
                modes: [modeInput(slot: 0, url: huge)],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("大小不可得时仍须执行有界读取并拒绝超限源")
        } catch let error as AhaKeyStudioApplyError {
            guard case .sourceFileTooLarge = error else {
                return XCTFail("应为 sourceFileTooLarge，实际 \(error)")
            }
        }
        XCTAssertTrue(failTransport.requestLog.isEmpty)
    }

    func testOwnedTemporaryGIFRemovedOnSuccessAndFailure() async throws {
        let before = normalizedTempGIFPaths()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let png = root.appendingPathComponent("still.png")
        try writePNG(width: 160, height: 80, to: png)

        let okTransport = FakeTransport()
        let okFacade = AhaKeyStudioRuntimeFacade(
            transport: okTransport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        _ = try await okFacade.apply(
            modes: [modeInput(slot: 0, url: png, frames: 1, width: 160, height: 80)],
            scope: .init(modeSlot: 0),
            targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
            baseRevision: .init(0)
        )
        XCTAssertEqual(normalizedTempGIFPaths().subtracting(before), [])

        struct ThrowingLoader: AhaKeyStudioResourceLoader {
            func load(from url: URL) throws -> AhaKeyStudioLoadedResource {
                throw AhaKeyStudioGIFResourceLoader.LoadError.notAnImage
            }
        }
        let failTransport = FakeTransport()
        let failFacade = AhaKeyStudioRuntimeFacade(
            transport: failTransport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0,
            resourceLoader: ThrowingLoader()
        )
        do {
            _ = try await failFacade.apply(
                modes: [modeInput(slot: 0, url: png, frames: 1, width: 160, height: 80)],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("loader 失败必须抛错")
        } catch is AhaKeyStudioApplyError {
        }
        XCTAssertTrue(failTransport.requestLog.isEmpty)
        XCTAssertEqual(normalizedTempGIFPaths().subtracting(before), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "不得删除用户源文件")
    }

    func testOwnedTemporaryGIFRemovedOnEncodeIngestApplyRejectAndCancel() async throws {
        let before = normalizedTempGIFPaths()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let png = root.appendingPathComponent("still.png")
        try writePNG(width: 160, height: 80, to: png)
        let second = root.appendingPathComponent("still-2.png")
        try writePNG(width: 160, height: 80, to: second)

        let bogus = root.appendingPathComponent("not-an-image.txt")
        try Data("not-an-image".utf8).write(to: bogus)
        do {
            _ = try await makeFacade().apply(
                modes: [modeInput(slot: 0, url: bogus, frames: 1, width: 160, height: 80)],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("编码失败必须抛错")
        } catch is AhaKeyStudioApplyError {
        }
        assertNoNewNormalizedTemps(before: before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bogus.path), "不得删除用户源文件")

        let ingestTransport = FakeTransport()
        ingestTransport.ingestResponse = .failure(try AhaKeyRuntimeEventCode("resource.quota"))
        do {
            _ = try await makeFacade(transport: ingestTransport).apply(
                modes: [modeInput(slot: 0, url: png, frames: 1, width: 160, height: 80)],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("ingest 拒绝必须抛错")
        } catch let error as AhaKeyStudioApplyError {
            XCTAssertEqual(error, .ingestRejected(try AhaKeyRuntimeEventCode("resource.quota")))
        }
        XCTAssertEqual(ingestTransport.requestLog, ["ingest(1)"])
        assertNoNewNormalizedTemps(before: before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "不得删除用户源文件")

        let applyTransport = FakeTransport()
        applyTransport.applyResponse = .failure(try AhaKeyRuntimeEventCode("device.busy"))
        do {
            _ = try await makeFacade(transport: applyTransport).apply(
                modes: [modeInput(slot: 0, url: png, frames: 1, width: 160, height: 80)],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("apply 拒绝必须抛错")
        } catch let error as AhaKeyStudioApplyError {
            XCTAssertEqual(error, .applyRejected(try AhaKeyRuntimeEventCode("device.busy")))
        }
        XCTAssertEqual(applyTransport.requestLog, ["ingest(1)", "apply"])
        assertNoNewNormalizedTemps(before: before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "不得删除用户源文件")

        let gate = GateAfterFirstOwnedTempNormalizer()
        let cancelTransport = FakeTransport()
        let cancelFacade = AhaKeyStudioRuntimeFacade(
            transport: cancelTransport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0,
            imageNormalizer: gate
        )
        let applyTask = Task {
            _ = try await cancelFacade.apply(
                modes: [modeInput(slot: 0, urls: [png, second])],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
        }
        XCTAssertEqual(gate.started.wait(timeout: .now() + 2), .success)
        applyTask.cancel()
        gate.release.signal()
        do {
            _ = try await applyTask.value
            XCTFail("取消后必须抛出 CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("应为 CancellationError，实际 \(error)")
        }
        XCTAssertTrue(cancelTransport.requestLog.isEmpty)
        assertNoNewNormalizedTemps(before: before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "不得删除用户源文件")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path), "不得删除用户源文件")
    }

    private final class GateAfterFirstOwnedTempNormalizer: AhaKeyStudioImageNormalizer, @unchecked Sendable {
        let inner = AhaKeyStudioOLEDImageNormalizer()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls = 0

        func normalize(
            from url: URL,
            maxFrames: Int,
            maxSourceFileBytes: Int
        ) throws -> AhaKeyStudioNormalizedImage {
            lock.lock()
            calls += 1
            let call = calls
            lock.unlock()
            if call == 1 {
                return try inner.normalize(
                    from: url,
                    maxFrames: maxFrames,
                    maxSourceFileBytes: maxSourceFileBytes
                )
            }
            started.signal()
            release.wait()
            try Task.checkCancellation()
            return try inner.normalize(
                from: url,
                maxFrames: maxFrames,
                maxSourceFileBytes: maxSourceFileBytes
            )
        }
    }

    private func makeFacade(
        transport: FakeTransport = FakeTransport()
    ) -> AhaKeyStudioRuntimeFacade {
        AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
    }

    private func modeInput(slot: UInt8, urls: [URL]) -> AhaKeyStudioModeInput {
        let empty = AhaKeyStudioTaskSetInput(assets: [
            AhaKeyStudioTaskAssetInput(state: .idle, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .working, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .waiting, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .done, framesPerSecond: 12),
        ])
        var setA = empty
        if let first = urls.first {
            setA.assets[1] = AhaKeyStudioTaskAssetInput(
                state: .working,
                localFileURL: first,
                framesPerSecond: 12,
                declaredFrameCount: 1,
                pixelWidth: 160,
                pixelHeight: 80
            )
        }
        if urls.count > 1 {
            setA.assets[3] = AhaKeyStudioTaskAssetInput(
                state: .done,
                localFileURL: urls[1],
                framesPerSecond: 12,
                declaredFrameCount: 1,
                pixelWidth: 160,
                pixelHeight: 80
            )
        }
        return AhaKeyStudioModeInput(
            slot: slot,
            keys: [
                AhaKeyStudioKeyInput(
                    role: .approve,
                    action: .shortcut(try! .init(modifiers: [], keyCode: 0x28)),
                    description: "Accept"
                ),
            ],
            oled: AhaKeyStudioOLEDInput(
                statusLine: "s", framesPerSecond: 12, taskSets: [setA, empty], activeSet: 0
            ),
            lightBar: AhaKeyStudioLightBarInput(
                stateMappings: [AhaKeyStudioLightMappingInput(state: 3, effect: "singleMove")],
                brightness: 35
            )
        )
    }

    private func assertNoNewNormalizedTemps(before: Set<String>) {
        XCTAssertEqual(normalizedTempGIFPaths().subtracting(before), [])
    }

    private func normalizedTempGIFPaths() -> Set<String> {
        let dir = FileManager.default.temporaryDirectory
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return Set(items.filter { $0.lastPathComponent.hasPrefix("ahakey-oled-normalized-") }.map(\.path))
    }
}
