import Foundation

/// A bounded, read-only probe for the device-info sheet. It never takes BLE
/// ownership or starts while an explicit configuration operation owns the channel.
enum DeviceInfoFirmwareReadback {
    struct Connection: Equatable, Hashable {
        let connected: Bool
        let generation: UInt64
    }

    struct State {
        let connection: Connection
        let statusReady: Bool
        let operationBusy: Bool
        let profileKnown: Bool
    }

    @MainActor
    static func run(connection: Connection,
                    state: () -> State,
                    read: () async throws -> Void,
                    wait: () async throws -> Void = { try await Task.sleep(nanoseconds: 100_000_000) },
                    maximumWaits: Int = 50) async throws -> Bool {
        guard connection.connected else { return false }
        for attempt in 0...max(0, maximumWaits) {
            try Task.checkCancellation()
            let current = state()
            guard current.connection == connection, !current.profileKnown else { return false }
            if current.statusReady && !current.operationBusy {
                try await read()
                try Task.checkCancellation()
                return state().connection == connection
            }
            guard attempt < maximumWaits else { return false }
            try await wait()
        }
        return false
    }
}
