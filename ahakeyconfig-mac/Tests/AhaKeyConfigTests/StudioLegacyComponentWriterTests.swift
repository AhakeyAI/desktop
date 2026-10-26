import XCTest
@testable import AhaKeyConfig

@MainActor
final class StudioLegacyComponentWriterTests: XCTestCase {
    private func session(current: @escaping () -> Bool = { true }, release: @escaping () -> Void = {}) -> StudioInspectorSession {
        .init(access: .init(begin: { 1 }, isCurrent: { _ in current() }, isReady: { true }, generation: { 7 },
            deviceID: { "A" }, release: { _ in release() }, pause: {}))
    }
    private func plan() throws -> StudioLegacyComponentPlan {
        try .init(mode: .mode0, part: .key2, submitted: .default(for: .mode0), deviceID: "A")
    }
    func testKeyWriteUsesOnlyCapturedPlanAndReturnsLeaseWithoutLightProbe() async throws {
        let plan = try plan()
        var commands: [Data] = [], releases = 0
        _ = try await StudioLegacyComponentWriter.run(plan: plan, userConfirmed: true,
            session: session(release: { releases += 1 }),
            verifyLegacy: { true }, checkHost: {}, verifyLighting: { XCTFail("key cannot write brightness") },
            upload: { XCTFail("key cannot upload"); return .init(localAssetPath: nil, statusLine: "") },
            write: { commands.append($0) }, writeStarted: {})
        XCTAssertEqual(commands, plan.commands.map(\.data)); XCTAssertEqual(releases, 1)
    }
    func testWrongFirmwareNeverMutatesAndReleasesConnection() async throws {
        var writes = 0, releases = 0
        do {
            _ = try await StudioLegacyComponentWriter.run(plan: plan(), userConfirmed: true,
                session: session(release: { releases += 1 }), verifyLegacy: { false }, checkHost: {},
                verifyLighting: { writes += 1 }, upload: { writes += 1; return .init(localAssetPath: nil, statusLine: "") },
                write: { _ in writes += 1 }, writeStarted: { writes += 1 })
            XCTFail("unsupported profile")
        } catch {}
        XCTAssertEqual(writes, 0); XCTAssertEqual(releases, 1)
    }
    func testConnectionChangeAfterFirstAckStopsRemainingCommands() async throws {
        var current = true, writes = 0
        do {
            _ = try await StudioLegacyComponentWriter.run(plan: plan(), userConfirmed: true,
                session: session(current: { current }), verifyLegacy: { true }, checkHost: {},
                verifyLighting: { XCTFail() }, upload: { XCTFail(); return .init(localAssetPath: nil, statusLine: "") },
                write: { _ in writes += 1; current = false }, writeStarted: {})
            XCTFail("ownership changed")
        } catch {}
        XCTAssertEqual(writes, 1)
    }
    func testCancellationStopsTheSaveCommandAndReleasesLease() async throws {
        var writes = 0, releases = 0
        do {
            _ = try await StudioLegacyComponentWriter.run(plan: plan(), userConfirmed: true,
                session: session(release: { releases += 1 }), verifyLegacy: { true }, checkHost: {},
                verifyLighting: { XCTFail() }, upload: { XCTFail(); return .init(localAssetPath: nil, statusLine: "") },
                write: { _ in writes += 1; throw CancellationError() }, writeStarted: {})
            XCTFail("cancelled write")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(writes, 1); XCTAssertEqual(releases, 1)
    }
    func testNoConfirmationDoesNotAcquireOrProbe() async throws {
        var probes = 0
        do {
            _ = try await StudioLegacyComponentWriter.run(plan: plan(), userConfirmed: false,
                session: session(), verifyLegacy: { probes += 1; return true }, checkHost: {},
                verifyLighting: { XCTFail() }, upload: { XCTFail(); return .init(localAssetPath: nil, statusLine: "") },
                write: { _ in XCTFail() }, writeStarted: { XCTFail() })
            XCTFail("missing consent")
        } catch {}
        XCTAssertEqual(probes, 0)
    }
}
