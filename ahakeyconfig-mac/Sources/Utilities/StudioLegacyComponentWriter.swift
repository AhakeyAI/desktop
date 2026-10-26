import Foundation
import AhaKeyConfigShared

@MainActor
enum StudioLegacyComponentWriter {
    static func run(plan: StudioLegacyComponentPlan, userConfirmed: Bool,
        session: StudioInspectorSession,
        verifyLegacy: () async throws -> Bool, checkHost: () throws -> Void,
        verifyLighting: () async throws -> Void,
        upload: () async throws -> AhaKeyOLEDDraft,
        write: (Data) async throws -> Void, writeStarted: () -> Void,
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(50)) }) async throws -> AhaKeyOLEDDraft? {
        guard userConfirmed, let deviceID = plan.deviceID, !deviceID.isEmpty else { throw StudioLegacyComponentPlan.Failure.unsupported }
        return try await session.withConnection(expectedDeviceID: deviceID) { context in
            guard try await verifyLegacy() else { throw StudioLegacyComponentPlan.Failure.unsupported }
            try session.validate(context); try checkHost()
            var artwork: AhaKeyOLEDDraft?
            if plan.part == .lightBar {
                writeStarted(); try await verifyLighting(); try session.validate(context)
            }
            if plan.uploadsArtwork {
                writeStarted(); artwork = try await upload(); try session.validate(context)
            }
            for (index, command) in plan.commands.enumerated() {
                try session.validate(context)
                writeStarted(); try await write(command.data)
                try session.validate(context)
                if index + 1 < plan.commands.count { try await pause(); try session.validate(context) }
            }
            return artwork
        }
    }
}
