import Foundation
import AhaKeyConfigShared

@MainActor
enum StudioK1VoiceSave {
    static func run(session: StudioInspectorSession, baseline: StudioInlineKeyFact,
                    key: AhaKeyKeyDraft, configuration: StudioVoiceConfiguration,
                    read: (UInt8) async throws -> StudioInlineKeyFact,
                    saveDescription: (OrdinaryKeyReadback, Data, UInt64) async throws -> Void,
                    saveRoute: (K1OutputRoute, K1OutputRoute, UInt64) async throws -> Void,
                    checkHostReady: () throws -> Void, prepareHost: () throws -> Void,
                    writeStarted: () -> Void) async throws -> StudioInlineKeySave.Result {
        guard let baselineRoute = baseline.k1Route, baseline.value.keyIndex == 0,
              baseline.value.mode < 4 else { throw K1OutputRouteTransaction.Failure.invalidTarget }
        let route = try StudioK1VoiceProposal.route(for: key)
        let description = try StudioK1VoiceProposal.description(for: key)
        let desired = StudioK1VoiceProposal.projection(route, mode: baseline.value.mode, description: description)
        return try await session.withConnection(expectedDeviceID: baseline.deviceID) { context in
            let actual = try await read(baseline.value.mode)
            try session.validate(context)
            guard actual.deviceID == context.deviceID else { throw StudioInspectorSession.Failure.deviceChanged }
            guard actual.value.mode == baseline.value.mode, actual.value.keyIndex == 0 else { throw K1OutputRouteTransaction.Failure.invalidTarget }
            guard let currentRoute = actual.k1Route else { throw K1OutputRouteTransaction.Failure.unsupported }
            guard StudioK1VoiceProposal.importing(route: currentRoute, actual: actual.value,
                      configuration: configuration, preserving: key) != nil else { return .readOnly(actual) }
            guard actual.value == baseline.value, currentRoute == baselineRoute else {
                return .conflict(.init(deviceID: context.deviceID, actual: actual.value, desired: desired,
                    voiceDraft: key, k1Route: currentRoute, desiredK1Route: route))
            }
            try checkHostReady(); try session.validate(context)
            let changedDescription = actual.value.description != description
            let changedRoute = currentRoute != route
            if changedDescription {
                writeStarted()
                try await saveDescription(actual.value, description, context.generation)
                try session.validate(context)
            }
            try prepareHost(); try session.validate(context)
            if changedRoute {
                writeStarted()
                try await saveRoute(currentRoute, route, context.generation)
                try session.validate(context)
            }
            let confirmed = changedDescription || changedRoute ? try await read(baseline.value.mode) : actual
            try session.validate(context)
            guard confirmed.deviceID == context.deviceID, confirmed.k1Route == route,
                  confirmed.value == desired else { throw K1OutputRouteTransaction.Failure.verificationMismatch }
            return changedDescription || changedRoute ? .saved(confirmed) : .unchanged(confirmed)
        }
    }
}
