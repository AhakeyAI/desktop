/// Existing firmware range allocation (command_solve.h), not new opcodes.
/// SDK and factory tools must use their own explicitly scoped transports.
public enum FirmwareCommandNamespace: Equatable, Sendable {
    case official, userSDK, systemFactory

    public init(command: UInt8) {
        switch command {
        case 0x00...0x9F: self = .official
        case 0xA0...0xEF: self = .userSDK
        default: self = .systemFactory
        }
    }
}
