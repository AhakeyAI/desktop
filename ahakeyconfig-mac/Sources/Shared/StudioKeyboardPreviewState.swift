import Foundation

/// Local screen simulation. It has no transport, persistence or hardware commands.
public struct StudioKeyboardPreviewState: Equatable {
    public enum Computer: String, Equatable { case mac, windows }
    public enum Scene: Equatable {
        case artwork, daily, boot, reconnecting, system(Computer), shuttingDown, off
    }
    public enum Action {
        case shortPower, longPower, selectMode(Int), theme(AhaKeyDeviceTheme)
        case daily, connect, selectSystem, answerSystem(Bool), restart
        case advance(revision: UInt64)
    }
    public struct Scheduled: Equatable {
        public let milliseconds: Int
        public let revision: UInt64
    }

    public private(set) var mode: Int
    public private(set) var theme: AhaKeyDeviceTheme
    public private(set) var scene: Scene = .artwork
    public private(set) var powered = true
    public private(set) var connected = true
    public private(set) var computer: Computer? = .mac
    public private(set) var revision: UInt64 = 0

    public init(mode: Int = 0, theme: AhaKeyDeviceTheme = .dark) {
        self.mode = (0..<4).contains(mode) ? mode : 0
        self.theme = theme
    }

    @discardableResult
    public mutating func send(_ action: Action) -> Scheduled? {
        var delay: Int?
        switch action {
        case .selectMode(let mode):
            guard (0..<4).contains(mode), mode != self.mode else { return nil }
            self.mode = mode
            if powered { scene = .daily; delay = 1100 }
        case .shortPower:
            if powered { mode = (mode + 1) % 4; scene = .daily; delay = 1100 }
            else { powered = true; scene = .boot; delay = 300 }
        case .longPower:
            guard powered else { return nil }
            scene = .shuttingDown; delay = 750
        case .theme(let theme):
            guard theme != self.theme else { return nil }
            self.theme = theme
            if powered { scene = .daily; delay = 2200 }
        case .daily:
            guard powered else { return nil }
            scene = .daily; delay = 2200
        case .connect:
            guard powered else { return nil }
            connected = false; scene = .reconnecting; delay = 1300
        case .selectSystem:
            guard powered else { return nil }
            computer = nil; scene = .system(.mac)
        case .answerSystem(let yes):
            guard case .system(let proposed) = scene else { return nil }
            if yes {
                computer = proposed; connected = true; scene = .daily; delay = 1100
            } else { scene = .system(proposed == .mac ? .windows : .mac) }
        case .restart:
            powered = true; scene = .boot; delay = 300
        case .advance(let revision):
            guard revision == self.revision else { return nil }
            switch scene {
            case .boot:
                scene = connected ? .daily : .reconnecting
                delay = connected ? 1100 : 1300
            case .daily: scene = .artwork
            case .reconnecting:
                connected = true
                if computer == nil { scene = .system(.mac) }
                else { scene = .daily; delay = 1100 }
            case .shuttingDown: powered = false; connected = false; scene = .off
            case .artwork, .system, .off: return nil
            }
        }
        self.revision &+= 1
        return delay.map { Scheduled(milliseconds: $0, revision: self.revision) }
    }
}
