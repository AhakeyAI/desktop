import Foundation

/// A bounded, explicit runtime preview, never flash storage or synthetic hooks.
/// Cleanup runs even on cancellation, before the caller releases its BLE lease.
@MainActor
public enum WS3MultitaskLightPreview {
    public static func run(restoreMode: WS3PresentationMode = .single, activate: (_ willChangeMode: () -> Void) async throws -> Void,
                           send: @escaping @MainActor (WS3PresentationCommand) async throws -> Void,
                           sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                           cleanupFailed: @escaping @MainActor () -> Void) async throws {
        var failure: Error?
        var modeMayHaveChanged = false
        do {
            try Task.checkCancellation()
            try await activate { modeMayHaveChanged = true }
            for step in 0..<4 {
                try Task.checkCancellation()
                try await send(.multi(WS3TaskLightAnimation.mock(at: Double(step * 3)).snapshot))
                try await sleep(.seconds(step == 3 ? 1 : 3))
            }
        } catch { failure = error }
        guard modeMayHaveChanged else {
            if let failure { throw failure }
            throw WS3PresentationError.unsupported
        }
        // An ACK may have been lost after changing mode, so cleanup is required
        // even if activation threw. The supplied sender revalidates ownership.
        let cleaned = await Task { @MainActor in
            do {
                try await send(.multi(WS3TaskSnapshot(slots: [nil, nil, nil, nil])!))
                try await send(.setMode(restoreMode))
                return true
            } catch { cleanupFailed(); return false }
        }.value
        if let failure { throw failure }
        guard cleaned else { throw WS3PresentationError.connectionChanged }
    }
}
