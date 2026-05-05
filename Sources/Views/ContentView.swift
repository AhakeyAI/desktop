import SwiftUI

struct ContentView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager

    var body: some View {
        if #available(macOS 14.0, *) {
            AhaKeyStudioView(bleManager: bleManager)
                .focusEffectDisabled()
        } else {
            AhaKeyStudioView(bleManager: bleManager)
        }
    }
}
