import CryptoKit
import ImageIO
import XCTest
@testable import AhaKeyConfigShared

/// WBS-5.6 切片 3：事务执行器（WAL 集成、恢复、取消、baseline 原子推进）。
final class AhaKeyConfigurationTransactionRunnerTests: XCTestCase {

    private var root: URL!
    private var store: AhaKeyRuntimePersistentStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-tests-\(UUID().uuidString)")
        store = try! AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyConfigurationPlanner.AcceptanceValidator()
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func capabilities() -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: 2, stateCount: 4,
            flags: 0, maxPacketSize: 200, userSlotLimit: 288, factorySlotBase: 8,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    /// 受理校验以 CAS 实际图片为准：测试资源必须是真实 GIF（128×128×8 帧，与声明一致）。
    private func makeGIFData(width: Int = 128, height: Int = 128, frames: Int = 8) -> Data {
        let buffer = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            buffer, "com.compuserve.gif" as CFString, frames, nil
        )!
        for _ in 0 ..< frames {
            var rgba = [UInt8](repeating: 200, count: width * height * 4)
            let context = CGContext(
                data: &rgba, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        }
        CGImageDestinationFinalize(destination)
        return buffer as Data
    }

    private func resourceFile(_ name: String) -> URL {
        let url = root.appendingPathComponent(name)
        try! makeGIFData().write(to: url)
        return url
    }

