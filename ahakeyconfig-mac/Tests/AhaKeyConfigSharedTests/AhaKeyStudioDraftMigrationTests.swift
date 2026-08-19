import XCTest
@testable import AhaKeyConfigShared

/// 双 schema 草稿迁移测试。
/// fixture 说明：
/// - draft-legacy-real.json：本机 `defaults read lab.jawa.ahakeyconfig ahakey.studio.draft.v1`
///   导出的真实样本（最老格式：oled 仅 localAssetPath/statusLine/framesPerSecond，无任务图字段）。
/// - draft-mainline.json：主线格式（3 态单套 taskGIFAssets），按主线 encoder 形状构造。
/// - draft-rhino.json：Rhino 格式（4 态双套 taskGIFSets + activeGIFSet + schema 3），
///   按 Rhino encoder 形状构造。
final class AhaKeyStudioDraftMigrationTests: XCTestCase {
    // MARK: - fixture 加载

    private func fixtureData(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        guard let url, let data = try? Data(contentsOf: url) else {
            XCTFail("fixture 缺失：\(name).json")
            return Data()
        }
        return data
    }

    private func jsonDict(_ data: Data, file: StaticString = #filePath, line: UInt = #line) -> [String: Any] {
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            XCTFail("非法 JSON", file: file, line: line)
            return [:]
        }
        return dict
    }

    private func modes(_ dict: [String: Any]) -> [[String: Any]] {
        dict["modes"] as? [[String: Any]] ?? []
    }

    private func oled(of mode: [String: Any]) -> [String: Any] {
        mode["oled"] as? [String: Any] ?? [:]
    }

    private func assets(set: Int, in oled: [String: Any]) -> [[String: Any]] {
        let sets = oled["taskGIFSets"] as? [[String: Any]] ?? []
        guard sets.indices.contains(set) else { return [] }
        return sets[set]["assets"] as? [[String: Any]] ?? []
    }

    private func asset(state: Int, set: Int, in oled: [String: Any]) -> [String: Any]? {
        assets(set: set, in: oled).first { ($0["state"] as? Int) == state }
    }

    // MARK: - 格式判别

    func testDetectFormat() {
        for (name, expected) in [
            ("draft-legacy-real", AhaKeyStudioDraftMigration.OLEDFormat.legacyDefaultOnly),
            ("draft-mainline", .legacySingleSet),
            ("draft-rhino", .dualSet),
        ] as [(String, AhaKeyStudioDraftMigration.OLEDFormat)] {
            for mode in modes(jsonDict(fixtureData(name))) {
                XCTAssertEqual(
                    AhaKeyStudioDraftMigration.detectOLEDFormat(oled(of: mode)), expected,
                    "\(name) mode \(mode["mode"] ?? "?")"
                )
            }
        }
    }

    // MARK: - 真实样本（最老格式）

    func testLegacyRealSampleMigratesWithKeyFieldsIntact() throws {
        let input = fixtureData("draft-legacy-real")
        let migrated = try XCTUnwrap(AhaKeyStudioDraftMigration.migrateDraftData(input))
        let out = modes(jsonDict(migrated))
        let inModes = modes(jsonDict(input))
        XCTAssertEqual(out.count, 4)

        for (index, mode) in out.enumerated() {
            let o = oled(of: mode)
            let inOLED = oled(of: inModes[index])
            // 统一格式字段齐备
            XCTAssertEqual(o["activeGIFSet"] as? Int, 0)
            XCTAssertEqual(o["taskGIFSchemaVersion"] as? Int, 0)
            XCTAssertNil(o["taskGIFAssets"])
            XCTAssertEqual((o["taskGIFSets"] as? [[String: Any]])?.count, 2)
            // 默认动画路径不丢，且种子进套图 A 的 done 槽
            XCTAssertEqual(o["localAssetPath"] as? String, inOLED["localAssetPath"] as? String)
            XCTAssertEqual(asset(state: 3, set: 0, in: o)?["localAssetPath"] as? String, inOLED["localAssetPath"] as? String)
            // 无 working 资源时 idle 为空（不回退），working/waiting 为空
            XCTAssertNil(asset(state: 0, set: 0, in: o)?["localAssetPath"] as? String)
            XCTAssertNil(asset(state: 1, set: 0, in: o)?["localAssetPath"] as? String)
            // 套图 B 全空
            XCTAssertTrue(assets(set: 1, in: o).allSatisfy { $0["localAssetPath"] == nil })
            // 状态行保留
            XCTAssertEqual(o["statusLine"] as? String, inOLED["statusLine"] as? String)
            // 键位与灯效原样保留
            XCTAssertTrue(NSDictionary(dictionary: ["v": mode["keys"] ?? 0]).isEqual(to: ["v": inModes[index]["keys"] ?? 0]), "keys 不一致 mode \(index)")
            XCTAssertTrue(NSDictionary(dictionary: ["v": mode["lightBar"] ?? 0]).isEqual(to: ["v": inModes[index]["lightBar"] ?? 0]), "lightBar 不一致 mode \(index)")
        }
        // 真实样本特征值：mode 0 的语音键 keyCode 109 "Record"、自定义 done 图路径
        let mode0 = out[0]
        let keys = mode0["keys"] as? [[String: Any]] ?? []
        let voice = keys.first { ($0["role"] as? Int) == 0 }
        XCTAssertEqual((voice?["shortcut"] as? [String: Any])?["keyCode"] as? Int, 109)
        XCTAssertEqual(voice?["description"] as? String, "Record")
        XCTAssertEqual(oled(of: mode0)["localAssetPath"] as? String,
                       "/Users/heartline/Documents/Codex/ahakeyconfig-latest-task-gif/6张GIF动图文件/02_7周年键盘-已结束1.gif")
    }

    // MARK: - 主线格式（3 态单套）

    func testMainlineFormatMigratesToDualSet() throws {
        let input = fixtureData("draft-mainline")
        let migrated = try XCTUnwrap(AhaKeyStudioDraftMigration.migrateDraftData(input))
        let out = modes(jsonDict(migrated))
        let inModes = modes(jsonDict(input))

        // mode 0：三态齐全 → 套图 A 三态路径不丢，idle 回退 working（含 fps）
        let o0 = oled(of: out[0])
        XCTAssertEqual(asset(state: 1, set: 0, in: o0)?["localAssetPath"] as? String, "/tmp/mainline/m0-working.gif")
        XCTAssertEqual(asset(state: 2, set: 0, in: o0)?["localAssetPath"] as? String, "/tmp/mainline/m0-waiting.gif")
        XCTAssertEqual(asset(state: 3, set: 0, in: o0)?["localAssetPath"] as? String, "/tmp/mainline/m0-done.gif")
        let idle0 = try XCTUnwrap(asset(state: 0, set: 0, in: o0))
        XCTAssertEqual(idle0["localAssetPath"] as? String, "/tmp/mainline/m0-working.gif")
        XCTAssertEqual(idle0["framesPerSecond"] as? Int, 11)
        XCTAssertEqual(o0["taskGIFSchemaVersion"] as? Int, 0)
        XCTAssertEqual(o0["activeGIFSet"] as? Int, 0)
        XCTAssertNil(o0["taskGIFAssets"])
        // localAssetPath 顶层语义不动
        XCTAssertEqual(o0["localAssetPath"] as? String, "/tmp/mainline/m0-done.gif")
        // 套图 B 为空
        XCTAssertTrue(assets(set: 1, in: o0).allSatisfy { $0["localAssetPath"] == nil })

        // mode 1：waiting 缺失 → 归一化补空槽，working/done 不丢，idle 回退 working
        let o1 = oled(of: out[1])
        XCTAssertEqual(asset(state: 1, set: 0, in: o1)?["localAssetPath"] as? String, "/tmp/mainline/m1-working.gif")
        XCTAssertNil(asset(state: 2, set: 0, in: o1)?["localAssetPath"] as? String)
        XCTAssertEqual(asset(state: 3, set: 0, in: o1)?["localAssetPath"] as? String, "/tmp/mainline/m1-done.gif")
        XCTAssertEqual(asset(state: 0, set: 0, in: o1)?["localAssetPath"] as? String, "/tmp/mainline/m1-working.gif")

        // mode 2/3：无任务图（真实样本里本就没有 taskGIFAssets，同 legacyDefaultOnly 处理）
        XCTAssertEqual(oled(of: out[2])["taskGIFSchemaVersion"] as? Int, 0)

        // 键位 / 灯效不丢
        for (index, mode) in out.enumerated() {
            XCTAssertTrue(NSDictionary(dictionary: ["v": mode["keys"] ?? 0]).isEqual(to: ["v": inModes[index]["keys"] ?? 0]))
            XCTAssertTrue(NSDictionary(dictionary: ["v": mode["lightBar"] ?? 0]).isEqual(to: ["v": inModes[index]["lightBar"] ?? 0]))
        }
    }

    // MARK: - Rhino 格式（4 态双套）

    func testRhinoFormatReadsLosslessly() throws {
        let input = fixtureData("draft-rhino")
        let migrated = try XCTUnwrap(AhaKeyStudioDraftMigration.migrateDraftData(input))
        let out = modes(jsonDict(migrated))
        let inModes = modes(jsonDict(input))

        for (index, mode) in out.enumerated() {
            let o = oled(of: mode)
            let inOLED = oled(of: inModes[index])
            // schema 3 / activeGIFSet 1 保留，不触发 schema<2 去重
            XCTAssertEqual(o["taskGIFSchemaVersion"] as? Int, 3)
            XCTAssertEqual(o["activeGIFSet"] as? Int, 1)
            // 双套 8 个槽位路径与 deviceSchemaVersion 全部保留
            for set in 0 ... 1 {
                for state in 0 ... 3 {
                    let suffix = "\(set == 0 ? "a" : "b")-"
                    let stateName = ["idle", "working", "waiting", "done"][state]
                    XCTAssertEqual(
                        asset(state: state, set: set, in: o)?["localAssetPath"] as? String,
                        "/tmp/rhino/m\(index)-\(suffix)\(stateName).gif",
                        "set\(set) state\(state) mode\(index)"
                    )
                    XCTAssertEqual(asset(state: state, set: set, in: o)?["deviceSchemaVersion"] as? Int, 3)
                }
            }
            XCTAssertEqual(o["localAssetPath"] as? String, inOLED["localAssetPath"] as? String)
            // 键位 / 灯效不丢
            XCTAssertTrue(NSDictionary(dictionary: ["v": mode["keys"] ?? 0]).isEqual(to: ["v": inModes[index]["keys"] ?? 0]))
            XCTAssertTrue(NSDictionary(dictionary: ["v": mode["lightBar"] ?? 0]).isEqual(to: ["v": inModes[index]["lightBar"] ?? 0]))
        }
    }

    // MARK: - schema < 2 套图 B 去重（Rhino 规则）

    func testSchema1DuplicateSetBIsCleared() throws {
        let setAssets: [[String: Any]] = [
            ["state": 0, "framesPerSecond": 12],
            ["state": 1, "localAssetPath": "/tmp/w.gif", "framesPerSecond": 12],
            ["state": 2, "framesPerSecond": 12],
            ["state": 3, "localAssetPath": "/tmp/d.gif", "framesPerSecond": 12],
        ]
        var draft = jsonDict(fixtureData("draft-rhino"))
        var ms = modes(draft)
        var o = oled(of: ms[0])
        o["taskGIFSchemaVersion"] = 1
        o["taskGIFSets"] = [["assets": setAssets], ["assets": setAssets]]
        ms[0]["oled"] = o
        draft["modes"] = ms
        let data = try JSONSerialization.data(withJSONObject: draft)

        let migrated = try XCTUnwrap(AhaKeyStudioDraftMigration.migrateDraftData(data))
        let outOLED = oled(of: modes(jsonDict(migrated))[0])
        // 套图 A 原样，套图 B 被清空
        XCTAssertEqual(asset(state: 1, set: 0, in: outOLED)?["localAssetPath"] as? String, "/tmp/w.gif")
        XCTAssertTrue(assets(set: 1, in: outOLED).allSatisfy { $0["localAssetPath"] == nil })
        XCTAssertEqual(outOLED["taskGIFSchemaVersion"] as? Int, 1)
    }

    func testSchema2DuplicateSetBIsPreserved() throws {
        let setAssets: [[String: Any]] = [
            ["state": 0, "framesPerSecond": 12],
            ["state": 1, "localAssetPath": "/tmp/w.gif", "framesPerSecond": 12],
            ["state": 2, "framesPerSecond": 12],
            ["state": 3, "localAssetPath": "/tmp/d.gif", "framesPerSecond": 12],
        ]
        var draft = jsonDict(fixtureData("draft-rhino"))
        var ms = modes(draft)
        var o = oled(of: ms[0])
        o["taskGIFSchemaVersion"] = 2
        o["taskGIFSets"] = [["assets": setAssets], ["assets": setAssets]]
        ms[0]["oled"] = o
        draft["modes"] = ms
        let data = try JSONSerialization.data(withJSONObject: draft)

        let migrated = try XCTUnwrap(AhaKeyStudioDraftMigration.migrateDraftData(data))
        let outOLED = oled(of: modes(jsonDict(migrated))[0])
        // schema >= 2 时 B==A 视为有意配置，保留
        XCTAssertEqual(asset(state: 1, set: 1, in: outOLED)?["localAssetPath"] as? String, "/tmp/w.gif")
    }

    // MARK: - 幂等 / 异常输入

    func testMigrationIsIdempotent() throws {
        for name in ["draft-legacy-real", "draft-mainline", "draft-rhino"] {
            let once = try XCTUnwrap(AhaKeyStudioDraftMigration.migrateDraftData(fixtureData(name)), name)
            let twice = try XCTUnwrap(AhaKeyStudioDraftMigration.migrateDraftData(once), name)
            XCTAssertEqual(jsonDict(once) as NSDictionary, jsonDict(twice) as NSDictionary, name)
        }
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(AhaKeyStudioDraftMigration.migrateDraftData(Data("not json".utf8)))
        XCTAssertNil(AhaKeyStudioDraftMigration.migrateDraftData(Data("{\"foo\":1}".utf8)))
        XCTAssertNil(AhaKeyStudioDraftMigration.migrateDraftData(Data()))
    }
}
