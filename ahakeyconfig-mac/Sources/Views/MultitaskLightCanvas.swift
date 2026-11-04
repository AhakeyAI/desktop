import SwiftUI
import AhaKeyConfigShared

/// Layer-backed animation keeps blink frames out of SwiftUI layout.
struct MultitaskLightCanvas: NSViewRepresentable {
    var animation: WS3TaskLightAnimation?
    var mockStartedAt: TimeInterval?
    var animates: Bool = true

    func makeNSView(context: Context) -> LightBarLayerView { LightBarLayerView(barCount: 8) }
    func updateNSView(_ view: LightBarLayerView, context: Context) {
        let animation = animation, mockStartedAt = mockStartedAt, animates = animates
        view.configure(framesPerSecond: animates ? 10 : nil) { clock in
            let time = animates ? clock : Date().timeIntervalSince1970
            let elapsed = max(0, time - (mockStartedAt ?? time))
            let value = mockStartedAt == nil ? (animation ?? .init()) : .mock(at: elapsed)
            return value.snapshot.slots.enumerated().flatMap { slot, task -> [CGColor] in
                let color: NSColor
                switch task?.state {
                case .running: color = .systemGreen
                case .waiting: color = .systemYellow
                case .done: color = .systemRed
                case nil: color = .black
                }
                let intensity = animates ? value.intensity(slot: slot, at: mockStartedAt == nil ? time : elapsed) : 1
                return Array(repeating: color.withAlphaComponent(task == nil ? 0.12 : intensity).cgColor, count: 2)
            }
        }
    }
    static func dismantleNSView(_ view: LightBarLayerView, coordinator: ()) { view.dismantle() }
}