    private func makePackage(
        modeCount: Int = 1
    ) throws -> (AhaKeyConfigurationPackage, [AhaKeyResourceIdentifier: URL]) {
        let asset = try AhaKeyDesiredConfiguration.TaskAsset(
            state: .done, resource: AhaKeyResourceIdentifier("img-a"),
            framesPerSecond: 12, pixelWidth: 128, pixelHeight: 128, declaredFrameCount: 8
        )
        let setA = try AhaKeyDesiredConfiguration.TaskSet(assets: [asset])
        let setB = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [setA, setB], activeSet: 0
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try! .init(keyCode: 0x28)), description: "Yes"
        )
        let modes = try (0..<modeCount).map {
            try AhaKeyDesiredConfiguration.Mode(slot: UInt8($0), keys: [key], oled: oled, lightBar: lightBar)
        }
        let desired = try AhaKeyDesiredConfiguration(modes: modes)
        let gifData = makeGIFData()
        let sha = SHA256.hash(data: gifData).map { String(format: "%02x", $0) }.joined()
        let package = try AhaKeyConfigurationPackage(
            targetDeviceID: .init("4F3E"),
            baseRevision: .init(0),
            desiredConfiguration: desired.canonicalData(),
            resources: [try! AhaKeyConfigurationResource(
                logicalIdentifier: "img-a", sha256: sha, byteCount: UInt64(gifData.count), mediaType: "gif"
            )]
        )
        let url = root.appendingPathComponent("img-a.gif")
        try! gifData.write(to: url)
        return (package, [try! AhaKeyResourceIdentifier("img-a"): url])
    }

    // MARK: 通过路径：全步骤成功 → completed + baseline 原子推进

    func testHappyPathCompletesAndAdvancesBaseline() async throws {
        let (package, files) = try makePackage()
        var executed: [String] = []
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package, resourceFiles: files,
            capabilities: capabilities(), protocolMode: .current
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(executed, ["resource:img-a", "base:mode:0"])
        // baseline 原子推进：revision 0→1，内容逐字一致
        let baseline = try await store.syncBaseline(for: package.targetDeviceID)
        XCTAssertEqual(baseline?.revision.rawValue, 1)
        XCTAssertEqual(baseline?.confirmedConfiguration, package.desiredConfiguration)
        // 事务终态落盘
        let finalRecord = try await store.transaction(package.operationID)
        XCTAssertEqual(finalRecord?.state, .completed)
    }

    // MARK: planner 拒绝 → failedWithoutWrites，不动 baseline

    func testPlannerRejectionFailsWithoutWrites() async throws {
        let (package, files) = try makePackage()
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package, resourceFiles: files,
            capabilities: capabilities(), protocolMode: .legacy  // current-only
        ) { _ in .success }
        XCTAssertEqual(state, .failedWithoutWrites)
        let noBaseline = try await store.syncBaseline(for: package.targetDeviceID)
        XCTAssertNil(noBaseline)
        let record = try await store.transaction(package.operationID)
        XCTAssertEqual(record?.messageCode, .configurationPlanRejected)
        XCTAssertNil(record?.failureContext)
    }

    // MARK: 永久失败：有写入 → failedWithPartialCommit

    func testPermanentFailureAfterWriteKeepsPartialCommit() async throws {
        let (package, files) = try makePackage(modeCount: 2)
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package, resourceFiles: files,
            capabilities: capabilities(), protocolMode: .current
        ) { step in
            step.rawValue == "base:mode:1" ? .permanentFailure : .success
        }
        XCTAssertEqual(state, .failedWithPartialCommit)
        let noBaseline = try await store.syncBaseline(for: package.targetDeviceID)
        XCTAssertNil(noBaseline)
        // 已确认步骤保留（恢复对账依据）
        let confirmed = try await store.confirmedSteps(for: package.operationID).map(\.rawValue)
        XCTAssertEqual(confirmed, ["resource:img-a", "base:mode:0"])
        let record = try await store.transaction(package.operationID)
        XCTAssertEqual(record?.failureContext?.failedStepID?.rawValue, "base:mode:1")
        XCTAssertNil(record?.messageCode)
        XCTAssertNil(record?.failureContext?.opcode)
    }

    func testTypedPermanentFailurePersistsOpcodeStatusAndReloads() async throws {
        let (package, files) = try makePackage(modeCount: 2)
        let step = try AhaKeyRuntimeStepIdentifier("base:mode:1")
        let context = AhaKeyRuntimeOperationFailureContext(
            failedStepID: step,
            opcode: 0x97,
            deviceStatus: 3
        )
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package, resourceFiles: files,
            capabilities: capabilities(), protocolMode: .current
        ) { current in
            if current == step {
                return .failure(.init(
                    retryable: false,
                    messageCode: .configurationDeviceRejected,
                    context: context
                ))
            }
            return .success
        }
        XCTAssertEqual(state, .failedWithPartialCommit)
        let first = try await store.transaction(package.operationID)
        XCTAssertEqual(first?.messageCode, .configurationDeviceRejected)
        XCTAssertEqual(first?.failureContext, context)

        let reopened = try AhaKeyRuntimePersistentStore(
            rootDirectory: root,
            acceptanceValidator: AhaKeyConfigurationPlanner.AcceptanceValidator()
        )
        let reloaded = try await reopened.transaction(package.operationID)
        XCTAssertEqual(reloaded?.messageCode, .configurationDeviceRejected)
        XCTAssertEqual(reloaded?.failureContext, context)
        XCTAssertEqual(reloaded?.state, .failedWithPartialCommit)
    }

    // MARK: 可重试失败 → resumablePartial，重跑恢复并完成

    func testRetryableFailureResumesOnRerun() async throws {
        let (package, files) = try makePackage(modeCount: 2)
        var firstRun = true
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        let state1 = try await runner.run(
            package: package, resourceFiles: files,
            capabilities: capabilities(), protocolMode: .current
        ) { step in
            if firstRun && step.rawValue == "base:mode:0" { return .retryableFailure }
            return .success
        }
        XCTAssertEqual(state1, .resumablePartial)
        let paused = try await store.transaction(package.operationID)
        XCTAssertEqual(paused?.failureContext?.failedStepID?.rawValue, "base:mode:0")
        XCTAssertNil(paused?.failureContext?.opcode)

        // 模拟断线后重跑：同 package 幂等 accept，跳过已确认步
        firstRun = false
        var executed: [String] = []
        let state2 = try await runner.run(
            package: package, resourceFiles: files,
            capabilities: capabilities(), protocolMode: .current
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(state2, .completed)
        XCTAssertEqual(executed, ["base:mode:0", "base:mode:1"])  // resource 步未重放
        let completed = try await store.transaction(package.operationID)
        XCTAssertNil(completed?.failureContext)
        XCTAssertNil(completed?.messageCode)
        let resumedBaseline = try await store.syncBaseline(for: package.targetDeviceID)
        XCTAssertEqual(resumedBaseline?.revision.rawValue, 1)
    }

    // MARK: 取消：无写入终态 / 有写入可恢复

    func testCancelWithoutWritesFailsClean() async throws {
        let (package, files) = try makePackage()
        try await store.accept(package, resourceFiles: files)
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        try await runner.requestCancel(operationID: package.operationID)
        let settled = try await runner.settleCancellation(operationID: package.operationID)
        XCTAssertEqual(settled, .failedWithoutWrites)
    }

    func testCancelWithWritesSettlesAtStepBoundary() async throws {
        let (package, files) = try makePackage(modeCount: 2)
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        // 跑一步就取消
        try await store.accept(package, resourceFiles: files)
        try await store.confirmStep(try! .init("resource:img-a"), for: package.operationID)
        try await store.updateOperation(AhaKeyRuntimeOperationSummary(
            id: package.operationID, targetDeviceID: package.targetDeviceID,
            state: .running, completedSteps: 1, totalSteps: 3
        ))
        try await runner.requestCancel(operationID: package.operationID)
        // R3 步间安全点：run 在循环顶部重读取消态并直接结算——
        // 有写入 → resumablePartial，且绝不执行后续步骤
        var executed: [String] = []
        let settled = try await runner.run(
            package: package, resourceFiles: files,
            capabilities: capabilities(), protocolMode: .current
        ) { step in executed.append(step.rawValue); return .success }
        XCTAssertEqual(settled, .resumablePartial)
        XCTAssertTrue(executed.isEmpty, "取消结算后不得再执行任何步骤")
        // 结算幂等：非 cancellationRequested 态返回 nil
        let settledAgain = try await runner.settleCancellation(operationID: package.operationID)
        XCTAssertNil(settledAgain)
        // 显式重跑 = 用户恢复意图：跳过已确认步并完成
        let after = try await runner.run(
            package: package, resourceFiles: files,
            capabilities: capabilities(), protocolMode: .current
        ) { _ in .success }
        XCTAssertEqual(after, .completed)
    }

    // MARK: revision 单调：第二次配置推进到 2

    func testSecondPackageAdvancesRevisionMonotonically() async throws {
        let (package1, files) = try makePackage()
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        _ = try await runner.run(package: package1, resourceFiles: files,
                           capabilities: capabilities(), protocolMode: .current) { _ in .success }
        var package2 = package1
        package2 = try AhaKeyConfigurationPackage(
            operationID: .init(),
            targetDeviceID: package1.targetDeviceID,
            baseRevision: .init(1),
            desiredConfiguration: package1.desiredConfiguration,
            resources: package1.resources
        )
        let state = try await runner.run(package: package2, resourceFiles: files,
                                   capabilities: capabilities(), protocolMode: .current) { _ in .success }
        XCTAssertEqual(state, .completed)
        let secondBaseline = try await store.syncBaseline(for: package1.targetDeviceID)
        XCTAssertEqual(secondBaseline?.revision.rawValue, 2)
    }

    private func makeKeysAndLightPackage() throws -> AhaKeyConfigurationPackage {
        let emptySet = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try .init(state: .idle, resource: nil, framesPerSecond: 12),
            try .init(state: .working, resource: nil, framesPerSecond: 12),
            try .init(state: .waiting, resource: nil, framesPerSecond: 12),
            try .init(state: .done, resource: nil, framesPerSecond: 12),
        ])
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [emptySet, emptySet], activeSet: 0
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try .init(keyCode: 0x28)), description: "Yes"
        )
        let mode = try AhaKeyDesiredConfiguration.Mode(slot: 0, keys: [key], oled: oled, lightBar: lightBar)
        let desired = try AhaKeyDesiredConfiguration(modes: [mode])
        return try AhaKeyConfigurationPackage(
            targetDeviceID: .init("4F3E"),
            baseRevision: .init(0),
            desiredConfiguration: desired.canonicalData(),
            resources: []
        )
    }

    func testV02PicturePackageFailsWithoutWrites() async throws {
        let (package, files) = try makePackage()
        let release = AhaKeyReleaseFeaturePolicy.current.projection(.parsed(capabilities()))
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package, resourceFiles: files,
            capabilities: capabilities(), protocolMode: .current, release: release
        ) { _ in .success }
        XCTAssertEqual(state, .failedWithoutWrites)
        let noBaseline = try await store.syncBaseline(for: package.targetDeviceID)
        XCTAssertNil(noBaseline)
        let record = try await store.transaction(package.operationID)
        XCTAssertEqual(record?.messageCode, .configurationPlanRejected)
    }

    func testV02KeysAndLightPackageRunsBaseOnly() async throws {
        let package = try makeKeysAndLightPackage()
        let release = AhaKeyReleaseFeaturePolicy.current.projection(.parsed(capabilities()))
        var executed: [String] = []
        let state = try await AhaKeyConfigurationTransactionRunner(store: store).run(
            package: package, resourceFiles: [:],
            capabilities: capabilities(), protocolMode: .current, release: release
        ) { step in
            executed.append(step.rawValue)
            return .success
        }
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(executed, ["base:mode:0"])
    }
}
