import XCTest
@testable import AhaKeyConfigShared

final class CodexHookTrustTests: XCTestCase {

    /// 与本机 codex 0.144.1 实跑验证过的向量：写入该 trusted_hash 后，
    /// `codex exec`（不带 --dangerously-bypass-hook-trust）会真正执行 SessionStart hook。
    func testTrustedHashMatchesCodexComputedValue() {
        let command = "/bin/zsh -lc ''\\''/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent'\\'' hook CodexSessionStart'"
        let hash = CodexHookTrust.trustedHash(event: "SessionStart", matcher: "", command: command, timeout: 10)
        XCTAssertEqual(hash, "sha256:f2e49c181cca8d8ffd944c181e7be66aead8c4b2f654c4cba522e673d42e1dd4")
    }

    func testStateKeyUsesSnakeCaseEventLabel() {
        let key = CodexHookTrust.stateKey(configPath: "/Users/x/.codex/config.toml", event: "UserPromptSubmit")
        XCTAssertEqual(key, "/Users/x/.codex/config.toml:user_prompt_submit:0:0")
    }

    func testUnknownEventReturnsNil() {
        XCTAssertNil(CodexHookTrust.trustedHash(event: "Bogus", matcher: "", command: "true", timeout: 10))
        XCTAssertNil(CodexHookTrust.stateKey(configPath: "/tmp/c.toml", event: "Bogus"))
    }

    func testUpsertAppendsAndIsIdempotent() {
        let entries: [(key: String, hash: String)] = [
            ("/Users/x/.codex/config.toml:session_start:0:0", "sha256:aaa"),
            ("/Users/x/.codex/config.toml:stop:0:0", "sha256:bbb"),
        ]
        var config = "model = \"gpt\"\n\n[[hooks.SessionStart]]\nmatcher = \"\"\n"
        let once = CodexHookTrust.upsertTrustEntries(in: config, configPath: "/Users/x/.codex/config.toml", entries: entries)
        XCTAssertTrue(once.contains("[hooks.state.\"/Users/x/.codex/config.toml:session_start:0:0\"]\ntrusted_hash = \"sha256:aaa\""))
        XCTAssertTrue(once.contains("[[hooks.SessionStart]]"))
        // 重复安装先删后写，不产生重复表
        let twice = CodexHookTrust.upsertTrustEntries(in: once, configPath: "/Users/x/.codex/config.toml", entries: entries)
        XCTAssertEqual(twice.components(separatedBy: "hooks.state.").count - 1, 2)
    }

    func testUpsertPreservesForeignTrustEntries() {
        var config = """
        [hooks.state."/proj/.codex/hooks.json:pre_tool_use:0:0"]
        trusted_hash = "sha256:keep"

        [hooks.state."/Users/x/.codex/config.toml:stop:0:0"]
        enabled = false
        trusted_hash = "sha256:stale"
        """
        let result = CodexHookTrust.upsertTrustEntries(
            in: config,
            configPath: "/Users/x/.codex/config.toml",
            entries: [("/Users/x/.codex/config.toml:stop:0:0", "sha256:fresh")]
        )
        XCTAssertTrue(result.contains("sha256:keep"), "项目 hooks.json 的信任条目必须保留")
        XCTAssertFalse(result.contains("sha256:stale"), "同路径旧条目（含 enabled 行）必须整体移除")
        XCTAssertTrue(result.contains("sha256:fresh"))
    }

    func testRemoveTrustEntries() {
        let config = """
        model = "gpt"
        [hooks.state."/Users/x/.codex/config.toml:stop:0:0"]
        trusted_hash = "sha256:aaa"
        [other]
        key = 1
        """
        let result = CodexHookTrust.removeTrustEntries(in: config, configPath: "/Users/x/.codex/config.toml")
        XCTAssertFalse(result.contains("hooks.state"))
        XCTAssertTrue(result.contains("[other]"))
        XCTAssertTrue(result.contains("model = \"gpt\""))
    }
}
