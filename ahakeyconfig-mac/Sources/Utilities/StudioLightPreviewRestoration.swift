import Foundation
import AhaKeyConfigShared

/// Restore an explicitly selected normal mode after the preview releases BLE.
/// A newer explicit choice wins, including one racing the read/apply boundary.
@MainActor
enum StudioLightPreviewRestoration {
    static func run(mode: WS3PresentationMode?, deviceID: String,
                    access: StudioLCDInspectorModel.Access) async throws {
        guard let mode else { return }
        let ownership = access.revision()
        var expectedGeneration: UInt64?
        for attempt in 0..<4 {
            let overview = try await StudioLCDInspectorModel.freshOverview(using: access)
            guard access.revision() == ownership, let generation = overview.connectionGeneration,
                  expectedGeneration == nil || expectedGeneration == generation else {
                throw WS3PresentationError.connectionChanged
            }
            expectedGeneration = generation
            guard overview.requestedMode == nil else { return }
            guard overview.targetedModeWrites == true, let restore = access.restore else {
                throw StudioLCDInspectorModel.Failure.oldBackend
            }
            do {
                let result = try await restore(mode, deviceID, generation)
                guard access.revision() == ownership, result.connected,
                      result.connectionGeneration == generation, result.requestedMode != nil else {
                    throw WS3PresentationError.connectionChanged
                }
                return
            } catch WS3PresentationError.busy where attempt < 3 {
                // The backend rejected before touching the mode. Its approval
                // read may still be draining immediately after reconnection.
                guard access.revision() == ownership else { throw WS3PresentationError.connectionChanged }
                try await access.pause()
            }
        }
    }
}
