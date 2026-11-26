import AppKit
import SwiftUI

struct StudioStatusHookIcon: View {
    let assetName: String?

    private static let images: [String: NSImage] = {
        let names = StudioHookClient.allCases.map(\.rawValue) + StudioHarnessCatalog.featured.compactMap(\.iconAsset)
        let monochrome = Set(["codex", "copilot", "openCode", "pi"])
        let bundle = Bundle.main
        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            let url = bundle.url(forResource: name, withExtension: "svg", subdirectory: "StatusHookIcons")
                ?? bundle.url(forResource: name, withExtension: "png", subdirectory: "StatusHookIcons")
            guard let url, let image = NSImage(contentsOf: url) else { return nil }
            image.isTemplate = monochrome.contains(name)
            return (name, image)
        })
    }()

    var body: some View {
        Group {
            if let assetName, let image = Self.images[assetName] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 27, height: 27)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
