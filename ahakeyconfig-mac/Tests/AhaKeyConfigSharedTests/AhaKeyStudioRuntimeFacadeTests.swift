import CryptoKit
import XCTest
@testable import AhaKeyConfigShared

/// WBS 5.7 切片 1：Studio Runtime facade 的连接状态机测试。
/// 覆盖：handshake→snapshot 首屏、event cursor 跟随、断档 snapshotRequired→重取快照、
/// 传输错误→offline→重连恢复、stop 语义与视图状态流。
final class AhaKeyStudioRuntimeFacadeTests: XCTestCase {

    /// 可编程假传输：按请求类型返回脚本化响应，支持注入错误与一次性断档。
    private final class FakeTransport: AhaKeyStudioRuntimeTransport, @unchecked Sendable {
        private let lock = NSLock()
        var snapshot: AhaKeyRuntimeSnapshot
        /// 每次 events 请求返回的下一批事件；脚本用完后返回空批。
        var eventBatches: [[AhaKeyRuntimeEvent]] = []
        /// 非 0 时对 events 请求返回断档（每次请求消耗 1）。
        var gapResponsesRemaining = 0
        /// 注入错误：非 nil 时下一次 exchange 抛错（自动消费）。
        var nextError: Error?
        /// 切片 2：ingest/apply/cancel 脚本化响应（nil = 默认成功）。
        var ingestResponse: AhaKeyRuntimeXPCResponse?
        var applyResponse: AhaKeyRuntimeXPCResponse?
        var cancellationDisposition: AhaKeyRuntimeCancellationDisposition = .requested
        private(set) var ingestedItems: [AhaKeyXPCResourceIngestionItem]?
        private(set) var appliedPackage: AhaKeyConfigurationPackage?
        private(set) var cancelledOperation: AhaKeyRuntimeOperationID?
        private(set) var requestLog: [String] = []
        /// 已服务事件推进到的最新序号（snapshot 响应据此重建，模拟 Runtime 权威序号）。
        private var latestSequence: UInt64

        init(snapshot: AhaKeyRuntimeSnapshot) {
            self.snapshot = snapshot
            self.latestSequence = snapshot.latestEventSequence.rawValue
        }

        /// 以当前 latestSequence 重建权威快照（其余字段沿用脚本快照）。
        private func currentSnapshot() -> AhaKeyRuntimeSnapshot {
            AhaKeyRuntimeSnapshot(
                runtimeVersion: snapshot.runtimeVersion,
                interfaceVersion: snapshot.interfaceVersion,
                supportedConfigurationSchemaVersions: snapshot.supportedConfigurationSchemaVersions,
                lifecycleState: snapshot.lifecycleState,
                devices: snapshot.devices,
                activeDeviceID: snapshot.activeDeviceID,
                configurationRevision: snapshot.configurationRevision,
                operations: snapshot.operations,
                policy: snapshot.policy,
                permissions: snapshot.permissions,
                keepAliveReasons: snapshot.keepAliveReasons,
                latestEventSequence: .init(latestSequence)
            )
        }

