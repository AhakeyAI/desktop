import SwiftUI

struct ContentView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager

    var body: some View {
        AhaKeyStudioView(bleManager: bleManager)
            .focusEffectDisabled()
    }
}
