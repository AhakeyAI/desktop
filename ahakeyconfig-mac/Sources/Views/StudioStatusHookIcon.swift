import AppKit
import SwiftUI

struct StudioStatusHookIcon: View {
    let client: StudioHookClient?

    private static let images: [StudioHookClient: NSImage] = Dictionary(
        uniqueKeysWithValues: StudioHookClient.allCases.compactMap { client in
            let template: Bool
            let fileExtension: String
            switch client {
            case .codex, .copilot, .openCode, .pi:
                template = true
                fileExtension = "svg"
            case .claude:
                template = false
                fileExtension = "svg"
            default:
                template = false
                fileExtension = "png"
            }
            guard let url = Bundle.main.url(forResource: client.rawValue, withExtension: fileExtension,
                                            subdirectory: "StatusHookIcons"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.isTemplate = template
            return (client, image)
        }
    )

    var body: some View {
        Group {
            if let client, let image = Self.images[client] {
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
