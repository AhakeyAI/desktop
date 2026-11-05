import Foundation
import AhaKeyConfigShared

/// Restore an explicitly selected normal mode after the preview releases BLE.
/// A newer explicit choice wins, including one racing the read/apply boundary.
@MainActor
enum StudioLightPreviewRestoration {
    static func run(mode: WS3PresentationMode?, deviceID: String,
                    access: StudioLCDInspectorModel.Access) async throws {
        guard let mode else { return }
        let overview = try await StudioLCDInspectorModel.freshOverview(using: access)
        guard overview.requestedMode == nil else { return }
        guard overview.targetedModeWrites == true else { throw StudioLCDInspectorModel.Failure.oldBackend }
        guard let generation = overview.connectionGeneration else { throw WS3PresentationError.unavailable }
        let revision = access.revision()
        let result: WS3TaskOverview
        if let restore = access.restore { result = try await restore(mode, deviceID, generation) }
        else { throw StudioLCDInspectorModel.Failure.oldBackend }
        guard access.revision() == revision, result.connected, result.connectionGeneration == generation,
              result.requestedMode != nil else { throw WS3PresentationError.connectionChanged }
    }
}
