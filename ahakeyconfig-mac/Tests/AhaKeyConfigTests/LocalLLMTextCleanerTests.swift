import Foundation
import XCTest
@testable import AhaKeyConfig

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
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

private extension URLRequest {
    var httpBodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}

final class LocalLLMTextCleanerTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        suiteName = "LocalLLMTextCleanerTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() async throws {
        MockURLProtocol.requestHandler = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        UserDefaults.standard.removeObject(forKey: LocalLLMTextCleaner.Keys.mode)
        UserDefaults.standard.removeObject(forKey: LocalLLMTextCleaner.Keys.baseURL)
        UserDefaults.standard.removeObject(forKey: LocalLLMTextCleaner.Keys.model)
        UserDefaults.standard.removeObject(forKey: LocalLLMTextCleaner.Keys.apiKey)
        await MainActor.run {
            AhaTypeTextOptimizer.shared.localCleaner = .shared
            AhaTypeTextOptimizer.shared.refreshFromDisk()
        }
        try await super.tearDown()
    }

    // MARK: - Routing Tests

    func testRoutingLocalModeUsesLocalEndpointAndNotAhaType() async {
        // WHY: When cleanup.mode is 'local', speech text optimization must route directly
        // to the local LLM endpoint without invoking cloud AhaType token checks or cloud network endpoints.
        testDefaults.set("local", forKey: LocalLLMTextCleaner.Keys.mode)
        testDefaults.set("http://127.0.0.1:11434", forKey: LocalLLMTextCleaner.Keys.baseURL)

        var requestedURL: URL?
        MockURLProtocol.requestHandler = { request in
            requestedURL = request.url
            let json = """
            {
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": "整理后的本地文本。"
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }

        let cleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)
        let optimizer = await AhaTypeTextOptimizer.shared
        await MainActor.run {
            optimizer.localCleaner = cleaner
        }

        let result = await optimizer.processIfEnabled("未整理的原始文本")
        XCTAssertEqual(result.text, "整理后的本地文本。")
        XCTAssertNil(result.failureReason)
        XCTAssertEqual(requestedURL?.path, "/v1/chat/completions")
    }

    func testRoutingDefaultOrAhatypePreservesCloudPath() async {
        // WHY: Unset or 'ahatype' cleanup.mode must maintain 100% backward compatibility
        // with the existing cloud AhaType flow (which checks cloud token/expiry/config).
        testDefaults.removeObject(forKey: LocalLLMTextCleaner.Keys.mode)
        XCTAssertEqual(LocalLLMTextCleaner.currentMode(userDefaults: testDefaults), .ahatype)

        testDefaults.set("ahatype", forKey: LocalLLMTextCleaner.Keys.mode)
        XCTAssertEqual(LocalLLMTextCleaner.currentMode(userDefaults: testDefaults), .ahatype)
    }

    func testRoutingLegacyOffModeSafelyDefaultsToAhaType() async {
        // WHY: If user previously had 'off' stored in UserDefaults, it must safely fall back
        // to .ahatype mode without crashing or entering an undefined state.
        testDefaults.set("off", forKey: LocalLLMTextCleaner.Keys.mode)
        XCTAssertEqual(LocalLLMTextCleaner.currentMode(userDefaults: testDefaults), .ahatype)
    }

    func testAhaTypeIsEnabledStaysTiedToTypelessEnabledInLocalMode() async {
        // WHY: AhaType UI toggles and badges in Studio (e.g. "AhaType 开启/云端整理已启用", diagnostics,
        // and cloud account section) bind directly to AhaTypeTextOptimizer.isEnabled. In local mode,
        // isEnabled must NOT be forced to true, keeping existing cloud UI toggles truthful.
        let optimizer = await AhaTypeTextOptimizer.shared

        testDefaults.set("local", forKey: LocalLLMTextCleaner.Keys.mode)
        let cleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)

        await MainActor.run {
            optimizer.localCleaner = cleaner
            optimizer.setEnabled(false)
            XCTAssertFalse(optimizer.isEnabled, "AhaType 的 isEnabled 必须如实反映 typeless_enabled 为 false")

            optimizer.setEnabled(true)
            XCTAssertTrue(optimizer.isEnabled, "AhaType 的 isEnabled 必须如实反映 typeless_enabled 为 true")
        }
    }

    func testIsCleanupEnabledIsTrueInLocalModeEvenWhenAhaTypeDisabled() async {
        // WHY: Per-press toggles and speech transcription finalize pipeline check isCleanupEnabled.
        // In local mode, cleanup is active regardless of whether cloud AhaType is enabled or logged in.
        let optimizer = await AhaTypeTextOptimizer.shared

        testDefaults.set("local", forKey: LocalLLMTextCleaner.Keys.mode)
        let localCleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)

        await MainActor.run {
            optimizer.localCleaner = localCleaner
            optimizer.setEnabled(false)
            XCTAssertFalse(optimizer.isEnabled, "AhaType 自身未开启")
            XCTAssertTrue(optimizer.isCleanupEnabled, "本地整理模式下 isCleanupEnabled 必须为 true")
            XCTAssertEqual(optimizer.activeCleanupDisplayName, "本地整理")
        }

        testDefaults.set("ahatype", forKey: LocalLLMTextCleaner.Keys.mode)
        let ahatypeCleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)

        await MainActor.run {
            optimizer.localCleaner = ahatypeCleaner
            optimizer.setEnabled(false)
            XCTAssertFalse(optimizer.isCleanupEnabled, "AhaType 模式下未开启时 isCleanupEnabled 应为 false")
            XCTAssertEqual(optimizer.activeCleanupDisplayName, "AhaType")

            optimizer.setEnabled(true)
            optimizer.patchCloudToken("test-token-for-cleanup-check")
            XCTAssertTrue(optimizer.isCleanupEnabled, "AhaType 模式下开启且有 token 时 isCleanupEnabled 为 true")

            optimizer.patchCloudToken("")
            XCTAssertFalse(optimizer.isCleanupEnabled, "AhaType 模式下开启但未登录（无 token）时 isCleanupEnabled 应为 false，避免每次录音结束弹出未整理警告")
        }
    }

    // MARK: - Server Fallback & Error Handling Tests

    func testFallbackToRawWhenServerDownOrCannotConnect() async {
        // WHY: Speech transcription must never lose user speech. If local Ollama/server
        // is down or connection is refused, return the raw transcript without crashing.
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        let cleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)
        let rawInput = "服务器未启动时的原始语音"
        let output = await cleaner.clean(rawInput)
        XCTAssertEqual(output, rawInput)

        let detailed = await cleaner.cleanResult(rawInput)
        XCTAssertEqual(detailed.text, rawInput)
        XCTAssertNotNil(detailed.failureReason)
    }

    func testFallbackToRawWhenServerReturnsHTTP500() async {
        // WHY: If local LLM throws an internal server error (e.g. out of VRAM / OOM),
        // cleaner must gracefully degrade to raw transcript rather than returning an error string.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            let errorJson = #"{"error":"Internal CUDA out of memory"}"#
            return (response, errorJson.data(using: .utf8)!)
        }

        let cleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)
        let rawInput = "模型显存不足时的文本"
        let output = await cleaner.clean(rawInput)
        XCTAssertEqual(output, rawInput)

        let detailed = await cleaner.cleanResult(rawInput)
        XCTAssertEqual(detailed.text, rawInput)
        XCTAssertTrue(detailed.failureReason?.contains("500") == true)
    }

    func testFallbackToRawWhenRequestTimesOut() async {
        // WHY: Voice dictation requires prompt typing feedback; if local inference hangs,
        // it must time out quickly and return raw text without stalling the user.
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        // Inject a short timeout (0.1s) for the test
        let cleaner = LocalLLMTextCleaner(
            session: session,
            userDefaults: testDefaults,
            timeoutInterval: 0.1
        )
        let rawInput = "推理超时测试语音"
        let output = await cleaner.clean(rawInput)
        XCTAssertEqual(output, rawInput)

        let detailed = await cleaner.cleanResult(rawInput)
        XCTAssertEqual(detailed.text, rawInput)
        XCTAssertTrue(detailed.failureReason?.contains("超时") == true)
    }

    func testFallbackToRawWhenResponseIsMalformedOrMissingContent() async {
        // WHY: Unexpected response bodies or malformed JSON from third-party proxies
        // must not crash the app or produce empty text.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let badJson = #"{"something_unexpected": 123}"#
            return (response, badJson.data(using: .utf8)!)
        }

        let cleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)
        let rawInput = "解析异常保留原文"
        let output = await cleaner.clean(rawInput)
        XCTAssertEqual(output, rawInput)
    }

    func testFallbackToRawWhenCleanedResultIsEmpty() async {
        // WHY: If model output trims down to empty text (e.g. only produced whitespace or whitespace-only thinking),
        // we must not erase user speech; raw text must be preserved.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": "   <think>everything thought</think>   "
                  }
                }
              ]
            }
            """
            return (response, json.data(using: .utf8)!)
        }

        let cleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)
        let rawInput = "空结果回退测试"
        let output = await cleaner.clean(rawInput)
        XCTAssertEqual(output, rawInput)
    }

    // MARK: - Think Block Stripping Tests

    func testThinkBlockStrippingStandardSingleLine() {
        // WHY: Reasoning models output internal thinking within <think>...</think>;
        // these thoughts must be stripped so only final cleaned text is pasted.
        let input = "<think>思考纠错中</think>今天天气很好。"
        let stripped = LocalLLMTextCleaner.stripThinkBlocks(input)
        XCTAssertEqual(stripped, "今天天气很好。")
    }

    func testThinkBlockStrippingMultilineAndCaseInsensitive() {
        // WHY: Reasoning models frequently output multiline chains of thought with indentation
        // and may use mixed casing in tags (<Think>...</think>). All must be stripped.
        let input = """
        <Think>
        1. 识别口语“那个”
        2. 删除语气助词
        3. 整理标点符号
        </Think>
        我们下午两点开会。
        """
        let stripped = LocalLLMTextCleaner.stripThinkBlocks(input)
        XCTAssertEqual(stripped, "我们下午两点开会。")
    }

    func testThinkBlockStrippingUnclosedTruncatedBlock() {
        // WHY: If the model response hit token limit and was cut off inside <think>,
        // the unclosed thinking tag and thoughts should be purged, resulting in empty
        // output that cleanly triggers raw transcript fallback.
        let input = "<think>还在继续思考未闭合的推理过程..."
        let stripped = LocalLLMTextCleaner.stripThinkBlocks(input)
        XCTAssertEqual(stripped, "")
    }

    // MARK: - Authorization Header Tests

    func testAuthorizationBearerHeaderIncludedWhenApiKeyNonEmpty() async {
        // WHY: Authenticated OpenAI-compatible proxies (e.g. vLLM or LiteLLM with API token)
        // require an Authorization Bearer header.
        testDefaults.set("secret-key-123", forKey: LocalLLMTextCleaner.Keys.apiKey)

        var capturedAuthHeader: String?
        MockURLProtocol.requestHandler = { request in
            capturedAuthHeader = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#
            return (response, json.data(using: .utf8)!)
        }

        let cleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)
        _ = await cleaner.clean("测试文本")

        XCTAssertEqual(capturedAuthHeader, "Bearer secret-key-123")
    }

    func testAuthorizationHeaderOmittedWhenApiKeyEmpty() async {
        // WHY: Local Ollama / llama.cpp servers do not use authentication, and extraneous
        // empty Bearer headers can cause 401 or rejection on some reverse proxies.
        testDefaults.removeObject(forKey: LocalLLMTextCleaner.Keys.apiKey)

        var capturedAuthHeader: String?
        MockURLProtocol.requestHandler = { request in
            capturedAuthHeader = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#
            return (response, json.data(using: .utf8)!)
        }

        let cleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)
        _ = await cleaner.clean("测试文本")

        XCTAssertNil(capturedAuthHeader)
    }

    // MARK: - Payload Structure Tests

    func testChatCompletionsPayloadStructureMatchesOpenAISpec() async throws {
        // WHY: Local inference engines adhere to the OpenAI chat completions schema.
        // The payload must contain model, messages (with system prompt and user text),
        // stream=false, and temperature.
        testDefaults.set("custom-qwen-model", forKey: LocalLLMTextCleaner.Keys.model)

        var capturedBodyData: Data?
        MockURLProtocol.requestHandler = { request in
            capturedBodyData = request.httpBodyData
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"choices":[{"message":{"role":"assistant","content":"整理后的结果"}}]}"#
            return (response, json.data(using: .utf8)!)
        }

        let cleaner = LocalLLMTextCleaner(session: session, userDefaults: testDefaults)
        _ = await cleaner.clean("用户说话的原始文本")

        let bodyData = try XCTUnwrap(capturedBodyData)
        let bodyJson = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        XCTAssertEqual(bodyJson["model"] as? String, "custom-qwen-model")
        XCTAssertEqual(bodyJson["stream"] as? Bool, false)
        XCTAssertEqual(bodyJson["temperature"] as? Double, 0.1)
        let templateKwargs = try XCTUnwrap(bodyJson["chat_template_kwargs"] as? [String: Any])
        XCTAssertEqual(templateKwargs["enable_thinking"] as? Bool, false)

        let messages = try XCTUnwrap(bodyJson["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, LocalLLMTextCleaner.defaultSystemPrompt)
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "用户说话的原始文本")
    }

    // MARK: - URL Endpoint Resolution Tests

    func testResolveEndpointURLNormalization() {
        // WHY: Users might enter base URLs with or without trailing slashes, scheme, or /v1 path.
        // All forms must normalize to a valid /v1/chat/completions endpoint URL.
        XCTAssertEqual(
            LocalLLMTextCleaner.resolveEndpointURL(baseURL: "http://localhost:11434")?.absoluteString,
            "http://localhost:11434/v1/chat/completions"
        )
        XCTAssertEqual(
            LocalLLMTextCleaner.resolveEndpointURL(baseURL: "http://localhost:11434/")?.absoluteString,
            "http://localhost:11434/v1/chat/completions"
        )
        XCTAssertEqual(
            LocalLLMTextCleaner.resolveEndpointURL(baseURL: "http://localhost:11434/v1")?.absoluteString,
            "http://localhost:11434/v1/chat/completions"
        )
        XCTAssertEqual(
            LocalLLMTextCleaner.resolveEndpointURL(baseURL: "http://localhost:11434/v1/chat/completions")?.absoluteString,
            "http://localhost:11434/v1/chat/completions"
        )
        XCTAssertEqual(
            LocalLLMTextCleaner.resolveEndpointURL(baseURL: "localhost:11434")?.absoluteString,
            "http://localhost:11434/v1/chat/completions"
        )
        XCTAssertEqual(
            LocalLLMTextCleaner.resolveEndpointURL(baseURL: "")?.absoluteString,
            "http://localhost:11434/v1/chat/completions"
        )
    }
}
