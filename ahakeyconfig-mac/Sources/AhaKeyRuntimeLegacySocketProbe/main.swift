import Darwin
import Foundation
import AhaKeyConfigShared

@main
enum AhaKeyRuntimeLegacySocketProbe {
    static func main() {
        signal(SIGPIPE, SIG_DFL)
        let mode = CommandLine.arguments.dropFirst().first ?? "writer"
        guard let pair = AhaKeyRuntimeLegacySocketIO.makeUnixStreamPair() else { exit(2) }
        let payload = Data("{\"switchState\":null,\"lightMode\":null}\n".utf8)
        switch mode {
        case "raw":
            Darwin.close(pair.1)
            _ = payload.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(pair.0, base, raw.count)
            }
            Darwin.close(pair.0)
            exit(0)
        default:
            guard AhaKeyRuntimeLegacySocketIO.prepareAcceptedClient(pair.0) else { exit(4) }
            Darwin.close(pair.1)
            let result = AhaKeyRuntimeLegacySocketIO.writeAll(payload, to: pair.0)
            var fd = pair.0
            AhaKeyRuntimeLegacySocketIO.closeOnce(&fd)
            AhaKeyRuntimeLegacySocketIO.closeOnce(&fd)
            switch result {
            case .completed, .peerClosed:
                exit(0)
            case .failed:
                exit(3)
            }
        }
    }
}
