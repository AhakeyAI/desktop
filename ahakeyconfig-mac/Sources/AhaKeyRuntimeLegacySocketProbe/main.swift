import Darwin
import Foundation
import AhaKeyConfigShared

@main
enum AhaKeyRuntimeLegacySocketProbe {
    static func main() {
        signal(SIGPIPE, SIG_DFL)
        guard let pair = AhaKeyRuntimeLegacySocketIO.makeUnixStreamPair() else { exit(2) }
        guard AhaKeyRuntimeLegacySocketIO.prepareAcceptedClient(pair.0) else { exit(4) }
        Darwin.close(pair.1)
        let payload = Data("{\"switchState\":null,\"lightMode\":null}\n".utf8)
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
