import AppKit
import Foundation

/// Vibe Island 展开/收起与交互提示音（与主界面 Settings 灵动岛 Tab 共用）。
enum VibeBarIslandSoundSettings {
    static let mutedDefaultsKey = "lab.jawa.vibebar.island.soundMuted"
    static let defaultSoundName = "Bottle"

    static var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: mutedDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: mutedDefaultsKey) }
    }

    @discardableResult
    static func toggleMuted() -> Bool {
        isMuted.toggle()
        return isMuted
    }

    static func playInteractionIfEnabled() {
        guard !isMuted else { return }
        guard let sound = NSSound(named: NSSound.Name(defaultSoundName)) else {
            NSSound.beep()
            return
        }
        sound.stop()
        sound.play()
    }
}
