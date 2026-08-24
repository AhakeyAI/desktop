import XCTest
@testable import AhaKeyConfigShared

// MARK: - Test Fixtures

private final class TestModule: RuntimeModule, @unchecked Sendable {
    let id: RuntimeModuleID
    private(set) var status: RuntimeModuleStatus = .idle
    var shouldFailStart = false
    var shouldFailStop = false
    var startCallCount = 0
    var stopCallCount = 0

    init(id: RuntimeModuleID) {
        self.id = id
    }

    func start() async throws {
        startCallCount += 1
        if shouldFailStart {
            throw RuntimeModuleError.startFailed(module: id, underlying: "injected-start-failure")
        }
        status = .running
    }

    func stop() async {
        stopCallCount += 1
        if shouldFailStop {
            status = .failed(.stopFailed(module: id, underlying: "injected-stop-failure"))
            return
        }
        status = .idle
    }
}

// MARK: - Tests

final class RuntimeModuleRegistryTests: XCTestCase {
    private var registry: RuntimeModuleRegistry!

    override func setUp() async throws {
        registry = RuntimeModuleRegistry()
    }

    override func tearDown() async throws {
        await registry?.stopAll()
        registry = nil
    }

    // MARK: 注册与状态查询

    func testRegisteredModuleDefaultsToIdle() async {
        let module = TestModule(id: .powerProtection)
        await registry.register(module)

        let status = await registry.status(of: .powerProtection)
        XCTAssertEqual(status, .idle)
    }

    func testUnregisteredModuleReturnsIdle() async {
        let status = await registry.status(of: .ahaType)
        XCTAssertEqual(status, .idle)
    }

    // MARK: 正常启动与停止

    func testStartTransitionBringsModuleToRunning() async throws {
        let module = TestModule(id: .dynamicLighting)
        await registry.register(module)

        let transition = RuntimeModuleTransition(
            started: [.dynamicLighting],
            stopped: [],
            residencyChanged: true
        )
        let changed = await registry.applyTransition(transition)

        XCTAssertTrue(changed.contains(.dynamicLighting))
        let status = await registry.status(of: .dynamicLighting)
        XCTAssertEqual(status, .running)
        XCTAssertEqual(module.startCallCount, 1)
    }

    func testStopTransitionBringsModuleToIdle() async throws {
        let module = TestModule(id: .aiIntegration)
        await registry.register(module)

        // 先启动
        _ = await registry.applyTransition(RuntimeModuleTransition(
            started: [.aiIntegration], stopped: [], residencyChanged: true
        ))

        // 再停止
        let transition = RuntimeModuleTransition(
            started: [],
            stopped: [.aiIntegration],
            residencyChanged: false
        )
        let changed = await registry.applyTransition(transition)

        XCTAssertTrue(changed.contains(.aiIntegration))
        let status = await registry.status(of: .aiIntegration)
        XCTAssertEqual(status, .idle)
        XCTAssertEqual(module.stopCallCount, 1)
    }

    // MARK: Transition 驱动多模块并行

    func testParallelStartAndStop() async throws {
        let modA = TestModule(id: .ahaType)
        let modB = TestModule(id: .dynamicLighting)
        await registry.register(modA)
        await registry.register(modB)

        // 先启动两者
        _ = await registry.applyTransition(RuntimeModuleTransition(
            started: [.ahaType, .dynamicLighting], stopped: [], residencyChanged: true
        ))

        // 停 A，启 B（B 已是 running，应保持）
        let transition = RuntimeModuleTransition(
            started: [],
            stopped: [.ahaType],
            residencyChanged: nil
        )
        let changed = await registry.applyTransition(transition)

        XCTAssertTrue(changed.contains(.ahaType))
        let statusA = await registry.status(of: .ahaType)
        let statusB = await registry.status(of: .dynamicLighting)
        XCTAssertEqual(statusA, .idle)
        XCTAssertEqual(statusB, .running)
    }

    // MARK: 错误隔离

    func testSingleModuleStartFailureDoesNotAffectOthers() async {
        let good = TestModule(id: .powerProtection)
        let bad = TestModule(id: .aiIntegration)
        bad.shouldFailStart = true
        await registry.register(good)
        await registry.register(bad)

        let transition = RuntimeModuleTransition(
            started: [.powerProtection, .aiIntegration],
            stopped: [],
            residencyChanged: true
        )
        let changed = await registry.applyTransition(transition)

        XCTAssertTrue(changed.contains(.powerProtection))
        XCTAssertTrue(changed.contains(.aiIntegration))

        let statusGood = await registry.status(of: .powerProtection)
        XCTAssertEqual(statusGood, .running)

        let statusBad = await registry.status(of: .aiIntegration)
        if case .failed(let error) = statusBad {
            if case .startFailed(let module, _) = error {
                XCTAssertEqual(module, .aiIntegration)
            } else {
                XCTFail("Expected startFailed, got \(error)")
            }
        } else {
            XCTFail("Expected .failed status for bad module")
        }
    }

    func testSingleModuleStopFailureDoesNotAffectOthers() async {
        let good = TestModule(id: .dynamicLighting)
        let bad = TestModule(id: .ahaType)
        bad.shouldFailStop = true
        await registry.register(good)
        await registry.register(bad)

        // 先启动两者
        _ = await registry.applyTransition(RuntimeModuleTransition(
            started: [.dynamicLighting, .ahaType], stopped: [], residencyChanged: true
        ))

        let transition = RuntimeModuleTransition(
            started: [],
            stopped: [.dynamicLighting, .ahaType],
            residencyChanged: false
        )
        let changed = await registry.applyTransition(transition)

        XCTAssertTrue(changed.contains(.dynamicLighting))
        XCTAssertTrue(changed.contains(.ahaType))

        let statusGood = await registry.status(of: .dynamicLighting)
        XCTAssertEqual(statusGood, .idle)

        let statusBad = await registry.status(of: .ahaType)
        if case .failed(let error) = statusBad {
            if case .stopFailed(let module, _) = error {
                XCTAssertEqual(module, .ahaType)
            } else {
                XCTFail("Expected stopFailed, got \(error)")
            }
        } else {
            XCTFail("Expected .failed status for bad module")
        }
    }

    // MARK: Snapshot

    func testSnapshotReflectsCurrentStatuses() async {
        let modA = TestModule(id: .powerProtection)
        let modB = TestModule(id: .dynamicLighting)
        await registry.register(modA)
        await registry.register(modB)

        _ = await registry.applyTransition(RuntimeModuleTransition(
            started: [.powerProtection], stopped: [], residencyChanged: true
        ))

        let snap = await registry.snapshot()
        XCTAssertEqual(snap[.powerProtection], .running)
        XCTAssertEqual(snap[.dynamicLighting], .idle)
    }

    // MARK: stopAll

    func testStopAllStopsAllRunningModules() async {
        let modA = TestModule(id: .ahaType)
        let modB = TestModule(id: .aiIntegration)
        await registry.register(modA)
        await registry.register(modB)

        _ = await registry.applyTransition(RuntimeModuleTransition(
            started: [.ahaType, .aiIntegration], stopped: [], residencyChanged: true
        ))

        await registry.stopAll()

        let statusA = await registry.status(of: .ahaType)
        let statusB = await registry.status(of: .aiIntegration)
        XCTAssertEqual(statusA, .idle)
        XCTAssertEqual(statusB, .idle)
        XCTAssertEqual(modA.stopCallCount, 1)
        XCTAssertEqual(modB.stopCallCount, 1)
    }
}
