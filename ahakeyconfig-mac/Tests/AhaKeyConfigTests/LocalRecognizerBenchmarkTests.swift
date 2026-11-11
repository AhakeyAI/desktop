import XCTest
@testable import AhaKeyConfig

/// 延迟基准：只在 AHAKEY_BENCH=1 时运行，用于决定是否暴露 coreml provider（结果见 PR 描述）。
/// 不做断言：机器差异太大，基准数字不能作为通过/失败门槛。
final class LocalRecognizerBenchmarkTests: XCTestCase {
    func testDecodeLatencyCPUvsCoreML() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AHAKEY_BENCH"] == "1", LocalRecognizer.isEngineAvailable,
              let dir = env["AHAKEY_TEST_MODEL_DIR"], let wav = env["AHAKEY_TEST_ZH_WAV"] else {
            throw XCTSkip("set AHAKEY_BENCH=1 AHAKEY_TEST_MODEL_DIR AHAKEY_TEST_ZH_WAV")
        }
        let modelDir = URL(fileURLWithPath: dir)
        let samples = try LocalRecognizerKnownAnswerTests.readMono16k(URL(fileURLWithPath: wav))
        for provider in ["cpu", "coreml"] {
            var loadStart = Date()
            let recognizer = try LocalRecognizer(configuration: .init(
                model: .senseVoice(model: modelDir.appendingPathComponent("model.int8.onnx"),
                                   tokens: modelDir.appendingPathComponent("tokens.txt")),
                provider: provider
            ))
            let load = Date().timeIntervalSince(loadStart)
            var times: [Double] = []
            var text = ""
            for _ in 0..<5 {
                loadStart = Date()
                text = recognizer.transcribe(samples)
                times.append(Date().timeIntervalSince(loadStart))
            }
            print("[Bench] provider=\(provider) load=\(String(format: "%.2f", load))s decodes=\(times.map { String(format: "%.3f", $0) }) text=\(text)")
        }
    }
}
