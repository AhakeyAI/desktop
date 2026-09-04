import XCTest
@testable import AhaKeyConfigShared

/// WBS-5.6 切片 2：事务状态机决策测试（取消/恢复/永久失败/断线/完成语义）。
final class AhaKeyConfigurationTransactionEngineTests: XCTestCase {

    private typealias Engine = AhaKeyConfigurationTransactionEngine
    private typealias Planner = AhaKeyConfigurationPlanner

    private func step(_ id: String) -> AhaKeyRuntimeStepIdentifier { try! .init(id) }

    private var plan: Planner.Plan {
        let upload = Planner.ResourceUpload(
            resource: try! AhaKeyConfigurationResource(
                logicalIdentifier: "img-a", sha256: String(repeating: "a", count: 64),
                byteCount: 100, mediaType: "gif"),
            slotIndex: 0
        )
        return Planner.Plan(
            transactions: [.resources([upload]), .base(modeSlots: [0, 1])],
            slotAssignments: [try! AhaKeyResourceIdentifier("img-a"): 0]
        )
    }

    private func record(
        state: AhaKeyRuntimeOperationState, completed: UInt32, total: UInt32
    ) -> AhaKeyRuntimePersistedTransaction {
        AhaKeyRuntimePersistedTransaction(
            operationID: .init(),
            package: try! AhaKeyConfigurationPackage(
                targetDeviceID: .init("device-1"),
                baseRevision: .init(0),
                desiredConfiguration: Data("{}".utf8),
                resources: []
            ),
            state: state, completedSteps: completed, totalSteps: total, messageCode: nil
        )
    }

    func testStepIdentifiersFollowPlanOrder() {
        XCTAssertEqual(
            Engine.stepIdentifiers(for: plan),
            [step("resource:img-a"), step("base:mode:0"), step("base:mode:1")]
        )
    }

    func testStartExecutesFirstUnconfirmedStep() {
        let actions = Engine.decide(
            event: .start, record: record(state: .accepted, completed: 0, total: 3),
            confirmedSteps: [], plan: plan
        )
        XCTAssertEqual(actions, [.persistState(.running), .executeStep(step("resource:img-a"))])
    }

    func testResumeSkipsConfirmedSteps() {
        // 断线恢复：第一步已确认，从 base:mode:0 继续
        let actions = Engine.decide(
            event: .start, record: record(state: .resumablePartial, completed: 1, total: 3),
            confirmedSteps: [step("resource:img-a")], plan: plan
        )
        XCTAssertEqual(actions, [.persistState(.running), .executeStep(step("base:mode:0"))])
    }

    func testAllStepsConfirmedCommitsCompleted() {
        let actions = Engine.decide(
            event: .start, record: record(state: .running, completed: 3, total: 3),
            confirmedSteps: [step("resource:img-a"), step("base:mode:0"), step("base:mode:1")],
            plan: plan
        )
        XCTAssertEqual(actions, [.commitCompleted])
    }

    func testStepSucceededAdvancesToNext() {
        let actions = Engine.decide(
            event: .stepSucceeded(step("resource:img-a")),
            record: record(state: .running, completed: 1, total: 3),
            confirmedSteps: [step("resource:img-a")], plan: plan
        )
        XCTAssertEqual(actions, [.executeStep(step("base:mode:0"))])
    }

    func testStepSucceededIgnoresUnconfirmedClaim() {
        // 没先落 WAL 的成功上报不被采信
        let actions = Engine.decide(
            event: .stepSucceeded(step("base:mode:1")),
            record: record(state: .running, completed: 0, total: 3),
            confirmedSteps: [], plan: plan
        )
        XCTAssertEqual(actions, [.none])
    }

    func testRetryableFailureWithoutWritesPauses() {
        let actions = Engine.decide(
            event: .stepFailedRetryable(step("resource:img-a")),
            record: record(state: .running, completed: 0, total: 3),
            confirmedSteps: [], plan: plan
        )
        XCTAssertEqual(actions, [.persistState(.paused)])
    }

    func testRetryableFailureWithWritesBecomesResumablePartial() {
        let actions = Engine.decide(
            event: .disconnected,
            record: record(state: .running, completed: 1, total: 3),
            confirmedSteps: [step("resource:img-a")], plan: plan
        )
        XCTAssertEqual(actions, [.persistState(.resumablePartial)])
    }

    func testPermanentFailureSemantics() {
        // 无写入 → failedWithoutWrites
        XCTAssertEqual(
            Engine.decide(event: .stepFailedPermanent(step("resource:img-a")),
                          record: record(state: .running, completed: 0, total: 3),
                          confirmedSteps: [], plan: plan),
            [.commitTerminal(.failedWithoutWrites)]
        )
        // 有写入 → failedWithPartialCommit
        XCTAssertEqual(
            Engine.decide(event: .stepFailedPermanent(step("base:mode:0")),
                          record: record(state: .running, completed: 1, total: 3),
                          confirmedSteps: [step("resource:img-a")], plan: plan),
            [.commitTerminal(.failedWithPartialCommit)]
        )
    }

    func testCancelRequestedThenSettlement() {
        let actions = Engine.decide(
            event: .cancelRequested,
            record: record(state: .running, completed: 1, total: 3),
            confirmedSteps: [step("resource:img-a")], plan: plan
        )
        XCTAssertEqual(actions, [.persistState(.cancellationRequested)])
        // 已请求取消的事务不被 start 复活
        XCTAssertEqual(
            Engine.decide(event: .start,
                          record: record(state: .cancellationRequested, completed: 1, total: 3),
                          confirmedSteps: [step("resource:img-a")], plan: plan),
            [.none]
        )
        // 结算：有写入 → resumablePartial；无写入 → failedWithoutWrites
        XCTAssertEqual(
            Engine.settleCancellation(confirmedSteps: [step("resource:img-a")]),
            .persistState(.resumablePartial)
        )
        XCTAssertEqual(
            Engine.settleCancellation(confirmedSteps: []),
            .commitTerminal(.failedWithoutWrites)
        )
        XCTAssertEqual(
            Engine.settleCancellation(
                confirmedSteps: [step("page:local:screenStatusLine:0")],
                hasWrites: false
            ),
            .commitTerminal(.failedWithoutWrites)
        )
    }

    func testTerminalStateIgnoresEverything() {
        let terminal = record(state: .completed, completed: 3, total: 3)
        for event in [Engine.Event.start, .cancelRequested, .disconnected,
                      .stepSucceeded(step("base:mode:1"))] {
            XCTAssertEqual(Engine.decide(event: event, record: terminal,
                                         confirmedSteps: [], plan: plan), [.none])
        }
    }

    func testNoRecordDoesNothing() {
        XCTAssertEqual(Engine.decide(event: .start, record: nil, confirmedSteps: [], plan: plan), [.none])
    }
}
