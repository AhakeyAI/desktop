import CryptoKit
import Foundation
import XCTest
@testable import AhaKeyConfig

// MARK: - Mock URLProtocol for Offline Network Testing

/// 专用于 LocalModelStore 单元测试的模拟 URL 协议，拦截 mock:// 请求以提供受控的 HTTP 响应与载荷
final class LocalModelStoreMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return request.url?.scheme == "mock"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - LocalModelStore Tests

@MainActor
final class LocalModelStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var mockSession: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        // 每个测试用例使用独立的临时目录，避免状态污染
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalModelStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LocalModelStoreMockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        LocalModelStoreMockURLProtocol.requestHandler = nil
    }

    override func tearDown() async throws {
        LocalModelStoreMockURLProtocol.requestHandler = nil
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        try await super.tearDown()
    }

    // MARK: - 辅助方法

    private func computeSHA256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 1. Pins Table Sanity Test

    /// WHY:
    /// 模型静态配置（Pins）是客户端安全与功能基石：
    /// 1. 若模型 ID 存在重复，不同模型目录会发生冲突覆盖导致数据损毁。
    /// 2. 若 SHA256 哈希不是标准的 64 位小写十六进制字符串，校验逻辑将无法工作。
    /// 3. SenseVoice 的 SHA256 和字节数必须与 Rust 端（ahakey-studio-tauri/crates/speech/src/model.rs）严格一致，
    ///    确保 Swift 与 Tauri 两套客户端共享相同的模型缓存与模型版本基线。
    func testPinsTableSanity() {
        let allModels = LocalSpeechModel.allCases
        XCTAssertEqual(allModels.count, 5, "必须提供 5 种支持的模型配置（SenseVoice + Whisper 4种尺寸）")

        // 验证所有 ID 唯一性
        let ids = allModels.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "所有模型的目录 ID 必须全局唯一，避免目录冲突")

        // 验证 SenseVoice 的 pins 必须与 Rust 端完全一致
        let senseVoice = LocalSpeechModel.senseVoice
        XCTAssertEqual(senseVoice.id, "sensevoice-2024-07-17")
        XCTAssertEqual(senseVoice.fileList.count, 2)

        let svModelFile = senseVoice.fileList.first { $0.filename == "model.int8.onnx" }
        XCTAssertNotNil(svModelFile)
        XCTAssertEqual(svModelFile?.expectedBytes, 239_233_841, "SenseVoice 模型大小必须与 Rust MODEL_BYTES 严格一致")
        XCTAssertEqual(svModelFile?.sha256, "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51", "SenseVoice 模型 SHA256 必须与 Rust MODEL_SHA256 严格一致")

        let svTokensFile = senseVoice.fileList.first { $0.filename == "tokens.txt" }
        XCTAssertNotNil(svTokensFile)
        XCTAssertEqual(svTokensFile?.expectedBytes, 315_894, "SenseVoice tokens 大小必须与 Rust TOKENS_BYTES 严格一致")
        XCTAssertEqual(svTokensFile?.sha256, "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc", "SenseVoice tokens SHA256 必须与 Rust TOKENS_SHA256 严格一致")

        // 验证所有模型的 SHA256 格式与正向字节大小
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        for model in allModels {
            XCTAssertFalse(model.displayName.isEmpty)
            XCTAssertFalse(model.fileList.isEmpty)
            XCTAssertGreaterThan(model.totalSize, 0)

            for file in model.fileList {
                XCTAssertEqual(file.sha256.count, 64, "SHA256 必须是 64 位字符: \(file.filename)")
                XCTAssertTrue(file.sha256.unicodeScalars.allSatisfy { hexCharacterSet.contains($0) }, "SHA256 必须由小写 16 进制字符构成: \(file.sha256)")
                XCTAssertGreaterThan(file.expectedBytes, 0, "期望字节大小必须大于 0: \(file.filename)")
                XCTAssertEqual(file.remoteURL.scheme, "https", "下载地址必须使用安全 HTTPS 协议: \(file.remoteURL)")
            }
        }
    }

    // MARK: - 2. Verification Accepts Correct File

    /// WHY:
    /// 当磁盘上已存在大小与 SHA256 均正确匹配的文件时，
    /// 必须确认 isInstalled(model) 快速判定通过，且 verify(model:) 全量校验成功，这是识别器能正常初始化的基本保证。
    func testVerificationAcceptsCorrectFile() throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        let payload = "Antigravity-SenseVoice-ValidModelPayload".data(using: .utf8)!
        let payloadHash = computeSHA256(data: payload)

        let fixtureFile = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/test.bin")!,
            filename: "model.bin",
            expectedBytes: Int64(payload.count),
            sha256: payloadHash
        )
        let model = LocalSpeechModel.testFixture(id: "test-valid", displayName: "Test Valid", files: [fixtureFile])

        let modelDir = store.modelDirectory(for: model)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try payload.write(to: modelDir.appendingPathComponent("model.bin"))

        XCTAssertTrue(store.isInstalled(model), "文件存在且大小吻合时 isInstalled 必须返回 true")
        XCTAssertNoThrow(try store.verify(model: model), "文件大小与 SHA256 均吻合时 verify 必须成功通过")
    }

    // MARK: - 3. Verification Rejects Wrong Size

    /// WHY:
    /// 若网络中断或下载被截断，文件字节数可能不完整。
    /// 系统必须在轻量 isInstalled 阶段与 verify 阶段均能拒绝不正确的大小，防止损坏的文件传递给 C++ 识别器导致崩溃。
    func testVerificationRejectsWrongSize() throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        let shortPayload = "Short".data(using: .utf8)!
        let fixtureFile = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/test.bin")!,
            filename: "model.bin",
            expectedBytes: 100, // 期望 100 字节，实际仅 5 字节
            sha256: "0000000000000000000000000000000000000000000000000000000000000000"
        )
        let model = LocalSpeechModel.testFixture(id: "test-short", displayName: "Test Short", files: [fixtureFile])

        let modelDir = store.modelDirectory(for: model)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try shortPayload.write(to: modelDir.appendingPathComponent("model.bin"))

        XCTAssertFalse(store.isInstalled(model), "文件大小不匹配时 isInstalled 必须直接返回 false")
        XCTAssertThrowsError(try store.verify(model: model), "文件大小不匹配时 verify 必须抛出 sizeMismatch") { error in
            guard case LocalModelStoreError.sizeMismatch(let file, let expected, let actual) = error else {
                XCTFail("预期 sizeMismatch 错误，实际抛出: \(error)")
                return
            }
            XCTAssertEqual(file, "model.bin")
            XCTAssertEqual(expected, 100)
            XCTAssertEqual(actual, Int64(shortPayload.count))
        }
    }

    // MARK: - 4. Verification Rejects Wrong Hash Even If Size Matches

    /// WHY:
    /// 大小匹配但内容被篡改或损坏（例如传输比特反转或恶意载荷注入）时，必须通过 SHA256 校验拦截。
    /// 这是保障本地语音推理安全与模型完整性的核心防线。
    func testVerificationRejectsWrongHashEvenIfSizeMatches() throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        let corruptedPayload = "Antigravity-CorruptedPayload".data(using: .utf8)!
        let differentPayload = "Antigravity-ExpectedOriginal".data(using: .utf8)!
        XCTAssertEqual(corruptedPayload.count, differentPayload.count, "测试载荷大小一致以测试纯哈希校验")

        let expectedHash = computeSHA256(data: differentPayload)

        let fixtureFile = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/test.bin")!,
            filename: "model.bin",
            expectedBytes: Int64(corruptedPayload.count),
            sha256: expectedHash // 期望 expectedHash，实际写入 corruptedPayload
        )
        let model = LocalSpeechModel.testFixture(id: "test-badhash", displayName: "Test Bad Hash", files: [fixtureFile])

        let modelDir = store.modelDirectory(for: model)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try corruptedPayload.write(to: modelDir.appendingPathComponent("model.bin"))

        // isInstalled 仅检查文件存在与大小，故返回 true
        XCTAssertTrue(store.isInstalled(model), "仅快速检查大小时会通过，因大小吻合")

        // 但全量 verify 必须拒绝错误的 SHA256
        XCTAssertThrowsError(try store.verify(model: model), "哈希不匹配时 verify 必须抛出 checksumMismatch") { error in
            guard case LocalModelStoreError.checksumMismatch(let file, let expected, let actual) = error else {
                XCTFail("预期 checksumMismatch 错误，实际抛出: \(error)")
                return
            }
            XCTAssertEqual(file, "model.bin")
            XCTAssertEqual(expected, expectedHash)
            XCTAssertEqual(actual, self.computeSHA256(data: corruptedPayload))
        }
    }

    // MARK: - 5. Failed Download Leaves No Final Directory

    /// WHY:
    /// 原子安装原则：当新模型下载或校验失败（例如 SHA256 校验不通过或大小不符），
    /// 必须彻底清理临时目录 `.partial-<id>`，且绝不能在正式目录 `<root>/<id>` 留下任何半残文件。
    func testFailedDownloadLeavesNoFinalDirectory() async throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        let corruptedData = "BadDownloadDataContent".data(using: .utf8)!
        let fixtureFile = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/corrupt.bin")!,
            filename: "corrupt.bin",
            expectedBytes: Int64(corruptedData.count),
            sha256: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" // 错误哈希
        )
        let model = LocalSpeechModel.testFixture(id: "test-fail-clean", displayName: "Test Fail Clean", files: [fixtureFile])

        LocalModelStoreMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, corruptedData)
        }

        do {
            try await store.download(model)
            XCTFail("哈希不匹配的下载必须抛出错误")
        } catch {
            // 预期抛出错误
        }

        let finalDir = store.modelDirectory(for: model)
        let partialDir = tempDirectory.appendingPathComponent(".partial-\(model.id)", isDirectory: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: finalDir.path), "下载校验失败时绝不能创建最终模型目录")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialDir.path), "下载失败后临时 .partial 目录必须被清理")
        XCTAssertFalse(store.isInstalled(model))

        if case .failed = store.state(for: model) {
            // 状态已更新为 failed，符合预期
        } else {
            XCTFail("下载失败后状态必须为 failed，实际为: \(store.state(for: model))")
        }
    }

    // MARK: - 6. Failed Download Preserves Previously Good Install

    /// WHY:
    /// 安全回退原则：若用户本地已经有一个正常可用已安装的模型，后续触发重新下载或更新如果失败（例如校验和不符或网络中断），
    /// 必须完整保留此前已有的良好安装，不可导致原本可用的语音引擎被毁坏。
    func testFailedDownloadPreservesPreviouslyGoodInstall() async throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        let goodData = "GoodOriginalModelBytes".data(using: .utf8)!
        let goodHash = computeSHA256(data: goodData)

        let fixtureFile = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/preserve.bin")!,
            filename: "model.bin",
            expectedBytes: Int64(goodData.count),
            sha256: goodHash
        )
        let model = LocalSpeechModel.testFixture(id: "test-preserve", displayName: "Test Preserve", files: [fixtureFile])

        // 预置已有正常安装
        let finalDir = store.modelDirectory(for: model)
        try FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
        let goodFile = finalDir.appendingPathComponent("model.bin")
        try goodData.write(to: goodFile)

        XCTAssertTrue(store.isInstalled(model), "预置模型必须是已安装状态")

        // 模拟后续下载返回错误的数据
        let badData = "WrongBadSubsequentDownload".data(using: .utf8)!
        LocalModelStoreMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, badData)
        }

        do {
            try await store.download(model)
            XCTFail("重新下载返回错误数据必须抛出失败")
        } catch {
            // 预期捕获错误
        }

        // 验证原有的正常文件依然安然无恙
        XCTAssertTrue(FileManager.default.fileExists(atPath: goodFile.path), "失败的下载绝不能删除或损坏原有正常安装")
        let currentContents = try Data(contentsOf: goodFile)
        XCTAssertEqual(currentContents, goodData, "原有模型文件内容必须完整保持原样")
        XCTAssertTrue(store.isInstalled(model), "原有安装仍必须被判定为已安装")
    }

    // MARK: - 7. Import From Folder Atomic Success and Integrity

    /// WHY:
    /// 用户在离线或弱网环境下可能从移动硬盘/U盘拷贝模型文件夹。
    /// 导入功能必须对指定文件夹中的所有文件进行严格验证，全部通过后原子移入正式目录，并使路径解析辅助方法生效。
    func testImportFromFolderAtomicSuccessAndIntegrity() async throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        let data1 = "Component1-ValidWeightData".data(using: .utf8)!
        let data2 = "Component2-ValidTokensData".data(using: .utf8)!

        let file1 = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/file1.bin")!,
            filename: "file1.bin",
            expectedBytes: Int64(data1.count),
            sha256: computeSHA256(data: data1)
        )
        let file2 = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/file2.bin")!,
            filename: "file2.bin",
            expectedBytes: Int64(data2.count),
            sha256: computeSHA256(data: data2)
        )
        let model = LocalSpeechModel.testFixture(id: "test-import-ok", displayName: "Test Import OK", files: [file1, file2])

        // 准备用户指定的源文件夹
        let sourceDir = tempDirectory.appendingPathComponent("UserPickedFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try data1.write(to: sourceDir.appendingPathComponent("file1.bin"))
        try data2.write(to: sourceDir.appendingPathComponent("file2.bin"))

        // 执行导入
        try await store.importFromFolder(model, from: sourceDir)

        XCTAssertTrue(store.isInstalled(model), "导入成功后模型必须处于已安装状态")
        XCTAssertEqual(store.state(for: model), .installed)

        let finalDir = store.modelDirectory(for: model)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalDir.appendingPathComponent("file1.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalDir.appendingPathComponent("file2.bin").path))

        // 验证源文件夹未被破坏（应采用复制而不是移动）
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDir.appendingPathComponent("file1.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDir.appendingPathComponent("file2.bin").path))
    }

    // MARK: - 8. Import From Folder Rejects Corrupt Source and Preserves Good Install

    /// WHY:
    /// 若用户选择的文件夹中缺少文件、文件大小错误或 SHA256 损坏，导入必须立即拒绝，
    /// 清理临时目录，且如果原本已有正常模型安装，必须保留原安装不被破坏。
    func testImportFromFolderRejectsCorruptSourceAndPreservesGoodInstall() async throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        let goodData = "GoodOriginalPayloadForImportTest".data(using: .utf8)!
        let fileSpec = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/file.bin")!,
            filename: "file.bin",
            expectedBytes: Int64(goodData.count),
            sha256: computeSHA256(data: goodData)
        )
        let model = LocalSpeechModel.testFixture(id: "test-import-corrupt", displayName: "Test Import Corrupt", files: [fileSpec])

        // 预置已有正常安装
        let finalDir = store.modelDirectory(for: model)
        try FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
        let existingFile = finalDir.appendingPathComponent("file.bin")
        try goodData.write(to: existingFile)

        // 构造被损坏的源文件夹（哈希不匹配）
        let corruptSourceDir = tempDirectory.appendingPathComponent("CorruptedSource", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptSourceDir, withIntermediateDirectories: true)
        let corruptData = "CorruptedOriginalPayloadForTest!".data(using: .utf8)!
        XCTAssertEqual(corruptData.count, goodData.count)
        try corruptData.write(to: corruptSourceDir.appendingPathComponent("file.bin"))

        do {
            try await store.importFromFolder(model, from: corruptSourceDir)
            XCTFail("损坏源文件夹的导入必须抛出异常")
        } catch {
            // 预期抛出异常
        }

        // 验证原安装完好
        XCTAssertTrue(store.isInstalled(model))
        let existingContents = try Data(contentsOf: existingFile)
        XCTAssertEqual(existingContents, goodData, "原有模型内容必须完好无损")

        let partialDir = tempDirectory.appendingPathComponent(".partial-\(model.id)", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialDir.path), "导入失败后临时 .partial 目录必须清理")
    }

    // MARK: - 9. Download Cancellation Cleans Up Partial Directory

    /// WHY:
    /// 用户在界面上点击「取消下载」或任务被 Task.cancel() 取消时，
    /// 必须立即中止网络传输，彻底删除已下载的 .partial 缓存以释放磁盘空间，状态恢复为未安装或已有安装。
    func testDownloadCancellationCleansUpPartialDirectory() async throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        let fixtureFile = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/slow.bin")!,
            filename: "slow.bin",
            expectedBytes: 1000,
            sha256: "0000000000000000000000000000000000000000000000000000000000000000"
        )
        let model = LocalSpeechModel.testFixture(id: "test-cancel", displayName: "Test Cancel", files: [fixtureFile])

        // 模拟一个挂起的异步请求
        LocalModelStoreMockURLProtocol.requestHandler = { _ in
            // 延迟返回，期间触发取消
            Thread.sleep(forTimeInterval: 0.2)
            throw URLError(.cancelled)
        }

        let downloadTask = Task {
            try await store.download(model)
        }

        // 稍微等待下载启动后执行取消
        try await Task.sleep(nanoseconds: 50_000_000)
        store.cancel(model)

        do {
            _ = try await downloadTask.value
            XCTFail("被取消的任务必须抛出 operationCancelled 错误")
        } catch {
            // 预期抛出取消错误
        }

        let partialDir = tempDirectory.appendingPathComponent(".partial-\(model.id)", isDirectory: true)
        let finalDir = store.modelDirectory(for: model)

        XCTAssertFalse(FileManager.default.fileExists(atPath: partialDir.path), "取消后 .partial 临时目录必须被彻底删除")
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalDir.path), "取消后不应存在最终安装目录")
        XCTAssertEqual(store.state(for: model), .notInstalled, "取消后状态必须重置为 notInstalled")
    }

    // MARK: - 10. Delete Removes Model Files and Updates State

    /// WHY:
    /// 模型文件体积较大（数十至数百兆），当用户选择删除模型时，必须彻底清理本地文件并更新状态为 notInstalled，
    /// 防止出现「界面显示已删除但磁盘仍被占用」或「状态依然为已安装」的脱节问题。
    func testDeleteRemovesModelFilesAndUpdatesState() throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        let payload = "ToDeletePayload".data(using: .utf8)!
        let fixtureFile = LocalModelFileSpec(
            remoteURL: URL(string: "mock://model/del.bin")!,
            filename: "del.bin",
            expectedBytes: Int64(payload.count),
            sha256: computeSHA256(data: payload)
        )
        let model = LocalSpeechModel.testFixture(id: "test-delete", displayName: "Test Delete", files: [fixtureFile])

        let finalDir = store.modelDirectory(for: model)
        try FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
        try payload.write(to: finalDir.appendingPathComponent("del.bin"))

        XCTAssertTrue(store.isInstalled(model))

        store.delete(model)

        XCTAssertFalse(FileManager.default.fileExists(atPath: finalDir.path), "删除后模型目录必须从磁盘移除")
        XCTAssertFalse(store.isInstalled(model), "删除后 isInstalled 必须为 false")
        XCTAssertEqual(store.state(for: model), .notInstalled, "删除后状态必须更新为 notInstalled")
    }

    // MARK: - 11. Recognizer Path Accessors Return Correct URLs

    /// WHY:
    /// 本地识别器 LocalRecognizer 初始化强依赖 SenseVoice 的 (model, tokens) 路径
    /// 以及 Whisper 的 (encoder, decoder, tokens) 路径。
    /// 未安装时辅助函数必须返回 nil（防止给 ONNX 传入不存在的路径）；
    /// 安装就绪后必须返回准确指向各文件的本地 URL。
    func testRecognizerPathAccessorsReturnCorrectURLs() throws {
        let store = LocalModelStore(modelsDirectory: tempDirectory, urlSession: mockSession)

        // 1. 未安装时均返回 nil
        XCTAssertNil(store.senseVoicePaths(), "SenseVoice 未安装时 senseVoicePaths() 必须返回 nil")
        XCTAssertNil(store.whisperPaths(for: .whisperBase), "Whisper 未安装时 whisperPaths(for:) 必须返回 nil")

        // 2. 模拟安装 SenseVoice
        let svDir = store.modelDirectory(for: .senseVoice)
        try FileManager.default.createDirectory(at: svDir, withIntermediateDirectories: true)
        for file in LocalSpeechModel.senseVoice.fileList {
            let dummy = Data(count: Int(file.expectedBytes))
            // 快速写入匹配长度的数据以满足 isInstalled 判定
            FileManager.default.createFile(atPath: svDir.appendingPathComponent(file.filename).path, contents: dummy)
        }

        XCTAssertTrue(store.isInstalled(.senseVoice))
        let svPaths = store.senseVoicePaths()
        XCTAssertNotNil(svPaths, "SenseVoice 已安装时 senseVoicePaths() 必须返回非空元组")
        XCTAssertEqual(svPaths?.model.lastPathComponent, "model.int8.onnx")
        XCTAssertEqual(svPaths?.tokens.lastPathComponent, "tokens.txt")

        // 3. 模拟安装 Whisper Base
        let wbDir = store.modelDirectory(for: .whisperBase)
        try FileManager.default.createDirectory(at: wbDir, withIntermediateDirectories: true)
        for file in LocalSpeechModel.whisperBase.fileList {
            let dummy = Data(count: Int(file.expectedBytes))
            FileManager.default.createFile(atPath: wbDir.appendingPathComponent(file.filename).path, contents: dummy)
        }

        XCTAssertTrue(store.isInstalled(.whisperBase))
        let wbPaths = store.whisperPaths(for: .whisperBase)
        XCTAssertNotNil(wbPaths, "Whisper 已安装时 whisperPaths(for:) 必须返回非空元组")
        XCTAssertEqual(wbPaths?.encoder.lastPathComponent, "base-encoder.int8.onnx")
        XCTAssertEqual(wbPaths?.decoder.lastPathComponent, "base-decoder.int8.onnx")
        XCTAssertEqual(wbPaths?.tokens.lastPathComponent, "base-tokens.txt")

    }
}