        func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
            lock.lock()
            defer { lock.unlock() }
            if let error = nextError {
                nextError = nil
                requestLog.append("error")
                throw error
            }
            switch request {
            case .handshake:
                requestLog.append("handshake")
                return .handshakeAccepted(.init(
                    runtimeVersion: .development,
                    interfaceVersion: .current,
                    supportedConfigurationSchemaVersions: [3],
                    capabilities: [.snapshot, .eventReplay, .configuration]
                ))
            case .snapshot:
                requestLog.append("snapshot")
                return .snapshot(currentSnapshot())
            case .events(let after):
                requestLog.append("events(\(after?.rawValue.description ?? "nil"))")
                if gapResponsesRemaining > 0 {
                    gapResponsesRemaining -= 1
                    return .eventReplay(.snapshotRequired(latest: currentSnapshot().latestEventSequence))
                }
                guard !eventBatches.isEmpty else {
                    return .eventReplay(.events([]))
                }
                let batch = eventBatches.removeFirst()
                if let last = batch.last { latestSequence = max(latestSequence, last.sequence.rawValue) }
                return .eventReplay(.events(batch))
            case .ingestResources(let items):
                requestLog.append("ingest(\(items.count))")
                ingestedItems = items
                return ingestResponse ?? .resourcesIngested
            case .apply(let package):
                requestLog.append("apply")
                appliedPackage = package
                return applyResponse ?? .operationAccepted(package.operationID)
            case .requestCancellation(let operationID):
                requestLog.append("cancel(\(operationID.rawValue.uuidString))")
                cancelledOperation = operationID
                return .cancellation(cancellationDisposition)
            default:
                return .failure(try! AhaKeyRuntimeEventCode("unsupported"))
            }
        }
    }

    /// 状态记录器：经 facade 的 publishHookForTesting 同步记录每次发布，
    /// 确定性捕获瞬态（不依赖 AsyncStream 订阅时序）。
    private final class StateRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var states: [AhaKeyStudioRuntimeViewState] = []

        func record(_ state: AhaKeyStudioRuntimeViewState) {
            lock.lock()
            states.append(state)
            lock.unlock()
        }

        func contains(_ predicate: (AhaKeyStudioRuntimeViewState) -> Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return states.contains(where: predicate)
        }
    }

    private func makeSnapshot(sequence: UInt64) -> AhaKeyRuntimeSnapshot {
        AhaKeyRuntimeSnapshot(
            lifecycleState: .running,
            devices: [],
            activeDeviceID: nil,
            configurationRevision: .init(0),
            operations: [],
            policy: .init(),
            permissions: .init(states: [:]),
            keepAliveReasons: [],
            latestEventSequence: .init(sequence)
        )
    }

    private func makeEvent(_ sequence: UInt64) -> AhaKeyRuntimeEvent {
        AhaKeyRuntimeEvent(
            sequence: .init(sequence),
            context: .init(),
            payload: .lifecycleChanged(.running)
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ predicate: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    func testHandshakeThenSnapshotFirstScreen() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0
        )
        await facade.start()
        let online = await waitUntil { await facade.currentState().connection == .online }
        XCTAssertTrue(online)
        let state = await facade.currentState()
        XCTAssertNotNil(state.snapshot)
        XCTAssertEqual(state.eventCursor, .init(0))
        XCTAssertNil(state.lastError)
        XCTAssertEqual(transport.requestLog.first, "handshake")
        XCTAssertEqual(transport.requestLog.dropFirst().first, "snapshot")
        await facade.stop()
    }

    func testEventCursorFollowsMonotonicBatches() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        transport.eventBatches = [[makeEvent(1), makeEvent(2)], [makeEvent(3)]]
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0
        )
        await facade.start()
        let followed = await waitUntil {
            await facade.currentState().eventCursor == AhaKeyRuntimeEventSequence(3)
        }
        XCTAssertTrue(followed)
        let finalState = await facade.currentState()
        XCTAssertEqual(finalState.connection, .online)
        await facade.stop()
    }

    func testNonEmptyEventsRefetchAuthoritativeSnapshotAtomically() async {
        // R1：非空事件批后必须重取权威 snapshot，且 snapshot+cursor 同一次发布。
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        transport.eventBatches = [[makeEvent(1)]]
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0
        )
        await facade.start()
        let followed = await waitUntil {
            await facade.currentState().eventCursor == AhaKeyRuntimeEventSequence(1)
        }
        XCTAssertTrue(followed)
        let state = await facade.currentState()
        // 原子发布：snapshot 的 latestEventSequence 与 cursor 一致（来自重取的权威快照）。
        XCTAssertEqual(state.snapshot?.latestEventSequence, .init(1))
        XCTAssertEqual(state.connection, .online)
        // 首屏 snapshot + 事件后重取 snapshot 至少 2 次。
        let snapshotCount = transport.requestLog.filter { $0 == "snapshot" }.count
        XCTAssertGreaterThanOrEqual(snapshotCount, 2)
        await facade.stop()
    }

    func testGapTriggersSnapshotResync() async {
        // Runtime 已推进到 5；回放断档一次，随后恢复空批。
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 5))
        transport.gapResponsesRemaining = 1
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0
        )
        let recorder = StateRecorder()
        await facade.setPublishHookForTesting { state in recorder.record(state) }
        await facade.start()
        // 确定性：等待「已记录到 resyncing 瞬态」且「重取快照后 online + 游标 5」同时成立，
        // 不采样时序碰运气（publishHook 在 update 内同步触发，发布过的瞬态必被记录）。
        let resynced = await waitUntil {
            let state = await facade.currentState()
            return state.connection == .online
                && state.eventCursor == .init(5)
                && recorder.contains { $0.connection == .resyncing }
        }
        XCTAssertTrue(resynced, "断档后必须发布过 resyncing 瞬态，重取快照并把游标复位到 5")
        // 首屏 snapshot + 断档重取 snapshot ≥ 2 次。
        let snapshotCount = transport.requestLog.filter { $0 == "snapshot" }.count
        XCTAssertGreaterThanOrEqual(snapshotCount, 2)
        await facade.stop()
    }

    func testTransportErrorGoesOfflineThenReconnects() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        transport.nextError = AhaKeyRuntimeXPCTransportError.requestTimedOut
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0
        )
        let recorder = StateRecorder()
        await facade.setPublishHookForTesting { state in recorder.record(state) }
        await facade.start()
        let recovered = await waitUntil {
            await facade.currentState().connection == .online
                && recorder.contains { $0.connection == .offline && $0.lastError != nil }
        }
        XCTAssertTrue(recovered, "必须经历 offline(带错误) 后重连恢复 online")
        XCTAssertEqual(transport.requestLog.first, "error")
        await facade.stop()
    }

    func testStopPublishesOfflineAndIsIdempotent() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0
        )
        await facade.start()
        _ = await waitUntil { await facade.currentState().connection == .online }
        await facade.stop()
        var state = await facade.currentState()
        XCTAssertEqual(state.connection, .offline)
        // stop 幂等。
        await facade.stop()
        state = await facade.currentState()
        XCTAssertEqual(state.connection, .offline)
        // start 幂等：重复 start 不叠加循环。
        await facade.start()
        await facade.start()
        _ = await waitUntil { await facade.currentState().connection == .online }
        state = await facade.currentState()
        XCTAssertEqual(state.connection, .online)
        await facade.stop()
    }

    func testViewStateStreamYieldsCurrentThenUpdates() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0
        )
        // 确定性：先 await viewStates()（actor 方法返回时 continuation 已注册并 yield 当前值），
        // 再 start——首元素必为订阅时刻的 offline，不受消费任务调度时序影响。
        let stream = await facade.viewStates()
        await facade.start()
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first?.connection, .offline, "订阅即收到当前值（offline）")
        // 随后必出现 online 更新。
        var sawOnline = false
        let deadline = Date().addingTimeInterval(5)
        while !sawOnline, Date() < deadline, let state = await iterator.next() {
            if state.connection == .online { sawOnline = true }
        }
        XCTAssertTrue(sawOnline, "启动后必须发布 online")
        await facade.stop()
    }

    // MARK: - 切片 2：apply / ingest / 取消

    /// 假资源加载器：返回固定字节与元数据，可注入错误。
    private struct FakeResourceLoader: AhaKeyStudioResourceLoader {
        var data: Data
        var frameCount: Int
        var pixelWidth: Int
        var pixelHeight: Int
        var error: Error?

        func load(from url: URL) throws -> AhaKeyStudioLoadedResource {
            if let error { throw error }
            var hasher = SHA256()
            hasher.update(data: data)
            let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return try AhaKeyStudioLoadedResource(
                data: data,
                sha256: AhaKeySHA256Digest(hex),
                frameCount: frameCount,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
        }
    }

    private struct IdentityImageNormalizer: AhaKeyStudioImageNormalizer {
        var frameCount: Int
        var pixelWidth: Int = 160
        var pixelHeight: Int = 80

        func normalize(
            from url: URL,
            maxFrames: Int,
            maxSourceFileBytes: Int
        ) throws -> AhaKeyStudioNormalizedImage {
            AhaKeyStudioNormalizedImage(
                fileURL: url,
                frameCount: frameCount,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                encodedByteCount: frameCount * AhaKeyOLEDFrameEncoderCore.encodedFrameBytes
            )
        }
    }

    private func gifAsset(
        _ state: AhaKeyDesiredConfiguration.TaskDisplayState,
        name: String,
        frames: Int
    ) -> AhaKeyStudioTaskAssetInput {
        AhaKeyStudioTaskAssetInput(
            state: state,
            localFileURL: URL(fileURLWithPath: "/tmp/ahakey-facade-\(name).gif"),
            framesPerSecond: 12,
            declaredFrameCount: frames,
            pixelWidth: 160,
            pixelHeight: 80
        )
    }

    /// 单模式输入：套图 A done 带资源（6 帧），其余槽无资源。
    private func applyModeInput(slot: UInt8 = 0) -> AhaKeyStudioModeInput {
        let emptySet = AhaKeyStudioTaskSetInput(assets: [
            AhaKeyStudioTaskAssetInput(state: .idle, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .working, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .waiting, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .done, framesPerSecond: 12),
        ])
        var setA = emptySet
        setA.assets[3] = gifAsset(.done, name: "done", frames: 6)
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
                statusLine: "s", framesPerSecond: 12, taskSets: [setA, emptySet], activeSet: 0
            ),
            lightBar: AhaKeyStudioLightBarInput(
                stateMappings: [AhaKeyStudioLightMappingInput(state: 3, effect: "singleMove")],
                brightness: 35
            )
        )
    }

    func testApplyIngestsBeforeApplyAndEchoesOperationID() async throws {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let loader = FakeResourceLoader(data: payload, frameCount: 6, pixelWidth: 160, pixelHeight: 80)
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0,
            resourceLoader: loader, imageNormalizer: IdentityImageNormalizer(frameCount: 6),
            allowsPictureResources: true
        )
        let device = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let operationID = try await facade.apply(
            modes: [applyModeInput()],
            scope: .init(modeSlot: 0),
            targetDeviceID: device,
            baseRevision: .init(7)
        )
        // 顺序断言：ingest 先于 apply。
        XCTAssertEqual(transport.requestLog, ["ingest(1)", "apply"])
        // operationID 与包内一致（FakeTransport 回声），且发布到 view state。
        XCTAssertEqual(operationID, transport.appliedPackage?.operationID)
        let state = await facade.currentState()
        XCTAssertEqual(state.lastApplyOperationID, operationID)
        // 包内容：device/revision/canonical 配置。
        let package = try XCTUnwrap(transport.appliedPackage)
        XCTAssertEqual(package.targetDeviceID, device)
        XCTAssertEqual(package.baseRevision, .init(7))
        let desired = try AhaKeyDesiredConfiguration.decode(from: package.desiredConfiguration)
        XCTAssertEqual(desired.modes[0].oled.defaultAnimationFrames, 6, "申报帧数与加载帧数一致")
        // 资源摘要：sha256/byteCount 对源数据（冻结契约：CAS 存 GIF 源，客户端不预编码）。
        let item = try XCTUnwrap(transport.ingestedItems?.first)
        var hasher = SHA256()
        hasher.update(data: payload)
        let expectedHex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(item.sha256.rawValue, expectedHex)
        XCTAssertEqual(item.byteCount, UInt64(payload.count))
        XCTAssertEqual(item.logicalIdentifier.rawValue, "mode0-default")
        XCTAssertEqual(package.resources.first?.sha256.rawValue, expectedHex)
        XCTAssertEqual(package.resources.first?.mediaType.rawValue, "gif")
        await facade.stop()
    }

    func testIngestRejectionSkipsApply() async throws {
        let loader = FakeResourceLoader(data: Data([1]), frameCount: 6, pixelWidth: 160, pixelHeight: 80)
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        transport.ingestResponse = .failure(try AhaKeyRuntimeEventCode("resource.quota"))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0,
            resourceLoader: loader, imageNormalizer: IdentityImageNormalizer(frameCount: 6),
            allowsPictureResources: true
        )
        do {
            _ = try await facade.apply(
                modes: [applyModeInput()],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("ingest 被拒必须抛错")
        } catch let error as AhaKeyStudioApplyError {
            XCTAssertEqual(error, .ingestRejected(try AhaKeyRuntimeEventCode("resource.quota")))
        }
        XCTAssertEqual(transport.requestLog, ["ingest(1)"], "ingest 失败不得发 apply")
        XCTAssertNil(transport.appliedPackage)
    }

    func testApplyRejectionIsDistinguishable() async throws {
        let loader = FakeResourceLoader(data: Data([1]), frameCount: 6, pixelWidth: 160, pixelHeight: 80)
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        transport.applyResponse = .failure(try AhaKeyRuntimeEventCode("device.busy"))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0,
            resourceLoader: loader, imageNormalizer: IdentityImageNormalizer(frameCount: 6),
            allowsPictureResources: true
        )
        do {
            _ = try await facade.apply(
                modes: [applyModeInput()],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("apply 被拒必须抛错")
        } catch let error as AhaKeyStudioApplyError {
            XCTAssertEqual(error, .applyRejected(try AhaKeyRuntimeEventCode("device.busy")))
        }
        XCTAssertEqual(transport.requestLog, ["ingest(1)", "apply"])
    }

    func testResourceLoadFailureSkipsTransport() async throws {
        struct Boom: Error {}
        var loader = FakeResourceLoader(data: Data(), frameCount: 6, pixelWidth: 160, pixelHeight: 80)
        loader.error = Boom()
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0,
            resourceLoader: loader, imageNormalizer: IdentityImageNormalizer(frameCount: 6),
            allowsPictureResources: true
        )
        do {
            _ = try await facade.apply(
                modes: [applyModeInput()],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("资源缺失必须抛错")
        } catch let error as AhaKeyStudioApplyError {
            guard case .resourceLoadFailed(let identifier, let path, _) = error else {
                return XCTFail("应为 resourceLoadFailed，实际 \(error)")
            }
            XCTAssertEqual(identifier, "mode0-default")
            XCTAssertTrue(path.hasSuffix("ahakey-facade-done.gif"))
        }
        XCTAssertTrue(transport.requestLog.isEmpty, "资源读失败不得发任何请求")
    }

    func testDeclaredMetadataMismatchSkipsTransport() async throws {
        // 申报 6 帧，实际加载 3 帧 → fail-fast，不发 ingest/apply。
        let loader = FakeResourceLoader(data: Data([1]), frameCount: 3, pixelWidth: 160, pixelHeight: 80)
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0,
            resourceLoader: loader, imageNormalizer: IdentityImageNormalizer(frameCount: 6),
            allowsPictureResources: true
        )
        do {
            _ = try await facade.apply(
                modes: [applyModeInput()],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
            XCTFail("元数据不符必须抛错")
        } catch let error as AhaKeyStudioApplyError {
            XCTAssertEqual(error, .resourceMetadataMismatch(identifier: "mode0-default"))
        }
        XCTAssertTrue(transport.requestLog.isEmpty)
    }

    func testRequestCancellationPassthrough() async throws {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        transport.cancellationDisposition = .requested
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0
        )
        let target = AhaKeyRuntimeOperationID()
        let disposition = try await facade.requestCancellation(target)
        XCTAssertEqual(disposition, .requested)
        XCTAssertEqual(transport.cancelledOperation, target)
        XCTAssertEqual(transport.requestLog, ["cancel(\(target.rawValue.uuidString))"])
    }

    func testApplyWithoutResourcesSkipsIngest() async throws {
        // 无资源引用的纯键位/灯条配置：直接 apply，不发 ingest。
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0
        )
        let emptySet = AhaKeyStudioTaskSetInput(assets: [
            AhaKeyStudioTaskAssetInput(state: .idle, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .working, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .waiting, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .done, framesPerSecond: 12),
        ])
        var mode = applyModeInput()
        mode.oled.taskSets = [emptySet, emptySet]
        _ = try await facade.apply(
            modes: [mode],
            scope: .init(modeSlot: 0),
            targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
            baseRevision: .init(0)
        )
        XCTAssertEqual(transport.requestLog, ["apply"])
        XCTAssertNil(transport.ingestedItems)
    }

    private final class GateImageNormalizer: AhaKeyStudioImageNormalizer, @unchecked Sendable {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        func normalize(
            from url: URL,
            maxFrames: Int,
            maxSourceFileBytes: Int
        ) throws -> AhaKeyStudioNormalizedImage {
            started.signal()
            release.wait()
            try Task.checkCancellation()
            return AhaKeyStudioNormalizedImage(
                fileURL: url,
                frameCount: 6,
                pixelWidth: 160,
                pixelHeight: 80,
                encodedByteCount: 6 * AhaKeyOLEDFrameEncoderCore.encodedFrameBytes
            )
        }
    }

    func testBlockingNormalizerDoesNotHoldActor() async throws {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let loader = FakeResourceLoader(data: payload, frameCount: 6, pixelWidth: 160, pixelHeight: 80)
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let gate = GateImageNormalizer()
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0,
            resourceLoader: loader, imageNormalizer: gate,
            allowsPictureResources: true
        )
        let applyTask = Task {
            _ = try await facade.apply(
                modes: [applyModeInput()],
                scope: .init(modeSlot: 0),
                targetDeviceID: AhaKeyRuntimeDeviceID("DEVICE-1"),
                baseRevision: .init(0)
            )
        }
        XCTAssertEqual(gate.started.wait(timeout: .now() + 2), .success)
        let state = await facade.currentState()
        XCTAssertEqual(state.connection, .offline)
        await facade.stop()
        let stopped = await facade.currentState()
        XCTAssertEqual(stopped.connection, .offline)
        gate.release.signal()
        _ = try await applyTask.value
    }

    func testNormalizeCancellationIsPropagated() async throws {
        let loader = FakeResourceLoader(data: Data([1]), frameCount: 6, pixelWidth: 160, pixelHeight: 80)
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let gate = GateImageNormalizer()
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0,
            resourceLoader: loader, imageNormalizer: gate,
            allowsPictureResources: true
        )
        let applyTask = Task {
            try await facade.apply(
                modes: [applyModeInput()],
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
        XCTAssertTrue(transport.requestLog.isEmpty)
    }

    func testV02DefaultApplyStripsPictureResourcesAndSkipsIngest() async throws {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let loader = FakeResourceLoader(data: payload, frameCount: 6, pixelWidth: 160, pixelHeight: 80)
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0, idlePollInterval: 0,
            resourceLoader: loader, imageNormalizer: IdentityImageNormalizer(frameCount: 6)
        )
        let device = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let operationID = try await facade.apply(
            modes: [applyModeInput()],
            scope: .init(modeSlot: 0),
            targetDeviceID: device,
            baseRevision: .init(7)
        )
        XCTAssertEqual(transport.requestLog, ["apply"])
        XCTAssertNil(transport.ingestedItems)
        let package = try XCTUnwrap(transport.appliedPackage)
        XCTAssertEqual(package.operationID, operationID)
        XCTAssertTrue(package.resources.isEmpty)
        let desired = try AhaKeyDesiredConfiguration.decode(from: package.desiredConfiguration)
        XCTAssertNil(desired.modes[0].oled.defaultAnimation)
        XCTAssertEqual(desired.modes[0].oled.activeSet, -1)
        XCTAssertTrue(desired.modes[0].oled.taskSets.allSatisfy { set in
            set.assets.allSatisfy { $0.resource == nil }
        })
        XCTAssertEqual(desired.modes[0].keys.count, 1)
        XCTAssertEqual(desired.modes[0].lightBar.brightness, 35)
        await facade.stop()
    }
}
