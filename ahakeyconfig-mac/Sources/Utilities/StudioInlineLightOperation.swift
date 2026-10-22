import Foundation
import AhaKeyConfigShared

@MainActor
enum StudioInlineLightOperation {
    typealias Target = StudioLightDrafts.Target
    typealias Fact = StudioLightDrafts.Fact

    struct Reading {
        let selected: Fact
        let brightness: UInt8
    }

    enum Action {
        case read
        case save(baseline: Fact, desired: UInt8, requiresPersistence: Bool = false)
        case preview(WS3DisplayPreview)
    }

    enum Result {
        case read(Reading)
        case readOnly(Reading)
        case conflict(Reading, desired: UInt8)
        case saved(Reading, wrote: Bool)
        case previewed(Reading)
    }

    static func saving(target: Target, values: StudioLightDrafts, baselineOverride: Fact? = nil,
                       desiredOverride: UInt8? = nil) -> Action? {
        guard let baseline = baselineOverride ?? values.facts[target],
              let desired = desiredOverride ?? values.drafts[target],
              target.accepts(baseline.value), target.accepts(desired) else { return nil }
        return .save(baseline: baseline, desired: desired, requiresPersistence: values.unconfirmed.contains(target))
    }

    /// A result is delivered only after ownership/generation validation and
    /// returning the short lease. No result itself authorizes the next operation.
    static func run(target: Target, action: Action, session: StudioInspectorSession,
                    expectedDeviceID: String?,
                    read: (Target, StudioInspectorSession.Context) async throws -> Reading,
                    save: (WS3DisplaySetting, UInt8, UInt64) async throws -> Void,
                    preview: (WS3DisplayPreview) async throws -> Void,
                    writeStarted: () -> Void) async throws -> Result {
        if case .save(let baseline, let desired, _) = action {
            guard target.accepts(desired), target.accepts(baseline.value),
                  expectedDeviceID == baseline.deviceID else { throw ConfirmedWS3DisplaySetting.Failure.invalidValue }
        }
        return try await session.withConnection(expectedDeviceID: expectedDeviceID) { context in
            let reading = try await read(target, context)
            try Task.checkCancellation()
            guard reading.selected.deviceID == context.deviceID else { throw StudioInspectorSession.Failure.deviceChanged }
            switch action {
            case .read: return .read(reading)
            case .save(let baseline, let desired, let requiresPersistence):
                guard target.accepts(reading.selected.value) else { return .readOnly(reading) }
                guard reading.selected == baseline else { return .conflict(reading, desired: desired) }
                let wrote = requiresPersistence || desired != reading.selected.value
                if wrote {
                    writeStarted()
                    try await save(target.setting(desired), reading.selected.value, context.generation)
                    try Task.checkCancellation()
                }
                let confirmed = Reading(selected: .init(deviceID: context.deviceID, value: desired),
                                        brightness: target == .brightness ? desired : reading.brightness)
                return .saved(confirmed, wrote: wrote)
            case .preview(let request):
                guard request == .stop || target.accepts(reading.selected.value) else { return .readOnly(reading) }
                guard request.request != nil else { throw ConfirmedWS3DisplaySetting.Failure.invalidValue }
                try await preview(request)
                return .previewed(reading)
            }
        }
    }
}
