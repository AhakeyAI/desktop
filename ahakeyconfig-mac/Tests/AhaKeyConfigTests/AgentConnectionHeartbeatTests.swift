import Combine
import Foundation
import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class AgentConnectionHeartbeatTests: XCTestCase {
    @MainActor
    func testSlowTaskOverviewIsRevokedAcrossDisconnectAndReconnect() async {
        let script = QueryScript()
        script.onCall = { $0 != 2 }
        let manager = AgentManager(startServices: false, connectionQuery: { script.query($0) })
        let connected = expectation(description: "initial connected")
        let disconnected = expectation(description: "actual heartbeat disconnect")
        let reconnected = expectation(description: "actual heartbeat reconnect")
        var changes = 0
        let observer = manager.$isAgentBLEConnected.dropFirst().sink { _ in
            changes += 1
            [connected, disconnected, reconnected][changes - 1].fulfill()
        }
        manager.refreshBLEConnectionStatus(shouldQuery: true)
        await fulfillment(of: [connected], timeout: 2)
        let started = expectation(description: "old overview entered")
        let release = DispatchSemaphore(value: 0)
        let pending = Task { @MainActor in
            await manager.readTaskOverview(shouldQuery: { true }, query: { _ in
                started.fulfill()
                _ = release.wait(timeout: .now() + 3)
                return WS3TaskOverview.decode(Data(#"{"connected":true,"tasks":[],"unrepresentedEvents":0}"#.utf8))
            })
        }
        await fulfillment(of: [started], timeout: 2)
        manager.refreshBLEConnectionStatus(shouldQuery: true)
        await fulfillment(of: [disconnected], timeout: 2)
        manager.refreshBLEConnectionStatus(shouldQuery: true)
        await fulfillment(of: [reconnected], timeout: 2)
        release.signal()
        let result = await pending.value
        XCTAssertNil(result, "A reply from before disconnect must not survive reconnect")
        withExtendedLifetime(observer) {}
    }

    private final class QueryScript: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var onCall: (@Sendable (Int) -> Bool)?
        func query(_ path: String) -> Bool {
            lock.lock(); count += 1; let number = count; lock.unlock()
            return onCall?(number) ?? false
        }
        var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    @MainActor
    func testHeartbeatWithdrawsStaleConnectedWithoutFullRefresh() async {
        let script = QueryScript()
        script.onCall = { $0 == 1 }
        let manager = AgentManager(startServices: false, connectionQuery: { script.query($0) })
        let changes = expectation(description: "connected then disconnected")
        changes.expectedFulfillmentCount = 2
        var values: [Bool] = []
        let observer = manager.$isAgentBLEConnected.dropFirst().sink { value in
            values.append(value); changes.fulfill()
        }
        manager.startConnectionHeartbeat(interval: 0.01, shouldQuery: { true })
        await fulfillment(of: [changes], timeout: 2)
        manager.stopConnectionHeartbeat()
        XCTAssertEqual(values, [true, false])
        XCTAssertFalse(manager.isAgentBLEConnected)
        withExtendedLifetime(observer) {}
    }

    @MainActor
    func testUnchangedHeartbeatDoesNotRepublish() async {
        let script = QueryScript()
        let queried = expectation(description: "several real timer ticks")
        script.onCall = { number in if number == 4 { queried.fulfill() }; return true }
        let manager = AgentManager(startServices: false, connectionQuery: { script.query($0) })
        var values: [Bool] = []
        let observer = manager.$isAgentBLEConnected.dropFirst().sink { values.append($0) }
        manager.startConnectionHeartbeat(interval: 0.01, shouldQuery: { true })
        await fulfillment(of: [queried], timeout: 2)
        manager.stopConnectionHeartbeat()
        XCTAssertEqual(values, [true])
        withExtendedLifetime(observer) {}
    }

    @MainActor
    func testRevokedSlowReplyCannotRestoreConnectedAndQueriesDoNotOverlap() async {
        let script = QueryScript()
        let first = expectation(description: "initial connected")
        let started = expectation(description: "second query entered")
        let returned = expectation(description: "second query returned")
        let release = DispatchSemaphore(value: 0)
        script.onCall = { number in
            if number == 2 {
                started.fulfill()
                _ = release.wait(timeout: .now() + 2)
                returned.fulfill()
            }
            return true
        }
        let manager = AgentManager(startServices: false, connectionQuery: { script.query($0) })
        let observer = manager.$isAgentBLEConnected.dropFirst().sink { value in if value { first.fulfill() } }
        manager.refreshBLEConnectionStatus(shouldQuery: true)
        await fulfillment(of: [first], timeout: 2)
        manager.refreshBLEConnectionStatus(shouldQuery: true)
        await fulfillment(of: [started], timeout: 2)
        for _ in 0..<10 { manager.refreshBLEConnectionStatus(shouldQuery: true) }
        XCTAssertEqual(script.calls, 2)
        // Exercise the same pure entry point used before production unload;
        // do not touch the user's launchd job or approval configuration.
        manager.prepareForAgentUnload()
        XCTAssertFalse(manager.isAgentBLEConnected)
        release.signal()
        await fulfillment(of: [returned], timeout: 2)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(manager.isAgentBLEConnected)
        XCTAssertEqual(script.calls, 2)
        manager.stopConnectionHeartbeat()
        withExtendedLifetime(observer) {}
    }
}
