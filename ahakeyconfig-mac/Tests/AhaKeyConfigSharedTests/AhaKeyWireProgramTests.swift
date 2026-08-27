import XCTest
@testable import AhaKeyConfigShared

/// WBS-5.6 切片 5：线协议帧字节级兼容 + 程序执行 seam 测试。
final class AhaKeyWireProgramTests: XCTestCase {

    typealias Builder = AhaKeyWireFrameBuilder

    // MARK: 字节级兼容（对齐 App 侧 AhaKeyCommand 既有格式）

    func testKeyShortcutFrameBytes() {
        // AA BB 73 73 [mode] [key] [hid...] CC DD
        XCTAssertEqual(
            Builder.commandFrame(for: .setKeyShortcut(mode: 2, keyIndex: 1, hidCodes: [0xE3, 0x28])),
            Data([0xAA, 0xBB, 0x73, 0x73, 0x02, 0x01, 0xE3, 0x28, 0xCC, 0xDD])
        )
    }

    func testKeyMacroFrameBytes() {
        XCTAssertEqual(
            Builder.commandFrame(for: .setKeyMacro(mode: 0, keyIndex: 2, pairs: [1, 0x51, 2, 0x51])),
            Data([0xAA, 0xBB, 0x73, 0x74, 0x00, 0x02, 1, 0x51, 2, 0x51, 0xCC, 0xDD])
        )
    }

    func testPrepareWriteLegacyAndSessionBytes() {
        // 0x80: flag(0) len(4096 LE) addr(0x00070000 LE)
        XCTAssertEqual(
            Builder.commandFrame(for: .prepareWrite(sessionID: nil, chunkLength: 4096, address: 0x00070000)),
            Data([0xAA, 0xBB, 0x80, 0x00, 0x00, 0x10, 0x00, 0x00, 0x07, 0x00, 0xCC, 0xDD])
        )
        // 0x9B: session(0x1234 LE) len addr
        XCTAssertEqual(
            Builder.commandFrame(for: .prepareWrite(sessionID: 0x1234, chunkLength: 100, address: 0)),
            Data([0xAA, 0xBB, 0x9B, 0x34, 0x12, 0x64, 0x00, 0, 0, 0, 0, 0xCC, 0xDD])
        )
    }

    func testBindTaskPictureSetBytes() {
        // 0x95 mode set state startIdx(LE) frames(LE) interval(LE)
        XCTAssertEqual(
            Builder.commandFrame(for: .bindTaskPicture(mode: 2, set: 1, state: 3,
                                                       startIndex: 40, frameCount: 12, intervalMs: 100)),
            Data([0xAA, 0xBB, 0x95, 2, 1, 3, 40, 0, 12, 0, 100, 0, 0xCC, 0xDD])
        )
    }

    func testMiscFrames() {
        XCTAssertEqual(Builder.commandFrame(for: .setActiveTaskPictureSet(mode: 0, set: 1)),
                       Data([0xAA, 0xBB, 0x97, 0, 1, 0xCC, 0xDD]))
        XCTAssertEqual(Builder.commandFrame(for: .finishTaskPictureWrite),
                       Data([0xAA, 0xBB, 0x98, 0xCC, 0xDD]))
        XCTAssertEqual(Builder.commandFrame(for: .saveConfig),
                       Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]))
        XCTAssertEqual(Builder.commandFrame(for: .setBrightness(55)),
                       Data([0xAA, 0xBB, 0x85, 55, 0xCC, 0xDD]))
        XCTAssertEqual(Builder.commandFrame(for: .setLightMapping(mode: 1, effects: [0, 4, 0, 0, 0, 0, 0, 0, 0])),
                       Data([0xAA, 0xBB, 0x84, 1, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0xCC, 0xDD]))
        // 数据块无命令帧
        XCTAssertNil(Builder.commandFrame(for: .writeResourceChunk(
            digest: try! .init(String(repeating: "a", count: 64)), offset: 0, length: 10)))
        // 描述非 ASCII 过滤 + 20B 截断
        let frame = Builder.commandFrame(for: .setKeyDescription(mode: 0, keyIndex: 0, text: "Yes确定123"))
        XCTAssertEqual(frame, Data([0xAA, 0xBB, 0x73, 0x75, 0, 0]) + "Yes123".data(using: .ascii)! + Data([0xCC, 0xDD]))
    }


    // MARK: 执行 seam

    private final class FakeTransport: AhaKeyDeviceProgramTransport, @unchecked Sendable {
        var commands: [Data] = []
        var chunks: [(Int, Int, UInt16?)] = []
        var cancelled = false
        var failAtCommand: Int? = nil
        var abortCalls = 0

        func sendCommand(_ frame: Data, expectingAck ack: UInt8) async throws {
            if let failAt = failAtCommand, commands.count == failAt {
                throw AhaKeyDeviceProgramExecutionError.cancelled
            }
            commands.append(frame)
        }
        func writeChunk(digest: AhaKeySHA256Digest, offset: Int, length: Int, sessionID: UInt16?) async throws {
            chunks.append((offset, length, sessionID))
        }
        func isCancellationRequested() async -> Bool { cancelled }
        func abortActiveSession() async { abortCalls += 1 }
    }

    func testExecutorRoutesCommandsAndChunks() async throws {
        let d = try AhaKeySHA256Digest(String(repeating: "a", count: 64))
        let program: [AhaKeyDeviceProgramStep] = [
            .prepareWrite(sessionID: 7, chunkLength: 100, address: 0x1000),
            .writeResourceChunk(digest: d, offset: 0, length: 100),
            .saveConfig,
        ]
        let transport = FakeTransport()
        try await AhaKeyDeviceProgramExecutor.execute(program, over: transport)
        XCTAssertEqual(transport.commands.count, 2)
        XCTAssertEqual(transport.commands[0][2], 0x9B)
        XCTAssertEqual(transport.commands[1][2], 0x04)
        XCTAssertEqual(transport.chunks.map { "\($0.0):\($0.1)" }, ["0:100"])
        // prepareWrite 的 session 必须传给紧随的数据块（0x81 校验用）
        XCTAssertEqual(transport.chunks[0].2, 7)
        XCTAssertEqual(transport.abortCalls, 0, "成功路径不得触发 0x9A 回滚")
    }

    func testExecutorStopsAtCancellationCheckpoint() async {
        let d = try! AhaKeySHA256Digest(String(repeating: "a", count: 64))
        let transport = FakeTransport()
        transport.cancelled = true
        do {
            try await AhaKeyDeviceProgramExecutor.execute([
                .writeResourceChunk(digest: d, offset: 0, length: 10),
            ], over: transport)
            XCTFail("应抛 cancelled")
        } catch {
            XCTAssertEqual(error as? AhaKeyDeviceProgramExecutionError, .cancelled)
            XCTAssertTrue(transport.chunks.isEmpty)
            XCTAssertEqual(transport.abortCalls, 1, "取消必须补 0x9A 收尾")
        }
    }

    func testExecutorAbortsSessionOnCommandFailure() async {
        let d = try! AhaKeySHA256Digest(String(repeating: "a", count: 64))
        let transport = FakeTransport()
        transport.failAtCommand = 1  // saveConfig 失败
        do {
            try await AhaKeyDeviceProgramExecutor.execute([
                .prepareWrite(sessionID: 9, chunkLength: 10, address: 0),
                .writeResourceChunk(digest: d, offset: 0, length: 10),
                .saveConfig,
            ], over: transport)
            XCTFail("应抛错")
        } catch {
            XCTAssertEqual(transport.abortCalls, 1, "命令失败必须补 0x9A 收尾")
        }
    }
}
